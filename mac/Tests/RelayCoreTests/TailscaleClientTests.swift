import Foundation
import Testing
@testable import RelayCore

@Test
func tailscalePlansAlwaysTargetTheRelayWatchPort() {
    let tailscale = URL(fileURLWithPath: "/Applications/Tailscale.app/Contents/MacOS/Tailscale")
    let cliEnvironment = ["TAILSCALE_BE_CLI": "1"]

    #expect(
        TailscaleCommandPlan.status(tailscale: tailscale) == CommandInvocation(
            executableURL: tailscale,
            arguments: ["status", "--json"],
            environment: cliEnvironment
        )
    )
    #expect(
        TailscaleCommandPlan.loginURL(tailscale: tailscale) == CommandInvocation(
            executableURL: tailscale,
            arguments: ["login", "--timeout=1s"],
            environment: cliEnvironment
        )
    )
    #expect(
        TailscaleCommandPlan.enableFunnel(tailscale: tailscale) == CommandInvocation(
            executableURL: tailscale,
            arguments: [
                "funnel",
                "--bg",
                "http://127.0.0.1:43117",
            ],
            environment: cliEnvironment
        )
    )
    #expect(
        TailscaleCommandPlan.disableFunnel(tailscale: tailscale) == CommandInvocation(
            executableURL: tailscale,
            arguments: ["funnel", "43117", "off"],
            environment: cliEnvironment
        )
    )
    #expect(
        TailscaleCommandPlan.funnelStatus(tailscale: tailscale) == CommandInvocation(
            executableURL: tailscale,
            arguments: ["funnel", "status", "--json"],
            environment: cliEnvironment
        )
    )
}

@Test
func tailscaleLoginUsesTheOfficialFlowWithoutAcceptingAnAuthKey() async throws {
    let opened = URLRecorder()
    let runner = QueueCommandRunner(
        results: [
            CommandResult(
                exitCode: 1,
                standardOutput: "",
                standardError: "Open https://login.tailscale.com/a/sensitive-token to authenticate"
            ),
            CommandResult(
                exitCode: 0,
                standardOutput: #"{"BackendState":"NeedsLogin"}"#,
                standardError: ""
            ),
            CommandResult(
                exitCode: 0,
                standardOutput: #"{"BackendState":"Running","Self":{"DNSName":"relay.tailnet.ts.net."}}"#,
                standardError: ""
            ),
        ]
    )
    let client = TailscaleClient(
        executableURL: URL(fileURLWithPath: "/usr/local/bin/tailscale"),
        runner: runner
    )

    let status = try await client.login(
        openURL: { url in await opened.record(url) },
        sleep: {},
        maximumPolls: 2
    )

    #expect(status.signedIn)
    #expect(status.dnsName == "relay.tailnet.ts.net")
    #expect(await runner.invocations.map(\.arguments) == [
        ["login", "--timeout=1s"],
        ["status", "--json"],
        ["status", "--json"],
    ])
    #expect(await opened.urls == [URL(string: "https://login.tailscale.com/a/sensitive-token")!])
    #expect(
        await runner.invocations.allSatisfy {
            $0.environment == ["TAILSCALE_BE_CLI": "1"]
                && !$0.arguments.contains(where: { $0.contains("auth-key") })
        }
    )
}

@Test
func tailscaleLoginCanBeCancelledWhilePolling() async {
    let runner = QueueCommandRunner(
        results: [
            CommandResult(
                exitCode: 1,
                standardOutput: "https://login.tailscale.com/a/cancel",
                standardError: ""
            ),
            CommandResult(
                exitCode: 0,
                standardOutput: #"{"BackendState":"NeedsLogin"}"#,
                standardError: ""
            ),
        ]
    )
    let client = TailscaleClient(
        executableURL: URL(fileURLWithPath: "/usr/local/bin/tailscale"),
        runner: runner
    )

    await #expect(throws: CancellationError.self) {
        try await client.login(
            openURL: { _ in },
            sleep: { throw CancellationError() },
            maximumPolls: 2
        )
    }
}

@Test
func tailscaleLoginTimesOutWithoutSavingCredentials() async {
    let needsLogin = CommandResult(
        exitCode: 0,
        standardOutput: #"{"BackendState":"NeedsLogin"}"#,
        standardError: ""
    )
    let runner = QueueCommandRunner(
        results: [
            CommandResult(
                exitCode: 1,
                standardOutput: "https://login.tailscale.com/a/timeout",
                standardError: ""
            ),
            needsLogin,
            needsLogin,
        ]
    )
    let client = TailscaleClient(
        executableURL: URL(fileURLWithPath: "/usr/local/bin/tailscale"),
        runner: runner
    )

    await #expect(throws: TailscaleClientError.loginTimedOut) {
        try await client.login(
            openURL: { _ in },
            sleep: {},
            maximumPolls: 2
        )
    }
}

@Test
func funnelEnableRequiresSignInAndTheBridgeSecuritySelfTest() async throws {
    let tailscale = URL(fileURLWithPath: "/usr/local/bin/tailscale")
    let runner = QueueCommandRunner(
        results: [
            CommandResult(
                exitCode: 0,
                standardOutput: #"{"BackendState":"Running","Self":{"DNSName":"relay.tailnet.ts.net."}}"#,
                standardError: ""
            ),
        ]
    )
    let client = TailscaleClient(executableURL: tailscale, runner: runner)

    await #expect(throws: TailscaleClientError.bridgeSecurityCheckFailed) {
        try await client.enableFunnel {
            AdminSecuritySelfTest(
                ok: false,
                checks: AdminSecurityChecks(
                    adminLoopbackOnly: true,
                    watchLoopbackOnly: false,
                    strongAdminToken: true
                )
            )
        }
    }
    #expect(await runner.invocations.count == 1)
    #expect(await runner.invocations.first?.arguments == ["status", "--json"])
}

@Test
func emergencyStopAttemptsBridgeShutdownWhenFunnelDisableFails() async {
    let runner = QueueCommandRunner(
        results: [
            CommandResult(exitCode: 1, standardOutput: "", standardError: "failed"),
        ]
    )
    let bridge = BridgeShutdownRecorder()
    let client = TailscaleClient(
        executableURL: URL(fileURLWithPath: "/usr/local/bin/tailscale"),
        runner: runner
    )

    let result = await client.emergencyStop {
        await bridge.stop()
    }

    #expect(result == EmergencyStopResult(funnelDisabled: false, bridgeStopped: true))
    #expect(await bridge.stopped)
}

private actor QueueCommandRunner: CommandRunning {
    private var results: [CommandResult]
    private(set) var invocations: [CommandInvocation] = []

    init(results: [CommandResult]) {
        self.results = results
    }

    func run(_ invocation: CommandInvocation) async throws -> CommandResult {
        invocations.append(invocation)
        return results.removeFirst()
    }
}

private actor BridgeShutdownRecorder {
    private(set) var stopped = false

    func stop() {
        stopped = true
    }
}

private actor URLRecorder {
    private(set) var urls: [URL] = []

    func record(_ url: URL) {
        urls.append(url)
    }
}

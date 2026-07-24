import Foundation
import Testing
@testable import RelayCore

@Test
func adbPlansUseExactExecutableAndArgumentArrays() {
    let adb = URL(fileURLWithPath: "/Applications/Relay.app/Contents/Resources/platform-tools/adb")
    let apk = URL(fileURLWithPath: "/Applications/Relay.app/Contents/Resources/relay-wear.apk")

    #expect(
        ADBCommandPlan.pair(
            adb: adb,
            address: "192.168.1.20:37123",
            code: "123456"
        ) == CommandInvocation(
            executableURL: adb,
            arguments: ["pair", "192.168.1.20:37123", "123456"]
        )
    )
    #expect(
        ADBCommandPlan.connect(
            adb: adb,
            address: "192.168.1.20:39887"
        ) == CommandInvocation(
            executableURL: adb,
            arguments: ["connect", "192.168.1.20:39887"]
        )
    )
    #expect(
        ADBCommandPlan.install(
            adb: adb,
            serial: "192.168.1.20:39887",
            apk: apk
        ) == CommandInvocation(
            executableURL: adb,
            arguments: [
                "-s", "192.168.1.20:39887",
                "install", "-r", apk.path,
            ]
        )
    )
}

@Test
func adbDiscoverySeparatesPairingAndConnectionServices() {
    let services = ADBClient.parseMDNSServices(
        """
        adb-1234 _adb-tls-pairing._tcp 192.168.1.20:37123
        adb-1234 _adb-tls-connect._tcp 192.168.1.20:39887
        """
    )

    #expect(services.pairing == ["192.168.1.20:37123"])
    #expect(services.connection == ["192.168.1.20:39887"])
}

@Test
func adbClientVerifiesWearOSAndTheInstalledPackageVersion() async throws {
    let runner = ADBQueueRunner(
        results: [
            CommandResult(
                exitCode: 0,
                standardOutput: "feature:android.hardware.type.watch\n",
                standardError: ""
            ),
            CommandResult(exitCode: 0, standardOutput: "Success\n", standardError: ""),
            CommandResult(
                exitCode: 0,
                standardOutput: "versionCode=1 minSdk=33 targetSdk=36\n",
                standardError: ""
            ),
            CommandResult(exitCode: 0, standardOutput: "Starting\n", standardError: ""),
        ]
    )
    let client = ADBClient(
        executableURL: URL(fileURLWithPath: "/platform-tools/adb"),
        runner: runner
    )
    let apk = URL(fileURLWithPath: "/Relay/relay-wear.apk")

    try await client.verifyWearOS(serial: "watch:39887")
    try await client.install(
        apk: apk,
        serial: "watch:39887",
        packageID: "dev.ungaaaabungaaa.relay",
        expectedVersionCode: 1
    )
    try await client.launch(
        serial: "watch:39887",
        component: "dev.ungaaaabungaaa.relay/.MainActivity"
    )

    let invocations = await runner.invocations
    #expect(invocations[0].arguments == [
        "-s", "watch:39887", "shell", "pm", "list", "features",
    ])
    #expect(invocations[1].arguments == [
        "-s", "watch:39887", "install", "-r", apk.path,
    ])
    #expect(invocations[2].arguments.contains("dev.ungaaaabungaaa.relay"))
}

private actor ADBQueueRunner: CommandRunning {
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

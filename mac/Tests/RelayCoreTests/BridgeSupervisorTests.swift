import Foundation
import Testing
@testable import RelayCore

@Test
func bridgeSupervisorRunsOneSidecarAndStopsCleanly() async throws {
    let launcher = FakeBridgeLauncher()
    let supervisor = BridgeSupervisor(
        launcher: launcher,
        configuration: testConfiguration,
        maximumAutomaticRestarts: 2,
        restartDelay: .zero
    )

    try await supervisor.start()
    try await supervisor.start()
    #expect(launcher.launchCount == 1)
    #expect(await supervisor.snapshot().state == .running)

    await supervisor.stop()
    #expect(launcher.process(at: 0)?.terminateCount == 1)
    #expect(await supervisor.snapshot().state == .stopped)

    launcher.process(at: 0)?.exit(code: 0)
    await Task.yield()
    #expect(launcher.launchCount == 1)
}

@Test
func bridgeSupervisorBoundsCrashRestartsAndRedactsErrors() async throws {
    let launcher = FakeBridgeLauncher()
    let supervisor = BridgeSupervisor(
        launcher: launcher,
        configuration: testConfiguration,
        maximumAutomaticRestarts: 2,
        restartDelay: .zero
    )

    try await supervisor.start()
    launcher.process(at: 0)?.exit(
        code: 1,
        stderr: "Authorization: Bearer admin-token\nOPENAI_API_KEY=voice-secret\nordinary failure"
    )
    try await eventually { launcher.launchCount == 2 }
    launcher.process(at: 1)?.exit(code: 1, stderr: "second failure")
    try await eventually { launcher.launchCount == 3 }
    launcher.process(at: 2)?.exit(code: 1, stderr: "third failure")
    try await eventually { await supervisor.snapshot().state == .failed }

    let snapshot = await supervisor.snapshot()
    #expect(snapshot.automaticRestartCount == 2)
    #expect(!snapshot.lastDiagnostic.contains("admin-token"))
    #expect(!snapshot.lastDiagnostic.contains("voice-secret"))
    #expect(snapshot.lastDiagnostic.contains("[REDACTED]"))
}

@Test
func emergencyStopNeverAutomaticallyRestartsTheBridge() async throws {
    let launcher = FakeBridgeLauncher()
    let supervisor = BridgeSupervisor(
        launcher: launcher,
        configuration: testConfiguration,
        maximumAutomaticRestarts: 2,
        restartDelay: .zero
    )

    try await supervisor.start()
    await supervisor.emergencyStop()
    launcher.process(at: 0)?.exit(code: 1, stderr: "stopped")
    await Task.yield()

    #expect(launcher.launchCount == 1)
    #expect(await supervisor.snapshot().state == .emergencyStopped)
}

private let testConfiguration = BridgeLaunchConfiguration(
    executableURL: URL(fileURLWithPath: "/tmp/relay-bridge-arm64"),
    arguments: ["serve"],
    environment: [
        "CODEWATCH_ADMIN_TOKEN": "admin-token",
        "OPENAI_API_KEY": "voice-secret",
    ],
    sensitiveValues: ["admin-token", "voice-secret"]
)

private func eventually(
    attempts: Int = 100,
    condition: @escaping @Sendable () async -> Bool
) async throws {
    for _ in 0..<attempts {
        if await condition() {
            return
        }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Condition did not become true")
}

private final class FakeBridgeProcess: BridgeProcessHandle, @unchecked Sendable {
    private let lock = NSLock()
    private var running = true
    private var handler: (@Sendable (Int32, String) -> Void)?
    private(set) var terminateCount = 0

    var isRunning: Bool {
        lock.withLock { running }
    }

    func setExitHandler(_ handler: @escaping @Sendable (Int32, String) -> Void) {
        lock.withLock {
            self.handler = handler
        }
    }

    func terminate() {
        lock.withLock {
            terminateCount += 1
            running = false
        }
    }

    func exit(code: Int32, stderr: String = "") {
        let callback = lock.withLock {
            running = false
            return handler
        }
        callback?(code, stderr)
    }
}

private final class FakeBridgeLauncher: BridgeProcessLaunching, @unchecked Sendable {
    private let lock = NSLock()
    private var processes: [FakeBridgeProcess] = []

    var launchCount: Int {
        lock.withLock { processes.count }
    }

    func launch(
        configuration: BridgeLaunchConfiguration,
        onExit: @escaping @Sendable (Int32, String) -> Void
    ) throws -> any BridgeProcessHandle {
        let process = FakeBridgeProcess()
        process.setExitHandler(onExit)
        lock.withLock {
            processes.append(process)
        }
        return process
    }

    func process(at index: Int) -> FakeBridgeProcess? {
        lock.withLock {
            processes.indices.contains(index) ? processes[index] : nil
        }
    }
}

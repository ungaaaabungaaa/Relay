import Foundation

public struct BridgeLaunchConfiguration: Equatable, Sendable {
    public var executableURL: URL
    public var arguments: [String]
    public var environment: [String: String]
    public var sensitiveValues: [String]

    public init(
        executableURL: URL,
        arguments: [String] = ["serve"],
        environment: [String: String],
        sensitiveValues: [String]
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.sensitiveValues = sensitiveValues
    }
}

public protocol BridgeProcessHandle: AnyObject, Sendable {
    var isRunning: Bool { get }
    func terminate()
}

public protocol BridgeProcessLaunching: Sendable {
    func launch(
        configuration: BridgeLaunchConfiguration,
        onExit: @escaping @Sendable (Int32, String) -> Void
    ) throws -> any BridgeProcessHandle
}

public enum BridgeSupervisorState: String, Equatable, Sendable {
    case stopped
    case starting
    case running
    case restarting
    case failed
    case emergencyStopped
}

public struct BridgeSupervisorSnapshot: Equatable, Sendable {
    public var state: BridgeSupervisorState
    public var launchCount: Int
    public var automaticRestartCount: Int
    public var lastDiagnostic: String
}

public actor BridgeSupervisor {
    private let launcher: any BridgeProcessLaunching
    private let configuration: BridgeLaunchConfiguration
    private let maximumAutomaticRestarts: Int
    private let restartDelay: Duration
    private var process: (any BridgeProcessHandle)?
    private var generation: UUID?
    private var state: BridgeSupervisorState = .stopped
    private var launchCount = 0
    private var automaticRestartCount = 0
    private var lastDiagnostic = ""
    private var emergencyStopped = false

    public init(
        launcher: any BridgeProcessLaunching,
        configuration: BridgeLaunchConfiguration,
        maximumAutomaticRestarts: Int = 2,
        restartDelay: Duration = .seconds(1)
    ) {
        self.launcher = launcher
        self.configuration = configuration
        self.maximumAutomaticRestarts = max(0, maximumAutomaticRestarts)
        self.restartDelay = restartDelay
    }

    public func start() throws {
        if state == .running || state == .starting || state == .restarting {
            return
        }
        emergencyStopped = false
        automaticRestartCount = 0
        try launch()
    }

    public func stop() {
        generation = nil
        let active = process
        process = nil
        state = .stopped
        active?.terminate()
    }

    public func emergencyStop() {
        emergencyStopped = true
        generation = nil
        let active = process
        process = nil
        state = .emergencyStopped
        active?.terminate()
    }

    public func snapshot() -> BridgeSupervisorSnapshot {
        BridgeSupervisorSnapshot(
            state: state,
            launchCount: launchCount,
            automaticRestartCount: automaticRestartCount,
            lastDiagnostic: lastDiagnostic
        )
    }

    private func launch() throws {
        state = .starting
        let launchGeneration = UUID()
        do {
            let launched = try launcher.launch(configuration: configuration) {
                [weak self] code, standardError in
                Task {
                    await self?.processExited(
                        generation: launchGeneration,
                        code: code,
                        standardError: standardError
                    )
                }
            }
            generation = launchGeneration
            process = launched
            launchCount += 1
            state = .running
        } catch {
            appendDiagnostic(String(describing: error))
            state = .failed
            throw error
        }
    }

    private func processExited(
        generation exitedGeneration: UUID,
        code: Int32,
        standardError: String
    ) {
        guard generation == exitedGeneration else {
            return
        }
        generation = nil
        process = nil
        if !standardError.isEmpty {
            appendDiagnostic(standardError)
        } else if code != 0 {
            appendDiagnostic("Bridge exited with status \(code)")
        }
        if emergencyStopped {
            state = .emergencyStopped
            return
        }
        guard automaticRestartCount < maximumAutomaticRestarts else {
            state = code == 0 ? .stopped : .failed
            return
        }
        automaticRestartCount += 1
        state = .restarting
        let expectedRestart = automaticRestartCount
        Task { [weak self, restartDelay] in
            if restartDelay > .zero {
                try? await Task.sleep(for: restartDelay)
            }
            await self?.restartIfStillNeeded(expectedRestart)
        }
    }

    private func restartIfStillNeeded(_ expectedRestart: Int) {
        guard
            state == .restarting,
            !emergencyStopped,
            automaticRestartCount == expectedRestart
        else {
            return
        }
        do {
            try launch()
        } catch {
            state = .failed
        }
    }

    private func appendDiagnostic(_ diagnostic: String) {
        let redacted = redact(
            diagnostic,
            sensitiveValues: configuration.sensitiveValues
        )
        let combined = [lastDiagnostic, redacted]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        lastDiagnostic = String(combined.suffix(4_096))
    }
}

public final class ProcessBridgeLauncher: BridgeProcessLaunching, @unchecked Sendable {
    public init() {}

    public func launch(
        configuration: BridgeLaunchConfiguration,
        onExit: @escaping @Sendable (Int32, String) -> Void
    ) throws -> any BridgeProcessHandle {
        let process = Process()
        let errorPipe = Pipe()
        let buffer = LockedTextBuffer()
        process.executableURL = configuration.executableURL
        process.arguments = configuration.arguments
        process.environment = ProcessInfo.processInfo.environment.merging(
            configuration.environment
        ) { _, configured in configured }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            buffer.append(handle.availableData)
        }
        process.terminationHandler = { terminated in
            errorPipe.fileHandleForReading.readabilityHandler = nil
            buffer.append(
                (try? errorPipe.fileHandleForReading.readToEnd()) ?? Data()
            )
            onExit(terminated.terminationStatus, buffer.string)
        }
        try process.run()
        return ProcessBridgeHandle(process: process, errorPipe: errorPipe)
    }
}

private final class ProcessBridgeHandle: BridgeProcessHandle, @unchecked Sendable {
    private let process: Process
    private let errorPipe: Pipe

    init(process: Process, errorPipe: Pipe) {
        self.process = process
        self.errorPipe = errorPipe
    }

    var isRunning: Bool {
        process.isRunning
    }

    func terminate() {
        if process.isRunning {
            process.terminate()
        }
    }
}

private final class LockedTextBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ newData: Data) {
        guard !newData.isEmpty else {
            return
        }
        lock.withLock {
            data.append(newData)
            if data.count > 65_536 {
                data = data.suffix(65_536)
            }
        }
    }

    var string: String {
        lock.withLock {
            String(decoding: data, as: UTF8.self)
        }
    }
}

private func redact(_ text: String, sensitiveValues: [String]) -> String {
    var value = text
    for sensitive in sensitiveValues where !sensitive.isEmpty {
        value = value.replacingOccurrences(of: sensitive, with: "[REDACTED]")
    }
    return value
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { line in
            let lower = line.lowercased()
            guard
                lower.contains("authorization")
                    || lower.contains("api_key")
                    || lower.contains("apikey")
                    || lower.contains("token=")
                    || lower.contains("secret=")
            else {
                return String(line)
            }
            if let separator = line.firstIndex(where: { $0 == "=" || $0 == ":" }) {
                return "\(line[...separator])[REDACTED]"
            }
            return "[REDACTED]"
        }
        .joined(separator: "\n")
}

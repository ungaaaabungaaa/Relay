import Foundation

public struct CommandInvocation: Equatable, Sendable {
    public var executableURL: URL
    public var arguments: [String]
    public var environment: [String: String]

    public init(
        executableURL: URL,
        arguments: [String],
        environment: [String: String] = [:]
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
    }
}

public struct CommandResult: Equatable, Sendable {
    public var exitCode: Int32
    public var standardOutput: String
    public var standardError: String

    public init(
        exitCode: Int32,
        standardOutput: String,
        standardError: String
    ) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public protocol CommandRunning: Sendable {
    func run(_ invocation: CommandInvocation) async throws -> CommandResult
}

public struct ProcessCommandRunner: CommandRunning {
    private let maximumOutputBytes: Int

    public init(maximumOutputBytes: Int = 1_048_576) {
        self.maximumOutputBytes = max(1_024, maximumOutputBytes)
    }

    public func run(_ invocation: CommandInvocation) async throws -> CommandResult {
        let maximumOutputBytes = maximumOutputBytes
        return try await Task.detached(priority: .utility) {
            try Self.runSynchronously(
                invocation,
                maximumOutputBytes: maximumOutputBytes
            )
        }.value
    }

    private static func runSynchronously(
        _ invocation: CommandInvocation,
        maximumOutputBytes: Int
    ) throws -> CommandResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let output = LockedDataBuffer(maximumBytes: maximumOutputBytes)
        let error = LockedDataBuffer(maximumBytes: maximumOutputBytes)
        process.executableURL = invocation.executableURL
        process.arguments = invocation.arguments
        process.environment = ProcessInfo.processInfo.environment.merging(
            invocation.environment
        ) { _, configured in configured }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            output.append(handle.availableData)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            error.append(handle.availableData)
        }
        try process.run()
        process.waitUntilExit()
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        output.append((try? outputPipe.fileHandleForReading.readToEnd()) ?? Data())
        error.append((try? errorPipe.fileHandleForReading.readToEnd()) ?? Data())
        return CommandResult(
            exitCode: process.terminationStatus,
            standardOutput: output.string,
            standardError: error.string
        )
    }
}

private final class LockedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let maximumBytes: Int
    private var data = Data()

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    func append(_ newData: Data) {
        guard !newData.isEmpty else {
            return
        }
        lock.withLock {
            let remaining = maximumBytes - data.count
            if remaining > 0 {
                data.append(newData.prefix(remaining))
            }
        }
    }

    var string: String {
        lock.withLock {
            String(decoding: data, as: UTF8.self)
        }
    }
}

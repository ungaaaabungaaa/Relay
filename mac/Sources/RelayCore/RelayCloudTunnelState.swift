import Foundation

public enum RelayCloudTunnelPhase: Equatable, Sendable {
    case signedOut
    case connecting(attempt: Int)
    case connected
    case retrying(attempt: Int, delaySeconds: Int)
    case stopped
}

public enum RelayCloudTunnelFailure: Equatable, Sendable {
    case authentication
    case incompatible
    case recoverable
}

public struct RelayCloudTunnelState: Equatable, Sendable {
    public private(set) var phase: RelayCloudTunnelPhase = .signedOut
    public private(set) var attempt = 0

    public init() {}

    public mutating func begin() {
        attempt += 1
        phase = .connecting(attempt: attempt)
    }

    public mutating func opened() {
        attempt = 0
        phase = .connected
    }

    @discardableResult
    public mutating func failed(_ failure: RelayCloudTunnelFailure) -> Int? {
        switch failure {
        case .authentication:
            phase = .signedOut
            return nil
        case .incompatible:
            phase = .stopped
            return nil
        case .recoverable:
            let retryAttempt = max(1, attempt)
            let delay = Self.retryDelay(forAttempt: retryAttempt)
            phase = .retrying(attempt: retryAttempt, delaySeconds: delay)
            return delay
        }
    }

    public mutating func stop() { phase = .stopped }

    public static func retryDelay(forAttempt attempt: Int) -> Int {
        guard attempt > 1 else { return 1 }
        return min(1 << min(attempt - 1, 5), 30)
    }
}

public enum RelayCloudHandshakeError: Error, Equatable, Sendable {
    case rejected(status: Int)
}

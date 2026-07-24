import Foundation

public enum SetupRequirementStatus: Equatable, Sendable {
    case checking
    case ready
    case missing
    case failed(String)

    public var isReady: Bool {
        self == .ready
    }
}

public struct SetupState: Equatable, Sendable {
    public var codex: SetupRequirementStatus
    public var tailscale: SetupRequirementStatus
    public var bridge: SetupRequirementStatus
    public var watchInstalled: Bool
    public var watchPaired: Bool
    public var remoteAccess: SetupRequirementStatus

    public init(
        codex: SetupRequirementStatus,
        tailscale: SetupRequirementStatus,
        bridge: SetupRequirementStatus,
        watchInstalled: Bool,
        watchPaired: Bool,
        remoteAccess: SetupRequirementStatus
    ) {
        self.codex = codex
        self.tailscale = tailscale
        self.bridge = bridge
        self.watchInstalled = watchInstalled
        self.watchPaired = watchPaired
        self.remoteAccess = remoteAccess
    }

    public var isReady: Bool {
        codex.isReady
            && tailscale.isReady
            && bridge.isReady
            && watchInstalled
            && watchPaired
            && remoteAccess.isReady
    }

    public static let checking = SetupState(
        codex: .checking,
        tailscale: .checking,
        bridge: .checking,
        watchInstalled: false,
        watchPaired: false,
        remoteAccess: .checking
    )
}

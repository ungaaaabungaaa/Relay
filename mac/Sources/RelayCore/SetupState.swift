import Foundation

public enum SetupJourneyStepID: String, CaseIterable, Sendable {
    case integrityAndCodex
    case emailSignIn
    case relayCloud
    case watchPairing
    case workspaces
    case startAtLogin
}

public struct SetupJourneyStep: Equatable, Identifiable, Sendable {
    public var id: SetupJourneyStepID
    public var title: String
    public var detail: String
    public var complete: Bool
}

public struct SetupJourney: Equatable, Sendable {
    public var steps: [SetupJourneyStep]

    public init(
        codexAndIntegrityReady: Bool,
        signedIn: Bool,
        cloudConnected: Bool,
        watchPaired: Bool,
        workspacesSelected: Bool,
        startAtLoginEnabled: Bool
    ) {
        steps = [
            SetupJourneyStep(
                id: .integrityAndCodex,
                title: "Relay and Codex",
                detail: "Verify Relay and connect to the Codex CLI on this Mac.",
                complete: codexAndIntegrityReady
            ),
            SetupJourneyStep(
                id: .emailSignIn,
                title: "Sign in by email",
                detail: "Relay opens a single-use link in your browser. No password is shared with Relay.",
                complete: signedIn
            ),
            SetupJourneyStep(
                id: .relayCloud,
                title: "Connect Relay Cloud",
                detail: "This Mac opens an encrypted outbound connection. No ports or VPN are required.",
                complete: cloudConnected
            ),
            SetupJourneyStep(
                id: .watchPairing,
                title: "Pair a watch",
                detail: "Install Relay from Google Play, enter the code, and compare fingerprints.",
                complete: watchPaired
            ),
            SetupJourneyStep(
                id: .workspaces,
                title: "Allowed workspaces",
                detail: "Choose the only Mac folders your watches may use.",
                complete: workspacesSelected
            ),
            SetupJourneyStep(
                id: .startAtLogin,
                title: "Start Relay at login",
                detail: "Keep the Mac bridge available after you sign in to macOS.",
                complete: startAtLoginEnabled
            ),
        ]
    }

    public var completedCount: Int {
        steps.count(where: \.complete)
    }

    public var current: SetupJourneyStep? {
        steps.first(where: { !$0.complete })
    }

    public var isComplete: Bool {
        current == nil
    }

    public static let complete = SetupJourney(
        codexAndIntegrityReady: true,
        signedIn: true,
        cloudConnected: true,
        watchPaired: true,
        workspacesSelected: true,
        startAtLoginEnabled: true
    )
}

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
    public var account: SetupRequirementStatus
    public var bridge: SetupRequirementStatus
    public var watchPaired: Bool
    public var cloud: SetupRequirementStatus

    public init(
        codex: SetupRequirementStatus,
        account: SetupRequirementStatus,
        bridge: SetupRequirementStatus,
        watchPaired: Bool,
        cloud: SetupRequirementStatus
    ) {
        self.codex = codex
        self.account = account
        self.bridge = bridge
        self.watchPaired = watchPaired
        self.cloud = cloud
    }

    public var isReady: Bool {
        codex.isReady
            && account.isReady
            && bridge.isReady
            && watchPaired
            && cloud.isReady
    }

    public static let checking = SetupState(
        codex: .checking,
        account: .checking,
        bridge: .checking,
        watchPaired: false,
        cloud: .checking
    )
}

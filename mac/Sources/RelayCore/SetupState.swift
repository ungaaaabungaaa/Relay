import Foundation

public enum SetupJourneyStepID: String, CaseIterable, Sendable {
    case integrityAndCodex
    case tailscaleInstall
    case tailscaleLogin
    case bridgePreflight
    case platformTools
    case watchInstall
    case watchPairing
    case workspaces
    case remoteAccess
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
        tailscaleInstalled: Bool,
        tailscaleSignedIn: Bool,
        bridgePreflightPassed: Bool,
        platformToolsReady: Bool,
        watchInstalled: Bool,
        watchPaired: Bool,
        workspacesSelected: Bool,
        remoteAccessEnabled: Bool
    ) {
        steps = [
            SetupJourneyStep(
                id: .integrityAndCodex,
                title: "Relay and Codex",
                detail: "Verify the bundled bridge and find the Codex CLI.",
                complete: codexAndIntegrityReady
            ),
            SetupJourneyStep(
                id: .tailscaleInstall,
                title: "Install Tailscale",
                detail: "Use the official Apple-silicon Mac application.",
                complete: tailscaleInstalled
            ),
            SetupJourneyStep(
                id: .tailscaleLogin,
                title: "Sign in to Tailscale",
                detail: "Relay opens Tailscale's official browser login.",
                complete: tailscaleSignedIn
            ),
            SetupJourneyStep(
                id: .bridgePreflight,
                title: "Security preflight",
                detail: "Confirm both Relay ports remain loopback-only.",
                complete: bridgePreflightPassed
            ),
            SetupJourneyStep(
                id: .platformTools,
                title: "Android Platform Tools",
                detail: "Install Google's verified ADB tools without an emulator.",
                complete: platformToolsReady
            ),
            SetupJourneyStep(
                id: .watchInstall,
                title: "Install the watch app",
                detail: "Discover the Wear OS watch and install the signed APK.",
                complete: watchInstalled
            ),
            SetupJourneyStep(
                id: .watchPairing,
                title: "Pair and approve",
                detail: "Compare both fingerprints before approving the watch.",
                complete: watchPaired
            ),
            SetupJourneyStep(
                id: .workspaces,
                title: "Allowed workspaces",
                detail: "Choose the only Mac folders visible to the watch.",
                complete: workspacesSelected
            ),
            SetupJourneyStep(
                id: .remoteAccess,
                title: "Remote access",
                detail: "Enable authenticated HTTPS access after every check passes.",
                complete: remoteAccessEnabled
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
        tailscaleInstalled: true,
        tailscaleSignedIn: true,
        bridgePreflightPassed: true,
        platformToolsReady: true,
        watchInstalled: true,
        watchPaired: true,
        workspacesSelected: true,
        remoteAccessEnabled: true
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

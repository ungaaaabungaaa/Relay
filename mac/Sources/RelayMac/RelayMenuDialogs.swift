import AppKit
import Foundation
import RelayCore

enum RelayMenuPresentation {
    static let privacyPolicyURL = URL(string: "https://relayforcodex.com/privacy")!
    static let supportURL = URL(string: "https://relayforcodex.com/support")!
    static let licensesURL = URL(string: "https://relayforcodex.com/licenses")!

    static func pairingMacFingerprint(
        sessionFingerprint: String?,
        hostFingerprint: String
    ) -> String {
        guard let sessionFingerprint, !sessionFingerprint.isEmpty else {
            return hostFingerprint
        }
        return sessionFingerprint
    }

    static func canStartSecurePairing(
        cloudConnected: Bool,
        bridgeState: BridgeSupervisorState
    ) -> Bool {
        cloudConnected && bridgeState == .running
    }

    static func canResolvePairing(
        cloudPhase: RelayCloudTunnelPhase,
        bridgeState: BridgeSupervisorState
    ) -> Bool {
        cloudPhase == .connected && bridgeState == .running
    }

    static func statusRows(
        bridgeState: BridgeSupervisorState,
        codexStatus: String,
        cloudPhase: RelayCloudTunnelPhase,
        activeDeviceCount: Int
    ) -> [String] {
        [
            "Bridge \(bridgeLabel(bridgeState))",
            "Codex \(codexStatus.lowercased())",
            cloudLabel(cloudPhase),
            "\(activeDeviceCount) watch\(activeDeviceCount == 1 ? "" : "es")",
        ]
    }

    static func pairingExpiryLabel(expiresAt: Int64, now: Date = .now) -> String {
        let seconds = max(0, Int((expiresAt - Int64(now.timeIntervalSince1970 * 1_000)) / 1_000))
        guard seconds > 0 else { return "Expired" }
        if seconds >= 60 { return "Expires in \(seconds / 60)m" }
        return "Expires in \(seconds)s"
    }

    static func workspaceDisplayName(_ path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? path : name
    }

    static func safeDiagnostic(
        bridgeState: BridgeSupervisorState,
        cloudPhase: RelayCloudTunnelPhase,
        activeDeviceCount: Int,
        voiceConfigured: Bool
    ) -> String {
        return [
            "Bridge: \(bridgeLabel(bridgeState))",
            "Relay Cloud: \(cloudStatus(cloudPhase))",
            "Paired watches: \(max(0, activeDeviceCount))",
            "Voice configured: \(voiceConfigured ? "yes" : "no")",
        ].joined(separator: "\n")
    }

    static func updateLabel(_ state: RelayUpdateState) -> String {
        switch state {
        case .unknown: "Update status unknown"
        case .checking: "Checking for updates…"
        case .current: "Relay is up to date"
        case let .available(version): "Version \(version) is available"
        case .failed: "Update check unavailable"
        }
    }

    static func appVersion(infoDictionary: [String: Any]? = Bundle.main.infoDictionary) -> String {
        guard
            let version = infoDictionary?["CFBundleShortVersionString"] as? String,
            !version.isEmpty
        else {
            return "Unknown"
        }
        return version
    }

    static func cloudLabel(_ phase: RelayCloudTunnelPhase) -> String {
        "Relay Cloud \(cloudStatus(phase))"
    }

    private static func bridgeLabel(_ state: BridgeSupervisorState) -> String {
        switch state {
        case .running: "running"
        case .starting: "starting"
        case .restarting: "restarting"
        case .failed: "failed"
        case .emergencyStopped: "emergency stopped"
        case .stopped: "stopped"
        }
    }

    private static func cloudStatus(_ phase: RelayCloudTunnelPhase) -> String {
        switch phase {
        case .signedOut: "signed out"
        case .connecting: "connecting"
        case .connected: "connected"
        case let .retrying(_, delaySeconds): "retrying in \(delaySeconds)s"
        case .stopped: "stopped"
        }
    }
}

enum RelayDeviceRevocationDecision: Equatable {
    case blocked
    case localOnly
    case cloudAndLocal

    static func evaluate(
        vaultReadSucceeded: Bool,
        isCloudManaged: Bool,
        hasCloudAccess: Bool
    ) -> Self {
        guard vaultReadSucceeded else { return .blocked }
        guard isCloudManaged else { return .localOnly }
        return hasCloudAccess ? .cloudAndLocal : .blocked
    }
}

enum RelayVoiceKeyReconfigurationPlan: Equatable {
    case keep
    case rebuild

    static func forChange(previousKey: String?, nextKey: String?) -> Self {
        previousKey == nextKey ? .keep : .rebuild
    }
}

enum RelayReconnectPlan: Equatable {
    case keep
    case restart
    case create

    static func forSupervisor(state: BridgeSupervisorState?) -> Self {
        guard let state else { return .create }
        switch state {
        case .running, .starting, .restarting: return .keep
        case .stopped, .failed, .emergencyStopped: return .restart
        }
    }
}

@MainActor
enum RelayMenuDialogs {
    static func requestEmail() -> String? {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "name@example.com"
        let alert = NSAlert()
        alert.messageText = "Sign in to Relay Cloud"
        alert.informativeText = "Relay opens a secure browser verification page."
        alert.accessoryView = field
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let email = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return email.isEmpty ? nil : email
    }

    static func requestOpenAIKey() -> String? {
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        let alert = NSAlert()
        alert.messageText = "Set OpenAI API key"
        alert.informativeText = "Relay stores this key in your macOS Keychain."
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    static func chooseWorkspace() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Add Folder"
        guard panel.runModal() == .OK else { return nil }
        return panel.url?.path
    }

    static func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    static func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func confirm(_ action: DestructiveRelayAction) -> Bool {
        confirm(
            title: action.title,
            message: action.consequence,
            confirmationLabel: action.confirmationLabel
        )
    }

    static func confirm(
        title: String,
        message: String,
        confirmationLabel: String
    ) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirmationLabel)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

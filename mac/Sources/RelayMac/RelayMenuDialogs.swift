import AppKit
import Foundation
import RelayCore

enum RelayMenuPresentation {
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
        diagnostic: String
    ) -> String {
        let pattern = #"(?i)\b(?:token|secret|password|api[ _-]?key|authorization)\s*[:=]\s*[^\s;]+"#
        let redacted = diagnostic.replacingOccurrences(
            of: pattern,
            with: "[redacted]",
            options: .regularExpression
        )
        return [
            "Bridge: \(bridgeLabel(bridgeState))",
            "Relay Cloud: \(cloudStatus(cloudPhase))",
            redacted,
        ].joined(separator: "\n")
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

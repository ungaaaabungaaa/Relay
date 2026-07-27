import AppKit
import SwiftUI
import RelayCore

struct MenuContent: View {
    @ObservedObject var model: RelayAppModel
    @ObservedObject private var updater: RelayUpdateController
    @Environment(\.openWindow) private var openWindow
    @State private var pendingAction: DestructiveRelayAction?

    init(model: RelayAppModel) {
        self.model = model
        updater = model.updateController
    }

    var body: some View {
        Group {
            Label(
                model.bridgeState == .running ? "Bridge running" : "Bridge stopped",
                systemImage: model.bridgeState == .running ? "bolt.horizontal.fill" : "bolt.slash"
            )
            Label("Codex \(model.codexStatus.lowercased())", systemImage: "terminal")
            Label(
                cloudLabel,
                systemImage: model.cloudConnected ? "lock.shield.fill" : "network.slash"
            )
            Label(
                "\(model.activeDeviceCount) watch\(model.activeDeviceCount == 1 ? "" : "es")",
                systemImage: "applewatch"
            )
            Label(
                "\(model.pendingActionCount) waiting actions",
                systemImage: "tray.full"
            )
            if case .available = updater.state {
                Label("Update available", systemImage: "arrow.down.circle.fill")
            }
            Divider()
            Button("Open Dashboard") {
                openWindow(id: "dashboard")
                NSApplication.shared.activate()
            }
            Button("Refresh") {
                Task { await model.refresh() }
            }
            Divider()
            Button("Emergency Stop", role: .destructive) {
                pendingAction = .emergencyStop
            }
            Button("Quit Relay") {
                Task {
                    await model.quit()
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .confirmationDialog(
            pendingAction?.title ?? "Confirm Relay action",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingAction
        ) { action in
            Button(action.confirmationLabel, role: .destructive) {
                pendingAction = nil
                if action == .emergencyStop {
                    Task { await model.emergencyStop() }
                }
            }
            Button("Cancel", role: .cancel) { pendingAction = nil }
        } message: { action in
            Text(action.consequence)
        }
    }

    private var cloudLabel: String {
        switch model.cloudTunnelPhase {
        case .signedOut: "Relay Cloud signed out"
        case .connecting: "Relay Cloud connecting"
        case .connected: "Relay Cloud connected"
        case .retrying: "Relay Cloud retrying"
        case .stopped: "Relay Cloud stopped"
        }
    }
}

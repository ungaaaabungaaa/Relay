import AppKit
import SwiftUI
import RelayCore

struct MenuContent: View {
    @ObservedObject var model: RelayAppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Label(
                model.bridgeState == .running ? "Bridge running" : "Bridge stopped",
                systemImage: model.bridgeState == .running ? "bolt.horizontal.fill" : "bolt.slash"
            )
            Label("Codex \(model.codexStatus.lowercased())", systemImage: "terminal")
            Label(
                model.funnelEnabled ? "Remote access on" : "Remote access off",
                systemImage: model.funnelEnabled ? "network" : "network.slash"
            )
            Label(
                "\(model.activeDeviceCount) watch\(model.activeDeviceCount == 1 ? "" : "es")",
                systemImage: "applewatch"
            )
            Label(
                "\(model.pendingActionCount) waiting actions",
                systemImage: "tray.full"
            )
            if model.updateAvailable {
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
                Task { await model.emergencyStop() }
            }
            Button("Quit Relay") {
                Task {
                    await model.quit()
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }
}

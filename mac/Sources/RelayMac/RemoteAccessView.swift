import SwiftUI

struct RemoteAccessView: View {
    @ObservedObject var model: RelayAppModel
    @State private var pendingAction: DestructiveRelayAction?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DashboardHeader(
                    eyebrow: "End-to-end encrypted",
                    title: "Relay Cloud",
                    detail: "The Mac makes one outbound connection. Relay Cloud routes encrypted envelopes but cannot read Codex content."
                )
                RelayPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label(
                                tunnelTitle,
                                systemImage: model.cloudConnected
                                    ? "lock.shield.fill"
                                    : "network.slash"
                            )
                            .font(.headline)
                            Spacer()
                            StatusPill(
                                text: tunnelStatus,
                                ready: model.cloudConnected
                            )
                        }
                        Text(
                            model.cloudConnected
                                ? "Approvals and mutations are available while this Mac stays awake and connected."
                                : "Watches show cached summaries as stale and disable every mutation while the Mac is offline."
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        if model.cloudSignedIn {
                            Button("Sign out") {
                                Task { await model.signOutOfRelayCloud() }
                            }
                        } else {
                            Text("Use Setup to request a single-use email sign-in link.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if model.cloudSignedIn {
                    RelayPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Delete Relay Account", systemImage: "person.crop.circle.badge.minus")
                                .font(.headline)
                                .foregroundStyle(RelayPalette.danger)
                            Text("Permanently removes the account metadata, revokes this Mac and every watch, and clears Relay Cloud keys from this Mac. Codex projects stay untouched.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Button("Delete account", role: .destructive) {
                                pendingAction = .deleteAccount
                            }
                        }
                    }
                }
                RelayPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Emergency Stop", systemImage: "hand.raised.fill")
                            .font(.headline)
                            .foregroundStyle(RelayPalette.danger)
                        Text("Disconnects this Mac, revokes watch sessions, and stops the bridge. Existing Codex tasks remain on the Mac.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Stop Relay access", role: .destructive) {
                            pendingAction = .emergencyStop
                        }
                    }
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
                execute(action)
            }
            Button("Cancel", role: .cancel) { pendingAction = nil }
        } message: { action in
            Text(action.consequence)
        }
    }

    private func execute(_ action: DestructiveRelayAction) {
        pendingAction = nil
        Task {
            switch action {
            case .emergencyStop: await model.emergencyStop()
            case .deleteAccount: await model.deleteRelayAccount()
            case .revokeWatch: break
            }
        }
    }

    private var tunnelTitle: String {
        switch model.cloudTunnelPhase {
        case .signedOut: "Relay Cloud signed out"
        case let .connecting(attempt): "Connecting encrypted tunnel · attempt \(attempt)"
        case .connected: "Encrypted tunnel connected"
        case let .retrying(_, delay): "Tunnel retrying in \(delay) seconds"
        case .stopped: "Relay Cloud tunnel stopped"
        }
    }

    private var tunnelStatus: String {
        switch model.cloudTunnelPhase {
        case .signedOut: "Signed out"
        case .connecting: "Connecting"
        case .connected: "Online"
        case .retrying: "Retrying"
        case .stopped: "Stopped"
        }
    }
}

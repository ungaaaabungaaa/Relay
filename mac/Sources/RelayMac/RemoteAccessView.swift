import SwiftUI

struct RemoteAccessView: View {
    @ObservedObject var model: RelayAppModel

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
                                model.cloudConnected ? "Encrypted tunnel connected" : "Cloud disconnected",
                                systemImage: model.cloudConnected
                                    ? "lock.shield.fill"
                                    : "network.slash"
                            )
                            .font(.headline)
                            Spacer()
                            StatusPill(
                                text: model.cloudConnected ? "Online" : "Offline",
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
                                Task { await model.deleteRelayAccount() }
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
                            Task { await model.emergencyStop() }
                        }
                    }
                }
            }
        }
    }
}

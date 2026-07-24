import SwiftUI

struct RemoteAccessView: View {
    @ObservedObject var model: RelayAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DashboardHeader(
                    eyebrow: "Private transport",
                    title: "Remote access",
                    detail: "Tailscale carries traffic to this Mac. Relay still verifies every watch request cryptographically."
                )
                RelayPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label(
                                model.funnelEnabled ? "Funnel enabled" : "Disabled by safe default",
                                systemImage: model.funnelEnabled ? "network.badge.shield.half.filled" : "network.slash"
                            )
                            .font(.headline)
                            Spacer()
                            StatusPill(
                                text: model.funnelEnabled ? "Reachable" : "Private",
                                ready: !model.funnelEnabled
                            )
                        }
                        Text(
                            "Relay will enable only port 43117 after Tailscale sign-in and the local bridge security self-test both pass. The admin port is never exposed."
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }
                RelayPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Emergency Stop", systemImage: "hand.raised.fill")
                            .font(.headline)
                            .foregroundStyle(RelayPalette.danger)
                        Text("Closes Relay watch access while leaving all Codex tasks running on your Mac.")
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

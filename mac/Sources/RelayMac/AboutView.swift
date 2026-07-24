import SwiftUI

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DashboardHeader(
                    eyebrow: "Relay",
                    title: "Codex, at a glance",
                    detail: "A small, security-first remote for talking to the Codex tasks already running on your Apple silicon Mac."
                )
                RelayPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Built for round Wear OS watches", systemImage: "applewatch")
                        Label("Mac bridge stays loopback-only", systemImage: "lock.shield")
                        Label("No Relay cloud account", systemImage: "cloud.slash")
                        Label("Apache License 2.0", systemImage: "doc.text")
                    }
                    .font(.headline)
                }
                RelayPanel {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Privacy in one sentence").font(.headline)
                        Text(
                            "Your Mac talks to Codex; the watch receives narrow task controls and never stores your Codex login, repository contents, Mac password, OpenAI key, or audio history."
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

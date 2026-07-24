import SwiftUI

struct SetupView: View {
    @ObservedObject var model: RelayAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DashboardHeader(
                    eyebrow: "Start here",
                    title: "Make the watch connection boring",
                    detail: "Relay checks each moving part locally. Remote access stays off until every security check passes."
                )
                RelayPanel {
                    VStack(spacing: 16) {
                        RequirementRow(
                            icon: "terminal",
                            title: "Codex",
                            detail: "Existing Mac tasks remain the source of truth.",
                            status: model.setupState.codex
                        )
                        Divider()
                        RequirementRow(
                            icon: "network",
                            title: "Tailscale",
                            detail: "Free private transport with an optional Funnel endpoint.",
                            status: model.setupState.tailscale
                        )
                        if !model.tailscaleInstalled {
                            HStack {
                                Spacer()
                                Link(
                                    "Download Tailscale",
                                    destination: URL(string: "https://tailscale.com/download/mac")!
                                )
                                .font(.caption)
                            }
                        }
                        if !model.platformToolsReady {
                            Divider()
                            HStack {
                                Label("Android Platform Tools", systemImage: "wrench.and.screwdriver")
                                Spacer()
                                Button("Install verified tools") {
                                    Task { await model.installPlatformTools() }
                                }
                            }
                        }
                        Divider()
                        RequirementRow(
                            icon: "lock.shield",
                            title: "Bridge security",
                            detail: "Loopback binding, strong admin token, signed watch requests.",
                            status: model.setupState.bridge
                        )
                        Divider()
                        RequirementRow(
                            icon: "applewatch",
                            title: "Watch",
                            detail: model.setupState.watchPaired
                                ? "A watch is paired and active."
                                : "Install and pair your Galaxy Watch6.",
                            status: model.setupState.watchPaired ? .ready : .missing
                        )
                        Divider()
                        RequirementRow(
                            icon: "point.3.connected.trianglepath.dotted",
                            title: "Remote access",
                            detail: "Disabled by default until the safe preflight passes.",
                            status: model.setupState.remoteAccess
                        )
                    }
                }
                HStack {
                    Button("Run checks") {
                        Task { await model.refresh() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(RelayPalette.accent)
                    if let error = model.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(RelayPalette.amber)
                    }
                }
            }
        }
    }
}

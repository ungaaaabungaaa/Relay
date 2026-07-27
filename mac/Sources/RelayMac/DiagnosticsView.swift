import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var model: RelayAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DashboardHeader(
                    eyebrow: "Safe to share",
                    title: "Diagnostics",
                    detail: "Relay keeps operational facts while redacting tokens, prompts, command output, file contents, and audio."
                )
                RelayPanel {
                    Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 12) {
                        diagnosticRow("Bridge", model.bridgeState.rawValue.capitalized)
                        diagnosticRow("Codex", model.codexStatus)
                        diagnosticRow("Active watches", "\(model.activeDeviceCount)")
                        diagnosticRow("Workspace roots", "\(model.workspaces.count)")
                        diagnosticRow("Voice", model.voiceConfigured ? "Configured" : "Off")
                        diagnosticRow("Cloud environment", model.cloudEnvironmentName)
                    }
                }
                RelayPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Latest redacted event").font(.headline)
                        Text(model.diagnostic)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                Button("Refresh diagnostics") {
                    Task {
                        await model.updateSupervisorSnapshot()
                        await model.refresh()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(RelayPalette.accent)
            }
        }
    }

    @ViewBuilder
    private func diagnosticRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).fontWeight(.medium)
        }
    }
}

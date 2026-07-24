import SwiftUI

struct UpdatesView: View {
    @ObservedObject var model: RelayAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DashboardHeader(
                    eyebrow: "GitHub Releases",
                    title: "Updates",
                    detail: "Relay updates the Mac app and watch APK together, with signed metadata and digest verification."
                )
                RelayPanel {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Relay development build").font(.headline)
                            Text("Apple silicon · Wear OS 4+")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusPill(
                            text: model.updateAvailable ? "Update ready" : "Up to date",
                            ready: !model.updateAvailable
                        )
                    }
                }
                RelayPanel {
                    Label("Rollback protection", systemImage: "checkmark.shield.fill")
                        .font(.headline)
                        .foregroundStyle(RelayPalette.accent)
                    Text("A failed or older download never replaces the working Mac app or watch APK.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 5)
                }
            }
        }
    }
}

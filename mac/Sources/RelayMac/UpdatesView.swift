import SwiftUI

struct UpdatesView: View {
    @ObservedObject var model: RelayAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DashboardHeader(
                    eyebrow: "GitHub Releases",
                    title: "Updates",
                    detail: "Sparkle updates the Mac app. Google Play updates the Wear OS app independently."
                )
                RelayPanel {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Relay development build").font(.headline)
                            Text("Apple silicon · Wear OS 3+")
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
                    VStack(alignment: .leading, spacing: 7) {
                        Label("Signed manifest verification ready", systemImage: "signature")
                            .font(.headline)
                            .foregroundStyle(RelayPalette.accent)
                        Text(
                            "Relay rejects a changed byte, an Intel artifact, an invalid signature, and any version older than the installed build."
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }
                Button("Check for Mac update") {
                    model.updateController.checkForUpdates()
                }
                .buttonStyle(.borderedProminent)
                .tint(RelayPalette.accent)
                RelayPanel {
                    Label("Rollback protection", systemImage: "checkmark.shield.fill")
                        .font(.headline)
                        .foregroundStyle(RelayPalette.accent)
                    Text("A failed or older Mac download never replaces the working app. Play keeps the watch app on its signed release track.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 5)
                }
            }
        }
    }
}

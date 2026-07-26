import SwiftUI

struct UpdatesView: View {
    @ObservedObject var model: RelayAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DashboardHeader(
                    eyebrow: "GitHub Releases",
                    title: "Updates",
                    detail: "Sparkle updates the Mac app. TestFlight or the App Store updates the Apple Watch app."
                )
                RelayPanel {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Relay development build").font(.headline)
                            Text("Apple silicon · watchOS 10+")
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
                    Text("A failed or older Mac download never replaces the working app. Apple manages signed Apple Watch updates.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 5)
                }
            }
        }
    }
}

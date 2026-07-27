import SwiftUI

struct RelayMoreView: View {
    @ObservedObject var model: RelayWatchModel

    var body: some View {
        RelayAdaptiveContainer {
            actionGrid
        } scrolling: {
            actionGrid.padding(.horizontal, 4)
        }
        .navigationTitle("More")
    }

    private var actionGrid: some View {
        Grid(
            horizontalSpacing: RelayCompactLayout.materialGridSpacing,
            verticalSpacing: RelayCompactLayout.materialGridSpacing
        ) {
            GridRow {
                tile(RelayMorePresentation.actions[0])
                tile(RelayMorePresentation.actions[1])
            }
            GridRow {
                tile(RelayMorePresentation.actions[2])
                tile(RelayMorePresentation.actions[3])
            }
        }
    }

    private func tile(_ action: RelayMoreAction) -> some View {
        RelayMaterialTile(title: action.title, systemImage: action.systemImage) {
            switch action.kind {
            case .voice: model.navigate(to: .voice)
            case .refresh: Task { await model.refresh() }
            case .history: model.navigate(to: .history)
            case .settings: model.navigate(to: .settings)
            }
        }
    }
}

struct RelaySettingsView: View {
    @ObservedObject var model: RelayWatchModel
    @State private var haptics = RelayHapticPreference()
    @State private var confirmForget = false

    var body: some View {
        List {
            Section("Feedback") {
                Toggle("Haptics", isOn: Binding(
                    get: { haptics.isEnabled },
                    set: { haptics.isEnabled = $0 }
                ))
            }
            Section("Relay") {
                NavigationLink("Watch identity", value: RelayWatchRoute.identity)
                NavigationLink("About Relay", value: RelayWatchRoute.about)
            }
            Button("Forget this Watch", role: .destructive) { confirmForget = true }
                .accessibilityHint("Erases this watch's Relay credentials and requires pairing again")
                .confirmationDialog(
                    "Erase Relay credentials from this watch?",
                    isPresented: $confirmForget,
                    titleVisibility: .visible
                ) {
                    Button("Forget and erase", role: .destructive, action: model.revokeLocally)
                    Button("Cancel", role: .cancel) {}
                }
        }
        .navigationTitle("Settings")
    }
}

struct RelayIdentityView: View {
    @ObservedObject var model: RelayWatchModel

    var body: some View {
        Text(model.watchFingerprint)
            .font(.caption.monospaced())
            .multilineTextAlignment(.center)
            .navigationTitle("Watch identity")
    }
}

struct RelayAboutView: View {
    private let version = Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String ?? "0"

    var body: some View {
        LabeledContent("Version", value: version)
            .navigationTitle("About Relay")
    }
}

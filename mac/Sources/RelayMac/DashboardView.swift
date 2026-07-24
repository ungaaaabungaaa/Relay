import SwiftUI

enum DashboardSection: String, CaseIterable, Identifiable {
    case setup
    case watches
    case remoteAccess
    case workspaces
    case voice
    case updates
    case diagnostics
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .setup: "Setup"
        case .watches: "Watches"
        case .remoteAccess: "Remote Access"
        case .workspaces: "Workspaces"
        case .voice: "Voice"
        case .updates: "Updates"
        case .diagnostics: "Diagnostics"
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .setup: "checklist"
        case .watches: "applewatch"
        case .remoteAccess: "network"
        case .workspaces: "folder.badge.gearshape"
        case .voice: "waveform"
        case .updates: "arrow.triangle.2.circlepath"
        case .diagnostics: "stethoscope"
        case .about: "info.circle"
        }
    }
}

struct DashboardView: View {
    @ObservedObject var model: RelayAppModel
    @State private var selection: DashboardSection? = .setup

    var body: some View {
        NavigationSplitView {
            List(DashboardSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .navigationTitle("Relay")
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(model.bridgeState == .running ? RelayPalette.accent : RelayPalette.amber)
                        .frame(width: 7, height: 7)
                    Text(model.bridgeState == .running ? "Local bridge ready" : "Bridge needs attention")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 215)
        } detail: {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.055, green: 0.07, blue: 0.085),
                        Color(red: 0.035, green: 0.045, blue: 0.055),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                Group {
                    switch selection ?? .setup {
                    case .setup: SetupView(model: model)
                    case .watches: WatchesView(model: model)
                    case .remoteAccess: RemoteAccessView(model: model)
                    case .workspaces: WorkspacesView(model: model)
                    case .voice: VoiceView(model: model)
                    case .updates: UpdatesView(model: model)
                    case .diagnostics: DiagnosticsView(model: model)
                    case .about: AboutView()
                    }
                }
                .padding(30)
            }
        }
        .frame(minWidth: 860, minHeight: 580)
        .preferredColorScheme(.dark)
    }
}

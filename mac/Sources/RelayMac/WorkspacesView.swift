import AppKit
import SwiftUI

struct WorkspacesView: View {
    @ObservedObject var model: RelayAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DashboardHeader(
                    eyebrow: "Privacy boundary",
                    title: "Approved workspaces",
                    detail: "The watch can browse folder names only below these roots. It never reads file contents."
                )
                if model.workspaces.isEmpty {
                    EmptyPanel(
                        icon: "folder.badge.plus",
                        title: "No folders shared",
                        detail: "Add only the project roots you want available when starting a task from the watch."
                    )
                } else {
                    ForEach(model.workspaces, id: \.self) { root in
                        RelayPanel {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(RelayPalette.accent)
                                Text(root)
                                    .font(.callout.monospaced())
                                    .textSelection(.enabled)
                                Spacer()
                                Button("Remove") {
                                    Task {
                                        await model.replaceWorkspaces(
                                            model.workspaces.filter { $0 != root }
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                Button("Add folder…") {
                    chooseFolder()
                }
                .buttonStyle(.borderedProminent)
                .tint(RelayPalette.accent)
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Approve Folder"
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        Task {
            await model.replaceWorkspaces(
                Array(Set(model.workspaces + [url.path])).sorted()
            )
        }
    }
}

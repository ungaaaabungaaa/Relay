import SwiftUI

struct RelayWatchHomeView: View {
    @ObservedObject var model: RelayWatchModel

    private var items: [RelayHomeItem] {
        RelayHomePresentation.items(
            approvals: model.inbox.approvals,
            questions: model.inbox.questions,
            limit: 2
        )
    }

    private var isOffline: Bool {
        model.connection == .offline || model.cacheIsStale
    }

    var body: some View {
        RelayAdaptiveContainer {
            homeContent
        } scrolling: {
            homeContent.padding(.horizontal, 4)
        }
        .navigationTitle("Relay")
    }

    @ViewBuilder
    private var homeContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isOffline {
                RelayStatusStrip(
                    connection: model.connection,
                    cacheIsStale: model.cacheIsStale,
                    error: model.error
                )
            }

            if items.isEmpty {
                allClearActions
            } else {
                pendingActions
            }

            if isOffline {
                Button("Try again") { Task { await model.refresh() } }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var pendingActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Needs you").font(.headline)
            ForEach(items) { item in
                NavigationLink(value: item.route) {
                    Label(item.title, systemImage: item.systemImage)
                        .lineLimit(2)
                }
                .accessibilityHint("Review the exact action and its consequences")
            }
            let remaining = RelayHomePresentation.remainingCount(
                total: model.cachedInboxCount,
                visible: items.count
            )
            if remaining > 0 {
                Text("\(remaining) more waiting")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            RelayActionDock(
                primaryTitle: "Tasks",
                secondaryTitle: "More",
                primary: { model.navigate(to: .tasks) },
                secondary: { model.navigate(to: .more) }
            )
        }
    }

    private var allClearActions: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("All clear").font(.headline)
            Grid(
                horizontalSpacing: RelayCompactLayout.materialGridSpacing,
                verticalSpacing: RelayCompactLayout.materialGridSpacing
            ) {
                GridRow {
                    actionTile(RelayHomePresentation.clearActions[0])
                    actionTile(RelayHomePresentation.clearActions[1])
                }
                GridRow {
                    actionTile(RelayHomePresentation.clearActions[2])
                    actionTile(RelayHomePresentation.clearActions[3])
                }
            }
        }
    }

    private func actionTile(_ action: RelayHomeAction) -> some View {
        RelayMaterialTile(title: action.title, systemImage: action.systemImage) {
            model.navigate(to: action.route)
        }
    }
}

import SwiftUI

struct RelayTasksView: View {
    @ObservedObject var model: RelayWatchModel

    var body: some View {
        List {
            RelayStatusStrip(connection: model.connection, cacheIsStale: model.cacheIsStale, error: model.error)
            ForEach(model.tasks) { task in
                NavigationLink(value: RelayWatchRoute.task(task.id)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                        Text(task.preview).font(.caption2).lineLimit(2)
                        Text("\(task.status.rawValue.capitalized) · \(task.cwd)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Tasks")
    }
}

struct RelayTaskSummaryView: View {
    @ObservedObject var model: RelayWatchModel
    let taskID: String
    @State private var confirmStop = false

    var body: some View {
        Group {
            if let detail {
                let summary = RelayTaskPresentation.summary(detail)
                RelayAdaptiveContainer {
                    summaryContent(title: detail.title, taskID: detail.id, summary: summary)
                } scrolling: {
                    summaryContent(title: detail.title, taskID: detail.id, summary: summary)
                        .padding(.horizontal, 4)
                }
            } else if let fallbackTask {
                let summary = RelayTaskPresentation.summary(fallbackTask)
                RelayAdaptiveContainer {
                    summaryContent(title: fallbackTask.title, taskID: fallbackTask.id, summary: summary)
                } scrolling: {
                    summaryContent(title: fallbackTask.title, taskID: fallbackTask.id, summary: summary)
                        .padding(.horizontal, 4)
                }
            } else {
                ProgressView("Loading task…")
            }
        }
        .navigationTitle("Task")
        .task { await model.loadTask(taskID) }
    }

    @ViewBuilder
    private func summaryContent(title: String, taskID: String, summary: RelayTaskSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            RelayStatusStrip(connection: model.connection, cacheIsStale: model.cacheIsStale, error: model.error)
            Text(summary.statusTitle).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Label(summary.workspaceName, systemImage: "folder")
                .font(.caption2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Latest activity").font(.caption2).foregroundStyle(.secondary)
                Text(summary.latestActivityTitle).font(.caption)
            }
            Button("Instruct") { model.navigate(to: .instruction(taskID)) }
                .disabled(!canMutate)
            if summary.canStop {
                Button("Stop", role: .destructive) { confirmStop = true }
                    .disabled(!canMutate)
                    .confirmationDialog(
                        "Stop the active Codex turn?",
                        isPresented: $confirmStop,
                        titleVisibility: .visible
                    ) {
                        Button("Stop turn", role: .destructive) { stop(taskID) }
                        Button("Cancel", role: .cancel) {}
                    }
            }
            if summary.canViewActivity {
                Button("View full activity") { model.navigate(to: .activity(taskID)) }
            }
        }
    }

    private var canMutate: Bool { model.actionsEnabled && !model.mutationPending }
    private var detail: RelayTaskDetail? { model.taskDetails[taskID] }
    private var fallbackTask: RelayTask? { model.tasks.first { $0.id == taskID } }

    private func stop(_ taskID: String) {
        Task {
            do {
                try await model.stop(taskID)
                model.reportActionSuccess()
            } catch { model.reportActionFailure(error) }
        }
    }
}

struct RelayTaskActivityView: View {
    @ObservedObject var model: RelayWatchModel
    let taskID: String?

    var body: some View {
        List {
            RelayStatusStrip(connection: model.connection, cacheIsStale: model.cacheIsStale, error: model.error)
            if let task {
                Section("Activity") {
                    if task.activity.isEmpty {
                        Text(task.preview).foregroundStyle(.secondary)
                    }
                    ForEach(task.activity) { activity in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.title)
                            if let detail = activity.detail {
                                Text(detail).font(.caption2).foregroundStyle(.secondary)
                            }
                            Text(activity.status.rawValue.capitalized).font(.caption2)
                        }
                    }
                }
            } else {
                ProgressView("Loading task…")
            }
        }
        .navigationTitle("Activity")
        .task {
            if let id = taskID ?? model.selectedTaskID { await model.loadTask(id) }
        }
    }

    private var task: RelayTaskDetail? {
        guard let taskID else { return model.selectedTaskDetail }
        return model.taskDetails[taskID]
    }
}

struct RelayHistoryView: View {
    @ObservedObject var model: RelayWatchModel

    var body: some View {
        List {
            Section("This watch session") {
                if model.mutationAttempts.isEmpty {
                    Text("No actions sent yet").foregroundStyle(.secondary)
                }
                ForEach(Array(model.mutationAttempts.enumerated()), id: \.offset) { _, attempt in
                    Label(summary(attempt.action), systemImage: symbol(attempt.status))
                        .foregroundStyle(attempt.status == .failed ? .orange : .primary)
                }
            }
            Text("History is limited to this running watch session and contains no secrets.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func summary(_ action: RelayMutation) -> String {
        switch action {
        case let .approval(_, decision, _): return decision == .approve ? "Approved action" : "Denied action"
        case .question: return "Answered question"
        case .newTask: return "Started task"
        case .instruction: return "Sent instruction"
        case .steer: return "Steered active turn"
        case .stop: return "Stopped active turn"
        }
    }

    private func symbol(_ status: RelayMutationAttempt.Status) -> String {
        switch status {
        case .pending: "clock"
        case .failed: "xmark.circle"
        case .succeeded: "checkmark.circle"
        }
    }
}

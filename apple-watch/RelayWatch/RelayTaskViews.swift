import SwiftUI

struct RelayTasksView: View {
    @ObservedObject var model: RelayWatchModel

    var body: some View {
        List {
            RelayStatusStrip(connection: model.connection, cacheIsStale: model.cacheIsStale, error: model.error)
            ForEach(model.tasks) { task in
                Button {
                    model.showTask(task.id)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                        Text(task.preview).font(.caption2).lineLimit(2)
                        Text("\(task.status.rawValue.capitalized) · \(task.cwd)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            RelayBackButton(model: model)
        }
    }
}

struct RelayTaskActivityView: View {
    @ObservedObject var model: RelayWatchModel
    let taskID: String?
    @State private var confirmStop = false

    var body: some View {
        List {
            RelayStatusStrip(connection: model.connection, cacheIsStale: model.cacheIsStale, error: model.error)
            if let task {
                Section {
                    Text(task.title).font(.headline)
                    Text("\(task.status.rawValue.capitalized) · \(task.cwd)")
                        .font(.caption2.monospaced())
                }
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
                if task.activeTurnId != nil {
                    Button("Stop active turn", role: .destructive) { confirmStop = true }
                        .disabled(!canMutate)
                        .accessibilityHint("Stops the currently active Codex turn on the Mac")
                        .confirmationDialog(
                            "Stop the active Codex turn?",
                            isPresented: $confirmStop,
                            titleVisibility: .visible
                        ) {
                            Button("Stop turn", role: .destructive) { stop(task.id) }
                            Button("Cancel", role: .cancel) {}
                        }
                }
                Button("Send instruction") { model.navigate(to: .instruction(task.id)) }
            } else {
                ProgressView("Loading task…")
            }
            RelayBackButton(model: model, destination: .tasks)
        }
        .task {
            if let id = taskID ?? model.selectedTaskID { await model.loadTask(id) }
        }
    }

    private var canMutate: Bool { model.actionsEnabled && !model.mutationPending }

    private var task: RelayTaskDetail? {
        guard let taskID else { return model.selectedTaskDetail }
        return model.taskDetails[taskID]
    }

    private func stop(_ taskID: String) {
        Task {
            do {
                try await model.stop(taskID)
                model.reportActionSuccess()
            } catch { model.reportActionFailure(error) }
        }
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
            RelayBackButton(model: model)
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

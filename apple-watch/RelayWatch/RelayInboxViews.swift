import SwiftUI

struct RelayInboxView: View {
    @ObservedObject var model: RelayWatchModel

    var body: some View {
        List {
            RelayConnectionBanner(model: model)

            Section("Needs you") {
                if model.inbox.approvals.isEmpty && model.inbox.questions.isEmpty {
                    Text("Nothing needs your review")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.inbox.approvals) { approval in
                    Button {
                        model.showApproval(approval.id)
                    } label: {
                        Label(
                            approval.command ?? approval.reason ?? "Codex approval",
                            systemImage: approval.risk == .dangerous
                                ? "exclamationmark.triangle.fill" : "checkmark.shield"
                        )
                    }
                    .accessibilityHint("Review the exact action and its consequences")
                }
                ForEach(model.inbox.questions) { question in
                    Button {
                        model.showQuestion(question.id)
                    } label: {
                        Label(
                            question.questions.first?.question ?? "Codex question",
                            systemImage: "questionmark.bubble"
                        )
                    }
                    .accessibilityHint("Answer using only the options supplied by the Mac")
                }
            }

            Section("Tasks") {
                ForEach(model.tasks) { task in
                    Button {
                        model.showTask(task.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title)
                            Text("\(task.status.rawValue.capitalized) · \(task.cwd)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Button("All tasks") { model.show(.tasks) }
            }

            Section("Relay") {
                Button("New task", systemImage: "plus.circle") { model.show(.newTask) }
                Button("Voice", systemImage: "mic") { model.show(.voice) }
                Button("History", systemImage: "clock.arrow.circlepath") { model.show(.history) }
                Button("Settings", systemImage: "gearshape") { model.show(.settings) }
            }

            Button("Refresh") { Task { await model.refresh() } }
        }
    }
}

struct RelayConnectionBanner: View {
    @ObservedObject var model: RelayWatchModel

    var body: some View {
        Section {
            if model.connection == .offline || model.cacheIsStale {
                Label("Mac offline · cached data", systemImage: "wifi.slash")
                    .foregroundStyle(.orange)
                Text("Review is available, but actions stay disabled until a fresh sync.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Label("Relay live", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.mint)
            }
            if let error = model.error {
                Text(error).font(.caption2).foregroundStyle(.orange)
            }
        }
    }
}

struct RelayBackButton: View {
    @ObservedObject var model: RelayWatchModel
    var destination: RelayWatchScreen = .inbox

    var body: some View {
        Button("Back") { model.show(destination) }
    }
}

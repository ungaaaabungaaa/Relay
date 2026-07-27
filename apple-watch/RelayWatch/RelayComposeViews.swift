import SwiftUI

struct RelayInstructionView: View {
    @ObservedObject var model: RelayWatchModel
    let taskID: String?
    @State private var text = ""

    var body: some View {
        List {
            RelayConnectionBanner(model: model)
            if selectedTaskID == nil {
                Section("Task") {
                    ForEach(model.tasks) { task in
                        Button(task.title) { model.selectedTaskID = task.id }
                    }
                }
            } else if let task = selectedTask {
                Label(task.title, systemImage: "terminal")
            }
            TextField("Tell Codex what to do", text: $text)
            Button("Send instruction") { send() }
                .disabled(!canSend)
                .accessibilityHint("Sends the reviewed text to the selected Codex task")
            RelayBackButton(model: model, destination: selectedTaskID == nil ? .inbox : .activity)
        }
    }

    private var canSend: Bool {
        model.actionsEnabled && !model.mutationPending
            && selectedTaskID != nil
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedTaskID: String? { taskID ?? model.selectedTaskID }
    private var selectedTask: RelayTask? {
        selectedTaskID.flatMap { id in model.tasks.first { $0.id == id } }
    }

    private func send() {
        guard let taskID = selectedTaskID else { return }
        let reviewedText = text
        Task {
            do {
                try await model.sendText(taskID: taskID, text: reviewedText)
                text = ""
                model.reportActionSuccess()
                model.navigate(to: .activity(taskID))
            } catch { model.reportActionFailure(error) }
        }
    }
}

struct RelayNewTaskView: View {
    @ObservedObject var model: RelayWatchModel
    @State private var cwd = ""
    @State private var modelID = ""
    @State private var effort = ""
    @State private var prompt = ""

    var body: some View {
        List {
            RelayConnectionBanner(model: model)
            Section("Workspace") {
                Picker("Folder", selection: $cwd) {
                    Text("Choose").tag("")
                    ForEach(model.folders) { folder in Text(folder.name).tag(folder.path) }
                }
            }
            Section("Model") {
                Picker("Model", selection: $modelID) {
                    Text("Choose").tag("")
                    ForEach(model.models) { relayModel in
                        Text(relayModel.name).tag(relayModel.id)
                    }
                }
                Picker("Effort", selection: $effort) {
                    Text("Choose").tag("")
                    ForEach(selectedModel?.efforts ?? [], id: \.self) { Text($0).tag($0) }
                }
            }
            TextField("What should Codex do?", text: $prompt)
            Button("Start reviewed task") { start() }
                .disabled(!canStart)
                .accessibilityHint("Starts Codex in the exact workspace, model, effort, and prompt shown")
            RelayBackButton(model: model)
        }
        .task {
            await model.loadCreationOptions()
            if prompt.isEmpty, !model.newTaskDraft.isEmpty {
                prompt = model.newTaskDraft
                model.newTaskDraft = ""
            }
            chooseDefaults()
        }
        .onChange(of: modelID) { _, _ in
            effort = selectedModel?.defaultEffort ?? ""
        }
    }

    private var selectedModel: RelayModel? { model.models.first { $0.id == modelID } }
    private var canStart: Bool {
        model.actionsEnabled && !model.mutationPending && !cwd.isEmpty
            && selectedModel != nil && selectedModel?.efforts.contains(effort) == true
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func chooseDefaults() {
        if cwd.isEmpty { cwd = model.folders.first?.path ?? "" }
        if modelID.isEmpty {
            modelID = model.models.first(where: \.isDefault)?.id ?? model.models.first?.id ?? ""
        }
        if effort.isEmpty { effort = selectedModel?.defaultEffort ?? "" }
    }

    private func start() {
        let reviewedPrompt = prompt
        Task {
            do {
                try await model.startTask(
                    cwd: cwd, modelID: modelID, effort: effort, prompt: reviewedPrompt
                )
                prompt = ""
                model.reportActionSuccess()
                model.show(.tasks)
            } catch { model.reportActionFailure(error) }
        }
    }
}

struct RelaySettingsView: View {
    @ObservedObject var model: RelayWatchModel
    @State private var confirmForget = false

    var body: some View {
        List {
            RelayConnectionBanner(model: model)
            Section("Connection") {
                Text("End-to-end encrypted through Relay Cloud")
                Text("Watch fingerprint \(model.watchFingerprint)")
                    .font(.caption2.monospaced())
            }
            Text("Apple Watch updates are installed through the App Store.")
                .font(.caption2)
            Button("Forget this watch", role: .destructive) { confirmForget = true }
                .accessibilityHint("Erases this watch's Relay credentials and requires pairing again")
                .confirmationDialog(
                    "Erase Relay credentials from this watch?",
                    isPresented: $confirmForget,
                    titleVisibility: .visible
                ) {
                    Button("Forget and erase", role: .destructive, action: model.revokeLocally)
                    Button("Cancel", role: .cancel) {}
                }
            RelayBackButton(model: model)
        }
    }
}

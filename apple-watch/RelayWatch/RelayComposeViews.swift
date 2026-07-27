import SwiftUI

struct RelayInstructionView: View {
    @ObservedObject var model: RelayWatchModel
    let taskID: String?
    @State private var text = ""

    var body: some View {
        List {
            RelayStatusStrip(connection: model.connection, cacheIsStale: model.cacheIsStale, error: model.error)
            if let task = selectedTask {
                Label(task.title, systemImage: "terminal")
                TextField("Tell Codex what to do", text: $text)
                Button("Send") { send() }
                    .disabled(!canSend)
                    .accessibilityHint("Sends the reviewed text to the selected Codex task")
            } else {
                ContentUnavailableView("Choose a task", systemImage: "terminal")
            }
        }
    }

    private var canSend: Bool {
        model.actionsEnabled && !model.mutationPending
            && selectedTask != nil
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedTask: RelayTask? {
        RelayTaskPresentation.instructionTask(
            routeTaskID: taskID,
            selectedTaskID: model.selectedTaskID,
            tasks: model.tasks
        )
    }
    private var selectedTaskID: String? { selectedTask?.id }

    private func send() {
        guard let taskID = selectedTaskID else { return }
        let reviewedText = text
        Task {
            do {
                try await model.sendText(taskID: taskID, text: reviewedText)
                text = ""
                model.reportActionSuccess()
                model.navigate(to: .task(taskID))
            } catch { model.reportActionFailure(error) }
        }
    }
}

struct RelayNewTaskView: View {
    @ObservedObject var model: RelayWatchModel
    @State private var step = RelayNewTaskStep.workspace
    @State private var draft = RelayNewTaskDraft()

    var body: some View {
        List {
            RelayStatusStrip(connection: model.connection, cacheIsStale: model.cacheIsStale, error: model.error)
            switch step {
            case .workspace: workspaceStep
            case .model: modelStep
            case .prompt: promptReviewStep
            }
        }
        .task {
            await model.loadCreationOptions()
            if draft.prompt.isEmpty, !model.newTaskDraft.isEmpty {
                draft.prompt = model.newTaskDraft
                model.newTaskDraft = ""
            }
            draft.applyDefaults(folders: model.folders, models: model.models)
        }
        .onChange(of: draft.modelID) { _, _ in
            draft.effort = selectedModel?.defaultEffort ?? ""
        }
        .toolbar {
            if step != .workspace {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Previous") { step = RelayNewTaskStep(rawValue: step.rawValue - 1) ?? .workspace }
                }
            }
        }
    }

    private var workspaceStep: some View {
        Section("1 of 3 · Workspace") {
            Picker("Folder", selection: $draft.cwd) {
                Text("Choose").tag("")
                ForEach(model.folders) { folder in Text(folder.name).tag(folder.path) }
            }
            Button("Continue") { step = draft.next(after: .workspace) }
                .disabled(!draft.canAdvance(
                    from: .workspace,
                    folders: model.folders,
                    models: model.models
                ))
        }
    }

    private var modelStep: some View {
        Section("2 of 3 · Model") {
            Picker("Model", selection: $draft.modelID) {
                Text("Choose").tag("")
                ForEach(model.models) { relayModel in Text(relayModel.name).tag(relayModel.id) }
            }
            Picker("Effort", selection: $draft.effort) {
                Text("Choose").tag("")
                ForEach(selectedModel?.efforts ?? [], id: \.self) { Text($0).tag($0) }
            }
            Button("Continue") { step = draft.next(after: .model) }
                .disabled(!draft.canAdvance(
                    from: .model,
                    folders: model.folders,
                    models: model.models
                ))
        }
    }

    private var promptReviewStep: some View {
        Section("3 of 3 · Review") {
            LabeledContent("Workspace", value: selectedFolder?.name ?? draft.cwd)
            LabeledContent("Model", value: selectedModel?.name ?? draft.modelID)
            LabeledContent("Effort", value: draft.effort)
            TextField("What should Codex do?", text: $draft.prompt, axis: .vertical)
            Button(RelayNewTaskPresentation.finalActionTitle) { start() }
                .disabled(!canStart)
                .accessibilityHint("Starts Codex in the exact workspace, model, effort, and prompt shown")
        }
    }

    private var selectedModel: RelayModel? { model.models.first { $0.id == draft.modelID } }
    private var selectedFolder: RelayFolder? { model.folders.first { $0.path == draft.cwd } }
    private var canStart: Bool {
        model.actionsEnabled && !model.mutationPending
            && draft.canAdvance(from: .workspace, folders: model.folders, models: model.models)
            && draft.canAdvance(from: .model, folders: model.folders, models: model.models)
            && draft.canAdvance(from: .prompt, folders: model.folders, models: model.models)
    }

    private func start() {
        let reviewedPrompt = draft.prompt
        Task {
            do {
                try await model.startTask(
                    cwd: draft.cwd, modelID: draft.modelID, effort: draft.effort, prompt: reviewedPrompt
                )
                draft.prompt = ""
                model.reportActionSuccess()
                model.popToRoot()
                model.navigate(to: .tasks)
            } catch { model.reportActionFailure(error) }
        }
    }
}

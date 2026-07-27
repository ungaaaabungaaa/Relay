import SwiftUI

struct RelayVoiceView: View {
    @ObservedObject var model: RelayWatchModel
    @ObservedObject var controller: RelayVoiceController
    @State private var targetNewTask = false

    var body: some View {
        List {
            RelayStatusStrip(connection: model.connection, cacheIsStale: model.cacheIsStale, error: model.error)
            Section("Destination") {
                Toggle("Draft a new task", isOn: $targetNewTask)
                    .disabled(controller.phase != .idle)
                if !targetNewTask {
                    if model.selectedTaskID == nil {
                        ForEach(model.tasks) { task in
                            Button(task.title) { model.selectedTaskID = task.id }
                        }
                    } else if let task = model.selectedTask {
                        Label(task.title, systemImage: "terminal")
                    }
                }
            }
            content
            Text("Audio is processed by the transcription provider configured on your Mac. Only the transcript you review and explicitly send reaches Codex.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            RelayBackButton(model: model)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch controller.phase {
        case .idle, .failed:
            Button("Start recording", systemImage: "mic.fill") { start() }
                .disabled(!canStart)
                .accessibilityHint("Records up to 30 seconds into a temporary file")
        case .recording:
            Label("Recording · 30 seconds maximum", systemImage: "waveform")
                .foregroundStyle(.red)
            Button("Stop and transcribe") { stop() }
            Button("Cancel and erase", role: .destructive) { cancel() }
                .accessibilityHint("Stops recording and erases temporary audio without transcription")
        case .transcribing:
            ProgressView("Transcribing on Mac…")
        case .review:
            TextField("Review transcript", text: $controller.transcript, axis: .vertical)
            Button("Send reviewed text") { send() }
                .disabled(controller.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityHint("Sends only the editable transcript, not the audio file, to Codex")
            Button("Cancel and erase", role: .destructive) { cancel() }
        case .sending:
            ProgressView("Sending reviewed text…")
        }
    }

    private var canStart: Bool {
        model.actionsEnabled && !model.mutationPending
            && (targetNewTask || model.selectedTaskID != nil)
    }

    private func start() {
        let target: RelayVoiceTarget
        if targetNewTask {
            target = .newTaskPrompt
        } else if let taskID = model.selectedTaskID {
            target = .instruction(
                taskID: taskID,
                turnID: model.selectedTaskDetail?.activeTurnId
            )
        } else { return }
        Task {
            do { try await controller.start(target: target) }
            catch { model.reportActionFailure(error) }
        }
    }

    private func stop() {
        Task {
            do { try await controller.stopAndTranscribe() }
            catch { model.reportActionFailure(error) }
        }
    }

    private func send() {
        Task {
            do {
                try await controller.sendReviewedTranscript()
                model.reportActionSuccess()
            } catch { model.reportActionFailure(error) }
        }
    }

    private func cancel() { Task { await controller.cancel() } }
}

import Foundation
import SwiftUI

struct RelayVoiceView: View {
    @ObservedObject var model: RelayWatchModel
    @ObservedObject var controller: RelayVoiceController
    @State private var targetNewTask = false
    @State private var recordingStartedAt: Date?

    var body: some View {
        RelayAdaptiveContainer {
            voiceContent
        } scrolling: {
            voiceContent.padding(.horizontal, 4)
        }
        .navigationTitle("Voice")
        .onDisappear { Task { await controller.cancel() } }
    }

    private var voiceContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            destination
            phaseContent
            Text("Audio is processed by the transcription provider configured on your Mac. Only the transcript you review and explicitly send reaches Codex.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var destination: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Destination").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
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
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch controller.phase {
        case .idle:
            Button("Start recording", systemImage: "mic.fill") { start() }
                .buttonStyle(.borderedProminent)
                .disabled(!canStart)
                .accessibilityHint("Records up to 30 seconds into a temporary file")
        case .recording:
            recordingContent
        case .transcribing:
            ProgressView("Transcribing on Mac…")
        case .review:
            reviewContent
        case .sending:
            ProgressView("Sending reviewed text…")
        case .failed:
            VStack(alignment: .leading, spacing: 8) {
                Label("Voice recording needs another try", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Button("Try again", action: start)
                    .disabled(!canStart)
                Button("Erase", role: .destructive, action: cancel)
            }
        }
    }

    private var recordingContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Label("Recording · \(elapsedText(at: context.date)) / 0:30", systemImage: "waveform")
                    .foregroundStyle(.red)
            }
            Button("Stop & Transcribe", action: stop)
                .buttonStyle(.borderedProminent)
            Button("Erase", role: .destructive, action: cancel)
                .accessibilityHint("Stops recording and erases temporary audio without transcription")
        }
    }

    private var reviewContent: some View {
        RelayAdaptiveContainer {
            reviewFields
        } scrolling: {
            reviewFields.padding(.horizontal, 4)
        }
    }

    private var reviewFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Review transcript").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextField("Review transcript", text: $controller.transcript, axis: .vertical)
            Button("Send reviewed text", action: send)
                .buttonStyle(.borderedProminent)
                .disabled(controller.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityHint("Sends only the editable transcript, not the audio file, to Codex")
            Button("Erase", role: .destructive, action: cancel)
        }
    }

    private var canStart: Bool {
        model.actionsEnabled && !model.mutationPending
            && (targetNewTask || model.selectedTaskID != nil)
    }

    private func elapsedText(at date: Date) -> String {
        let elapsed = min(30, max(0, Int(date.timeIntervalSince(recordingStartedAt ?? date))))
        return String(format: "0:%02d", elapsed)
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
        recordingStartedAt = .now
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

    private func cancel() {
        recordingStartedAt = nil
        Task { await controller.cancel() }
    }
}

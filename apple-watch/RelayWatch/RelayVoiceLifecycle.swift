import Combine
import Foundation

struct RelayRecording: Equatable, Sendable {
    let fileURL: URL
    let durationMs: Int
    let contentType: String
}

@MainActor
protocol RelayAudioRecording: AnyObject {
    func start() async throws
    func stop() async throws -> RelayRecording
    func cancel() async
}

enum RelayVoiceTarget: Equatable, Sendable {
    case instruction(taskID: String, turnID: String?)
    case newTaskPrompt
}

enum RelayVoicePhase: Equatable, Sendable {
    case idle, recording, transcribing, review, sending, failed
}

enum RelayVoiceLifecycleError: Error, Equatable, Sendable {
    case invalidPhase
    case emptyTranscript
    case unsafeRecording
}

@MainActor
final class RelayVoiceController: ObservableObject {
    typealias Transcribe = @MainActor @Sendable (RelayRecording) async throws -> String
    typealias Send = @MainActor @Sendable (RelayVoiceTarget, String) async throws -> Void
    typealias Sleep = @Sendable (Duration) async throws -> Void

    @Published private(set) var phase: RelayVoicePhase = .idle
    @Published var transcript = ""
    @Published private(set) var target: RelayVoiceTarget?

    private let recorder: any RelayAudioRecording
    private let transcribe: Transcribe
    private let send: Send
    private let sleep: Sleep
    private var automaticStopTask: Task<Void, Never>?
    private var lastRecordingURL: URL?
    private var lifecycleRevision = 0
    private var automaticStopInProgress = false

    init(
        recorder: any RelayAudioRecording,
        transcribe: @escaping Transcribe,
        send: @escaping Send,
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.recorder = recorder
        self.transcribe = transcribe
        self.send = send
        self.sleep = sleep
    }

    func start(target: RelayVoiceTarget) async throws {
        if phase == .recording || phase == .transcribing || phase == .sending {
            await cancel()
        } else {
            automaticStopTask?.cancel()
            automaticStopTask = nil
            transcript = ""
            self.target = nil
            phase = .idle
        }
        transcript = ""
        self.target = target
        lifecycleRevision += 1
        let revision = lifecycleRevision
        phase = .recording
        do {
            try await recorder.start()
            guard lifecycleRevision == revision, phase == .recording else {
                await recorder.cancel()
                throw CancellationError()
            }
        } catch {
            if lifecycleRevision == revision { phase = .failed }
            throw error
        }
        automaticStopTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.sleep(.seconds(30))
                guard !Task.isCancelled else { return }
                self.automaticStopInProgress = true
                defer { self.automaticStopInProgress = false }
                try await self.stopAndTranscribe()
            } catch is CancellationError {
                return
            } catch {
                self.phase = .failed
            }
        }
    }

    func stopAndTranscribe() async throws {
        guard phase == .recording else { throw RelayVoiceLifecycleError.invalidPhase }
        let revision = lifecycleRevision
        if !automaticStopInProgress { automaticStopTask?.cancel() }
        let recording = try await recorder.stop()
        lastRecordingURL = recording.fileURL
        defer {
            remove(recording.fileURL)
            lastRecordingURL = nil
        }
        guard lifecycleRevision == revision else { throw CancellationError() }
        guard
            recording.durationMs > 0,
            recording.durationMs <= relayVoiceMaximumDurationMs,
            let size = try? recording.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
            size > 0,
            size <= relayVoiceMaximumBytes
        else {
            transcript = ""
            phase = .failed
            throw RelayVoiceLifecycleError.unsafeRecording
        }
        phase = .transcribing
        do {
            let result = try await transcribe(recording)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard lifecycleRevision == revision, phase == .transcribing else {
                throw CancellationError()
            }
            transcript = result
            guard !result.isEmpty else { throw RelayVoiceLifecycleError.emptyTranscript }
            phase = .review
        } catch {
            if lifecycleRevision == revision {
                transcript = ""
                phase = error is CancellationError ? .idle : .failed
            }
            throw error
        }
    }

    func sendReviewedTranscript() async throws {
        guard phase == .review, let target else {
            throw RelayVoiceLifecycleError.invalidPhase
        }
        let reviewed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reviewed.isEmpty else { throw RelayVoiceLifecycleError.emptyTranscript }
        let revision = lifecycleRevision
        phase = .sending
        do {
            try await send(target, reviewed)
            guard lifecycleRevision == revision, phase == .sending else {
                throw CancellationError()
            }
            transcript = ""
            self.target = nil
            phase = .idle
        } catch {
            if lifecycleRevision == revision { phase = .review }
            throw error
        }
    }

    func cancel() async {
        lifecycleRevision += 1
        automaticStopTask?.cancel()
        automaticStopTask = nil
        await recorder.cancel()
        if let lastRecordingURL { remove(lastRecordingURL) }
        lastRecordingURL = nil
        transcript = ""
        target = nil
        phase = .idle
    }

    func connectionLost() async { await cancel() }
    func appBecameInactive() async { await cancel() }
    func waitForAutomaticStop() async { await automaticStopTask?.value }

    private func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

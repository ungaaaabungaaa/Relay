import Foundation
import Testing
@testable import RelayWatchCore

@MainActor
@Test
func voiceReviewDeletesAudioAndSendsOnlyAfterExplicitSend() async throws {
    let file = FileManager.default.temporaryDirectory
        .appendingPathComponent("relay-voice-\(UUID().uuidString).m4a")
    try Data([1, 2, 3]).write(to: file)
    let recorder = VoiceRecorderFake(recording: .init(
        fileURL: file, durationMs: 1_000, contentType: "audio/mp4"
    ))
    let sent = VoiceSendRecorder()
    let controller = RelayVoiceController(
        recorder: recorder,
        transcribe: { _ in "Draft transcript" },
        send: { target, text in await sent.record(target, text) },
        sleep: { _ in }
    )

    try await controller.start(target: .instruction(taskID: "task-1", turnID: "turn-1"))
    try await controller.stopAndTranscribe()
    #expect(controller.phase == .review)
    #expect(controller.transcript == "Draft transcript")
    #expect(!FileManager.default.fileExists(atPath: file.path))
    #expect(await sent.values.isEmpty)

    controller.transcript = "Edited transcript"
    try await controller.sendReviewedTranscript()
    #expect(await sent.values == [
        .init(target: .instruction(taskID: "task-1", turnID: "turn-1"), text: "Edited transcript")
    ])
    #expect(controller.transcript.isEmpty)
}

@MainActor
@Test
func voiceTimeoutStopsAtThirtySecondsAndCancelDisconnectInactivityEraseState() async throws {
    let recorder = VoiceRecorderFake(recording: .init(
        fileURL: temporaryAudio(), durationMs: relayVoiceMaximumDurationMs,
        contentType: "audio/mp4"
    ))
    let sleeper = VoiceSleeper()
    let controller = RelayVoiceController(
        recorder: recorder,
        transcribe: { _ in "Timed transcript" },
        send: { _, _ in },
        sleep: { duration in await sleeper.sleep(duration) }
    )

    try await controller.start(target: .newTaskPrompt)
    await sleeper.release()
    await controller.waitForAutomaticStop()
    #expect(recorder.stopCount == 1)
    #expect(controller.phase == .review)

    try await controller.start(target: .newTaskPrompt)
    await controller.connectionLost()
    #expect(controller.phase == .idle)
    #expect(controller.transcript.isEmpty)
    #expect(recorder.cancelCount == 1)

    try await controller.start(target: .newTaskPrompt)
    await controller.appBecameInactive()
    #expect(controller.phase == .idle)
    #expect(recorder.cancelCount == 2)
}

@MainActor
@Test
func voiceTranscriptionFailureAndCancelDeleteTemporaryAudio() async throws {
    let failureFile = temporaryAudio()
    let recorder = VoiceRecorderFake(recording: .init(
        fileURL: failureFile, durationMs: 1_000, contentType: "audio/mp4"
    ))
    let controller = RelayVoiceController(
        recorder: recorder,
        transcribe: { _ in throw VoiceTestError.rejected },
        send: { _, _ in },
        sleep: { _ in try await Task.sleep(for: .seconds(60)) }
    )
    try await controller.start(target: .newTaskPrompt)
    await #expect(throws: VoiceTestError.rejected) { try await controller.stopAndTranscribe() }
    #expect(!FileManager.default.fileExists(atPath: failureFile.path))
    #expect(controller.transcript.isEmpty)

    let cancelFile = temporaryAudio()
    recorder.setRecording(.init(
        fileURL: cancelFile, durationMs: 500, contentType: "audio/mp4"
    ))
    try await controller.start(target: .newTaskPrompt)
    await controller.cancel()
    #expect(!FileManager.default.fileExists(atPath: cancelFile.path))
    #expect(controller.phase == .idle)
}

@MainActor
@Test
func voiceStartingAnotherRecordingDiscardsTheReviewedTranscript() async throws {
    let recorder = VoiceRecorderFake(recording: .init(
        fileURL: temporaryAudio(), durationMs: 1_000, contentType: "audio/mp4"
    ))
    let controller = RelayVoiceController(
        recorder: recorder,
        transcribe: { _ in "First reviewed transcript" },
        send: { _, _ in },
        sleep: { _ in try await Task.sleep(for: .seconds(60)) }
    )

    try await controller.start(target: .newTaskPrompt)
    try await controller.stopAndTranscribe()
    #expect(controller.phase == .review)

    let nextFile = temporaryAudio()
    recorder.setRecording(.init(fileURL: nextFile, durationMs: 1_000, contentType: "audio/mp4"))
    try await controller.start(target: .instruction(taskID: "task-1", turnID: nil))

    #expect(controller.phase == .recording)
    #expect(controller.transcript.isEmpty)
    await controller.cancel()
    #expect(!FileManager.default.fileExists(atPath: nextFile.path))
}

@MainActor
@Test
func disconnectDuringTranscriptionCannotRestoreAudioOrTranscript() async throws {
    let file = temporaryAudio()
    let recorder = VoiceRecorderFake(recording: .init(
        fileURL: file, durationMs: 1_000, contentType: "audio/mp4"
    ))
    let transcriber = BlockingTranscriber()
    let controller = RelayVoiceController(
        recorder: recorder,
        transcribe: { recording in try await transcriber.transcribe(recording) },
        send: { _, _ in },
        sleep: { _ in try await Task.sleep(for: .seconds(60)) }
    )

    try await controller.start(target: .newTaskPrompt)
    let transcription = Task { try await controller.stopAndTranscribe() }
    #expect(await transcriber.waitUntilCalled())
    await controller.connectionLost()
    await transcriber.release("late transcript")
    await #expect(throws: CancellationError.self) { try await transcription.value }

    #expect(controller.phase == .idle)
    #expect(controller.transcript.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: file.path))
}

private enum VoiceTestError: Error { case rejected }

private func temporaryAudio() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("relay-voice-\(UUID().uuidString).m4a")
    FileManager.default.createFile(atPath: url.path, contents: Data([1]))
    return url
}

@MainActor
private final class VoiceRecorderFake: RelayAudioRecording {
    private var recording: RelayRecording
    private(set) var stopCount = 0
    private(set) var cancelCount = 0

    init(recording: RelayRecording) { self.recording = recording }
    func setRecording(_ value: RelayRecording) { recording = value }
    func start() async throws {}
    func stop() async throws -> RelayRecording { stopCount += 1; return recording }
    func cancel() async {
        cancelCount += 1
        try? FileManager.default.removeItem(at: recording.fileURL)
    }
}

private actor VoiceSleeper {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    func sleep(_ duration: Duration) async {
        #expect(duration == .seconds(30))
        if released { released = false; return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        guard let continuation else { released = true; return }
        continuation.resume()
        self.continuation = nil
    }
}

private actor VoiceSendRecorder {
    struct Value: Equatable { let target: RelayVoiceTarget; let text: String }
    private(set) var values: [Value] = []
    func record(_ target: RelayVoiceTarget, _ text: String) {
        values.append(.init(target: target, text: text))
    }
}

private actor BlockingTranscriber {
    private var called = false
    private var continuation: CheckedContinuation<String, Error>?
    private var calledWaiters: [CheckedContinuation<Void, Never>] = []

    func transcribe(_ recording: RelayRecording) async throws -> String {
        called = true
        calledWaiters.forEach { $0.resume() }
        calledWaiters.removeAll()
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func waitUntilCalled() async -> Bool {
        if called { return true }
        await withCheckedContinuation { calledWaiters.append($0) }
        return true
    }

    func release(_ transcript: String) {
        continuation?.resume(returning: transcript)
        continuation = nil
    }
}

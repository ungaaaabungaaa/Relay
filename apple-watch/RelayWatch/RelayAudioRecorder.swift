import AVFoundation
import Foundation

@MainActor
final class RelayAudioRecorder: NSObject, RelayAudioRecording {
    private var recorder: AVAudioRecorder?
    private var startedAt: Date?
    private var recordingURL: URL?

    func start() async throws {
        await cancel()
        guard await microphonePermission() else {
            throw RelayAudioRecorderError.permissionDenied
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .spokenAudio)
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-watch-voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 48_000,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.prepareToRecord()
            guard recorder.record() else { throw RelayAudioRecorderError.couldNotStart }
            self.recorder = recorder
            recordingURL = url
            startedAt = Date()
        } catch {
            try? FileManager.default.removeItem(at: url)
            try? session.setActive(false)
            throw error
        }
    }

    func stop() async throws -> RelayRecording {
        guard let recorder, let url = recordingURL, let startedAt else {
            throw RelayAudioRecorderError.notRecording
        }
        recorder.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
        self.recorder = nil
        recordingURL = nil
        self.startedAt = nil
        let duration = max(1, Int(Date().timeIntervalSince(startedAt) * 1_000))
        return RelayRecording(fileURL: url, durationMs: duration, contentType: "audio/mp4")
    }

    func cancel() async {
        recorder?.stop()
        recorder = nil
        startedAt = nil
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
        recordingURL = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func microphonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

enum RelayAudioRecorderError: Error {
    case notRecording
    case couldNotStart
    case permissionDenied
}

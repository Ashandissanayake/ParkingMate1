import Foundation
import AVFoundation
import Speech
import Observation

enum VoiceNoteError: LocalizedError {
    case microphoneDenied, speechDenied, recognizerUnavailable, recordingFailed
    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "Microphone access is off. Enable it in Settings > ParkingMate."
        case .speechDenied: "Speech recognition access is off. Your note was saved without a transcript."
        case .recognizerUnavailable: "Speech recognition isn't available right now. Your note was saved without a transcript."
        case .recordingFailed: "Couldn't start recording."
        }
    }
}
@MainActor
@Observable
final class VoiceNoteService: NSObject, AVAudioPlayerDelegate {
    private(set) var isRecording = false
    private(set) var isPlaying = false
    private(set) var isTranscribing = false
    private(set) var level: Double = 0
    private(set) var elapsed: TimeInterval = 0

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var meterTimer: Timer?

    func startRecording() async throws -> String {
        guard await AVAudioApplication.requestRecordPermission() else { throw VoiceNoteError.microphoneDenied }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        let fileName = "\(UUID().uuidString).m4a"
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: VoiceNoteStorage.url(for: fileName), settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw VoiceNoteError.recordingFailed }
        self.recorder = recorder
        isRecording = true
        elapsed = 0
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateMeter() }
        }
        return fileName
    }

    func stopRecording() {
        recorder?.stop()
        recorder = nil
        meterTimer?.invalidate()
        meterTimer = nil
        isRecording = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func updateMeter() {
        guard let recorder, recorder.isRecording else { return }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        level = Double(max(0, min(1, (power + 50) / 50)))
        elapsed = recorder.currentTime
    }

    func play(fileName: String) {
        stopPlayback()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        guard let player = try? AVAudioPlayer(contentsOf: VoiceNoteStorage.url(for: fileName)) else { return }
        player.delegate = self
        player.play()
        self.player = player
        isPlaying = true
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.isPlaying = false }
    }

    func transcribe(fileName: String) async throws -> String {
        let status = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard status == .authorized else { throw VoiceNoteError.speechDenied }
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(),
              recognizer.isAvailable else { throw VoiceNoteError.recognizerUnavailable }

        isTranscribing = true
        defer { isTranscribing = false }

        let request = SFSpeechURLRecognitionRequest(url: VoiceNoteStorage.url(for: fileName))
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }
                if let result, result.isFinal {
                    finished = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else if let error {
                    finished = true
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func deleteFile(named fileName: String) {
        try? FileManager.default.removeItem(at: VoiceNoteStorage.url(for: fileName))
    }
}


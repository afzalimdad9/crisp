import Foundation
import Observation

/// Coordinates transcription for a clip: extracts its audio once, then runs that
/// audio through the selected `TranscriptionProvider` (on-device today; cloud in
/// a later phase). Publishes a coarse `status` for the progress overlay.
///
/// The public surface (`modelName`, `status`, `transcribe(clip:)`) is unchanged
/// from when this type wrapped WhisperKit directly — the WhisperKit logic now
/// lives in `LocalWhisperProvider`.
@Observable
@MainActor
final class Transcriber {
    enum Status: Equatable {
        case idle
        case preparingModel
        case extractingAudio
        case transcribing
        case uploading
        case cloudTranscribing
        case done
        case failed(String)
    }

    var status: Status = .idle

    /// WhisperKit model identifier. Default chosen for the best speed/accuracy
    /// balance on Apple Silicon; configurable in Settings.
    var modelName = "large-v3-v20240930_turbo"

    private let local = LocalWhisperProvider()
    /// The cloud provider, injected by `AppState` (nil until signed-in plumbing
    /// is set up). Selected when `useCloud` is true for a run.
    var cloudProvider: TranscriptionProvider?
    /// Set by `AppState` per run after it resolves on-device vs cloud routing.
    var useCloud = false

    /// Transcribes a clip, returning time-aligned words in the clip's timebase.
    func transcribe(clip: MediaClip) async throws -> [Word] {
        status = .extractingAudio
        let audioURL = try await AudioExtractor.extractAudio(from: clip.url)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        local.modelName = modelName
        let provider = self.provider()

        let words = try await provider.transcribe(audioURL: audioURL, clipID: clip.id) { [weak self] phase in
            self?.status = Status(phase)
        }
        status = .done
        return words
    }

    /// Picks the provider for this run: cloud when requested and available,
    /// otherwise on-device.
    private func provider() -> TranscriptionProvider {
        if useCloud, let cloudProvider { return cloudProvider }
        return local
    }
}

private extension Transcriber.Status {
    init(_ phase: TranscriptionPhase) {
        switch phase {
        case .preparingModel:    self = .preparingModel
        case .transcribing:      self = .transcribing
        case .uploading, .queued: self = .uploading
        case .cloudTranscribing: self = .cloudTranscribing
        }
    }
}

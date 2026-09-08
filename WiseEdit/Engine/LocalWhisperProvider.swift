import Foundation
import WhisperKit

/// On-device transcription via WhisperKit, with word-level timestamps. The model
/// is loaded lazily on first use and cached for the session; the first ever run
/// downloads it (one-time, then fully offline). Operates on an already-extracted
/// audio file supplied by the coordinator.
@MainActor
final class LocalWhisperProvider: TranscriptionProvider {
    /// WhisperKit model identifier (configurable in Settings).
    var modelName = "large-v3-v20240930_turbo"

    private var whisperKit: WhisperKit?
    private var loadedModelName: String?

    func transcribe(
        audioURL: URL,
        clipID: UUID,
        onPhase: @escaping @MainActor (TranscriptionPhase) -> Void
    ) async throws -> [Word] {
        try await prepareIfNeeded(onPhase: onPhase)
        guard let whisperKit else { throw NSError(domain: "WiseEdit", code: 1) }

        onPhase(.transcribing)
        let options = DecodingOptions(wordTimestamps: true)
        let results = try await whisperKit.transcribe(audioPath: audioURL.path, decodeOptions: options)
        return Self.flatten(results, clipID: clipID)
    }

    /// Loads (and downloads, if needed) the model. Reuses an already-loaded one.
    private func prepareIfNeeded(onPhase: @escaping @MainActor (TranscriptionPhase) -> Void) async throws {
        if whisperKit != nil, loadedModelName == modelName { return }
        onPhase(.preparingModel)
        let config = WhisperKitConfig(model: modelName)
        whisperKit = try await WhisperKit(config)
        loadedModelName = modelName
    }

    /// Flattens WhisperKit segments into our `Word` model.
    private static func flatten(_ results: [TranscriptionResult], clipID: UUID) -> [Word] {
        var words: [Word] = []
        for result in results {
            for segment in result.segments {
                guard let timings = segment.words else { continue }
                for timing in timings {
                    let text = timing.word.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    words.append(
                        Word(
                            text: text,
                            start: Double(timing.start),
                            end: Double(timing.end),
                            clipID: clipID,
                            probability: Double(timing.probability)
                        )
                    )
                }
            }
        }
        return words.sorted { $0.start < $1.start }
    }
}

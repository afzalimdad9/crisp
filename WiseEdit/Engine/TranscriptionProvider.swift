import Foundation

/// A source of word-timestamped transcription for an already-extracted audio
/// file. Today there's one implementation — `LocalWhisperProvider` (on-device
/// WhisperKit). A `CloudTranscriptionProvider` will be added for users who can't
/// run the model locally. The audio `.m4a` is extracted once by the coordinator
/// (`Transcriber`) and handed to whichever provider is selected, so neither
/// provider re-extracts and no video ever leaves the device.
protocol TranscriptionProvider: AnyObject {
    /// Transcribe an extracted audio file into words in the clip's own timebase.
    /// `onPhase` reports coarse progress for the UI; it is always called on the
    /// main actor.
    func transcribe(
        audioURL: URL,
        clipID: UUID,
        onPhase: @escaping @MainActor (TranscriptionPhase) -> Void
    ) async throws -> [Word]
}

/// Coarse progress phases a provider reports as it works. The on-device cases are
/// used today; the cloud cases are wired up in a later phase.
enum TranscriptionPhase: Equatable {
    // On-device
    case preparingModel
    case transcribing
    // Cloud (used from the cloud phase onward)
    case uploading(Double)   // 0…1
    case queued
    case cloudTranscribing
}

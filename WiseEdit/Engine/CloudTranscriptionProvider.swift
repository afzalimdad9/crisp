import Foundation
import AVFoundation

/// Transcribes via the Crisp cloud backend (Deepgram) for users who can't or
/// don't want to run the model on-device. Uploads the already-extracted audio,
/// charges the user's cloud minutes, and maps the result back into `Word`s.
@MainActor
final class CloudTranscriptionProvider: TranscriptionProvider {
    private let api = APIClient()
    /// Supplies the current session token (from `AccountStore`), or nil if signed out.
    private let tokenProvider: () -> String?

    init(tokenProvider: @escaping () -> String?) {
        self.tokenProvider = tokenProvider
    }

    func transcribe(
        audioURL: URL,
        clipID: UUID,
        onPhase: @escaping @MainActor (TranscriptionPhase) -> Void
    ) async throws -> [Word] {
        guard let token = tokenProvider() else { throw APIError.notSignedIn }

        let durationSec = (try? await AVURLAsset(url: audioURL).load(.duration).seconds) ?? 0
        let audioData = try Data(contentsOf: audioURL)

        onPhase(.uploading(0))
        onPhase(.cloudTranscribing)
        let response = try await api.transcribe(
            audioData: audioData,
            filename: audioURL.lastPathComponent,
            mimeType: "audio/m4a",
            durationSec: durationSec,
            token: token)

        return response.words.map {
            Word(text: $0.text, start: $0.start, end: $0.end, clipID: clipID, probability: $0.confidence)
        }
    }
}

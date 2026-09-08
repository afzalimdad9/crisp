import AVFoundation

/// Extracts a clip's audio track to a temporary `.m4a` so WhisperKit can read it
/// (WhisperKit loads audio files, not video containers).
enum AudioExtractor {
    enum ExtractError: LocalizedError {
        case noAudioTrack
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .noAudioTrack: return "This clip has no audio track to transcribe."
            case .exportFailed(let message): return "Couldn't extract audio: \(message)"
            }
        }
    }

    static func extractAudio(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { throw ExtractError.noAudioTrack }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ExtractError.exportFailed("could not create export session")
        }
        export.outputURL = outputURL
        export.outputFileType = .m4a

        await withCheckedContinuation { continuation in
            export.exportAsynchronously { continuation.resume() }
        }

        guard export.status == .completed else {
            throw ExtractError.exportFailed(export.error?.localizedDescription ?? "unknown error")
        }
        return outputURL
    }
}

import AVFoundation
import AppKit
import UniformTypeIdentifiers

enum ExportError: LocalizedError {
    case cannotCreateSession
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cannotCreateSession: return "Couldn't create an export session."
        case .failed(let message): return message
        }
    }
}

/// Renders an edited composition to a file via `AVAssetExportSession`, reporting
/// progress. Cutting requires a re-encode; we use the highest-quality preset.
enum Exporter {
    static func export(
        composition: AVComposition,
        to outputURL: URL,
        fileType: AVFileType = .mp4,
        onProgress: @escaping (Double) -> Void
    ) async throws {
        try? FileManager.default.removeItem(at: outputURL)

        guard let session = AVAssetExportSession(asset: composition,
                                                 presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.cannotCreateSession
        }
        session.outputURL = outputURL
        session.outputFileType = fileType

        let poller = Task { @MainActor in
            while !Task.isCancelled {
                onProgress(Double(session.progress))
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }

        await withCheckedContinuation { continuation in
            session.exportAsynchronously { continuation.resume() }
        }
        poller.cancel()

        guard session.status == .completed else {
            throw ExportError.failed(session.error?.localizedDescription ?? "Export failed.")
        }
        onProgress(1.0)
    }
}

/// Presents the system save panel for choosing the export destination.
@MainActor
enum ExportPanel {
    static func presentSavePanel(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export Video"
        panel.prompt = "Export"
        panel.nameFieldStringValue = "\(suggestedName).mp4"
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}

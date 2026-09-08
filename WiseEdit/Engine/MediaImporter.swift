import AppKit
import UniformTypeIdentifiers

/// Presents the system open panel for picking video files.
enum MediaImporter {
    static let supportedTypes: [UTType] = [.movie, .video, .mpeg4Movie, .quickTimeMovie]

    @MainActor
    static func presentOpenPanel() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "Import Clips"
        panel.prompt = "Import"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = supportedTypes
        return panel.runModal() == .OK ? panel.urls : []
    }
}

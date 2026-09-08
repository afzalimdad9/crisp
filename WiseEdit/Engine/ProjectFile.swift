import Foundation
import AppKit
import UniformTypeIdentifiers

/// Reads/writes `.wiseproj` documents (JSON) and presents open/save panels.
/// The project is non-destructive: it references source clips by URL and stores
/// the transcript + edit decisions.
enum ProjectFile {
    static let fileExtension = "wiseproj"

    /// The registered exported type (declared in Info.plist). Falls back to the
    /// extension-derived type, which matches `.wiseproj` files on disk.
    static var contentType: UTType {
        UTType("com.wisedt.wiseproj")
            ?? UTType(filenameExtension: fileExtension)
            ?? .json
    }

    /// All types the open panel should accept (so saved files are never grayed
    /// out, even if the exported type hasn't been registered yet).
    private static var openableTypes: [UTType] {
        var types = [contentType]
        if let ext = UTType(filenameExtension: fileExtension) { types.append(ext) }
        types.append(.json)
        return types
    }

    static func encode(_ project: Project) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(project)
    }

    static func decode(_ data: Data) throws -> Project {
        try JSONDecoder().decode(Project.self, from: data)
    }

    @MainActor
    static func openPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open Project"
        panel.allowedContentTypes = openableTypes
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    static func savePanel(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save Project"
        panel.nameFieldStringValue = "\(suggestedName).\(fileExtension)"
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}

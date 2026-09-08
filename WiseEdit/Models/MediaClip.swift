import Foundation

/// A source video file imported into the project. Source files are never
/// modified — clips are referenced by URL and edited non-destructively.
struct MediaClip: Identifiable, Hashable, Codable {
    let id: UUID
    var url: URL
    var displayName: String
    /// Duration in seconds. 0 until the asset has been loaded.
    var duration: Double
    /// Position in the stitched timeline (0-based).
    var orderIndex: Int

    init(
        id: UUID = UUID(),
        url: URL,
        displayName: String? = nil,
        duration: Double = 0,
        orderIndex: Int = 0
    ) {
        self.id = id
        self.url = url
        self.displayName = displayName ?? url.deletingPathExtension().lastPathComponent
        self.duration = duration
        self.orderIndex = orderIndex
    }
}

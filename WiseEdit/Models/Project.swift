import Foundation

/// The editable document. Persisted as `.wiseproj` (JSON) in a later milestone.
/// Holds source clips and (later) the word-timestamped transcript + edit
/// decisions. Everything here is non-destructive metadata over the originals.
struct Project: Codable {
    var name: String = "Untitled"
    var clips: [MediaClip] = []
    var transcript = Transcript()

    /// Clips in stitch order.
    var orderedClips: [MediaClip] {
        clips.sorted { $0.orderIndex < $1.orderIndex }
    }

    var isEmpty: Bool { clips.isEmpty }
}

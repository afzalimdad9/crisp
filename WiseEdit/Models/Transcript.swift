import Foundation

/// A single transcribed word, time-aligned to its source clip. This is the unit
/// of editing: deleting a word removes its time range from the output.
struct Word: Identifiable, Hashable, Codable {
    var id = UUID()
    var text: String
    /// Start/end in the source clip's timebase, seconds.
    var start: Double
    var end: Double
    var clipID: UUID
    /// Whisper confidence 0…1.
    var probability: Double = 1

    // Edit + detection flags.
    var isDeleted = false
    /// Forces a cut after this word even though it's kept — used to tighten a
    /// long pause (silence trim) without deleting any speech.
    var cutAfter = false
    var isFiller = false
    var isRetake = false
    var inSilenceGap = false

    var duration: Double { max(0, end - start) }
}

/// Ordered, time-aligned words spanning the project's clips. The output video is
/// rebuilt from the non-deleted words' time ranges.
struct Transcript: Codable {
    var words: [Word] = []

    var isEmpty: Bool { words.isEmpty }

    /// Words that survive the current edit, in order.
    var keptWords: [Word] { words.filter { !$0.isDeleted } }
}

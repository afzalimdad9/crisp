import AVFoundation

/// The result of assembling an edit: a playable/exportable composition plus a
/// map from each kept word to its start time in the *edited* timeline (used to
/// seek the preview when a word is clicked).
/// One kept run in the edited timeline, with its source range — used to draw the
/// timeline (cut markers appear at the joins between segments).
struct EditSegment: Hashable {
    let clipID: UUID
    let sourceStart: Double
    let sourceEnd: Double
    let editedStart: Double
    var length: Double { sourceEnd - sourceStart }
    var editedEnd: Double { editedStart + length }
}

struct BuiltComposition {
    let composition: AVMutableComposition
    let duration: Double
    let wordStarts: [UUID: Double]
    let segments: [EditSegment]
}

/// Turns the transcript's *kept* words into an `AVMutableComposition` by
/// concatenating the source time ranges they cover. Deleted words break the
/// runs, so their time is dropped. This is both the cut engine and (in M7) the
/// multi-clip stitch engine.
///
/// We insert whole-asset time ranges (`insertTimeRange(_:of:at:)`) so
/// AVFoundation matches video+audio tracks itself and keeps them in sync.
enum CompositionBuilder {
    /// Small pads reduce clipped word edges; tuned conservatively.
    static let leadPad = 0.03
    static let tailPad = 0.06
    private static let timescale: CMTimeScale = 600

    static func build(project: Project) async throws -> BuiltComposition? {
        let words = orderedWords(in: project)
        guard words.contains(where: { !$0.isDeleted }) else { return nil }

        let composition = AVMutableComposition()
        let clipsByID = Dictionary(uniqueKeysWithValues: project.clips.map { ($0.id, $0) })

        // Cache the loaded asset per clip.
        var cache: [UUID: (asset: AVURLAsset, duration: Double)] = [:]
        func source(for clipID: UUID) async throws -> (asset: AVURLAsset, duration: Double)? {
            if let hit = cache[clipID] { return hit }
            guard let clip = clipsByID[clipID] else { return nil }
            let asset = AVURLAsset(url: clip.url)
            _ = try await asset.load(.tracks) // ensure tracks are loaded before insert
            let duration = (try? await asset.load(.duration).seconds) ?? clip.duration
            let entry = (asset, duration)
            cache[clipID] = entry
            return entry
        }

        var cursor = CMTime.zero
        var wordStarts: [UUID: Double] = [:]
        var segments: [EditSegment] = []

        // Accumulate a run of contiguous kept words, then flush it as one segment.
        var segClip: UUID?
        var segStart: Double?
        var segEnd = 0.0
        var segWords: [Word] = []

        func reset() { segClip = nil; segStart = nil; segEnd = 0; segWords = [] }

        func flush() async throws {
            defer { reset() }
            guard let clipID = segClip, let rawStart = segStart,
                  let src = try await source(for: clipID) else { return }
            let start = max(0, rawStart - leadPad)
            let end = min(src.duration, segEnd + tailPad)
            guard end > start else { return }

            let range = CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: timescale),
                end: CMTime(seconds: end, preferredTimescale: timescale))

            try await composition.insertTimeRange(range, of: src.asset, at: cursor)

            let base = cursor.seconds
            for w in segWords { wordStarts[w.id] = base + (w.start - start) }
            segments.append(EditSegment(clipID: clipID, sourceStart: start, sourceEnd: end, editedStart: base))
            cursor = cursor + range.duration
        }

        for word in words {
            if word.isDeleted { try await flush(); continue }
            if segClip != word.clipID { try await flush(); segClip = word.clipID }
            if segStart == nil { segStart = word.start }
            segEnd = max(segEnd, word.end)
            segWords.append(word)
            if word.cutAfter { try await flush() } // tighten a trailing pause
        }
        try await flush()

        return BuiltComposition(composition: composition,
                                duration: cursor.seconds,
                                wordStarts: wordStarts,
                                segments: segments)
    }

    /// Words ordered by clip stitch order, then by start time.
    private static func orderedWords(in project: Project) -> [Word] {
        let order = Dictionary(uniqueKeysWithValues: project.clips.map { ($0.id, $0.orderIndex) })
        return project.transcript.words.sorted {
            let a = order[$0.clipID] ?? 0, b = order[$1.clipID] ?? 0
            return a == b ? $0.start < $1.start : a < b
        }
    }
}

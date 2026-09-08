import Foundation

/// Flags long gaps between consecutive kept words (dead air) so they can be
/// tightened. Uses word timestamps; gaps spanning two clips are left to the
/// stitch logic (M7).
struct SilenceDetector {
    var threshold: Double = 0.6

    func detect(in words: [Word]) -> [Detection] {
        let active = words.filter { !$0.isDeleted }
        guard active.count > 1 else { return [] }

        var result: [Detection] = []
        for i in 0..<(active.count - 1) {
            let a = active[i], b = active[i + 1]
            guard a.clipID == b.clipID else { continue }
            let gap = b.start - a.end
            if gap > threshold {
                result.append(Detection(
                    kind: .silence,
                    wordIDs: [a.id],
                    label: String(format: "Pause %.1fs", gap),
                    startTime: a.end,
                    clipID: a.clipID,
                    gap: gap))
            }
        }
        return result
    }
}

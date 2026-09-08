import Foundation

/// Finds adjacent near-duplicate utterances (you flubbed a line and re-said it)
/// and suggests deleting the *earlier* take, keeping the cleaner later one.
struct RetakeDetector {
    var threshold = 0.8
    var minTokens = 3
    /// A pause longer than this also ends an utterance.
    var pauseSplit = 0.7

    private struct Utterance {
        var words: [Word]
        var tokens: [String]
        var text: String
    }

    func detect(in words: [Word]) -> [Detection] {
        let active = words.filter { !$0.isDeleted }
        let utterances = split(active)
        guard utterances.count > 1 else { return [] }

        var result: [Detection] = []
        var i = 0
        while i + 1 < utterances.count {
            let a = utterances[i], b = utterances[i + 1]
            if a.tokens.count >= minTokens, b.tokens.count >= minTokens,
               similarity(a.tokens, b.tokens) >= threshold {
                if let first = a.words.first {
                    result.append(Detection(kind: .retake, wordIDs: a.words.map(\.id),
                                            label: a.text, startTime: first.start, clipID: first.clipID))
                }
                i += 2 // keep the later take, move past both
            } else {
                i += 1
            }
        }
        return result
    }

    private func split(_ words: [Word]) -> [Utterance] {
        var utterances: [Utterance] = []
        var current: [Word] = []

        func flush() {
            guard !current.isEmpty else { return }
            let tokens = current.map { TextNormalize.word($0.text) }.filter { !$0.isEmpty }
            utterances.append(Utterance(words: current,
                                        tokens: tokens,
                                        text: current.map(\.text).joined(separator: " ")))
            current = []
        }

        for (idx, w) in words.enumerated() {
            current.append(w)
            let endsSentence = w.text.last.map { ".!?".contains($0) } ?? false
            var bigPause = false
            if idx + 1 < words.count {
                let next = words[idx + 1]
                bigPause = next.clipID == w.clipID && (next.start - w.end) > pauseSplit
            }
            if endsSentence || bigPause { flush() }
        }
        flush()
        return utterances
    }

    /// 1 − normalized word-level edit distance.
    private func similarity(_ a: [String], _ b: [String]) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let dist = levenshtein(a, b)
        return 1.0 - Double(dist) / Double(max(a.count, b.count))
    }

    private func levenshtein(_ a: [String], _ b: [String]) -> Int {
        var prev = Array(0...b.count)
        var curr = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            curr[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[b.count]
    }
}

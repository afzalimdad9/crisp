import Foundation

/// Configurable filler dictionary (editable in Settings, M10).
struct FillerConfig: Codable {
    var singleWords: [String]
    var phrases: [String]

    static let fallback = FillerConfig(
        singleWords: ["um", "uh", "uhh", "umm", "er", "err", "erm", "ah", "ahh",
                      "eh", "hmm", "mm", "mhm", "mmm", "basically", "literally", "actually"],
        phrases: ["you know", "i mean", "sort of", "kind of"])
}

/// Flags filler words and multi-word discourse markers by matching the
/// (normalized) transcript against a dictionary.
struct FillerDetector {
    let singleWords: Set<String>
    let phrases: [[String]]

    init(config: FillerConfig) {
        singleWords = Set(config.singleWords.map(TextNormalize.word))
        phrases = config.phrases
            .map { $0.split(separator: " ").map { TextNormalize.word(String($0)) } }
            .filter { !$0.isEmpty }
    }

    /// Loads the bundled dictionary, falling back to a built-in list.
    static func make() -> FillerDetector {
        if let url = Bundle.main.url(forResource: "fillers", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let config = try? JSONDecoder().decode(FillerConfig.self, from: data) {
            return FillerDetector(config: config)
        }
        return FillerDetector(config: .fallback)
    }

    func detect(in words: [Word]) -> [Detection] {
        let norm = words.map { TextNormalize.word($0.text) }
        var result: [Detection] = []
        var i = 0
        while i < words.count {
            if words[i].isDeleted { i += 1; continue }

            if let len = matchPhrase(norm, at: i) {
                let ids = (i..<(i + len)).map { words[$0].id }
                let label = (i..<(i + len)).map { words[$0].text }.joined(separator: " ")
                result.append(Detection(kind: .filler, wordIDs: ids, label: label,
                                        startTime: words[i].start, clipID: words[i].clipID))
                i += len
                continue
            }

            if !norm[i].isEmpty, singleWords.contains(norm[i]) {
                result.append(Detection(kind: .filler, wordIDs: [words[i].id], label: words[i].text,
                                        startTime: words[i].start, clipID: words[i].clipID))
            }
            i += 1
        }
        return result
    }

    /// Returns the length of the longest dictionary phrase matching at `i`.
    private func matchPhrase(_ norm: [String], at i: Int) -> Int? {
        for phrase in phrases.sorted(by: { $0.count > $1.count }) where i + phrase.count <= norm.count {
            if (0..<phrase.count).allSatisfy({ norm[i + $0] == phrase[$0] }) {
                return phrase.count
            }
        }
        return nil
    }
}

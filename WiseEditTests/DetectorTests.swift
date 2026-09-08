import XCTest
@testable import WiseEdit

final class DetectorTests: XCTestCase {
    private let clip = UUID()

    private func makeWords(_ specs: [(String, Double, Double)]) -> [Word] {
        specs.map { Word(text: $0.0, start: $0.1, end: $0.2, clipID: clip) }
    }

    // MARK: Filler

    func testFillerDetectsSingleAndPhrases() {
        let words = makeWords([
            ("So", 0.0, 0.2), ("um,", 0.2, 0.5), ("welcome", 0.9, 1.3),
            ("you", 8.5, 8.7), ("know,", 8.7, 8.9), ("it", 9.2, 9.3),
            ("is", 9.3, 9.4), ("basically", 9.4, 9.8), ("simple.", 9.8, 10.2),
        ])
        let detector = FillerDetector(config: .fallback)
        let hits = detector.detect(in: words)
        let labels = hits.map { $0.label.lowercased() }

        XCTAssertTrue(labels.contains { $0.contains("um") }, "should catch 'um'")
        XCTAssertTrue(labels.contains { $0.contains("you know") }, "should catch 'you know' phrase")
        XCTAssertTrue(labels.contains { $0.contains("basically") }, "should catch 'basically'")
        // "you know" should be a single 2-word detection
        XCTAssertTrue(hits.contains { $0.wordIDs.count == 2 })
    }

    func testFillerIgnoresNormalWords() {
        let words = makeWords([("welcome", 0, 0.4), ("to", 0.4, 0.5), ("my", 0.5, 0.6), ("channel", 0.6, 1.0)])
        XCTAssertTrue(FillerDetector(config: .fallback).detect(in: words).isEmpty)
    }

    // MARK: Silence

    func testSilenceDetectsLongGap() {
        let words = makeWords([
            ("editing.", 4.5, 4.9),  // big gap here (1.45s)
            ("Today", 6.35, 6.6),
            ("next", 6.7, 6.9),      // small gap (ok)
        ])
        let hits = SilenceDetector(threshold: 0.6).detect(in: words)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].wordIDs.first, words[0].id, "gap is flagged on the word before it")
        XCTAssertEqual(hits[0].gap, 1.45, accuracy: 0.01)
    }

    // MARK: Retake

    func testRetakeDetectsRepeatedSentence() {
        // "today i want to talk about a video editing." then the cleaner repeat.
        let first = makeWords([
            ("Today", 2.3, 2.5), ("I", 2.5, 2.7), ("want", 2.7, 2.9), ("to", 2.9, 3.0),
            ("talk", 3.0, 3.2), ("about", 3.2, 3.5), ("a", 3.5, 3.6),
            ("video", 4.0, 4.5), ("editing.", 4.5, 4.9),
        ])
        let second = makeWords([
            ("Today", 6.35, 6.5), ("I", 6.5, 6.7), ("want", 6.7, 6.9), ("to", 6.9, 7.0),
            ("talk", 7.0, 7.2), ("about", 7.2, 7.46), ("video", 7.46, 7.78), ("editing.", 7.78, 8.14),
        ])
        let hits = RetakeDetector().detect(in: first + second)
        XCTAssertEqual(hits.count, 1, "one retake pair")
        // the EARLIER take (the one containing the stray 'a') is the one to cut
        XCTAssertEqual(hits[0].wordIDs.first, first[0].id)
        XCTAssertTrue(hits[0].label.lowercased().contains("today"))
    }

    func testRetakeIgnoresDistinctSentences() {
        let words = makeWords([
            ("Welcome", 0, 0.4), ("to", 0.4, 0.5), ("my", 0.5, 0.6), ("channel.", 0.6, 1.0),
            ("Let's", 1.2, 1.5), ("get", 1.5, 1.7), ("started", 1.7, 2.1), ("now.", 2.1, 2.4),
        ])
        XCTAssertTrue(RetakeDetector().detect(in: words).isEmpty)
    }
}

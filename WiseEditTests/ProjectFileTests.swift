import XCTest
@testable import WiseEdit

/// Verifies a project round-trips through `.wiseproj` with all edit decisions
/// (cuts, flags, clip order, ids) intact.
final class ProjectFileTests: XCTestCase {
    func testRoundTripPreservesEditDecisions() throws {
        let clip = MediaClip(url: URL(fileURLWithPath: "/tmp/a.mov"), duration: 12.3, orderIndex: 0)
        var project = Project(name: "Demo")
        project.clips = [clip]

        var w1 = Word(text: "hello", start: 0, end: 0.5, clipID: clip.id)
        w1.cutAfter = true
        var w2 = Word(text: "um", start: 0.6, end: 0.9, clipID: clip.id)
        w2.isDeleted = true
        w2.isFiller = true
        project.transcript.words = [w1, w2]

        let restored = try ProjectFile.decode(ProjectFile.encode(project))

        XCTAssertEqual(restored.name, "Demo")
        XCTAssertEqual(restored.clips.count, 1)
        XCTAssertEqual(restored.clips[0].id, clip.id)
        XCTAssertEqual(restored.clips[0].duration, 12.3, accuracy: 0.001)
        XCTAssertEqual(restored.transcript.words.count, 2)
        XCTAssertTrue(restored.transcript.words[0].cutAfter)
        XCTAssertTrue(restored.transcript.words[1].isDeleted)
        XCTAssertTrue(restored.transcript.words[1].isFiller)
        XCTAssertEqual(restored.transcript.words[0].id, w1.id)
        XCTAssertEqual(restored.transcript.words[1].clipID, clip.id)
    }

    func testFillerConfigSplitsWordsAndPhrases() {
        let settings = AppSettings(fillerTerms: ["um", "you know", "uh", "sort of"])
        let config = settings.fillerConfig
        XCTAssertEqual(Set(config.singleWords), ["um", "uh"])
        XCTAssertEqual(Set(config.phrases), ["you know", "sort of"])
    }
}

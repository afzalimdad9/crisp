import XCTest
import AVFoundation
@testable import WiseEdit

/// Validates the cut engine against the real fixture asset (no model needed —
/// fast and runs on every build).
@MainActor
final class CompositionBuilderTests: XCTestCase {
    private func fixtureClip() -> MediaClip {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/sample.m4a")
        return MediaClip(url: url, duration: 10.674)
    }

    func testKeepsAllWhenNothingDeleted() async throws {
        let clip = fixtureClip()
        var project = Project()
        project.clips = [clip]
        project.transcript.words = [
            Word(text: "one", start: 0.0, end: 1.0, clipID: clip.id),
            Word(text: "two", start: 1.0, end: 2.0, clipID: clip.id),
            Word(text: "three", start: 2.0, end: 3.0, clipID: clip.id),
        ]

        let result = try await CompositionBuilder.build(project: project)
        let built = try XCTUnwrap(result)

        // One contiguous segment [0 … 3 + tailPad].
        XCTAssertEqual(built.duration, 3.0 + CompositionBuilder.tailPad, accuracy: 0.05)
        XCTAssertEqual(built.composition.duration.seconds, built.duration, accuracy: 0.05)
        XCTAssertEqual(built.wordStarts.count, 3)
        XCTAssertEqual(built.wordStarts[project.transcript.words[0].id] ?? -1, 0.0, accuracy: 0.05)
    }

    func testDeletingMiddleWordSplitsAndShortens() async throws {
        let clip = fixtureClip()
        var project = Project()
        project.clips = [clip]
        let w1 = Word(text: "one", start: 0.0, end: 1.0, clipID: clip.id)
        var w2 = Word(text: "two", start: 1.2, end: 2.2, clipID: clip.id)
        let w3 = Word(text: "three", start: 2.5, end: 3.5, clipID: clip.id)
        w2.isDeleted = true
        project.transcript.words = [w1, w2, w3]

        let result = try await CompositionBuilder.build(project: project)
        let built = try XCTUnwrap(result)

        let segA = (1.0 + CompositionBuilder.tailPad) - 0.0
        let segB = (3.5 + CompositionBuilder.tailPad) - (2.5 - CompositionBuilder.leadPad)
        XCTAssertEqual(built.duration, segA + segB, accuracy: 0.06)
        XCTAssertEqual(built.composition.duration.seconds, built.duration, accuracy: 0.06)

        XCTAssertNil(built.wordStarts[w2.id], "deleted word should not be in the edited timeline")
        XCTAssertEqual(built.wordStarts[w3.id] ?? -1, segA + CompositionBuilder.leadPad, accuracy: 0.06)
    }

    func testAllDeletedReturnsNil() async throws {
        let clip = fixtureClip()
        var project = Project()
        project.clips = [clip]
        var w = Word(text: "one", start: 0.0, end: 1.0, clipID: clip.id)
        w.isDeleted = true
        project.transcript.words = [w]

        let built = try await CompositionBuilder.build(project: project)
        XCTAssertNil(built)
    }
}

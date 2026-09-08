import XCTest
import AVFoundation
@testable import WiseEdit

/// Exports an edited composition built from the real video fixture and verifies
/// the output is a valid, shortened `.mp4` with a video track. Fast (~a couple
/// seconds); skips automatically if the fixture is missing.
@MainActor
final class ExporterTests: XCTestCase {
    func testExportProducesShorterVideoFile() async throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/sample_video.mp4")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: fixture.path), "video fixture missing")

        let clip = MediaClip(url: fixture, duration: 10.6)
        var project = Project()
        project.clips = [clip]
        let w1 = Word(text: "one", start: 0.0, end: 1.0, clipID: clip.id)
        var w2 = Word(text: "two", start: 1.2, end: 2.0, clipID: clip.id)
        w2.isDeleted = true // cut the middle → output should be well under the 10.6s original
        let w3 = Word(text: "three", start: 2.2, end: 3.0, clipID: clip.id)
        project.transcript.words = [w1, w2, w3]

        let result = try await CompositionBuilder.build(project: project)
        let composition = try XCTUnwrap(result).composition

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        var lastProgress = 0.0
        try await Exporter.export(composition: composition, to: output) { lastProgress = $0 }

        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(lastProgress, 1.0, accuracy: 0.001)

        let exported = AVURLAsset(url: output)
        let duration = try await exported.load(.duration).seconds
        XCTAssertGreaterThan(duration, 1.0)
        XCTAssertLessThan(duration, 3.0, "cut should make the output much shorter than 10.6s")

        let videoTracks = try await exported.loadTracks(withMediaType: .video)
        XCTAssertFalse(videoTracks.isEmpty, "exported file should contain video")

        try? FileManager.default.removeItem(at: output)
    }
}

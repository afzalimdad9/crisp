import XCTest
import AVFoundation
@testable import WiseEdit

/// Live, on-device transcription test. It downloads a Whisper model and runs
/// inference, so it is **skipped by default** to keep normal test runs fast and
/// offline. It runs only when `WISEEDIT_LIVE_TRANSCRIBE=1` is set, or when a
/// `Fixtures/.run_live` marker file is present.
@MainActor
final class TranscriberLiveTests: XCTestCase {
    func testTranscribesFixtureWithWordTimestamps() async throws {
        let fixturesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
        let enabledByEnv = ProcessInfo.processInfo.environment["WISEEDIT_LIVE_TRANSCRIBE"] == "1"
        let enabledByMarker = FileManager.default.fileExists(
            atPath: fixturesDir.appendingPathComponent(".run_live").path)
        try XCTSkipUnless(enabledByEnv || enabledByMarker,
                          "Live transcription test disabled (set WISEEDIT_LIVE_TRANSCRIBE=1).")

        let fixture = fixturesDir.appendingPathComponent("sample.m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.path), "fixture missing")

        let clip = MediaClip(url: fixture)
        let transcriber = Transcriber()
        transcriber.modelName = "base" // small/fast model for verification

        let words = try await transcriber.transcribe(clip: clip)

        XCTAssertFalse(words.isEmpty, "expected transcribed words")
        for word in words {
            XCTAssertGreaterThanOrEqual(word.end, word.start, "timestamps must be ordered")
        }

        let joined = words.map(\.text).joined(separator: " ").lowercased()
        print("=== TRANSCRIPT ===\n\(joined)\n==================")
        for word in words.prefix(60) {
            print(String(format: "  %6.2f–%6.2f  %@", word.start, word.end, word.text))
        }

        XCTAssertTrue(joined.contains("video") || joined.contains("editing") || joined.contains("channel"),
                      "expected recognizable words, got: \(joined)")
    }
}

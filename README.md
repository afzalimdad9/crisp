# Crisp

A native macOS video editor that lets you **edit video by editing the words.**

Crisp transcribes your footage on-device, links every word to its exact moment of
video, and lets you cut by editing text. Delete an "um" in the transcript and that
slice of video is gone. One-click Auto-clean flags filler words, repeated takes,
and dead air. Built for talking-head creators who just want to cut, clean, and ship.

**Download:** [crisp-afzalimdad9.vercel.app](https://crisp-afzalimdad9.vercel.app) · macOS 14+ · Apple Silicon · free

## Features

- **Transcript-driven editing** — words are clickable (seek), selectable (cut), and the video rebuilds non-destructively from the kept ranges.
- **Auto-clean** — on-device detection of fillers, near-duplicate retakes, and long pauses, with a review/accept panel.
- **Multi-clip stitch** — drop in several recordings, reorder, and export one continuous video.
- **Follow-along playback** — the transcript highlights word-by-word as it plays.
- **Private by default** — transcription runs locally via the Apple Neural Engine; footage never leaves your Mac.

## Tech

- **Swift + SwiftUI** (Swift 5 language mode), AppKit bridges for the player/text
- **AVFoundation** — `AVMutableComposition` for non-destructive cut/stitch, `AVAssetExportSession` for export
- **[WhisperKit](https://github.com/argmaxinc/WhisperKit)** — on-device Whisper with word-level timestamps (CoreML / ANE)
- Pure-Swift detectors (dictionary + string similarity + timestamp gaps)
- Project generated with **[XcodeGen](https://github.com/yonsm/XcodeGen)** from `project.yml`

## Build from source

Requires Xcode 16+ and [XcodeGen](https://github.com/yonsm/XcodeGen) (`brew install xcodegen`).

```bash
xcodegen generate
open WiseEdit.xcodeproj   # then Run, or:
xcodebuild -scheme WiseEdit -configuration Debug build
```

The Whisper model (~1.5 GB) downloads once on first transcription, then runs fully offline.

A notarized, distributable `.dmg` is produced by [`tools/release.sh`](tools/release.sh)
(requires an Apple Developer ID certificate and notarization credentials).

## Repository layout

| Path | What |
|---|---|
| `WiseEdit/` | The macOS app (App, Models, Engine, Views, Support) |
| `WiseEditTests/` | Unit tests for the detectors and core logic |
| `server/` | Optional cloud-transcription backend (Hono + Postgres + Deepgram) |
| `site/` | The download landing page |
| `tools/` | Build, icon, and release scripts |
| `project.yml` | XcodeGen project definition |

## License

MIT — see [LICENSE](LICENSE). WhisperKit is also MIT.

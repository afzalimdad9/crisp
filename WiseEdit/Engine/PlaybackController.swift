import AVKit
import Observation

/// Owns the single `AVPlayer` used for preview. It plays either a raw source
/// clip (before transcription) or the edited `AVComposition` (after), so cuts
/// are previewed live. Publishes playhead time, duration and play state.
@Observable
@MainActor
final class PlaybackController {
    let player = AVPlayer()
    private(set) var currentURL: URL?
    private(set) var hasContent = false
    /// Current playhead time in seconds (edited timeline).
    var currentTime: Double = 0
    /// Duration of the loaded item in seconds (0 if unknown).
    var duration: Double = 0
    /// Whether the player is actively playing.
    var isPlaying = false
    /// Output volume 0…1.
    var volume: Double = 1 {
        didSet { player.volume = Float(max(0, min(1, volume))) }
    }
    /// Called on every playback tick (used to track the current transcript word).
    @ObservationIgnored var onTimeUpdate: ((Double) -> Void)?

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?

    init() {
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let seconds = time.seconds
            self.currentTime = seconds
            if let d = self.player.currentItem?.duration.seconds, d.isFinite, d > 0 {
                self.duration = d
            }
            self.onTimeUpdate?(seconds)
        }
        statusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let playing = player.timeControlStatus == .playing
            Task { @MainActor in self?.isPlaying = playing }
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        statusObservation?.invalidate()
    }

    /// Loads a raw source URL for preview (or clears the player when nil).
    func load(url: URL?) {
        currentURL = url
        currentTime = 0
        if let url {
            let item = AVPlayerItem(url: url)
            player.replaceCurrentItem(with: item)
            hasContent = true
            duration = 0
            Task { if let d = try? await item.asset.load(.duration) { duration = d.seconds } }
        } else {
            player.replaceCurrentItem(with: nil)
            hasContent = false
            duration = 0
        }
    }

    /// Loads an edited composition for preview.
    func loadComposition(_ asset: AVComposition) {
        currentURL = nil
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
        hasContent = true
        duration = asset.duration.seconds
    }

    /// Seeks the preview to an absolute time in seconds (edited timeline).
    func seek(toSeconds seconds: Double) {
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = max(0, seconds)
    }

    func play() { player.play() }
    func pause() { player.pause() }
    func togglePlay() { isPlaying ? pause() : play() }

    /// Skips relative to the current time (clamped to the item bounds).
    func skip(by seconds: Double) {
        let target = currentTime + seconds
        let upper = duration > 0 ? duration : target
        seek(toSeconds: min(max(0, target), upper))
    }
}

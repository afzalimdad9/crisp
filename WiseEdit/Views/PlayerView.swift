import SwiftUI
import AVKit

/// The video monitor: an `AVPlayerView` (native controls disabled — we supply our
/// own transport) floated on a near-black "stage" with breathing room, so the
/// footage reads like a framed preview rather than filling a raw black box.
struct PlayerView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            Theme.stage

            PlayerSurface(player: appState.playback.player)
                .onTapGesture { appState.playback.togglePlay() }
                .padding(14)

            if !appState.playback.hasContent {
                placeholder.allowsHitTesting(false)
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text("Select a clip to preview")
                .font(.callout)
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

private struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none // we provide our own transport (PlaybackBar)
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player { nsView.player = player }
    }
}

import SwiftUI

/// The transport beneath the monitor: elapsed time, skip ±15s, a prominent
/// play/pause, a custom scrubber over the edited timeline, total time and volume.
/// (The native AVPlayerView controls are disabled so there is only one transport.)
struct PlaybackBar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var pb = appState.playback

        HStack(spacing: 14) {
            Text(pb.currentTime.timecodeString)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .frame(minWidth: 46, alignment: .leading)

            HStack(spacing: 10) {
                transportButton("gobackward.15", help: "Back 15s") { pb.skip(by: -15) }

                Button { pb.togglePlay() } label: {
                    Image(systemName: pb.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Theme.accent))
                }
                .buttonStyle(.plain)
                .help(pb.isPlaying ? "Pause (Space)" : "Play (Space)")

                transportButton("goforward.15", help: "Forward 15s") { pb.skip(by: 15) }
            }

            Scrubber(current: pb.currentTime, duration: pb.duration) { pb.seek(toSeconds: $0) }

            Text(pb.duration.timecodeString)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .frame(minWidth: 46, alignment: .trailing)

            HStack(spacing: 6) {
                Image(systemName: volumeSymbol)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 16)
                    .contentShape(Rectangle())
                    .onTapGesture { pb.volume = pb.volume > 0 ? 0 : 1 }
                Slider(value: $pb.volume, in: 0...1)
                    .controlSize(.mini)
                    .frame(width: 66)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(Theme.elevated)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        .disabled(!appState.playback.hasContent)
        .opacity(appState.playback.hasContent ? 1 : 0.45)
    }

    private func transportButton(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var volumeSymbol: String {
        switch appState.playback.volume {
        case 0:      return "speaker.slash.fill"
        case ..<0.5: return "speaker.wave.1.fill"
        default:     return "speaker.wave.2.fill"
        }
    }
}

/// A slim custom progress/scrub control: a track with an accent-filled played
/// portion and a draggable knob. Dragging previews locally and seeks on release.
private struct Scrubber: View {
    let current: Double
    let duration: Double
    let onSeek: (Double) -> Void

    @State private var dragValue: Double?

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let value = dragValue ?? current
            let frac = duration > 0 ? max(0, min(1, value / duration)) : 0
            let knobX = frac * width

            ZStack(alignment: .leading) {
                Capsule().fill(Theme.stroke).frame(height: 4)
                Capsule().fill(Theme.accent).frame(width: knobX, height: 4)
                Circle()
                    .fill(.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .offset(x: knobX - 6)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard duration > 0, width > 0 else { return }
                        dragValue = max(0, min(1, v.location.x / width)) * duration
                    }
                    .onEnded { v in
                        guard duration > 0, width > 0 else { return }
                        let t = max(0, min(1, v.location.x / width)) * duration
                        onSeek(t)
                        dragValue = nil
                    }
            )
        }
        .frame(height: 18)
    }
}

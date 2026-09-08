import SwiftUI

/// Bottom timeline showing the *edited* result as a clean, continuous track:
/// one rounded ribbon coloured per source clip, with cuts shown as subtle nicks
/// (not loud markers), clip joins as clean seams, a refined ruler, and a sleek
/// playhead with a top handle.
///
/// • Click / drag a tiny amount → scrub.
/// • Drag across a span → select a region; a **Remove** button cuts it.
struct TimelineView: View {
    @Environment(AppState.self) private var appState

    /// Selected region in edited seconds (nil = none).
    @State private var selection: ClosedRange<Double>?

    private let sidePad: CGFloat = 14
    private let rulerHeight: CGFloat = 15

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let duration = max(appState.editedDuration, 0.001)

            ZStack(alignment: .topLeading) {
                content(width: width, height: geo.size.height)

                if let selection, appState.editedDuration > 0 {
                    removeButton(for: selection, width: width, height: geo.size.height, duration: duration)
                }
            }
            .contentShape(Rectangle())
            .gesture(scrubOrSelect(width: width, duration: duration))
        }
        .background(Theme.window)
        .onChange(of: appState.editedDuration) { selection = nil } // edit changed → clear
    }

    private func scrubOrSelect(width: CGFloat, duration: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let usable = max(1, width - sidePad * 2)
                func frac(_ x: CGFloat) -> Double { Double(max(0, min(1, (x - sidePad) / usable))) }
                if abs(value.translation.width) < 6 {
                    appState.seek(toFraction: frac(value.location.x))
                    selection = nil
                } else {
                    let a = frac(value.startLocation.x) * duration
                    let b = frac(value.location.x) * duration
                    selection = min(a, b)...max(a, b)
                }
            }
    }

    private func removeButton(for selection: ClosedRange<Double>, width: CGFloat, height: CGFloat, duration: Double) -> some View {
        let usable = max(1, width - sidePad * 2)
        let mid = (selection.lowerBound + selection.upperBound) / 2
        let x = sidePad + CGFloat(mid / duration) * usable
        return Button {
            appState.cutEditedRange(selection)
            self.selection = nil
        } label: {
            Label("Remove \((selection.upperBound - selection.lowerBound).timecodeString)", systemImage: "scissors")
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .controlSize(.small)
        .position(x: min(max(x, 64), width - 64), y: rulerHeight + 22)
    }

    @ViewBuilder
    private func content(width: CGFloat, height: CGFloat) -> some View {
        if appState.editedSegments.isEmpty {
            Text(appState.project.transcript.isEmpty ? "Transcribe a clip to see the edited timeline" : "No clips kept")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Canvas { ctx, size in draw(in: &ctx, size: size) }
        }
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let segments = appState.editedSegments
        let duration = max(appState.editedDuration, 0.001)
        let usableWidth = size.width - sidePad * 2
        func x(_ t: Double) -> CGFloat { sidePad + CGFloat(t / duration) * usableWidth }

        let trackTop = rulerHeight + 10
        let trackBottom = size.height - 12
        let trackH = max(10, trackBottom - trackTop)
        let radius: CGFloat = 7

        let clipIndex = Dictionary(uniqueKeysWithValues:
            appState.project.orderedClips.enumerated().map { ($0.element.id, $0.offset) })

        // ── Ruler ───────────────────────────────────────────────────────────
        let step = niceStep(for: duration)
        var t = 0.0
        while t <= duration + 0.001 {
            let px = x(t)
            ctx.stroke(Path { $0.move(to: CGPoint(x: px, y: rulerHeight - 4)); $0.addLine(to: CGPoint(x: px, y: rulerHeight)) },
                       with: .color(Theme.textTertiary.opacity(0.6)), lineWidth: 1)
            ctx.draw(Text(t.timecodeString).font(.system(size: 9).monospacedDigit()).foregroundStyle(Theme.textTertiary),
                     at: CGPoint(x: px + 3, y: 6), anchor: .leading)
            t += step
        }

        // ── Track ribbon ────────────────────────────────────────────────────
        let trackRect = CGRect(x: x(0), y: trackTop, width: max(2, x(duration) - x(0)), height: trackH)
        let trackPath = Path(roundedRect: trackRect, cornerRadius: radius)

        // Base groove (shows through if content is tiny).
        ctx.fill(trackPath, with: .color(Theme.elevated.opacity(0.5)))

        // Fills + seams happen inside a layer clipped to the rounded track, so the
        // outer corners stay clean no matter how many internal cuts there are.
        var layer = ctx
        layer.clip(to: trackPath)

        // Coloured fill per segment (same colour across a clip's internal cuts).
        for seg in segments {
            let r = CGRect(x: x(seg.editedStart), y: trackTop,
                           width: max(0.5, x(seg.editedEnd) - x(seg.editedStart)), height: trackH)
            let color = ClipPalette.color(for: clipIndex[seg.clipID] ?? 0)
            layer.fill(Path(r), with: .linearGradient(
                Gradient(colors: [color.opacity(0.98), color.opacity(0.78)]),
                startPoint: CGPoint(x: r.minX, y: trackTop),
                endPoint: CGPoint(x: r.minX, y: trackBottom)))
        }

        // Subtle top gloss.
        let gloss = CGRect(x: trackRect.minX, y: trackTop, width: trackRect.width, height: trackH * 0.5)
        layer.fill(Path(gloss), with: .linearGradient(
            Gradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0)]),
            startPoint: CGPoint(x: 0, y: trackTop), endPoint: CGPoint(x: 0, y: trackTop + trackH * 0.5)))

        // Seams: clean clip joins, subtle (deduped) nicks for same-clip cuts.
        if segments.count > 1 {
            var lastCutX: CGFloat = -100
            for i in 1..<segments.count {
                let prev = segments[i - 1], seg = segments[i]
                let px = x(seg.editedStart)
                if prev.clipID != seg.clipID {
                    layer.fill(Path(CGRect(x: px - 1, y: trackTop, width: 2, height: trackH)),
                               with: .color(Theme.window))
                } else if seg.sourceStart > prev.sourceEnd + 0.02, px - lastCutX >= 5 {
                    // thin seam …
                    layer.fill(Path(CGRect(x: px - 0.5, y: trackTop, width: 1, height: trackH)),
                               with: .color(Theme.window.opacity(0.75)))
                    // … plus a small nick at the top edge to mark the cut.
                    var nick = Path()
                    nick.move(to: CGPoint(x: px - 3, y: trackTop))
                    nick.addLine(to: CGPoint(x: px + 3, y: trackTop))
                    nick.addLine(to: CGPoint(x: px, y: trackTop + 4))
                    nick.closeSubpath()
                    layer.fill(nick, with: .color(Theme.window))
                    lastCutX = px
                }
            }
        }

        // Track outline.
        ctx.stroke(trackPath, with: .color(Theme.stroke), lineWidth: 1)

        // ── Selection ───────────────────────────────────────────────────────
        if let selection {
            let selRect = CGRect(x: x(selection.lowerBound), y: trackTop - 3,
                                 width: max(2, x(selection.upperBound) - x(selection.lowerBound)), height: trackH + 6)
            let selPath = Path(roundedRect: selRect, cornerRadius: 5)
            ctx.fill(selPath, with: .color(Theme.accent.opacity(0.26)))
            ctx.stroke(selPath, with: .color(Theme.accent), lineWidth: 1.5)
        }

        // ── Playhead ────────────────────────────────────────────────────────
        let phx = x(min(appState.playback.currentTime, duration))
        ctx.fill(Path(CGRect(x: phx - 0.75, y: rulerHeight, width: 1.5, height: size.height - rulerHeight - 6)),
                 with: .color(.white))
        var head = Path()
        head.move(to: CGPoint(x: phx - 5, y: rulerHeight - 7))
        head.addLine(to: CGPoint(x: phx + 5, y: rulerHeight - 7))
        head.addLine(to: CGPoint(x: phx, y: rulerHeight + 1))
        head.closeSubpath()
        ctx.fill(head, with: .color(.white))
        ctx.fill(Path(ellipseIn: CGRect(x: phx - 2.5, y: rulerHeight - 5.5, width: 5, height: 5)),
                 with: .color(Theme.window))
    }

    private func niceStep(for duration: Double) -> Double {
        switch duration {
        case ..<6: return 1
        case ..<15: return 2
        case ..<40: return 5
        case ..<90: return 10
        case ..<300: return 30
        default: return 60
        }
    }
}

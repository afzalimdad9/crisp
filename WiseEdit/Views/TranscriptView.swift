import SwiftUI
import AppKit

/// Editable transcript, grouped by clip (in stitch order). Words flow like text.
/// Click to seek + select; ⇧-click to extend; ⌘-click to toggle. Press Delete or
/// the **Cut** button to cut selected words — the preview + timeline update live.
/// Deleted words are struck-through (click to restore). Auto-clean tints fillers
/// (orange) and re-takes (red) and shows pause pills.
struct TranscriptView: View {
    @Environment(AppState.self) private var appState
    @FocusState private var focused: Bool
    @State private var wordFrames: [UUID: CGRect] = [:]

    private static let space = "transcriptArea"
    private var words: [Word] { appState.project.transcript.words }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let step = appState.hintStep {
                NextStepHint(step: step).transition(.move(edge: .top).combined(with: .opacity))
            }
            Group {
                if words.isEmpty { placeholder } else { transcript }
            }
            .overlay {
                if appState.isTranscribing {
                    TranscribingOverlay().transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: appState.isTranscribing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.panel)
        .animation(.easeInOut(duration: 0.25), value: appState.hintStep)
    }

    // MARK: Header

    private var header: some View {
        PanelHeader(title: "Transcript", systemImage: "text.alignleft") {
            legend
            Spacer(minLength: 12)

            Toggle(isOn: Binding(
                get: { appState.settings.settings.followAlong },
                set: { appState.settings.settings.followAlong = $0 })) {
                Label("Follow", systemImage: "arrow.down.circle")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Auto-scroll the transcript to follow playback")

            if appState.selectionCount > 0 {
                Button(role: .destructive) {
                    appState.deleteSelectedWords()
                } label: {
                    Label("Cut \(appState.selectionCount)", systemImage: "scissors")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            legendItem(Theme.filler, "Filler")
            legendItem(Theme.retake, "Re-take")
            legendItem(Theme.pause, "Pause")
        }
    }

    private func legendItem(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: Transcript body

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(appState.project.orderedClips) { clip in
                        let clipWords = words.filter { $0.clipID == clip.id }
                        if !clipWords.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                if appState.project.clips.count > 1 { clipHeader(clip) }
                                wordFlow(clipWords)
                            }
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .coordinateSpace(.named(Self.space))
                .onPreferenceChange(WordFramesKey.self) { wordFrames = $0 }
                .gesture(sweepSelect)
            }
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onDeleteCommand { appState.deleteSelectedWords() }
            .onAppear { focused = true }
            .onChange(of: appState.currentWordID) { _, newID in
                // Auto-scroll to follow playback (only while playing and when the
                // Follow toggle is on, so it never fights the user when editing).
                guard let newID,
                      appState.playback.isPlaying,
                      appState.settings.settings.followAlong else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
    }

    private func wordFlow(_ clipWords: [Word]) -> some View {
        FlowLayout(spacing: 2, lineSpacing: 9) {
            ForEach(Array(clipWords.enumerated()), id: \.element.id) { index, word in
                WordChip(word: word,
                         isSelected: appState.selectedWordIDs.contains(word.id),
                         isCurrent: appState.currentWordID == word.id)
                    .id(word.id)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: WordFramesKey.self,
                                               value: [word.id: proxy.frame(in: .named(Self.space))])
                    })
                    .onTapGesture { handleTap(word) }
                    .contextMenu { menu(for: word) }

                if word.inSilenceGap {
                    PausePill(seconds: gapWithin(clipWords, index))
                }
            }
        }
    }

    /// Click-and-drag across words to select a run of them (then Cut/Delete).
    private var sweepSelect: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.space))
            .onChanged { value in
                guard let a = wordID(at: value.startLocation),
                      let b = wordID(at: value.location) else { return }
                appState.selectRange(from: a, to: b)
            }
    }

    /// The word under a point (or the nearest one), for sweep selection.
    private func wordID(at point: CGPoint) -> UUID? {
        for (id, rect) in wordFrames where rect.contains(point) { return id }
        var best: (UUID, CGFloat)?
        for (id, rect) in wordFrames {
            let dx = point.x - rect.midX, dy = point.y - rect.midY
            let distance = dx * dx + dy * dy
            if best == nil || distance < best!.1 { best = (id, distance) }
        }
        return best?.0
    }

    private func clipHeader(_ clip: MediaClip) -> some View {
        HStack(spacing: 7) {
            Circle().fill(ClipPalette.color(for: clip.orderIndex)).frame(width: 8, height: 8)
            Text(clip.displayName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(clip.duration.timecodeString)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(Theme.textTertiary)
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
        .padding(.top, 4)
    }

    private func gapWithin(_ clipWords: [Word], _ index: Int) -> Double {
        guard index + 1 < clipWords.count else { return 0 }
        var j = index + 1
        while j < clipWords.count, clipWords[j].isDeleted { j += 1 }
        guard j < clipWords.count else { return 0 }
        return max(0, clipWords[j].start - clipWords[index].end)
    }

    private func handleTap(_ word: Word) {
        let flags = NSEvent.modifierFlags
        let shift = flags.contains(.shift)
        let command = flags.contains(.command)

        if word.isDeleted && !shift && !command {
            appState.setDeleted(false, for: word) // click to restore
            return
        }
        if shift {
            appState.extendSelection(to: word)
        } else if command {
            appState.toggleSelection(word)
        } else {
            appState.selectSingle(word)
            appState.seek(toWord: word)
        }
    }

    @ViewBuilder
    private func menu(for word: Word) -> some View {
        if word.isDeleted {
            Button("Restore Word") { appState.setDeleted(false, for: word) }
        } else if appState.selectedWordIDs.contains(word.id), appState.selectedWordIDs.count > 1 {
            Button("Cut \(appState.selectedWordIDs.count) Selected Words") {
                appState.deleteSelectedWords()
            }
        } else {
            Button("Cut Word") { appState.setDeleted(true, for: word) }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.bubble")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            VStack(spacing: 5) {
                Text("No transcript yet")
                    .font(.headline)
                    .foregroundStyle(Theme.textSecondary)
                Text(appState.selectedClip == nil
                     ? "Import clips, then click Transcribe in the toolbar."
                     : "Click Transcribe in the toolbar to generate the editable transcript.")
                    .font(.callout)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One tappable word: dims + strikes through when cut, highlights when selected,
/// tints when flagged as a filler or re-take.
private struct WordChip: View {
    let word: Word
    let isSelected: Bool
    let isCurrent: Bool

    var body: some View {
        Text(word.text)
            .font(.system(size: 16, weight: isCurrent ? .semibold : .regular))
            .strikethrough(word.isDeleted, color: Theme.textTertiary)
            .foregroundStyle(foreground)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: Theme.chipRadius).fill(background)
            )
            .contentShape(Rectangle())
            .help(String(format: "%.2fs", word.start))
    }

    private var foreground: Color {
        if isCurrent { return .white }
        if word.isDeleted { return Theme.textTertiary }
        return Theme.textPrimary
    }

    private var background: Color {
        if isCurrent { return Theme.accent }                       // now playing
        if isSelected { return Theme.accent.opacity(0.32) }
        if word.isDeleted { return .clear }
        if word.isRetake { return Theme.retake.opacity(0.20) }
        if word.isFiller { return Theme.filler.opacity(0.22) }
        return .clear
    }
}

/// Collects each word's frame so drag-to-sweep can hit-test words.
private struct WordFramesKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// A dismissable "next step" callout shown just under the transcript header to
/// guide the user through the flow: after transcription it points at **Auto-clean**
/// (and runs it inline); after Auto-clean it points right at the **Review panel**
/// where the suggestions are applied. So the next move is always obvious.
private struct NextStepHint: View {
    @Environment(AppState.self) private var appState
    let step: AppState.NextStep

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            pointer
            action

            Button { appState.dismissHint() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 11).fill(Theme.accentSoft))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.accent.opacity(0.45), lineWidth: 1))
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // Directional pointer toward where the action lives.
    @ViewBuilder private var pointer: some View {
        switch step {
        case .autoClean:
            HStack(spacing: 4) {
                Image(systemName: "arrow.up").font(.system(size: 10, weight: .bold))
                Text("in the toolbar").font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(Theme.textTertiary)
        case .review:
            HStack(spacing: 4) {
                Text("in the Review panel").font(.system(size: 10, weight: .medium))
                Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(Theme.textTertiary)
        default:
            EmptyView()
        }
    }

    // Inline shortcut for the action (only for clean-up — review should be glanced
    // at on the right first, so we only point there).
    @ViewBuilder private var action: some View {
        if step == .autoClean {
            Button { appState.runAutoClean() } label: {
                Label("Auto-clean", systemImage: "wand.and.stars")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private var icon: String {
        step == .review ? "checklist" : "sparkles"
    }

    private var title: String {
        switch step {
        case .review:
            let n = appState.detections.count
            return "Found \(n) suggestion\(n == 1 ? "" : "s") — review & apply"
        default:
            return "Transcript ready — next, clean it up"
        }
    }

    private var subtitle: String {
        switch step {
        case .review:
            return "Check the suggestions on the right, then click Apply to make the cuts."
        default:
            return "Run Auto-clean to cut fillers, re-takes & pauses — or click any word to edit by hand."
        }
    }
}

/// Prominent progress state shown over the transcript area while transcribing —
/// so feedback lives where the user is looking and where the result appears,
/// not just in the bottom status bar. Reflects the live transcription phase and,
/// for multi-clip projects, which clip is being processed.
private struct TranscribingOverlay: View {
    @Environment(AppState.self) private var appState

    private var status: Transcriber.Status { appState.transcriber.status }

    var body: some View {
        ZStack {
            Theme.panel.opacity(0.94)

            VStack(spacing: 18) {
                PulsingWaveform()

                VStack(spacing: 6) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(Theme.textTertiary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if appState.transcribeClipCount > 1 {
                    VStack(spacing: 8) {
                        Text("Clip \(appState.transcribeClipIndex) of \(appState.transcribeClipCount)")
                            .font(.caption.weight(.medium).monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                        stepDots
                    }
                }
            }
            .padding(34)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 16).fill(Theme.elevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.stroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(1...max(appState.transcribeClipCount, 1), id: \.self) { i in
                Capsule()
                    .fill(i <= appState.transcribeClipIndex ? Theme.accent : Theme.stroke)
                    .frame(width: i == appState.transcribeClipIndex ? 18 : 7, height: 5)
                    .animation(.easeInOut(duration: 0.2), value: appState.transcribeClipIndex)
            }
        }
    }

    private var title: String {
        switch status {
        case .preparingModel:    return "Preparing the AI model…"
        case .extractingAudio:   return "Extracting audio…"
        case .transcribing:      return "Transcribing your video…"
        case .uploading:         return "Uploading audio…"
        case .cloudTranscribing: return "Transcribing in the cloud…"
        case .done:              return "Finishing up…"
        default:                 return "Starting…"
        }
    }

    private var subtitle: String? {
        switch status {
        case .preparingModel:
            return "First run downloads the model — this happens once, then it's fully offline."
        case .transcribing:
            return "Generating word-level timestamps on-device. This can take a moment."
        case .uploading, .cloudTranscribing:
            return "Your audio is processed securely and deleted after transcription."
        default:
            return nil
        }
    }
}

/// A small animated equalizer used as the transcription indicator (on-brand for
/// an audio/transcription task). Lightweight — driven by `TimelineView(.animation)`.
private struct PulsingWaveform: View {
    var color: Color = Theme.accent
    private let count = 5

    var body: some View {
        // Qualified: our own `TimelineView` (the editor's timeline) shadows SwiftUI's.
        SwiftUI.TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<count, id: \.self) { i in
                    let phase = Double(i) * 0.7
                    let h = 12 + 22 * (0.5 + 0.5 * sin(t * 5 + phase))
                    Capsule().fill(color).frame(width: 5, height: h)
                }
            }
            .frame(height: 46, alignment: .center)
        }
        .frame(height: 46)
    }
}

/// A small inline marker for a long pause between words.
private struct PausePill: View {
    let seconds: Double

    var body: some View {
        Text("⏸ \(String(format: "%.1fs", seconds))")
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.pause.opacity(0.18)))
            .foregroundStyle(Theme.pause)
    }
}

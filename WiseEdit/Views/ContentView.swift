import SwiftUI

/// The editor workspace, laid out like a proper NLE:
///
/// ```
/// ┌─────────┬──────────────────────────┬─────────┐
/// │ Library │  Monitor (video)         │ Review  │
/// │ (clips) │  Transport               │ (AI)    │
/// │         │  Transcript (document)   │         │
/// ├─────────┴──────────────────────────┴─────────┤
/// │ Timeline (full width)                         │
/// ├───────────────────────────────────────────────┤
/// │ Status bar (full width)                       │
/// └───────────────────────────────────────────────┘
/// ```
///
/// Panels are resizable (`HSplitView`); the timeline and status bar span the full
/// width. The whole app runs in a fixed dark appearance so the footage pops.
struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        return VStack(spacing: 0) {
            HSplitView {
                MediaBinView()
                    .frame(minWidth: 220, idealWidth: 264, maxWidth: 360)

                CenterStage()
                    .frame(minWidth: 480, maxWidth: .infinity)

                ReviewPanel()
                    .frame(minWidth: 264, idealWidth: 306, maxWidth: 400)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TimelinePanel()
            StatusBar()
        }
        .background(Theme.window)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .navigationTitle(appState.project.name)
        .toolbar { EditorToolbar() }
        .onChange(of: appState.selectedClipID) {
            appState.handleSelectionChange()
        }
        .onOpenURL { url in
            appState.openProject(at: url)
        }
        .alert(item: $appState.cloudGate) { gate in
            switch gate {
            case .signIn:
                return Alert(
                    title: Text("Sign in required"),
                    message: Text("Cloud transcription needs you to sign in with Apple. On-device transcription stays free — switch the mode in Settings ▸ Transcription."),
                    primaryButton: .default(Text("Sign in with Apple")) { appState.account.signInWithApple() },
                    secondaryButton: .cancel())
            case .consent:
                return Alert(
                    title: Text("Use cloud transcription?"),
                    message: Text("Your audio will be uploaded securely to transcribe it, then deleted. On-device stays free and private."),
                    primaryButton: .default(Text("Agree & Continue")) { appState.grantCloudConsentAndRetry() },
                    secondaryButton: .cancel())
            }
        }
    }
}

/// The middle column: framed video monitor + transport on top, transcript below,
/// with a draggable split between them.
private struct CenterStage: View {
    var body: some View {
        VSplitView {
            VStack(spacing: 0) {
                PlayerView()
                    .frame(minHeight: 200)
                PlaybackBar()
            }

            TranscriptView()
                .frame(minHeight: 220)
        }
        .background(Theme.panel)
    }
}

/// Full-width timeline tray pinned beneath the panels.
private struct TimelinePanel: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Timeline", systemImage: "ruler") {
                if appState.editedDuration > 0 {
                    Text("\(appState.editedSegments.count) segment\(appState.editedSegments.count == 1 ? "" : "s")  ·  \(appState.editedDuration.timecodeString)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            TimelineView()
                .frame(height: 108)
        }
        .background(Theme.window)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
        .frame(width: 1280, height: 820)
}

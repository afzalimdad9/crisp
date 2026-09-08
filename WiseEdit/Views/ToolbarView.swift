import SwiftUI

/// Window toolbar laid out as the editing workflow, left → right:
/// **Import → Transcribe → Auto-clean → Export**. The button matching the
/// current `suggestedStep` is emphasized (accent-filled) so "what do I click
/// next?" is always answered at a glance.
struct EditorToolbar: ToolbarContent {
    @Environment(AppState.self) private var appState

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                appState.importClips(urls: MediaImporter.presentOpenPanel())
            } label: {
                Label("Import", systemImage: "plus")
            }
            .prominent(appState.suggestedStep == .importClips)
            .help("Import video clips")

            Button {
                appState.transcribeAll()
            } label: {
                Label(appState.project.clips.count > 1 ? "Transcribe All" : "Transcribe",
                      systemImage: "waveform")
            }
            .prominent(appState.suggestedStep == .transcribe)
            .disabled(appState.project.isEmpty || appState.isBusy)
            .help("Transcribe clips into an editable transcript")

            Button {
                appState.runAutoClean()
            } label: {
                Label("Auto-clean", systemImage: "wand.and.stars")
            }
            .prominent(appState.suggestedStep == .autoClean)
            .disabled(appState.project.transcript.isEmpty || appState.isBusy)
            .help("Detect fillers, re-takes and long pauses")

            Spacer()

            Button {
                appState.exportVideo()
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .prominent(appState.suggestedStep == .export)
            .disabled(appState.project.transcript.isEmpty || appState.isBusy)
            .help("Export the edited video")
        }
    }
}

private extension View {
    /// Emphasizes a button (accent-filled) when it's the suggested next step,
    /// otherwise leaves it in the default toolbar style.
    @ViewBuilder
    func prominent(_ on: Bool) -> some View {
        if on { self.buttonStyle(.borderedProminent) }
        else { self }
    }
}

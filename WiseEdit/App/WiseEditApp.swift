import SwiftUI

@main
struct WiseEditApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 1040, minHeight: 680)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1320, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New") { appState.newProject() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Open…") { appState.openProject() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { appState.saveProject() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(appState.project.isEmpty)
                Button("Save As…") { appState.saveProjectAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(appState.project.isEmpty)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { appState.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!appState.canUndo)
                Button("Redo") { appState.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!appState.canRedo)
            }
        }

        Settings {
            SettingsView()
                .environment(appState)
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
        }
    }
}

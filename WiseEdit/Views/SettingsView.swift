import SwiftUI

/// Preferences: Whisper model, detection sensitivity, and the editable filler
/// dictionary. Changes persist immediately and apply to the next Auto-clean /
/// Transcribe.
struct SettingsView: View {
    @Environment(AppState.self) private var appState

    private let models: [(label: String, id: String)] = [
        ("Turbo — large-v3 (recommended)", "large-v3-v20240930_turbo"),
        ("Large v3 (most accurate)", "large-v3"),
        ("Small (faster)", "small"),
        ("Base (fastest)", "base"),
    ]

    var body: some View {
        @Bindable var store = appState.settings

        TabView {
            // Transcription + detection
            Form {
                Section("Transcription") {
                    Picker("Run transcription", selection: $store.settings.processingMode) {
                        Text("Automatic").tag(ProcessingMode.auto)
                        Text("On-device").tag(ProcessingMode.onDevice)
                        Text("Cloud (coming soon)").tag(ProcessingMode.cloud)
                    }
                    Text(DeviceCapability.recommendation)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Whisper model", selection: $store.settings.modelName) {
                        ForEach(models, id: \.id) { Text($0.label).tag($0.id) }
                    }
                    Text("Changing the model downloads it once on the next transcription.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Detection sensitivity") {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Pause length")
                            Spacer()
                            Text("\(store.settings.silenceThreshold, specifier: "%.1f") s")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        Slider(value: $store.settings.silenceThreshold, in: 0.3...2.0, step: 0.1)
                        Text("Pauses longer than this are flagged. Lower = catches shorter pauses.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Re-take match")
                            Spacer()
                            Text("\(Int(store.settings.retakeThreshold * 100))%")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        Slider(value: $store.settings.retakeThreshold, in: 0.6...0.95, step: 0.05)
                        Text("How similar two lines must be to count as a re-take. Lower = more aggressive.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Detection", systemImage: "wand.and.stars") }

            FillerEditor()
                .tabItem { Label("Filler Words", systemImage: "text.bubble") }

            AccountView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        .frame(width: 460, height: 420)
    }
}

/// Editable list of filler terms (a term with a space is treated as a phrase).
private struct FillerEditor: View {
    @Environment(AppState.self) private var appState
    @State private var newTerm = ""

    var body: some View {
        @Bindable var store = appState.settings

        VStack(spacing: 0) {
            List {
                ForEach(store.settings.fillerTerms, id: \.self) { term in
                    HStack {
                        Image(systemName: term.contains(" ") ? "text.word.spacing" : "textformat.abc")
                            .foregroundStyle(.secondary)
                        Text(term)
                    }
                }
                .onDelete { store.settings.fillerTerms.remove(atOffsets: $0) }
            }

            Divider()

            HStack {
                TextField("Add a filler word or phrase…", text: $newTerm)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
                Button("Reset to Defaults") { appState.settings.resetFillers() }
            }
            .padding(10)
        }
    }

    private func add() {
        let term = newTerm.lowercased().trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty, !appState.settings.settings.fillerTerms.contains(term) else { return }
        appState.settings.settings.fillerTerms.append(term)
        newTerm = ""
    }
}

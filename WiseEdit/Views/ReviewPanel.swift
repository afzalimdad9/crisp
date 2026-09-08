import SwiftUI

/// Right panel — AI suggestions from Auto-clean, grouped by kind as cards. Each
/// row has an accept toggle and a jump-to button; the footer applies the accepted
/// ones in one shot.
struct ReviewPanel: View {
    @Environment(AppState.self) private var appState

    private var acceptedCount: Int { appState.detections.filter(\.accepted).count }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Review", systemImage: "sparkles") {
                if !appState.detections.isEmpty {
                    Text("\(acceptedCount)/\(appState.detections.count)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                    Menu {
                        Button("Accept All") { appState.setAllDetections(accepted: true) }
                        Button("Reject All") { appState.setAllDetections(accepted: false) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 12))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .foregroundStyle(Theme.textSecondary)
                }
            }

            if appState.detections.isEmpty {
                empty
            } else {
                list
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.panel)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(DetectionKind.allCases, id: \.self) { kind in
                    let items = appState.detections.filter { $0.kind == kind }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: kind.symbol)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(color(for: kind))
                                Text("\(kind.title) · \(items.count)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            ForEach(items) { detection in
                                DetectionRow(detection: detection, accent: color(for: kind))
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
            Button {
                appState.applyAcceptedDetections()
            } label: {
                Text(acceptedCount > 0 ? "Apply \(acceptedCount) Edit\(acceptedCount == 1 ? "" : "s")" : "Nothing Selected")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(acceptedCount == 0)
            .attentionPulse(appState.suggestedStep == .review && acceptedCount > 0)
            .padding(12)
        }
        .background(Theme.panel)
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            VStack(spacing: 4) {
                Text("Nothing to review").font(.headline).foregroundStyle(Theme.textSecondary)
                Text(appState.project.transcript.isEmpty
                     ? "Transcribe a clip, then run Auto-clean."
                     : "Run Auto-clean to find fillers, re-takes and long pauses.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func color(for kind: DetectionKind) -> Color {
        switch kind {
        case .filler:  return Theme.filler
        case .retake:  return Theme.retake
        case .silence: return Theme.pause
        }
    }
}

private struct DetectionRow: View {
    @Environment(AppState.self) private var appState
    let detection: Detection
    let accent: Color

    var body: some View {
        HStack(spacing: 9) {
            Toggle("", isOn: Binding(
                get: { detection.accepted },
                set: { _ in appState.toggleDetection(detection) }))
                .labelsHidden()
                .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 1) {
                Text(displayLabel)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(detection.accepted ? Theme.textPrimary : Theme.textTertiary)
                Text(detection.startTime.timecodeString)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 4)

            Button { appState.jump(to: detection) } label: {
                Image(systemName: "play.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Jump to this point")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .fill(Theme.elevated.opacity(detection.accepted ? 0.9 : 0.45))
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent.opacity(detection.accepted ? 0.9 : 0.4))
                .frame(width: 3)
                .padding(.vertical, 6)
        }
    }

    private var displayLabel: String {
        switch detection.kind {
        case .filler: return "“\(detection.label)”"
        case .silence: return detection.label
        case .retake:
            let t = detection.label
            return t.count > 38 ? String(t.prefix(38)) + "…" : t
        }
    }
}

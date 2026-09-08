import SwiftUI

/// Full-width status bar pinned to the bottom of the window. Shows the current
/// status with a state icon (spinner while busy, green check on success, amber
/// warning on errors) and a progress bar during export.
struct StatusBar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 9) {
            leadingIndicator

            Text(appState.statusMessage)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 12)

            if let progress = appState.exportProgress {
                HStack(spacing: 8) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(width: 160)
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(Theme.elevated)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        .animation(.easeInOut(duration: 0.2), value: appState.isBusy)
        .animation(.easeInOut(duration: 0.2), value: appState.exportProgress)
    }

    @ViewBuilder
    private var leadingIndicator: some View {
        if appState.isBusy {
            ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14)
        } else {
            let isError = ["fail", "couldn't", "error"].contains { appState.statusMessage.lowercased().contains($0) }
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(isError ? Theme.filler : Color.green)
        }
    }
}

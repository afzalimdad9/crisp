import SwiftUI
import AppKit

/// Left panel — the clip library in stitch order. Poster thumbnails with a color
/// tag matching the timeline; drag rows to reorder the stitch; selection drives
/// the preview. Import via the header button, the empty-state button, or drop.
struct MediaBinView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            PanelHeader(title: "Library", systemImage: "film.stack") {
                if !appState.project.isEmpty {
                    Text("\(appState.project.clips.count)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                    Button { importClips() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
                    .help("Add clips…")
                }
            }

            if appState.project.isEmpty {
                emptyState
            } else {
                List(selection: $appState.selectedClipID) {
                    Section {
                        ForEach(appState.project.orderedClips) { clip in
                            ClipRow(clip: clip, selected: appState.selectedClipID == clip.id)
                                .tag(clip.id)
                                .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                        .onMove { from, to in
                            appState.moveClips(fromOffsets: from, toOffset: to)
                        }
                    } header: {
                        Text("Stitch order — drag to reorder")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                            .textCase(nil)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.panel)
        .dropDestination(for: URL.self) { urls, _ in
            let videos = urls.filter { ["mov", "mp4", "m4v"].contains($0.pathExtension.lowercased()) }
            appState.importClips(urls: videos)
            return !videos.isEmpty
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "film.stack")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            VStack(spacing: 4) {
                Text("No clips yet").font(.headline).foregroundStyle(Theme.textSecondary)
                Text("Import recordings or drag them here.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            Button { importClips() } label: {
                Label("Import Clips…", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func importClips() {
        appState.importClips(urls: MediaImporter.presentOpenPanel())
    }
}

private struct ClipRow: View {
    let clip: MediaClip
    let selected: Bool
    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Theme.stage)
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "film").foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(width: 64, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .leading) {
                // Color tag stripe matching the timeline.
                Capsule()
                    .fill(ClipPalette.color(for: clip.orderIndex))
                    .frame(width: 3, height: 26)
                    .padding(.leading, 3)
            }
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.stroke, lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(clip.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(clip.duration > 0 ? clip.duration.timecodeString : "loading…")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .fill(selected ? Theme.accentSoft : Theme.elevated.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(selected ? Theme.accent.opacity(0.8) : .clear, lineWidth: 1)
        )
        .task(id: clip.url) {
            thumbnail = await Thumbnailer.generate(url: clip.url)
        }
    }
}

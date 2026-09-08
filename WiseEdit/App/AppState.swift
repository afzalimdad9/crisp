import Foundation
import AVFoundation
import AppKit
import Observation

/// Top-level observable state. Owns the project document, the preview/transcribe
/// engines, transcript selection, the live edit (cut) pipeline, and undo/redo.
@Observable
@MainActor
final class AppState {
    var project = Project()
    var selectedClipID: MediaClip.ID?
    var statusMessage = "Ready"
    var isBusy = false
    /// True for the duration of a transcription run (drives the prominent
    /// in-transcript progress overlay). `isBusy` covers every long op; this is
    /// transcription-specific so the overlay only shows for transcription.
    var isTranscribing = false
    /// 1-based clip index and total in the current transcription run.
    var transcribeClipIndex = 0
    var transcribeClipCount = 0
    /// Whether Auto-clean has been run on the current transcript. Drives the
    /// "next step" hints and which toolbar action is emphasized.
    var didAutoClean = false
    /// Steps whose inline "next step" hint the user has dismissed (per transcript).
    var dismissedHints: Set<NextStep> = []
    /// URL of the saved `.wiseproj` document, if any.
    var documentURL: URL?

    let playback = PlaybackController()
    let transcriber = Transcriber()
    let settings = SettingsStore()
    let account = AccountStore()

    /// A cloud-routing gate that needs a user decision before transcription can
    /// proceed (drives an alert in `ContentView`).
    enum CloudGate: Identifiable { case signIn, consent; var id: Int { hashValue } }
    var cloudGate: CloudGate?

    /// Transcript words the user has selected (for cut/restore).
    var selectedWordIDs: Set<UUID> = []
    /// AI suggestions awaiting review (filler/retake/silence).
    var detections: [Detection] = []
    /// Export progress 0…1 while exporting, else nil.
    var exportProgress: Double?
    /// Start time of each kept word in the *edited* timeline (for click-to-seek).
    private(set) var editedWordStarts: [UUID: Double] = [:]
    /// Duration of the current edit, seconds.
    private(set) var editedDuration: Double = 0
    /// Kept segments of the current edit (drives the timeline + cut markers).
    private(set) var editedSegments: [EditSegment] = []
    /// The word currently under the playhead (drives follow-along highlighting).
    private(set) var currentWordID: UUID?
    /// Sorted (editedStart, wordID) pairs for fast current-word lookup.
    private var editedTimeline: [(start: Double, id: UUID)] = []

    init() {
        playback.onTimeUpdate = { [weak self] time in
            self?.updateCurrentWord(at: time)
        }
        transcriber.cloudProvider = CloudTranscriptionProvider(
            tokenProvider: { [weak self] in self?.account.token })
    }

    /// Whether this run should use the cloud, based on the user's processing mode
    /// and device capability. (`.auto` uses the cloud only when the Mac can't run
    /// the model locally.)
    private func wantsCloud() -> Bool {
        switch settings.settings.processingMode {
        case .onDevice: return false
        case .cloud:    return true
        case .auto:     return !DeviceCapability.canRunLocalModel
        }
    }

    /// Resolves cloud gating before a run. Returns true if transcription may
    /// proceed; otherwise sets `cloudGate` to prompt the user and returns false.
    private func resolveCloudRouting() -> Bool {
        let cloud = wantsCloud()
        if cloud {
            guard account.isSignedIn else { cloudGate = .signIn; return false }
            guard settings.settings.cloudConsentGiven else { cloudGate = .consent; return false }
        }
        transcriber.useCloud = cloud
        return true
    }

    /// Called after the user agrees to cloud consent — records it and retries.
    func grantCloudConsentAndRetry() {
        settings.settings.cloudConsentGiven = true
        cloudGate = nil
        transcribeAll()
    }

    private var anchorWordID: UUID?
    private var undoStack: [[Word]] = []
    private var redoStack: [[Word]] = []
    private var previewTask: Task<Void, Never>?

    var selectedClip: MediaClip? {
        guard let id = selectedClipID else { return nil }
        return project.clips.first { $0.id == id }
    }

    // MARK: - Guided workflow

    /// The step we nudge the user toward next. Used to emphasize the matching
    /// toolbar button so "what do I click next" is always answered.
    enum NextStep: Hashable { case importClips, transcribe, autoClean, review, export }

    var suggestedStep: NextStep {
        if project.isEmpty { return .importClips }
        if project.transcript.isEmpty { return .transcribe }
        if !didAutoClean { return .autoClean }
        if !detections.isEmpty { return .review }   // suggestions awaiting Apply
        return .export
    }

    /// The mid-flow step to surface an inline hint for (clean-up, then review) —
    /// the two steps that aren't otherwise obvious — or nil when none applies.
    var hintStep: NextStep? {
        guard !isTranscribing, !project.transcript.isEmpty else { return nil }
        switch suggestedStep {
        case .autoClean, .review:
            return dismissedHints.contains(suggestedStep) ? nil : suggestedStep
        default:
            return nil
        }
    }

    func dismissHint() { dismissedHints.insert(suggestedStep) }

    // MARK: - Import

    func importClips(urls: [URL]) {
        guard !urls.isEmpty else { return }
        var nextIndex = (project.clips.map(\.orderIndex).max() ?? -1) + 1
        var added: [MediaClip] = []
        for url in urls {
            let clip = MediaClip(url: url, orderIndex: nextIndex)
            nextIndex += 1
            project.clips.append(clip)
            added.append(clip)
        }
        statusMessage = "Imported \(added.count) clip\(added.count == 1 ? "" : "s")"
        if selectedClipID == nil { selectedClipID = added.first?.id }
        Task { await loadDurations(for: added) }
    }

    private func loadDurations(for clips: [MediaClip]) async {
        for clip in clips {
            let asset = AVURLAsset(url: clip.url)
            guard let duration = try? await asset.load(.duration) else { continue }
            if let idx = project.clips.firstIndex(where: { $0.id == clip.id }) {
                project.clips[idx].duration = duration.seconds
            }
        }
    }

    /// When no transcript exists yet, selecting a clip previews it raw. Once a
    /// transcript exists, the edited composition stays loaded.
    func handleSelectionChange() {
        guard project.transcript.isEmpty else { return }
        playback.load(url: selectedClip?.url)
    }

    // MARK: - Transcription

    /// True if the clip already has transcript words.
    func isTranscribed(_ clip: MediaClip) -> Bool {
        project.transcript.words.contains { $0.clipID == clip.id }
    }

    /// Transcribes every not-yet-transcribed clip (in stitch order) and merges
    /// the results into a single transcript spanning all clips.
    func transcribeAll() {
        let pending = project.orderedClips.filter { !isTranscribed($0) }
        guard !pending.isEmpty, !isBusy else {
            if pending.isEmpty { statusMessage = "All clips already transcribed." }
            return
        }
        guard resolveCloudRouting() else { return } // may prompt for sign-in/consent
        isBusy = true
        isTranscribing = true
        transcribeClipCount = pending.count
        transcribeClipIndex = 0
        didAutoClean = false      // a fresh transcript hasn't been cleaned yet
        dismissedHints.removeAll() // re-show the next-step hints for the new transcript
        transcriber.modelName = settings.settings.modelName
        Task {
            var failed = false
            for (i, clip) in pending.enumerated() {
                transcribeClipIndex = i + 1
                statusMessage = "Transcribing \(clip.displayName) (\(i + 1)/\(pending.count))…"
                do {
                    let words = try await transcriber.transcribe(clip: clip)
                    mergeWords(words, for: clip.id)
                } catch {
                    failed = true
                    statusMessage = "Failed on \(clip.displayName): \(error.localizedDescription)"
                }
            }
            selectedWordIDs = []
            undoStack.removeAll()
            redoStack.removeAll()
            rebuildEditedPreview()
            isTranscribing = false
            isBusy = false
            if !failed { statusMessage = "Transcript ready" }
        }
    }

    private func mergeWords(_ words: [Word], for clipID: UUID) {
        project.transcript.words.removeAll { $0.clipID == clipID }
        project.transcript.words.append(contentsOf: words)
        resortTranscript()
    }

    /// Keeps transcript words ordered by clip stitch order, then start time.
    private func resortTranscript() {
        let order = Dictionary(uniqueKeysWithValues: project.clips.map { ($0.id, $0.orderIndex) })
        project.transcript.words.sort {
            let a = order[$0.clipID] ?? 0, b = order[$1.clipID] ?? 0
            return a == b ? $0.start < $1.start : a < b
        }
    }

    /// Reorders clips in the stitch timeline (drag in the media bin).
    func moveClips(fromOffsets: IndexSet, toOffset: Int) {
        var ordered = project.orderedClips
        ordered.move(fromOffsets: fromOffsets, toOffset: toOffset)
        for (i, clip) in ordered.enumerated() {
            if let idx = project.clips.firstIndex(where: { $0.id == clip.id }) {
                project.clips[idx].orderIndex = i
            }
        }
        resortTranscript()
        rebuildEditedPreview()
    }

    // MARK: - Selection

    private var displayOrder: [UUID] { project.transcript.words.map(\.id) }

    func selectSingle(_ word: Word) {
        selectedWordIDs = [word.id]
        anchorWordID = word.id
    }

    func toggleSelection(_ word: Word) {
        if selectedWordIDs.contains(word.id) { selectedWordIDs.remove(word.id) }
        else { selectedWordIDs.insert(word.id) }
        anchorWordID = word.id
    }

    /// Selects every word between two words (inclusive), in display order — used
    /// by drag-to-sweep selection in the transcript.
    func selectRange(from a: UUID, to b: UUID) {
        let order = displayOrder
        guard let i = order.firstIndex(of: a), let j = order.firstIndex(of: b) else { return }
        let range = i <= j ? i...j : j...i
        selectedWordIDs = Set(order[range])
        anchorWordID = a
    }

    func extendSelection(to word: Word) {
        let order = displayOrder
        guard let anchor = anchorWordID ?? selectedWordIDs.first,
              let a = order.firstIndex(of: anchor),
              let b = order.firstIndex(of: word.id) else {
            selectSingle(word); return
        }
        let range = a <= b ? a...b : b...a
        selectedWordIDs = Set(order[range])
    }

    // MARK: - Editing (cut / restore)

    func deleteSelectedWords() {
        guard !selectedWordIDs.isEmpty else { return }
        recordUndo()
        for i in project.transcript.words.indices where selectedWordIDs.contains(project.transcript.words[i].id) {
            project.transcript.words[i].isDeleted = true
        }
        selectedWordIDs = []
        rebuildEditedPreview()
    }

    /// Cuts a span of the *edited* timeline (seconds): deletes every kept word
    /// whose position falls inside it. The builder then collapses the whole span
    /// — speech and any dead air between — into a single cut.
    func cutEditedRange(_ range: ClosedRange<Double>) {
        let ids = project.transcript.words.compactMap { word -> UUID? in
            guard !word.isDeleted, let start = editedWordStarts[word.id] else { return nil }
            return (start >= range.lowerBound && start <= range.upperBound) ? word.id : nil
        }
        guard !ids.isEmpty else {
            statusMessage = "No words in that range to cut."
            return
        }
        recordUndo()
        let set = Set(ids)
        for i in project.transcript.words.indices where set.contains(project.transcript.words[i].id) {
            project.transcript.words[i].isDeleted = true
        }
        selectedWordIDs = []
        rebuildEditedPreview()
    }

    func setDeleted(_ deleted: Bool, for word: Word) {
        recordUndo()
        if let i = project.transcript.words.firstIndex(where: { $0.id == word.id }) {
            project.transcript.words[i].isDeleted = deleted
        }
        rebuildEditedPreview()
    }

    func seek(toWord word: Word) {
        playback.seek(toSeconds: editedWordStarts[word.id] ?? word.start)
        playback.play()
    }

    /// Finds the word under the playhead (last word started at/ before `time`)
    /// and updates `currentWordID` only when it actually changes.
    private func updateCurrentWord(at time: Double) {
        guard !editedTimeline.isEmpty else {
            if currentWordID != nil { currentWordID = nil }
            return
        }
        var lo = 0, hi = editedTimeline.count - 1, idx = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if editedTimeline[mid].start <= time + 0.01 { idx = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        let newID = idx >= 0 ? editedTimeline[idx].id : nil
        if newID != currentWordID { currentWordID = newID }
    }

    /// Seeks the preview to a fraction (0…1) of the edited timeline.
    func seek(toFraction fraction: Double) {
        guard editedDuration > 0 else { return }
        playback.pause()
        playback.seek(toSeconds: max(0, min(1, fraction)) * editedDuration)
    }

    /// Number of currently selected words (for the Cut affordance).
    var selectionCount: Int { selectedWordIDs.count }

    // MARK: - Auto-clean (detect → review → apply)

    /// Runs all detectors and populates the Review panel. Also flags words so the
    /// transcript can highlight them.
    func runAutoClean() {
        guard !project.transcript.isEmpty, !isBusy else { return }
        let words = project.transcript.words
        let config = settings.settings
        var all = FillerDetector(config: config.fillerConfig).detect(in: words)
        all += RetakeDetector(threshold: config.retakeThreshold).detect(in: words)
        all += SilenceDetector(threshold: config.silenceThreshold).detect(in: words)
        all.sort { $0.startTime < $1.startTime }
        detections = all
        applyHighlightFlags()
        didAutoClean = true

        if all.isEmpty {
            statusMessage = "No fillers, re-takes or long pauses found."
        } else {
            let f = all.filter { $0.kind == .filler }.count
            let r = all.filter { $0.kind == .retake }.count
            let s = all.filter { $0.kind == .silence }.count
            statusMessage = "Found \(f) filler · \(r) re-take · \(s) pause — review on the right →"
        }
    }

    private func applyHighlightFlags() {
        var fillers = Set<UUID>(), retakes = Set<UUID>(), silences = Set<UUID>()
        for d in detections {
            switch d.kind {
            case .filler: fillers.formUnion(d.wordIDs)
            case .retake: retakes.formUnion(d.wordIDs)
            case .silence: silences.formUnion(d.wordIDs)
            }
        }
        for i in project.transcript.words.indices {
            let id = project.transcript.words[i].id
            project.transcript.words[i].isFiller = fillers.contains(id)
            project.transcript.words[i].isRetake = retakes.contains(id)
            project.transcript.words[i].inSilenceGap = silences.contains(id)
        }
    }

    func toggleDetection(_ detection: Detection) {
        if let i = detections.firstIndex(where: { $0.id == detection.id }) {
            detections[i].accepted.toggle()
        }
    }

    func setAllDetections(accepted: Bool) {
        for i in detections.indices { detections[i].accepted = accepted }
    }

    func jump(to detection: Detection) {
        if let first = detection.wordIDs.first, let t = editedWordStarts[first] {
            playback.seek(toSeconds: t)
        } else {
            playback.seek(toSeconds: detection.startTime)
        }
        playback.play()
    }

    /// Applies every accepted suggestion: filler/retake → delete, silence → trim.
    func applyAcceptedDetections() {
        let accepted = detections.filter(\.accepted)
        guard !accepted.isEmpty else { return }
        recordUndo()

        var deleteIDs = Set<UUID>(), cutAfterIDs = Set<UUID>()
        for d in accepted {
            switch d.kind {
            case .filler, .retake: deleteIDs.formUnion(d.wordIDs)
            case .silence: cutAfterIDs.formUnion(d.wordIDs)
            }
        }
        for i in project.transcript.words.indices {
            let id = project.transcript.words[i].id
            if deleteIDs.contains(id) { project.transcript.words[i].isDeleted = true }
            if cutAfterIDs.contains(id) { project.transcript.words[i].cutAfter = true }
        }
        detections = []
        rebuildEditedPreview()
    }

    // MARK: - Undo / redo

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private func recordUndo() {
        undoStack.append(project.transcript.words)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(project.transcript.words)
        project.transcript.words = prev
        selectedWordIDs = []
        rebuildEditedPreview()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(project.transcript.words)
        project.transcript.words = next
        selectedWordIDs = []
        rebuildEditedPreview()
    }

    // MARK: - Live preview rebuild

    func rebuildEditedPreview() {
        previewTask?.cancel()
        guard !project.transcript.isEmpty else {
            editedWordStarts = [:]
            editedDuration = 0
            editedSegments = []
            editedTimeline = []
            currentWordID = nil
            playback.load(url: selectedClip?.url)
            return
        }
        let snapshot = project
        let resume = playback.player.currentTime().seconds
        previewTask = Task {
            do {
                guard let built = try await CompositionBuilder.build(project: snapshot) else {
                    editedWordStarts = [:]
                    editedDuration = 0
                    editedSegments = []
                    editedTimeline = []
                    currentWordID = nil
                    playback.load(url: nil)
                    statusMessage = "Everything is cut — nothing left to preview."
                    return
                }
                if Task.isCancelled { return }
                editedWordStarts = built.wordStarts
                editedDuration = built.duration
                editedSegments = built.segments
                editedTimeline = built.wordStarts
                    .map { (start: $0.value, id: $0.key) }
                    .sorted { $0.start < $1.start }
                updateCurrentWord(at: playback.currentTime)
                playback.loadComposition(built.composition)
                if resume.isFinite, resume > 0 {
                    playback.seek(toSeconds: min(resume, built.duration))
                }
                updateEditStatus()
            } catch {
                statusMessage = "Preview error: \(error.localizedDescription)"
            }
        }
    }

    private func updateEditStatus() {
        let cutCount = project.transcript.words.lazy.filter(\.isDeleted).count
        if cutCount > 0 {
            statusMessage = "Edited: \(editedDuration.timecodeString) · \(cutCount) word\(cutCount == 1 ? "" : "s") cut"
        } else {
            statusMessage = "Transcribed \(project.transcript.words.count) words"
        }
    }

    // MARK: - Document (save / open / new)

    func newProject() {
        previewTask?.cancel()
        project = Project()
        documentURL = nil
        selectedClipID = nil
        selectedWordIDs = []
        detections = []
        editedWordStarts = [:]
        editedDuration = 0
        editedSegments = []
        undoStack.removeAll()
        redoStack.removeAll()
        didAutoClean = false
        dismissedHints.removeAll()
        playback.load(url: nil)
        statusMessage = "New project"
    }

    func openProject() {
        guard let url = ProjectFile.openPanel() else { return }
        openProject(at: url)
    }

    /// Loads a `.wiseproj` from a URL (used by the Open dialog and by
    /// double-clicking a project file in Finder).
    func openProject(at url: URL) {
        do {
            let data = try Data(contentsOf: url)
            project = try ProjectFile.decode(data)
            project.name = url.deletingPathExtension().lastPathComponent
            documentURL = url
            selectedClipID = project.orderedClips.first?.id
            selectedWordIDs = []
            detections = []
            undoStack.removeAll()
            redoStack.removeAll()
            didAutoClean = true              // opened projects are assumed already worked on
            dismissedHints = [.autoClean, .review] // …so don't nag with the next-step hints
            rebuildEditedPreview()
            statusMessage = project.clips.isEmpty
                ? "Opened \(url.lastPathComponent) (no clips inside)"
                : "Opened \(url.lastPathComponent) — \(project.clips.count) clip\(project.clips.count == 1 ? "" : "s")"
        } catch {
            statusMessage = "Couldn't open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func saveProject() {
        if let url = documentURL {
            writeProject(to: url)
        } else {
            saveProjectAs()
        }
    }

    func saveProjectAs() {
        guard let url = ProjectFile.savePanel(suggestedName: project.name) else { return }
        documentURL = url
        project.name = url.deletingPathExtension().lastPathComponent
        writeProject(to: url)
    }

    private func writeProject(to url: URL) {
        do {
            try ProjectFile.encode(project).write(to: url)
            statusMessage = "Saved \(url.lastPathComponent)"
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Export

    /// Builds the final composition and exports it to a user-chosen `.mp4`,
    /// revealing it in Finder when done.
    func exportVideo() {
        guard !project.transcript.isEmpty, !isBusy else { return }
        guard let outputURL = ExportPanel.presentSavePanel(suggestedName: project.name) else { return }

        isBusy = true
        exportProgress = 0
        statusMessage = "Preparing export…"
        Task {
            do {
                guard let built = try await CompositionBuilder.build(project: project) else {
                    statusMessage = "Nothing to export."
                    isBusy = false; exportProgress = nil
                    return
                }
                try await Exporter.export(composition: built.composition, to: outputURL) { progress in
                    self.exportProgress = progress
                    self.statusMessage = "Exporting… \(Int(progress * 100))%"
                }
                exportProgress = nil
                isBusy = false
                statusMessage = "Exported \(outputURL.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
            } catch {
                exportProgress = nil
                isBusy = false
                statusMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }
}

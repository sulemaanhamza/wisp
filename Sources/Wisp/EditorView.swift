import SwiftUI

enum FontSize: String, CaseIterable {
    case small
    case medium
    case large

    var pointSize: CGFloat {
        switch self {
        case .small: return 17
        case .medium: return 20
        case .large: return 24
        }
    }

    var next: FontSize {
        let all = FontSize.allCases
        let idx = all.firstIndex(of: self) ?? 0
        return all[(idx + 1) % all.count]
    }
}

@MainActor
final class EditorModel: ObservableObject {
    @Published var text: String = "" {
        didSet {
            headings = text.extractHeadings()
            guard didLoad, !isReloading else { return }
            scheduleSave()
        }
    }
    @Published var headings: [Heading] = []
    @Published var focusToken: Int = 0
    @Published var scrollToken: Int = 0
    private(set) var scrollTarget: Int = 0
    @Published private(set) var placeholder: String = ""
    @Published var showHelp: Bool = false
    @Published var showHotKeyCapture: Bool = false
    @Published var showFirstRunHint: Bool = false
    /// Tips this user hasn't been shown, fixed for the session so the
    /// "New" group doesn't vanish out from under them the moment the
    /// dot is marked seen.
    @Published private(set) var newTips: [Tip] = []
    /// Drives the dot on the `?`. Cleared as soon as they look.
    @Published private(set) var hasUnseenTips: Bool = false
    @Published var showTour: Bool = false
    /// Set to true when the user clicks "Later" on the update overlay.
    /// Reset to false on every panel-open so the overlay reappears on
    /// the next interaction if an update is still available.
    @Published var updateDismissed: Bool = false
    /// True when the last write to disk failed — ejected drive, lost
    /// permission, a sync folder that went away. Surfaced in the footer
    /// so the user is never told everything is fine while nothing is
    /// actually being saved.
    @Published private(set) var saveFailed: Bool = false

    // MARK: Find
    @Published var showFind: Bool = false
    @Published var findQuery: String = "" {
        didSet {
            // Only react while find is open. When the bar is torn down,
            // the text field resigns focus and writes its value back
            // through the binding; Swift's didSet fires even on an equal
            // write, which would otherwise re-highlight the just-cleared
            // match after closeFind().
            guard didLoad, showFind else { return }
            recomputeMatches(resetIndex: true)
        }
    }
    /// Number of matches for the current query (0 when none / empty).
    @Published private(set) var findMatchCount: Int = 0
    /// 1-based index of the current match for display ("3 / 12").
    /// 0 when there are no matches.
    @Published private(set) var findCurrentDisplayIndex: Int = 0
    /// Token + range driving the highlight in MinimalTextEditor — same
    /// pattern as scrollToken/scrollTarget. A zero-length range clears.
    @Published var findHighlightToken: Int = 0
    private(set) var findHighlightRange = NSRange(location: 0, length: 0)
    private var findMatches: [NSRange] = []
    private var findIndex = 0
    @Published var hotKey: HotKey = .default {
        didSet {
            guard didLoad else { return }
            hotKey.saveToDefaults()
        }
    }

    /// AppDelegate replaces this with the real Carbon-registration
    /// attempt. Returns nil on success or a user-facing error message
    /// if registration was rejected (typically because the combo is
    /// already in use system-wide). Default is a no-op so this is
    /// always callable.
    var tryUpdateHotKey: @MainActor (HotKey) -> String? = { _ in nil }

    private static let placeholders = [
        "What's on your mind?",
        "Type your first thought…",
        "Write it down before it's gone.",
        "Capture it before you forget.",
        "Anything to remember?",
    ]
    @Published var fontSize: FontSize = .medium {
        didSet {
            guard didLoad else { return }
            UserDefaults.standard.set(fontSize.rawValue, forKey: "FontSize")
        }
    }
    @Published var fontFace: FontFace = .charter {
        didSet {
            guard didLoad else { return }
            UserDefaults.standard.set(fontFace.rawValue, forKey: "FontFace")
        }
    }
    /// How much of the desktop shows through. Persisted.
    @Published var transparency: Transparency = .subtle {
        didSet {
            guard didLoad else { return }
            UserDefaults.standard.set(transparency.rawValue, forKey: "Transparency")
            onChromeChange?()
        }
    }
    /// User-facing choice: light, dark, or follow-system. Persisted.
    @Published var themePreference: ThemePreference = .system {
        didSet {
            guard didLoad else { return }
            UserDefaults.standard.set(themePreference.rawValue, forKey: "Theme")
            theme = themePreference.resolve()
        }
    }

    /// Resolved theme actually used for rendering. Driven by
    /// themePreference, or — when preference is .system — by the OS
    /// appearance via the KVO observer below.
    @Published private(set) var theme: Theme = .dark {
        didSet {
            onChromeChange?()
        }
    }

    /// PanelController subscribes to this so it can apply chrome changes
    /// (visualEffect material, tint color, panel appearance) when the
    /// theme or the transparency changes. SwiftUI handles its own
    /// re-render via @Published.
    var onChromeChange: (@MainActor () -> Void)?

    /// KVO observer that re-resolves the theme when the OS switches
    /// between Light and Dark while the user is on .system. Held strong
    /// so the observation stays alive for the model's lifetime.
    private var appearanceObservation: NSKeyValueObservation?

    private var didLoad = false
    private var saveTask: Task<Void, Never>?
    /// Set true while we're rewriting `text` from a disk reload — the
    /// `text.didSet` save trigger checks this so we don't immediately
    /// re-save the content we just loaded.
    private var isReloading = false
    /// mtime of the file the last time we successfully loaded from
    /// disk. Drives reloadFromDiskIfChanged so we only re-read when
    /// the file has actually moved on (e.g., another Mac wrote to it
    /// via iCloud sync).
    private var lastLoadedMTime: Date?
    /// Text last successfully written to disk. Two jobs: it is the
    /// "before" side of the snapshot big-shrink guard, and it tells us
    /// what the file holds, so a disk reload can never discard edits
    /// that haven't been saved yet.
    private var lastSavedText: String = ""

    init() {
        if let saved = UserDefaults.standard.string(forKey: "Theme"),
           let pref = ThemePreference(rawValue: saved) {
            themePreference = pref
        }
        theme = themePreference.resolve()
        appearanceObservation = NSApplication.shared.observe(
            \.effectiveAppearance,
            options: [.new]
        ) { [weak self] _, _ in
            Task { @MainActor in self?.systemAppearanceMaybeChanged() }
        }
        if let saved = UserDefaults.standard.string(forKey: "FontSize"),
           let f = FontSize(rawValue: saved) {
            fontSize = f
        }
        if let saved = UserDefaults.standard.string(forKey: "FontFace"),
           let face = FontFace(rawValue: saved) {
            fontFace = face
        }
        if let saved = UserDefaults.standard.string(forKey: "Transparency"),
           let level = Transparency(rawValue: saved) {
            transparency = level
        }
        if let saved = HotKey.loadFromDefaults() {
            hotKey = saved
        }
        let hasSeenTour = UserDefaults.standard.bool(forKey: "HasSeenFirstRunTour")
        showFirstRunHint = !hasSeenTour
        if hasSeenTour {
            // Someone who updated into this. Anything they've not been
            // shown gets flagged on the `?`.
            newTips = Tips.unseen(
                since: UserDefaults.standard.string(forKey: Tips.seenKey)
            )
            hasUnseenTips = !newTips.isEmpty
        } else {
            // Fresh install: the tour covers the basics and the help
            // overlay is already current, so nothing here is "new".
            UserDefaults.standard.set(Tips.version, forKey: Tips.seenKey)
        }
        let url = StorageLocation.currentURL
        if let loaded = try? String(contentsOf: url, encoding: .utf8) {
            text = loaded
            lastSavedText = loaded
            lastLoadedMTime = Self.fileMTime(at: url)
        } else {
            // Nothing readable. In a sync folder that usually means
            // iCloud is still holding the file in the cloud — ask for
            // it now and pick it up on a later panel open.
            StorageLocation.startDownloadIfPlaceholder()
        }
        placeholder = Self.placeholders.randomElement() ?? Self.placeholders[0]
        didLoad = true
        // Preserve the loaded content as a session-start snapshot
        // (deduped) so each launch is a recoverable point.
        let loadedText = text
        Task.detached(priority: .background) {
            Snapshots.recordCheckpoint(text: loadedText)
        }
    }

    /// Called when the panel is dismissed — a natural "I'm done for
    /// now" boundary. Flushes the debounced save before checkpointing:
    /// without that, re-summoning inside the debounce window reloads
    /// the *previous* save off disk and the last keystrokes vanish.
    func saveAndCheckpoint() {
        saveNow()
        let snapshot = text
        Task.detached(priority: .background) {
            Snapshots.recordCheckpoint(text: snapshot)
        }
    }

    /// Whether a panel-open should pull the file back into the editor.
    /// Pure and public so the rule that once cost people their last
    /// keystrokes is pinned by tests.
    enum ReloadDecision: Equatable {
        /// The file hasn't moved on since we last read or wrote it.
        case skipNotNewer
        /// The file changed, but we're holding edits it doesn't have.
        case skipUnsavedEdits
        case reload
    }

    nonisolated static func decideReload(
        fileMTime: Date,
        lastLoadedMTime: Date?,
        text: String,
        lastSavedText: String
    ) -> ReloadDecision {
        if let last = lastLoadedMTime, fileMTime <= last { return .skipNotNewer }
        // saveNow() keeps lastSavedText in step with the file, so a
        // mismatch here means we hold work the file doesn't. Local
        // edits win: losing what someone just typed is worse than
        // missing a remote change we'll pick up on the next open.
        guard text == lastSavedText else { return .skipUnsavedEdits }
        return .reload
    }

    /// Re-read scratchpad.md from disk if its modification time has
    /// advanced since we last loaded it. Called on every panel-open so
    /// changes from another Mac (via iCloud Drive / Dropbox / etc.)
    /// show up the next time the user summons Wisp. Mid-session writes
    /// to the file from outside Wisp aren't observed (no file watcher
    /// — kept intentionally simple).
    func reloadFromDiskIfChanged() {
        let url = StorageLocation.currentURL
        guard let mtime = Self.fileMTime(at: url) else {
            StorageLocation.startDownloadIfPlaceholder()
            return
        }
        switch Self.decideReload(
            fileMTime: mtime,
            lastLoadedMTime: lastLoadedMTime,
            text: text,
            lastSavedText: lastSavedText
        ) {
        case .skipNotNewer:
            return
        case .skipUnsavedEdits:
            lastLoadedMTime = mtime
            return
        case .reload:
            break
        }
        guard let loaded = try? String(contentsOf: url, encoding: .utf8) else { return }
        if loaded != text {
            isReloading = true
            text = loaded
            isReloading = false
        }
        lastSavedText = loaded
        lastLoadedMTime = mtime
    }

    /// Replace the in-memory text with a freshly chosen content (e.g.,
    /// after switching to a folder that already contained a synced
    /// scratchpad). Suppresses the auto-save that would otherwise fire
    /// from `text.didSet`, so we don't bounce-write what we just read.
    func adoptLoadedText(_ newText: String) {
        isReloading = true
        text = newText
        isReloading = false
        lastSavedText = newText
        lastLoadedMTime = Self.fileMTime(at: StorageLocation.currentURL)
    }

    nonisolated private static func fileMTime(at url: URL) -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.modificationDate] as? Date
    }

    func requestFocus() {
        focusToken &+= 1
    }

    func cycleFontSize() {
        fontSize = fontSize.next
        requestFocus()
    }

    func cycleTheme() {
        themePreference = themePreference.next
        requestFocus()
    }

    /// File the note into the Inbox and start with a clean pad. Returns
    /// false when there was nothing worth filing.
    @discardableResult
    func archiveToInbox() -> Bool {
        let current = text
        guard Inbox.isWorthArchiving(current) else { return false }
        do {
            try Inbox.archive(text: current)
        } catch {
            saveFailed = true
            return false
        }
        // The archived copy also goes to history, so an accidental
        // archive is recoverable from the same place as everything else.
        Snapshots.recordCheckpoint(text: current)
        text = ""
        saveNow()
        requestFocus()
        return true
    }

    private func systemAppearanceMaybeChanged() {
        guard themePreference == .system else { return }
        let resolved = themePreference.resolve()
        if resolved != theme { theme = resolved }
    }

    func jumpTo(_ heading: Heading) {
        scrollTarget = heading.lineStart
        scrollToken &+= 1
    }

    // MARK: Find

    func openFind() {
        showFind = true
        recomputeMatches(resetIndex: true)
    }

    func closeFind() {
        showFind = false
        clearFindHighlight()
        requestFocus()
    }

    func findNext() {
        guard !findMatches.isEmpty else { return }
        findIndex = (findIndex + 1) % findMatches.count
        navigateToCurrentMatch()
    }

    func findPrevious() {
        guard !findMatches.isEmpty else { return }
        findIndex = (findIndex - 1 + findMatches.count) % findMatches.count
        navigateToCurrentMatch()
    }

    private func recomputeMatches(resetIndex: Bool) {
        findMatches = TextSearch.matches(in: text, query: findQuery)
        findMatchCount = findMatches.count
        if resetIndex { findIndex = 0 }
        if findIndex >= findMatches.count { findIndex = max(0, findMatches.count - 1) }
        if findMatches.isEmpty {
            findCurrentDisplayIndex = 0
            clearFindHighlight()
        } else {
            navigateToCurrentMatch()
        }
    }

    private func navigateToCurrentMatch() {
        guard findIndex < findMatches.count else { return }
        findCurrentDisplayIndex = findIndex + 1
        findHighlightRange = findMatches[findIndex]
        findHighlightToken &+= 1
    }

    private func clearFindHighlight() {
        findHighlightRange = NSRange(location: 0, length: 0)
        findHighlightToken &+= 1
    }

    func refreshPlaceholder() {
        placeholder = Self.placeholders.randomElement() ?? Self.placeholders[0]
    }

    /// Opening the help is what marks tips seen — that's the moment
    /// they're in front of the user. `newTips` is deliberately left
    /// alone so the group stays on screen for this session.
    func openHelp() {
        showHelp = true
        guard hasUnseenTips else { return }
        hasUnseenTips = false
        UserDefaults.standard.set(Tips.version, forKey: Tips.seenKey)
    }

    func closeHelp() {
        showHelp = false
    }

    func openTour() {
        showTour = true
    }

    func dismissTour() {
        showTour = false
        showFirstRunHint = false
        UserDefaults.standard.set(true, forKey: "HasSeenFirstRunTour")
    }

    /// Force a synchronous flush — call from applicationWillTerminate so an
    /// in-flight debounced save isn't lost when the user quits.
    func flushSave() {
        saveNow()
        Snapshots.recordCheckpoint(text: text)
    }

    /// The one place that writes the scratchpad. Cancels any pending
    /// debounced save, preserves the old version if this write would
    /// collapse it, and — crucially — records the resulting mtime.
    /// Skipping that last step is what made our own writes look like
    /// somebody else's to reloadFromDiskIfChanged.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard didLoad else { return }
        let newText = text
        guard newText != lastSavedText || saveFailed else { return }
        // The old version goes to history first, while it still exists
        // on disk — this is the accidental select-all-and-type case.
        Snapshots.recordOnSave(old: lastSavedText, new: newText)
        do {
            try Self.write(newText)
            lastSavedText = newText
            lastLoadedMTime = Self.fileMTime(at: StorageLocation.currentURL)
            saveFailed = false
        } catch {
            // Keep lastSavedText untouched: the text stays "unsaved",
            // so the next change retries and a reload can't overwrite
            // it with the stale copy on disk.
            saveFailed = true
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    nonisolated private static func write(_ text: String) throws {
        let url = StorageLocation.currentURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}

struct EditorView: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var updater: Updater

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                HeaderBar(headings: model.headings) { heading in
                    model.jumpTo(heading)
                }
                ZStack(alignment: .topLeading) {
                    MinimalTextEditor(
                        text: $model.text,
                        focusToken: model.focusToken,
                        scrollToken: model.scrollToken,
                        scrollTarget: model.scrollTarget,
                        findHighlightToken: model.findHighlightToken,
                        findHighlightRange: model.findHighlightRange,
                        fontSize: model.fontSize,
                        fontFace: model.fontFace,
                        theme: model.theme,
                        transparency: model.transparency
                    )
                    .padding(.horizontal, 28)
                    .padding(.top, model.headings.isEmpty ? 28 : 4)
                    .padding(.bottom, 4)
                    if model.text.isEmpty {
                        Text(model.placeholder)
                            .font(.custom(model.fontFace.familyName, size: model.fontSize.pointSize))
                            .foregroundStyle(.tertiary)
                            .allowsHitTesting(false)
                            .padding(.horizontal, 28)
                            .padding(.top, model.headings.isEmpty ? 28 : 4)
                    }
                }
                BottomBar(
                    wordCount: wordCount,
                    saveFailed: model.saveFailed,
                    fontSize: model.fontSize,
                    onCycleFontSize: { model.cycleFontSize() },
                    themePreference: model.themePreference,
                    onCycleTheme: { model.cycleTheme() },
                    updateState: updater.state,
                    onUpdateClick: { updater.handleClick() },
                    hasUnseenTips: model.hasUnseenTips,
                    onHelpClick: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            if model.showHelp {
                                model.closeHelp()
                            } else {
                                model.openHelp()
                            }
                        }
                    }
                )
            }
            if model.showFirstRunHint && !model.showTour {
                FirstRunDot {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        model.openTour()
                    }
                }
                .padding(.top, 14)
                .padding(.trailing, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .transition(.opacity)
            }
            if model.showTour {
                TourOverlay(theme: model.theme) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        model.dismissTour()
                    }
                }
                .transition(.opacity)
            }
            if model.showHelp {
                HelpOverlay(theme: model.theme, newTips: model.newTips) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        model.closeHelp()
                    }
                }
                .transition(.opacity)
            }
            if model.showHotKeyCapture {
                HotKeyCaptureOverlay(
                    theme: model.theme,
                    onTryRegister: { hk in model.tryUpdateHotKey(hk) },
                    onSuccess: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            model.showHotKeyCapture = false
                        }
                    },
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            model.showHotKeyCapture = false
                        }
                    }
                )
                .transition(.opacity)
            }
            if shouldShowUpdateOverlay {
                UpdateAvailableOverlay(
                    theme: model.theme,
                    state: updater.state,
                    highlights: updater.highlights,
                    onUpdate: { updater.startUpdateAndRestart() },
                    onLater: {
                        updater.cancelAutoApply()
                        withAnimation(.easeInOut(duration: 0.18)) {
                            model.updateDismissed = true
                        }
                    }
                )
                .transition(.opacity)
            }
            if model.showFind {
                FindBar(
                    theme: model.theme,
                    query: $model.findQuery,
                    matchCount: model.findMatchCount,
                    currentIndex: model.findCurrentDisplayIndex,
                    onNext: { model.findNext() },
                    onPrev: { model.findPrevious() },
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            model.closeFind()
                        }
                    }
                )
                .padding(.top, 12)
                .padding(.trailing, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(borderColor, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    /// Show the update overlay whenever there's something installable
    /// (.available or .pending) or actively downloading, and the user
    /// hasn't dismissed it for this panel-open session. Yields to
    /// help/tour/hotkey-capture so those keep their full attention.
    private var shouldShowUpdateOverlay: Bool {
        guard !model.updateDismissed else { return false }
        guard !model.showHelp, !model.showTour, !model.showHotKeyCapture else { return false }
        switch updater.state {
        case .available, .downloading, .pending, .failed: return true
        case .idle: return false
        }
    }

    private var borderColor: Color {
        switch model.theme {
        case .light: return Color.black.opacity(0.12)
        case .dark: return Color.clear
        }
    }

    private var wordCount: Int {
        var count = 0
        let text = model.text
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { _, _, _, _ in
            count += 1
        }
        return count
    }
}

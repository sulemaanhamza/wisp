import SwiftUI
import AppKit

struct MinimalTextEditor: NSViewRepresentable {
    @Binding var text: String
    var focusToken: Int
    var scrollToken: Int
    var scrollTarget: Int
    var findHighlightToken: Int
    var findHighlightRange: NSRange
    /// Bumped when a reminder's notification is clicked: scroll to its
    /// line and highlight it once.
    var reminderFlashToken: Int = 0
    var reminderFlashRange = NSRange(location: 0, length: 0)
    var fontSize: FontSize
    var fontFace: FontFace
    var theme: Theme
    var transparency: Transparency

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = CaretTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.contentView.drawsBackground = false

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        // Swap in the HR-aware layout manager so HR-only lines render
        // as a full-width horizontal line that tracks panel width.
        // The replacement keeps the same text container and storage.
        if let textContainer = textView.textContainer {
            textContainer.replaceLayoutManager(HorizontalRuleLayoutManager())
        }

        let font = Self.makeFont(face: fontFace, size: fontSize.pointSize)
        let paragraph = MarkdownStyler.bodyParagraph()

        // Click a `[ ]` to tick it off. A gesture recogniser rather than
        // an NSTextView subclass: gestureRecognizerShouldBegin only
        // claims the click when it actually lands on a box, so ordinary
        // clicks still place the caret exactly as before.
        let click = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleCheckboxClick(_:))
        )
        click.delegate = context.coordinator
        textView.addGestureRecognizer(click)

        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = font
        textView.defaultParagraphStyle = paragraph
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindBar = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.setAccessibilityLabel("Scratchpad")
        textView.string = text
        textView.textStorage?.delegate = context.coordinator
        context.coordinator.observeWidth(of: scrollView, textView: textView)
        context.coordinator.observeReminders(in: textView)

        Self.applyPalette(
            to: textView, face: fontFace, size: fontSize,
            theme: theme, transparency: transparency
        )

        context.coordinator.lastFontSize = fontSize
        context.coordinator.lastFontFace = fontFace
        context.coordinator.lastTheme = theme
        context.coordinator.lastTransparency = transparency
        context.coordinator.updateColumn(textView: textView, in: scrollView)
        return scrollView
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.stopObservingWidth()
        coordinator.stopObservingReminders()
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            context.coordinator.pendingEdit = nil
            context.coordinator.lastHighlight = nil
            // Assigning .string drops every attribute. Without a
            // restyle here a note reloaded from disk (iCloud, folder
            // switch) shows literal `---` and flat headings until the
            // next keystroke.
            if let storage = textView.textStorage {
                Self.restyle(
                    storage, face: fontFace, size: fontSize,
                    theme: theme, transparency: transparency
                )
            }
        }
        if context.coordinator.lastFontSize != fontSize {
            context.coordinator.lastFontSize = fontSize
            applyFont(to: textView)
            context.coordinator.updateColumn(textView: textView, in: scrollView)
        }
        if context.coordinator.lastFontFace != fontFace {
            context.coordinator.lastFontFace = fontFace
            applyFont(to: textView)
        }
        if context.coordinator.lastTheme != theme
            || context.coordinator.lastTransparency != transparency {
            context.coordinator.lastTheme = theme
            context.coordinator.lastTransparency = transparency
            Self.applyPalette(
                to: textView, face: fontFace, size: fontSize,
                theme: theme, transparency: transparency
            )
        }
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
        if context.coordinator.lastScrollToken != scrollToken {
            context.coordinator.lastScrollToken = scrollToken
            let target = scrollTarget
            DispatchQueue.main.async {
                let length = (textView.string as NSString).length
                let safe = max(0, min(target, length))
                let range = NSRange(location: safe, length: 0)
                textView.scrollRangeToVisible(range)
                textView.setSelectedRange(range)
                textView.window?.makeFirstResponder(textView)
            }
        }
        if context.coordinator.lastReminderFlashToken != reminderFlashToken {
            context.coordinator.lastReminderFlashToken = reminderFlashToken
            let range = reminderFlashRange
            DispatchQueue.main.async {
                context.coordinator.flash(range, in: textView)
            }
        }
        if context.coordinator.lastFindHighlightToken != findHighlightToken {
            context.coordinator.lastFindHighlightToken = findHighlightToken
            let range = findHighlightRange
            let color = Palette.for(theme).findHighlight
            if let storage = textView.textStorage {
                // Use a real storage background attribute (not a temporary
                // layout attribute): storage mutations always trigger a
                // redraw, so the highlight clears deterministically.
                // Restyling the old match rather than a bare
                // removeAttribute: code spans use .backgroundColor too.
                if let previous = context.coordinator.lastHighlight {
                    Self.restyle(
                        storage, face: fontFace, size: fontSize,
                        theme: theme, transparency: transparency, edited: previous
                    )
                }
                context.coordinator.lastHighlight = nil
                if range.length > 0, NSMaxRange(range) <= storage.length {
                    storage.addAttribute(.backgroundColor, value: color, range: range)
                    context.coordinator.lastHighlight = range
                    textView.scrollRangeToVisible(range)
                }
            }
        }
    }

    /// Restyle the whole storage, or with `edited` just the paragraphs
    /// an edit touched. See MarkdownStyler.
    static func restyle(
        _ storage: NSTextStorage,
        face: FontFace,
        size: FontSize,
        theme: Theme,
        transparency: Transparency,
        edited: NSRange? = nil
    ) {
        MarkdownStyler.restyle(
            storage, face: face, size: size, theme: theme,
            transparency: transparency, edited: edited
        )
    }

    private func applyFont(to textView: NSTextView) {
        let font = Self.makeFont(face: fontFace, size: fontSize.pointSize)
        textView.font = font
        var attrs = textView.typingAttributes
        attrs[.font] = font
        textView.typingAttributes = attrs
        if let storage = textView.textStorage {
            Self.restyle(
                storage, face: fontFace, size: fontSize,
                theme: theme, transparency: transparency
            )
        }
    }

    private static func applyPalette(
        to textView: NSTextView,
        face: FontFace,
        size: FontSize,
        theme: Theme,
        transparency: Transparency
    ) {
        let palette = Palette.for(theme)
        let font = makeFont(face: face, size: size.pointSize)
        let paragraph = MarkdownStyler.bodyParagraph()
        textView.textColor = palette.text
        textView.insertionPointColor = palette.cursor
        textView.selectedTextAttributes = [
            .backgroundColor: palette.selection
        ]
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: palette.text,
            .paragraphStyle: paragraph,
        ]
        if let lm = textView.layoutManager as? HorizontalRuleLayoutManager {
            lm.ruleColor = palette.divider
            lm.codeBlockColor = Palette.codeBackground(for: theme, transparency: transparency)
        }
        (textView as? CaretTextView)?.answerColor = palette.text.withAlphaComponent(0.5)
        if let storage = textView.textStorage {
            restyle(storage, face: face, size: size, theme: theme, transparency: transparency)
        }
    }

    static func makeFont(face: FontFace, size: CGFloat) -> NSFont {
        if let font = face.font(size: size) {
            return font
        }
        // Selected face is missing for some reason — fall through to a
        // sensible serif so we never crash on font lookup.
        for fallback in ["Charter", "Iowan Old Style", "New York"] {
            if let font = NSFont(name: fallback, size: size) {
                return font
            }
        }
        let baseDescriptor = NSFont.systemFont(ofSize: size).fontDescriptor
        let serifDescriptor = baseDescriptor.withDesign(.serif) ?? baseDescriptor
        return NSFont(descriptor: serifDescriptor, size: size) ?? NSFont.systemFont(ofSize: size)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate, NSGestureRecognizerDelegate {
        var text: Binding<String>
        var lastFocusToken: Int = 0
        var lastScrollToken: Int = 0
        var lastFindHighlightToken: Int = 0
        var lastFontSize: FontSize = .medium
        var lastFontFace: FontFace = .charter
        var lastTheme: Theme = .dark
        var lastTransparency: Transparency = .subtle
        /// Characters changed since the last restyle, in current
        /// coordinates. Collected from the storage so every path that
        /// edits text — typing, paste, undo, list continuation — is
        /// covered without each one reporting in.
        var pendingEdit: NSRange?
        /// The find match currently painted, so the next step only has
        /// to restyle that one range instead of the whole note.
        var lastHighlight: NSRange?
        /// True when the pending change is one typed character, the only
        /// kind of edit that may complete a shortcode. Whole-line edits
        /// (⌘L, ⌥↑) and pastes carry text that happens to end in `:)`
        /// and must arrive exactly as written.
        private var typedSingleCharacter = false
        private var widthObserver: NSObjectProtocol?
        var lastReminderFlashToken = 0
        /// "Remind me" lines typed or changed here and not yet finished.
        /// A reminder is set when its line is finished — the caret
        /// leaves it, or the panel loses focus or closes — so typing
        /// "in 1" on the way to "in 15" never sets a stray one.
        private(set) var draftReminders: Set<String> = []
        /// The shared store; the self-tests hand in one of their own so
        /// they never touch the real reminders or post notifications.
        lazy var reminderStore: ReminderStore = .shared
        private var reminderObservers: [NSObjectProtocol] = []
        private var flashTimer: Timer?
        private var flashStep = 0
        private weak var flashLayoutManager: NSLayoutManager?
        private var flashRange = NSRange(location: 0, length: 0)
        private var flashHoldsStill = false

        init(text: Binding<String>) {
            self.text = text
        }

        nonisolated func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters) else { return }
            MainActor.assumeIsolated {
                pendingEdit = Self.merge(pendingEdit, editedRange, delta: delta)
            }
        }

        /// Union of an earlier pending range with a new edit. The earlier
        /// range's end moves with the edit when the edit lands at or
        /// before it; covering a little too much is harmless, too
        /// little is a stale style.
        nonisolated static func merge(_ earlier: NSRange?, _ edit: NSRange, delta: Int) -> NSRange {
            guard let earlier else { return edit }
            let start = min(earlier.location, edit.location)
            let earlierEnd = NSMaxRange(earlier) + (edit.location <= NSMaxRange(earlier) ? delta : 0)
            let end = max(earlierEnd, NSMaxRange(edit))
            return NSRange(location: start, length: max(0, end - start))
        }

        // MARK: Column width

        /// Past a comfortable measure, extra panel width becomes margin
        /// rather than longer lines. About 34 ems — 680pt at the default
        /// size — keeps lines near 70 characters.
        func updateColumn(textView: NSTextView, in scrollView: NSScrollView) {
            let width = scrollView.contentView.bounds.width
            let measure = lastFontSize.pointSize * 34
            let inset = max(0, ((width - measure) / 2).rounded(.down))
            if textView.textContainerInset.width != inset {
                textView.textContainerInset = NSSize(width: inset, height: 0)
            }
        }

        func observeWidth(of scrollView: NSScrollView, textView: NSTextView) {
            scrollView.contentView.postsFrameChangedNotifications = true
            widthObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self, weak scrollView, weak textView] _ in
                MainActor.assumeIsolated {
                    guard let self, let scrollView, let textView else { return }
                    self.updateColumn(textView: textView, in: scrollView)
                }
            }
        }

        func stopObservingWidth() {
            if let widthObserver { NotificationCenter.default.removeObserver(widthObserver) }
            widthObserver = nil
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string

            // A shortcode replacement calls didChangeText(), which
            // re-enters this method; that nested call does the restyle,
            // so bail out rather than styling the same text twice.
            let mayCompleteShortcode = typedSingleCharacter
            typedSingleCharacter = false
            if mayCompleteShortcode, EmojiReplace.replaceIfMatched(in: textView) { return }

            // Mid-composition (Japanese, Chinese, dead keys) the marked
            // text carries the input method's own underline; restyling
            // would strip it. The edit stays pending until it's committed.
            guard !textView.hasMarkedText(), let edited = pendingEdit,
                  let storage = textView.textStorage else { return }
            pendingEdit = nil
            // Typing clears a find highlight, as it always has. The edit
            // may have moved it, so the stored range can't be trusted;
            // one full pass takes it wherever it went.
            let clearsHighlight = lastHighlight != nil
            lastHighlight = nil
            MinimalTextEditor.restyle(
                storage, face: lastFontFace, size: lastFontSize,
                theme: lastTheme, transparency: lastTransparency,
                edited: clearsHighlight ? nil : edited
            )
            redrawLines(around: edited, in: textView)
            noteDraftReminders(around: edited, in: textView)
        }

        // MARK: Reminders

        /// Remember the reminder lines an edit touched, to set when
        /// they're finished.
        private func noteDraftReminders(around edited: NSRange, in textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let ns = storage.string as NSString
            let start = min(edited.location, ns.length)
            let end = min(max(start, NSMaxRange(edited)), ns.length)
            let paragraphs = ns.paragraphRange(for: NSRange(location: start, length: end - start))
            guard ns.range(of: "remind me", options: .caseInsensitive, range: paragraphs).location != NSNotFound else { return }
            ns.enumerateSubstrings(in: paragraphs, options: .byLines) { line, range, _, _ in
                guard let line, Reminders.isReminder(line),
                      range.location >= storage.length
                        || storage.attribute(.wispCodeBlock, at: range.location, effectiveRange: nil) == nil
                else { return }
                self.draftReminders.insert(line)
            }
        }

        /// Set the drafts whose lines are finished. The caret's own line
        /// is still being written unless the whole editor is being left.
        func commitDraftReminders(in textView: NSTextView, includingCaretLine: Bool) {
            guard !draftReminders.isEmpty else { return }
            let ns = textView.string as NSString
            let caret = min(textView.selectedRange().location, ns.length)
            let caretLine = Self.lineText(at: caret, in: ns)
            for draft in draftReminders where includingCaretLine || draft != caretLine {
                draftReminders.remove(draft)
                // A draft from an earlier keystroke ("in 1" before "in
                // 15") is no longer a line of the note; it sets nothing.
                guard Self.containsLine(draft, in: ns) else { continue }
                reminderStore.commit(line: draft, noteText: textView.string)
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !textView.isFieldEditor else { return }
            commitDraftReminders(in: textView, includingCaretLine: false)
        }

        func observeReminders(in textView: NSTextView) {
            let center = NotificationCenter.default
            // A finished thought: the panel lost focus or closed, or Wisp
            // is quitting.
            for name in [NSWindow.didResignKeyNotification, NSApplication.willTerminateNotification] {
                reminderObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self, weak textView] note in
                    let sender = (note.object as? NSWindow).map(ObjectIdentifier.init)
                    MainActor.assumeIsolated {
                        guard let self, let textView else { return }
                        if let sender, sender != textView.window.map(ObjectIdentifier.init) { return }
                        self.commitDraftReminders(in: textView, includingCaretLine: true)
                    }
                })
            }
            // A reminder set, sent, or blocked: its grey text changes.
            reminderObservers.append(center.addObserver(forName: ReminderStore.didChange, object: nil, queue: .main) { [weak self, weak textView] _ in
                MainActor.assumeIsolated {
                    guard let self, let textView else { return }
                    self.restyleReminderLines(in: textView)
                }
            })
        }

        func stopObservingReminders() {
            reminderObservers.forEach(NotificationCenter.default.removeObserver)
            reminderObservers = []
            flashTimer?.invalidate()
        }

        private func restyleReminderLines(in textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let ns = storage.string as NSString
            var search = NSRange(location: 0, length: ns.length)
            while search.length > 0 {
                let hit = ns.range(of: "remind me", options: .caseInsensitive, range: search)
                guard hit.location != NSNotFound else { break }
                let line = ns.lineRange(for: hit)
                MinimalTextEditor.restyle(
                    storage, face: lastFontFace, size: lastFontSize,
                    theme: lastTheme, transparency: lastTransparency, edited: line
                )
                redrawLines(around: line, in: textView)
                search = NSRange(location: NSMaxRange(line), length: ns.length - NSMaxRange(line))
            }
        }

        /// Bring a reminder's line into view and highlight it once: held,
        /// then faded, or simply held and cleared under Reduce Motion.
        func flash(_ range: NSRange, in textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  range.length > 0, NSMaxRange(range) <= (textView.string as NSString).length else { return }
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: NSMaxRange(range), length: 0))
            textView.scrollRangeToVisible(range)
            flashTimer?.invalidate()
            if let previous = flashLayoutManager {
                previous.removeTemporaryAttribute(.backgroundColor, forCharacterRange: flashRange)
            }
            layoutManager.addTemporaryAttribute(.backgroundColor, value: Self.flashColor(1), forCharacterRange: range)
            flashLayoutManager = layoutManager
            flashRange = range
            flashStep = 0
            flashHoldsStill = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            flashTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.stepFlash() }
            }
        }

        private func stepFlash() {
            guard let layoutManager = flashLayoutManager else {
                flashTimer?.invalidate()
                return
            }
            flashStep += 1
            // About half a second at full strength, then a second to fade.
            let strength = flashHoldsStill
                ? (flashStep < 15 ? 1.0 : 0.0)
                : min(1, max(0, 1 - Double(flashStep - 5) / 10))
            if strength <= 0 {
                layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: flashRange)
                flashTimer?.invalidate()
            } else {
                layoutManager.addTemporaryAttribute(.backgroundColor, value: Self.flashColor(strength), forCharacterRange: flashRange)
            }
        }

        private static func flashColor(_ strength: Double) -> NSColor {
            NSColor.controlAccentColor.withAlphaComponent(0.28 * strength)
        }

        private static func lineText(at location: Int, in ns: NSString) -> String {
            var line = ns.substring(with: ns.lineRange(for: NSRange(location: location, length: 0)))
            while let last = line.unicodeScalars.last, CharacterSet.newlines.contains(last) {
                line.unicodeScalars.removeLast()
            }
            return line
        }

        /// Whether `line` is a whole line of the note — a search, not a
        /// split, since this runs as the caret moves.
        private static func containsLine(_ line: String, in ns: NSString) -> Bool {
            var search = NSRange(location: 0, length: ns.length)
            while search.length > 0 {
                let hit = ns.range(of: line, options: .literal, range: search)
                guard hit.location != NSNotFound else { return false }
                let startsLine = hit.location == 0 || CharacterSet.newlines.contains(UnicodeScalar(ns.character(at: hit.location - 1)) ?? " ")
                let endsLine = NSMaxRange(hit) == ns.length || CharacterSet.newlines.contains(UnicodeScalar(ns.character(at: NSMaxRange(hit))) ?? " ")
                if startsLine && endsLine { return true }
                search = NSRange(location: hit.location + 1, length: ns.length - hit.location - 1)
            }
            return false
        }

        /// An inline-math answer is drawn past the end of its line's
        /// text, outside what AppKit repaints for an edit — so an answer
        /// that changed or went away could linger. Repaint the edited
        /// lines edge to edge.
        private func redrawLines(around edited: NSRange, in textView: NSTextView) {
            guard let layoutManager = textView.layoutManager else { return }
            let ns = textView.string as NSString
            let start = min(edited.location, ns.length)
            let end = min(max(start, NSMaxRange(edited)), ns.length)
            let paragraphs = ns.paragraphRange(for: NSRange(location: start, length: end - start))
            let glyphs = layoutManager.glyphRange(forCharacterRange: paragraphs, actualCharacterRange: nil)
            let originY = textView.textContainerOrigin.y
            layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in
                textView.setNeedsDisplay(NSRect(
                    x: 0, y: rect.minY + originY, width: textView.bounds.width, height: rect.height
                ))
            }
        }

        // MARK: Checkbox clicks

        /// Only claim the click when it lands on a `[ ]`, or is a ⌘-click
        /// on a link; every other click falls through to the text view
        /// untouched.
        func gestureRecognizerShouldBegin(_ recognizer: NSGestureRecognizer) -> Bool {
            guard let click = recognizer as? NSClickGestureRecognizer,
                  let textView = recognizer.view as? NSTextView else { return false }
            let point = click.location(in: textView)
            if NSEvent.modifierFlags.contains(.command) {
                return Self.link(in: textView, at: point) != nil
            }
            return Self.checkboxRange(in: textView, at: point) != nil
        }

        @objc func handleCheckboxClick(_ recognizer: NSClickGestureRecognizer) {
            guard let textView = recognizer.view as? NSTextView else { return }
            let point = recognizer.location(in: textView)
            if NSEvent.modifierFlags.contains(.command) {
                if let url = Self.link(in: textView, at: point) {
                    NSWorkspace.shared.open(url)
                }
                return
            }
            guard let box = Self.checkboxRange(in: textView, at: point) else { return }
            let state = NSRange(location: box.location + 1, length: 1)
            let current = (textView.string as NSString).substring(with: state)
            replace(in: textView, range: state, with: current == " " ? "x" : " ")
        }

        /// Whether `location` is inside a fenced code block, as of the
        /// last restyle — which ran on the previous keystroke.
        private static func isInCodeBlock(_ textView: NSTextView, at location: Int) -> Bool {
            guard let storage = textView.textStorage, location < storage.length else { return false }
            return storage.attribute(.wispCodeBlock, at: location, effectiveRange: nil) != nil
        }

        /// The link under `point`, if any.
        private static func link(in textView: NSTextView, at point: NSPoint) -> URL? {
            guard let index = characterIndex(in: textView, at: point),
                  let storage = textView.textStorage else { return nil }
            return storage.attribute(.wispLink, at: index, effectiveRange: nil) as? URL
        }

        /// The character whose glyph is actually under `point` — not
        /// merely the nearest one, which is what glyphIndex returns for
        /// a click past the end of a line.
        private static func characterIndex(in textView: NSTextView, at point: NSPoint) -> Int? {
            guard let layoutManager = textView.layoutManager,
                  let container = textView.textContainer,
                  layoutManager.numberOfGlyphs > 0 else { return nil }
            let origin = textView.textContainerOrigin
            let local = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
            var fraction: CGFloat = 0
            let glyph = layoutManager.glyphIndex(
                for: local, in: container, fractionOfDistanceThroughGlyph: &fraction
            )
            let bounds = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyph, length: 1), in: container
            )
            guard bounds.contains(local) else { return nil }
            let index = layoutManager.characterIndexForGlyph(at: glyph)
            return index < (textView.string as NSString).length ? index : nil
        }

        /// The `[ ]` marker under `point`, in document coordinates.
        private static func checkboxRange(in textView: NSTextView, at point: NSPoint) -> NSRange? {
            guard let index = characterIndex(in: textView, at: point) else { return nil }
            let ns = textView.string as NSString
            let lineRange = ns.lineRange(for: NSRange(location: index, length: 0))
            let line = ns.substring(with: lineRange)
            guard let box = Checkbox.boxRange(in: line) else { return nil }
            let absolute = NSRange(location: lineRange.location + box.location, length: box.length)
            return NSLocationInRange(index, absolute) ? absolute : nil
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                return handleEnter(in: textView)
            }
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                return acceptAnswer(in: textView)
            }
            return false
        }

        /// Intercept typed text. Used to convert `---` to a horizontal rule
        /// the moment the third hyphen is typed — no need for Enter.
        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            typedSingleCharacter = affectedCharRange.length == 0
                && (replacementString as NSString?)?.length == 1

            // Only single-char `-` insertions count. Pastes (multi-char) and
            // undo restorations have different replacement strings, so they
            // skip this path naturally.
            guard replacementString == "-",
                  affectedCharRange.length == 0
            else { return true }

            let s = textView.string as NSString
            let insertAt = affectedCharRange.location
            let lineRange = s.lineRange(for: NSRange(location: insertAt, length: 0))

            let beforeCursor = s.substring(with: NSRange(
                location: lineRange.location,
                length: insertAt - lineRange.location
            ))
            var lineEnd = lineRange.location + lineRange.length
            if lineEnd > lineRange.location, s.character(at: lineEnd - 1) == 0x0A {
                lineEnd -= 1
            }
            let afterCursor = s.substring(with: NSRange(
                location: insertAt,
                length: lineEnd - insertAt
            ))

            // Trigger only when the line up to the cursor is exactly "--" and
            // the rest of the line is empty — i.e., user is finishing "---"
            // at the end of a fresh line, not editing inside content.
            // Inside a fenced block `---` is code (a diff header, YAML).
            guard beforeCursor == "--", afterCursor.isEmpty,
                  !Self.isInCodeBlock(textView, at: lineRange.location) else { return true }

            let twoDashRange = NSRange(location: lineRange.location, length: 2)
            replaceWithHorizontalRule(in: textView, range: twoDashRange)
            return false  // suppress the typed "-"
        }

        /// Tab right after a line's `=` types its answer in. Anywhere
        /// else Tab is Tab.
        private func acceptAnswer(in textView: NSTextView) -> Bool {
            guard let storage = textView.textStorage,
                  let insertion = Self.answerInsertion(in: storage, selection: textView.selectedRange())
            else { return false }
            replace(in: textView, range: NSRange(location: insertion.location, length: 0), with: insertion.text)
            return true
        }

        /// What Tab would type at `selection`: the answer, with a space
        /// first if the caret is right after the `=`. The caret only has
        /// to be past the `=` with nothing but spaces after it — a stray
        /// trailing space shouldn't turn Tab back into Tab. Pure for tests.
        static func answerInsertion(in storage: NSTextStorage, selection: NSRange) -> (location: Int, text: String)? {
            let ns = storage.string as NSString
            let caret = selection.location
            guard selection.length == 0, caret > 0, caret <= ns.length,
                  let answer = storage.attribute(.wispMathAnswer, at: caret - 1, effectiveRange: nil) as? String
            else { return nil }
            var i = caret
            while i < ns.length, ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 { i += 1 }
            guard i == ns.length || [0x0A, 0x0D, 0x2028, 0x2029].contains(ns.character(at: i)) else { return nil }
            let gap = ns.character(at: caret - 1) == 0x3D ? " " : ""
            return (caret, gap + answer)
        }

        private func handleEnter(in textView: NSTextView) -> Bool {
            let s = textView.string as NSString
            let cursor = textView.selectedRange().location
            let lineRange = s.lineRange(for: NSRange(location: cursor, length: 0))
            var lineEnd = lineRange.location + lineRange.length
            if lineEnd > lineRange.location, s.character(at: lineEnd - 1) == 0x0A {
                lineEnd -= 1
            }
            let line = s.substring(with: NSRange(
                location: lineRange.location,
                length: lineEnd - lineRange.location
            ))

            // Fallback path: catches `---` that arrived via paste, where the
            // typed-character interceptor above wouldn't fire.
            if SmartEditing.isHorizontalRuleTrigger(line),
               !Self.isInCodeBlock(textView, at: lineRange.location) {
                let replaceRange = NSRange(
                    location: lineRange.location,
                    length: lineEnd - lineRange.location
                )
                replaceWithHorizontalRule(in: textView, range: replaceRange)
                return true
            }

            guard let marker = SmartEditing.nextListMarker(for: line) else {
                return false
            }

            if marker.isEmpty {
                let stripRange = NSRange(
                    location: lineRange.location,
                    length: cursor - lineRange.location
                )
                replace(in: textView, range: stripRange, with: "\n")
            } else {
                let insert = "\n" + marker
                replace(in: textView, range: NSRange(location: cursor, length: 0), with: insert)
            }
            return true
        }

        /// Replace `range` with the horizontal-rule string + newline and
        /// move the cursor past it. The HR characters are stored as
        /// plain `---` (markdown standard); the visible full-width
        /// line is drawn by HorizontalRuleLayoutManager, while the
        /// `---` characters themselves are rendered with a clear
        /// foreground so only the line shows.
        private func replaceWithHorizontalRule(in textView: NSTextView, range: NSRange) {
            let replacement = SmartEditing.horizontalRule + "\n"
            replace(in: textView, range: range, with: replacement)
            let hrLength = (SmartEditing.horizontalRule as NSString).length
            let hrRange = NSRange(location: range.location, length: hrLength)
            textView.textStorage?.addAttribute(
                .foregroundColor,
                value: NSColor.clear,
                range: hrRange
            )
        }

        private func replace(in textView: NSTextView, range: NSRange, with replacement: String) {
            guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
            textView.textStorage?.replaceCharacters(in: range, with: replacement)
            textView.didChangeText()
            let newCursor = range.location + (replacement as NSString).length
            let newRange = NSRange(location: newCursor, length: 0)
            textView.setSelectedRange(newRange)
            // Hand-rolled edits bypass NSTextView's keyDown path, so its
            // built-in "scroll caret into view" doesn't fire. Without
            // this, hitting Enter at the bottom edge leaves the new
            // line off-screen until the user scrolls manually.
            textView.scrollRangeToVisible(newRange)
        }
    }
}

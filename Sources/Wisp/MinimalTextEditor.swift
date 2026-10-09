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
    var reminderFlashToken: Int
    var reminderFlashRange: NSRange
    var fontSize: FontSize
    var fontFace: FontFace
    var theme: Theme
    var transparency: Transparency
    /// Hands the model the editor, for what it asks of it directly:
    /// finishing the line being written, ticking a line off.
    var connect: (NoteEditor) -> Void

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
        context.coordinator.textView = textView
        context.coordinator.observeReminders(in: textView)
        connect(context.coordinator)

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
            context.coordinator.forgetDrafts()
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
        (textView as? CaretTextView)?.labelFont = font
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
        (textView as? CaretTextView)?.labelFont = font
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
    final class Coordinator: NSObject, NoteEditor, NSTextViewDelegate, NSTextStorageDelegate, NSGestureRecognizerDelegate {
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
        private var draftReminders: Set<String> = []
        /// For each draft, the line it was edited from — how an edited
        /// reminder is told apart from a new one with the same time. The
        /// store is told, so a save mid-edit doesn't cancel the reminder
        /// being edited, and its line keeps showing it.
        private var draftOrigins: [String: String] = [:] {
            didSet { if draftOrigins != oldValue { reminderStore.editing = draftOrigins } }
        }
        /// Drafts that were put back — undone, pasted, unticked — rather
        /// than written: a reminder that already went off stays sent
        /// instead of being set again.
        private var restoredDrafts: Set<String> = []
        /// The current edit is an undo or redo, or what it inserts.
        private var editIsUndo = false
        private var editInserts = ""
        /// The edited line as it was before the current edit, when the
        /// edit stays within one line.
        private var lineBeforeEdit: String?
        /// The note's text view, for what the model asks directly.
        weak var textView: NSTextView?
        private var inTextDidChange = false
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
            inTextDidChange = true
            defer { inTextDidChange = false }
            text.wrappedValue = textView.string
            stopFlash()

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
            // Return, or an edit elsewhere, can leave a line finished.
            commitDraftReminders(in: textView, includingCaretLine: false)
        }

        // MARK: Reminders

        /// Remember the reminder lines an edit changed, to set when
        /// they're finished — and the line each came from. Only lines
        /// whose text changed: pressing Return at the end of a line
        /// touches it without changing it, and a line from another Mac
        /// ("not set on this Mac") stays unset until it's edited here.
        private func noteDraftReminders(around edited: NSRange, in textView: NSTextView) {
            let before = lineBeforeEdit
            lineBeforeEdit = nil
            guard let storage = textView.textStorage else { return }
            let ns = storage.string as NSString
            let start = min(edited.location, ns.length)
            let end = min(max(start, NSMaxRange(edited)), ns.length)
            let lines = ns.lineRange(for: NSRange(location: start, length: end - start))
            guard ns.range(of: "remind me", options: .caseInsensitive, range: lines).location != NSNotFound
                    || before.map({ draftReminders.contains($0) }) == true else { return }
            var edited: [(line: String, range: NSRange)] = []
            ns.enumerateSubstrings(in: lines, options: .byLines) { line, range, _, _ in
                if let line { edited.append((line, range)) }
            }
            // The line now reads differently: its previous text is no
            // longer a draft, and what that was edited from carries over —
            // a line being typed traces back to where it started, not to
            // a set line whose text it passed through.
            var origin = before
            if let before, !edited.contains(where: { $0.line == before }) {
                draftReminders.remove(before)
                restoredDrafts.remove(before)
                if let inherited = draftOrigins.removeValue(forKey: before) { origin = inherited }
            }
            for (line, range) in edited where line != before && Reminders.isReminder(line)
                && !reminderStore.isExternal(line)
                && (range.location >= storage.length
                    || storage.attribute(.wispCodeBlock, at: range.location, effectiveRange: nil) == nil) {
                draftReminders.insert(line)
                // Put back: by undo, by pasting the line, or by unticking it.
                // Not Backspace, a composed accent or an emoji shortcode —
                // those are writing it.
                let putBack = editIsUndo || editInserts.contains(line) || before.map { Reminders.ticked(line) == $0 } == true
                if putBack { restoredDrafts.insert(line) } else { restoredDrafts.remove(line) }
                if let origin { draftOrigins[line] = origin }
            }
        }

        /// Set the drafts whose lines are finished. The caret's own line
        /// is still being written unless the whole editor is being left.
        func commitDraftReminders(in textView: NSTextView, includingCaretLine: Bool) {
            guard !draftReminders.isEmpty else { return }
            let ns = textView.string as NSString
            let caret = min(textView.selectedRange().location, ns.length)
            let caretLine = Self.lineText(at: caret, in: ns)
            let finished = draftReminders.filter { includingCaretLine || $0 != caretLine }
            guard !finished.isEmpty else { return }
            // A draft whose line has gone — deleted, or pasted over — sets
            // nothing.
            let inNote = ReminderStore.present(finished, in: textView.string)
            for draft in finished {
                draftReminders.remove(draft)
                let origin = draftOrigins.removeValue(forKey: draft)
                let restored = restoredDrafts.remove(draft) != nil
                if inNote.contains(draft) { reminderStore.commit(line: draft, origin: origin, restored: restored) }
            }
        }

        /// The whole text was replaced from outside (reload, folder
        /// switch): nothing being typed carries over.
        func forgetDrafts() {
            draftReminders = []
            draftOrigins = [:]
            restoredDrafts = []
            lineBeforeEdit = nil
        }

        // MARK: NoteEditor

        func finishEditing() {
            guard let textView else { return }
            commitDraftReminders(in: textView, includingCaretLine: true)
        }

        func replaceLine(_ range: NSRange, reading line: String, with replacement: String) -> Bool {
            guard let textView else { return false }
            return replaceLine(range, reading: line, with: replacement, in: textView)
        }

        private func replaceLine(_ range: NSRange, reading line: String, with replacement: String, in textView: NSTextView) -> Bool {
            // Only on the note as the model has it: just after a reload
            // from disk, the view still shows the old text until SwiftUI
            // passes the new one on, and an edit there would be saved over
            // what was just loaded.
            guard textView.string == text.wrappedValue else { return false }
            let ns = textView.string as NSString
            // The whole line, as expected: "… post" must not match "…
            // post later", and a line changed since is left alone.
            guard NSMaxRange(range) <= ns.length,
                  ns.lineRange(for: NSRange(location: range.location, length: 0)).location == range.location,
                  Self.lineText(at: range.location, in: ns) == line else { return false }
            LineEditing.apply(
                LineEditing.replacing(range, with: replacement, keeping: textView.selectedRange()),
                to: textView, scroll: false
            )
            return true
        }

        /// The caret left a line: it's finished. Not mid-edit — AppKit
        /// moves the caret before reporting the edit, when the drafts
        /// still hold the line's old text — textDidChange does it then.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !textView.isFieldEditor,
                  pendingEdit == nil else { return }
            commitDraftReminders(in: textView, includingCaretLine: false)
        }

        func observeReminders(in textView: NSTextView) {
            let center = NotificationCenter.default
            // A finished thought: the panel lost focus or closed.
            reminderObservers.append(center.addObserver(
                forName: NSWindow.didResignKeyNotification, object: nil, queue: .main
            ) { [weak self, weak textView] note in
                let sender = (note.object as? NSWindow).map(ObjectIdentifier.init)
                MainActor.assumeIsolated {
                    guard let self, let textView, sender == textView.window.map(ObjectIdentifier.init) else { return }
                    self.commitDraftReminders(in: textView, includingCaretLine: true)
                }
            })
            // A reminder set, sent, or blocked: its grey text changes. It's
            // drawn, not stored, so a redraw is all it takes.
            reminderObservers.append(center.addObserver(
                forName: ReminderStore.didChange, object: nil, queue: .main
            ) { [weak textView] _ in
                MainActor.assumeIsolated { textView?.needsDisplay = true }
            })
        }

        func stopObservingReminders() {
            reminderObservers.forEach(NotificationCenter.default.removeObserver)
            reminderObservers = []
            flashTimer?.invalidate()
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

        /// Text moved under the highlight: the fixed range would now mark
        /// the wrong characters, or leave a stripe behind. Clear it.
        private func stopFlash() {
            guard flashTimer?.isValid == true || flashLayoutManager != nil else { return }
            flashTimer?.invalidate()
            if let layoutManager = flashLayoutManager, let storage = layoutManager.textStorage {
                layoutManager.removeTemporaryAttribute(
                    .backgroundColor, forCharacterRange: NSRange(location: 0, length: storage.length)
                )
            }
            flashLayoutManager = nil
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
            LineEditing.splitTerminator(ns.substring(with: ns.lineRange(for: NSRange(location: location, length: 0)))).body
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

        /// Only claim the click when it lands on a `[ ]` or a sent
        /// reminder's tick, or is a ⌘-click on a link; every other click
        /// falls through to the text view untouched.
        func gestureRecognizerShouldBegin(_ recognizer: NSGestureRecognizer) -> Bool {
            guard let click = recognizer as? NSClickGestureRecognizer,
                  let textView = recognizer.view as? NSTextView else { return false }
            let point = click.location(in: textView)
            if (textView as? CaretTextView)?.reminderTick(at: point) != nil { return true }
            if NSEvent.modifierFlags.contains(.command) {
                return Self.link(in: textView, at: point) != nil
            }
            return Self.checkboxRange(in: textView, at: point) != nil
        }

        @objc func handleCheckboxClick(_ recognizer: NSClickGestureRecognizer) {
            guard let textView = recognizer.view as? NSTextView else { return }
            let point = recognizer.location(in: textView)
            if tickReminder(at: point, in: textView) { return }
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

        /// A click on a sent reminder's tick: the line is ticked off, as
        /// one undoable edit, the caret left where it was.
        func tickReminder(at point: NSPoint, in textView: NSTextView) -> Bool {
            guard let line = (textView as? CaretTextView)?.reminderTick(at: point) else { return false }
            let text = (textView.string as NSString).substring(with: line)
            _ = replaceLine(line, reading: text, with: Reminders.ticked(text), in: textView)
            return true
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
            if !inTextDidChange {
                editIsUndo = textView.undoManager?.isUndoing == true || textView.undoManager?.isRedoing == true
                editInserts = replacementString ?? ""
            }
            // The line as it stood, for telling an edited reminder from a
            // new one. Not overwritten by an edit made while handling this
            // one (a shortcode turning into an emoji): the user's line is
            // what it was before they touched it.
            // Nor by the later steps of a composition (Japanese input,
            // ⌥e): its edits aren't reported until it's committed, and by
            // then the line held the marked text. The first step already
            // counts as composing, so it's the line kept from that step.
            if !inTextDidChange, !(textView.hasMarkedText() && lineBeforeEdit != nil) {
                let ns = textView.string as NSString
                let line = ns.lineRange(for: NSRange(location: min(affectedCharRange.location, ns.length), length: 0))
                lineBeforeEdit = NSMaxRange(affectedCharRange) <= NSMaxRange(line)
                    ? Self.lineText(at: line.location, in: ns) : nil
            }

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

/// What the model asks of the editor showing the note.
@MainActor
protocol NoteEditor: AnyObject {
    /// Finish the line being written — setting its reminder — before the
    /// note is filed, or Wisp quits or restarts into an update.
    func finishEditing()
    /// Replace one whole line as an edit of the editor's own: undoable,
    /// the caret left where it was. False when the line no longer reads
    /// `line`.
    func replaceLine(_ range: NSRange, reading line: String, with replacement: String) -> Bool
}

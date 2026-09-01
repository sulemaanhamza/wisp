import SwiftUI
import AppKit

struct MinimalTextEditor: NSViewRepresentable {
    @Binding var text: String
    var focusToken: Int
    var scrollToken: Int
    var scrollTarget: Int
    var findHighlightToken: Int
    var findHighlightRange: NSRange
    var fontSize: FontSize
    var fontFace: FontFace
    var theme: Theme
    var transparency: Transparency

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
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
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.45

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
        textView.string = text

        Self.applyPalette(
            to: textView, face: fontFace, size: fontSize,
            theme: theme, transparency: transparency
        )

        context.coordinator.lastFontSize = fontSize
        context.coordinator.lastFontFace = fontFace
        context.coordinator.lastTheme = theme
        context.coordinator.lastTransparency = transparency
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
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
        if context.coordinator.lastFindHighlightToken != findHighlightToken {
            context.coordinator.lastFindHighlightToken = findHighlightToken
            let range = findHighlightRange
            let color = Palette.for(theme).findHighlight
            if let storage = textView.textStorage {
                let full = NSRange(location: 0, length: storage.length)
                // Use a real storage background attribute (not a temporary
                // layout attribute): storage mutations always trigger a
                // redraw, so the highlight clears deterministically.
                // A full restyle rather than a bare removeAttribute:
                // code spans use .backgroundColor too, and clearing the
                // whole document would strip them until the next
                // keystroke.
                Self.restyle(
                    storage, face: fontFace, size: fontSize,
                    theme: theme, transparency: transparency
                )
                if range.length > 0, NSMaxRange(range) <= full.length {
                    storage.addAttribute(.backgroundColor, value: color, range: range)
                    textView.scrollRangeToVisible(range)
                }
            }
        }
    }

    /// Reset font and colour across the storage, then re-apply heading,
    /// bold/italic and horizontal-rule styling. Resetting first is what
    /// gives a line that *stopped* being an HR its visible text colour
    /// back. Cheap at scratchpad sizes.
    static func restyle(
        _ storage: NSTextStorage,
        face: FontFace,
        size: FontSize,
        theme: Theme,
        transparency: Transparency
    ) {
        let baseFont = makeFont(face: face, size: size.pointSize)
        let palette = Palette.for(theme)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.45
        let total = NSRange(location: 0, length: storage.length)
        storage.addAttribute(.font, value: baseFont, range: total)
        storage.addAttribute(.foregroundColor, value: palette.text, range: total)
        storage.addAttribute(.paragraphStyle, value: paragraph, range: total)
        // Every attribute the passes below can add has to be cleared
        // here, or it outlives the text that justified it — a reopened
        // checkbox would stay struck through, a deleted fence would
        // keep its panel.
        storage.removeAttribute(.backgroundColor, range: total)
        storage.removeAttribute(.wispCodeBlock, range: total)
        storage.removeAttribute(.strikethroughStyle, range: total)
        storage.removeAttribute(.strikethroughColor, range: total)
        styleHorizontalRules(in: storage)
        styleHeadings(in: storage, baseFont: baseFont)
        styleBoldItalic(in: storage, baseFont: baseFont)
        // Code goes last so it wins: markdown inside a fence is code,
        // not formatting, and stays flat.
        styleCode(
            in: storage, baseFont: baseFont,
            background: Palette.codeBackground(for: theme, transparency: transparency)
        )
        styleCheckedItems(in: storage, palette: palette)
    }

    /// Ticked task items read as done: the whole line dims and the text
    /// after the box is struck through. The file still says `- [x]`.
    private static func styleCheckedItems(in storage: NSTextStorage, palette: Palette) {
        let ns = storage.string as NSString
        let done = palette.text.withAlphaComponent(0.4)
        forEachLine(in: ns) { lineRange in
            var content = lineRange
            if content.length > 0,
               ns.character(at: NSMaxRange(content) - 1) == 0x0A {
                content.length -= 1
            }
            guard content.length > 0 else { return }
            let line = ns.substring(with: content)
            guard Checkbox.isChecked(line), let box = Checkbox.boxRange(in: line) else { return }
            storage.addAttribute(.foregroundColor, value: done, range: content)
            let textStart = content.location + NSMaxRange(box)
            let textLength = NSMaxRange(content) - textStart
            guard textLength > 0 else { return }
            storage.addAttributes([
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: done,
            ], range: NSRange(location: textStart, length: textLength))
        }
    }

    /// Inline `code` spans and ``` fenced blocks in the system
    /// monospace face. Backticks stay visible — same deal as bold.
    private static func styleCode(
        in storage: NSTextStorage, baseFont: NSFont, background: NSColor
    ) {
        let ns = storage.string as NSString
        let mono = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.92, weight: .regular)
        var fenceStart: Int? = nil
        var blocks: [NSRange] = []
        forEachLine(in: ns) { lineRange in
            let line = ns.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("```") else { return }
            if let start = fenceStart {
                blocks.append(NSRange(location: start, length: NSMaxRange(lineRange) - start))
                fenceStart = nil
            } else {
                fenceStart = lineRange.location
            }
        }
        // An unclosed fence runs to the end of the document, so a block
        // looks like code while you're still typing it.
        if let start = fenceStart, start < ns.length {
            blocks.append(NSRange(location: start, length: ns.length - start))
        }
        for block in blocks {
            // The ground here is drawn by HorizontalRuleLayoutManager
            // from .wispCodeBlock, full width; an attribute background
            // would stop at each line's last glyph.
            storage.addAttributes([.font: mono, .wispCodeBlock: true], range: block)
        }
        for match in storage.string.matches(of: /`([^`\n]+)`/) {
            let range = NSRange(match.range, in: storage.string)
            guard range.location < storage.length,
                  storage.attribute(.wispCodeBlock, at: range.location, effectiveRange: nil) == nil
            else { continue }
            storage.addAttributes([.font: mono, .backgroundColor: background], range: range)
        }
    }

    /// Walk the storage line by line. Every styling pass wants this and
    /// they were each rolling their own.
    private static func forEachLine(in ns: NSString, _ body: (NSRange) -> Void) {
        var lineStart = 0
        while lineStart < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: lineStart, length: 0))
            body(lineRange)
            lineStart = NSMaxRange(lineRange)
        }
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
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.45
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
        if let storage = textView.textStorage {
            restyle(storage, face: face, size: size, theme: theme, transparency: transparency)
        }
    }

    /// Apply bold + scaled font to lines that begin with a markdown heading
    /// marker (`#` through `######`). Plain text on disk; this is just a
    /// per-range font attribute so the heading reads as a section title
    /// without leaving plain-text mode.
    private static func styleHeadings(in storage: NSTextStorage, baseFont: NSFont) {
        let ns = storage.string as NSString
        let total = ns.length
        var lineStart = 0
        while lineStart < total {
            let lineRange = ns.lineRange(for: NSRange(location: lineStart, length: 0))
            let raw = ns.substring(with: lineRange)
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
            if let match = line.firstMatch(of: /^(#{1,6})\s+(\S.*)/) {
                _ = match.2
                let level = match.1.count
                let font = headingFont(level: level, baseFont: baseFont)
                var styleRange = lineRange
                if styleRange.length > 0,
                   ns.character(at: styleRange.location + styleRange.length - 1) == 0x0A {
                    styleRange.length -= 1
                }
                storage.addAttribute(.font, value: font, range: styleRange)
            }
            lineStart = lineRange.location + lineRange.length
        }
    }

    private static func headingFont(level: Int, baseFont: NSFont) -> NSFont {
        let baseSize = baseFont.pointSize
        let scaledSize: CGFloat
        switch level {
        case 1: scaledSize = baseSize * 1.20
        case 2: scaledSize = baseSize * 1.10
        default: scaledSize = baseSize
        }
        let boldDescriptor = baseFont.fontDescriptor.withSymbolicTraits(.bold)
        return NSFont(descriptor: boldDescriptor, size: scaledSize) ?? baseFont
    }

    /// Render `**bold**` and `*italic*` markdown runs with bold / italic
    /// font traits added to whatever font is currently at that range.
    /// Stays plain on disk; the asterisks remain visible to the user.
    private static func styleBoldItalic(in storage: NSTextStorage, baseFont: NSFont) {
        let text = storage.string
        for match in text.matches(of: /\*\*([^*\n]+)\*\*/) {
            let nsRange = NSRange(match.range, in: text)
            let current = currentFont(in: storage, at: nsRange.location, fallback: baseFont)
            storage.addAttribute(.font, value: traitFont(current, traits: .bold), range: nsRange)
        }
        // Italic: *content*, skipping matches that touch another `*` on
        // either side (which would mean the match is part of a **bold**).
        // Swift Regex literals don't support lookbehind, so we filter
        // post-match instead.
        for match in text.matches(of: /\*([^*\n]+)\*/) {
            let r = match.range
            if r.lowerBound > text.startIndex,
               text[text.index(before: r.lowerBound)] == "*" {
                continue
            }
            if r.upperBound < text.endIndex, text[r.upperBound] == "*" {
                continue
            }
            let nsRange = NSRange(r, in: text)
            let current = currentFont(in: storage, at: nsRange.location, fallback: baseFont)
            storage.addAttribute(.font, value: traitFont(current, traits: .italic), range: nsRange)
        }
    }

    private static func currentFont(in storage: NSTextStorage, at location: Int, fallback: NSFont) -> NSFont {
        guard location < storage.length else { return fallback }
        return (storage.attributes(at: location, effectiveRange: nil)[.font] as? NSFont) ?? fallback
    }

    private static func traitFont(_ base: NSFont, traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let merged = base.fontDescriptor.symbolicTraits.union(traits)
        let descriptor = base.fontDescriptor.withSymbolicTraits(merged)
        return NSFont(descriptor: descriptor, size: base.pointSize) ?? base
    }

    /// Walks the storage line-by-line; for any line whose entire
    /// content is HR markers (the new `---` form, or the legacy
    /// `─` x N form from pre-0.1.38 files), set the foreground to
    /// `.clear` so the characters are invisible. The full-width
    /// rule is then drawn by `HorizontalRuleLayoutManager`.
    private static func styleHorizontalRules(in storage: NSTextStorage) {
        let ns = storage.string as NSString
        let total = ns.length
        var lineStart = 0
        while lineStart < total {
            let lineRange = ns.lineRange(for: NSRange(location: lineStart, length: 0))
            if HorizontalRuleLayoutManager.isHorizontalRuleLine(
                lineRange: lineRange, in: ns
            ) {
                var contentRange = lineRange
                if contentRange.length > 0,
                   ns.character(at: contentRange.location + contentRange.length - 1) == 0x0A {
                    contentRange.length -= 1
                }
                if contentRange.length > 0 {
                    storage.addAttribute(
                        .foregroundColor,
                        value: NSColor.clear,
                        range: contentRange
                    )
                }
            }
            lineStart = lineRange.location + lineRange.length
        }
    }

    private static func makeFont(face: FontFace, size: CGFloat) -> NSFont {
        if let font = NSFont(name: face.familyName, size: size) {
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
    final class Coordinator: NSObject, NSTextViewDelegate, NSGestureRecognizerDelegate {
        var text: Binding<String>
        var lastFocusToken: Int = 0
        var lastScrollToken: Int = 0
        var lastFindHighlightToken: Int = 0
        var lastFontSize: FontSize = .medium
        var lastFontFace: FontFace = .charter
        var lastTheme: Theme = .dark
        var lastTransparency: Transparency = .subtle

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string

            // A shortcode replacement calls didChangeText(), which
            // re-enters this method; that nested call does the restyle,
            // so bail out rather than styling the same text twice.
            if EmojiReplace.replaceIfMatched(in: textView) { return }

            if let storage = textView.textStorage {
                MinimalTextEditor.restyle(
                    storage, face: lastFontFace, size: lastFontSize,
                    theme: lastTheme, transparency: lastTransparency
                )
            }
        }

        // MARK: Checkbox clicks

        /// Only claim the click when it lands on a `[ ]`; every other
        /// click falls through to the text view untouched.
        func gestureRecognizerShouldBegin(_ recognizer: NSGestureRecognizer) -> Bool {
            guard let click = recognizer as? NSClickGestureRecognizer,
                  let textView = recognizer.view as? NSTextView else { return false }
            return Self.checkboxRange(in: textView, at: click.location(in: textView)) != nil
        }

        @objc func handleCheckboxClick(_ recognizer: NSClickGestureRecognizer) {
            guard let textView = recognizer.view as? NSTextView,
                  let box = Self.checkboxRange(in: textView, at: recognizer.location(in: textView))
            else { return }
            let state = NSRange(location: box.location + 1, length: 1)
            let current = (textView.string as NSString).substring(with: state)
            replace(in: textView, range: state, with: current == " " ? "x" : " ")
        }

        /// The `[ ]` marker under `point`, in document coordinates.
        private static func checkboxRange(in textView: NSTextView, at point: NSPoint) -> NSRange? {
            guard let layoutManager = textView.layoutManager,
                  let container = textView.textContainer,
                  layoutManager.numberOfGlyphs > 0 else { return nil }
            let origin = textView.textContainerOrigin
            let local = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
            var fraction: CGFloat = 0
            let glyph = layoutManager.glyphIndex(
                for: local, in: container, fractionOfDistanceThroughGlyph: &fraction
            )
            // glyphIndex clamps to the nearest glyph, so a click past
            // the end of a line would "hit" its last character. Require
            // the point to actually be inside the glyph.
            let bounds = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyph, length: 1), in: container
            )
            guard bounds.contains(local) else { return nil }

            let index = layoutManager.characterIndexForGlyph(at: glyph)
            let ns = textView.string as NSString
            guard index < ns.length else { return nil }
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
            return false
        }

        /// Intercept typed text. Used to convert `---` to a horizontal rule
        /// the moment the third hyphen is typed — no need for Enter.
        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
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
            guard beforeCursor == "--", afterCursor.isEmpty else { return true }

            let twoDashRange = NSRange(location: lineRange.location, length: 2)
            replaceWithHorizontalRule(in: textView, range: twoDashRange)
            return false  // suppress the typed "-"
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
            if SmartEditing.isHorizontalRuleTrigger(line) {
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

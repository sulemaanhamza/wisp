import SwiftUI
import AppKit

struct MinimalTextEditor: NSViewRepresentable {
    @Binding var text: String
    var focusToken: Int
    var fontSize: FontSize
    var theme: Theme

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.contentView.drawsBackground = false

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        let font = Self.makeFont(size: fontSize.pointSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.45

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

        Self.applyPalette(Palette.for(theme), to: textView, font: font, paragraph: paragraph)

        context.coordinator.lastFontSize = fontSize
        context.coordinator.lastTheme = theme
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        if context.coordinator.lastFontSize != fontSize {
            context.coordinator.lastFontSize = fontSize
            applyFont(to: textView)
        }
        if context.coordinator.lastTheme != theme {
            context.coordinator.lastTheme = theme
            let font = Self.makeFont(size: fontSize.pointSize)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineHeightMultiple = 1.45
            Self.applyPalette(Palette.for(theme), to: textView, font: font, paragraph: paragraph)
        }
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    private func applyFont(to textView: NSTextView) {
        let font = Self.makeFont(size: fontSize.pointSize)
        textView.font = font
        var attrs = textView.typingAttributes
        attrs[.font] = font
        textView.typingAttributes = attrs
        if let storage = textView.textStorage {
            let range = NSRange(location: 0, length: storage.length)
            storage.addAttributes([.font: font], range: range)
        }
    }

    private static func applyPalette(
        _ palette: Palette,
        to textView: NSTextView,
        font: NSFont,
        paragraph: NSParagraphStyle
    ) {
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
        if let storage = textView.textStorage {
            let range = NSRange(location: 0, length: storage.length)
            storage.addAttributes([.foregroundColor: palette.text], range: range)
            dimHorizontalRules(in: storage, palette: palette)
        }
    }

    /// Walks the storage and applies `palette.divider` to runs of 3+
    /// horizontal-rule glyphs (U+2500). Runs the divider should read as a
    /// hint between paragraphs, not match word-weight.
    private static func dimHorizontalRules(in storage: NSTextStorage, palette: Palette) {
        let ns = storage.string as NSString
        let hrChar: unichar = 0x2500
        let length = ns.length
        var runStart = -1
        var i = 0
        while i < length {
            if ns.character(at: i) == hrChar {
                if runStart < 0 { runStart = i }
            } else if runStart >= 0 {
                let runLen = i - runStart
                if runLen >= 3 {
                    storage.addAttribute(
                        .foregroundColor,
                        value: palette.divider,
                        range: NSRange(location: runStart, length: runLen)
                    )
                }
                runStart = -1
            }
            i += 1
        }
        if runStart >= 0 {
            let runLen = length - runStart
            if runLen >= 3 {
                storage.addAttribute(
                    .foregroundColor,
                    value: palette.divider,
                    range: NSRange(location: runStart, length: runLen)
                )
            }
        }
    }

    private static func makeFont(size: CGFloat) -> NSFont {
        for name in ["Charter", "Iowan Old Style", "New York"] {
            if let font = NSFont(name: name, size: size) {
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
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var lastFocusToken: Int = 0
        var lastFontSize: FontSize = .medium
        var lastTheme: Theme = .dark

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
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

        /// Replace `range` with the horizontal-rule glyph string + newline,
        /// move the cursor past it, and apply the dim divider color so the
        /// glyph reads as a hint immediately.
        private func replaceWithHorizontalRule(in textView: NSTextView, range: NSRange) {
            let replacement = SmartEditing.horizontalRule + "\n"
            replace(in: textView, range: range, with: replacement)
            let hrLength = (SmartEditing.horizontalRule as NSString).length
            let hrRange = NSRange(location: range.location, length: hrLength)
            textView.textStorage?.addAttribute(
                .foregroundColor,
                value: Palette.for(lastTheme).divider,
                range: hrRange
            )
        }

        private func replace(in textView: NSTextView, range: NSRange, with replacement: String) {
            guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
            textView.textStorage?.replaceCharacters(in: range, with: replacement)
            textView.didChangeText()
            let newCursor = range.location + (replacement as NSString).length
            textView.setSelectedRange(NSRange(location: newCursor, length: 0))
        }
    }
}

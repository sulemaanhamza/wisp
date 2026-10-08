import AppKit

/// The editor's text view. Its one job beyond NSTextView: a caret the
/// height of the text rather than the height of the line.
///
/// Lines are set at `MarkdownStyler.lineHeightMultiple`, and TextKit
/// puts that extra height above each line's glyphs. The stock caret
/// spans the whole line, so it stood a third taller than the letters
/// beside it. Keeping the bottom edge — the line's descent — and
/// trimming the top to the font's own ascent lines it up with the text.
final class CaretTextView: NSTextView {
    /// Colour of inline-math answers and reminder times. Setting it
    /// repaints: they aren't text, so a restyle alone wouldn't redraw them.
    var answerColor: NSColor = .tertiaryLabelColor {
        didSet { needsDisplay = true }
    }

    // drawBackground, not draw(_:): it's NSTextView's hook for extra
    // drawing and gets the same dirty rect. Overriding draw(_:) itself
    // changed how AppKit treats the view — font substitution ran on a
    // different schedule than on a stock text view — and nothing about
    // answers needs that.
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawAnswers(in: rect)
    }

    /// Each line's inline-math answer, just after its `=`, in the
    /// line's own font, dimmed. Drawn, never stored: the file holds
    /// exactly what was typed, and Tab turns an answer into real text.
    ///
    /// Done in the view rather than the layout manager, which only draws
    /// the glyphs inside the dirty rect. An answer sits past its line's
    /// last glyph, so repainting just the answer's patch found no
    /// glyphs and wiped it. Looking lines up across the full width
    /// finds the line however small the patch.
    private func drawAnswers(in dirtyRect: NSRect) {
        guard let layoutManager, let container = textContainer,
              let storage = textStorage, storage.length > 0 else { return }
        let origin = textContainerOrigin
        let band = NSRect(
            x: 0, y: dirtyRect.minY - origin.y,
            width: container.size.width, height: dirtyRect.height
        )
        let glyphs = layoutManager.glyphRange(forBoundingRect: band, in: container)
        guard glyphs.length > 0 else { return }
        let chars = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let ns = storage.string as NSString
        // An answer follows its `=` like typed text, in the line's font;
        // a reminder's time stands a little apart, in the body font —
        // the line's last character may be an emoji or a code span.
        storage.enumerateAttribute(.wispMathAnswer, in: chars) { value, range, _ in
            guard let answer = value as? String, range.length > 0 else { return }
            let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? bodyFont
            drawTrailing([(range.length == 1 ? " " : "") + answer], after: range, font: font,
                         layoutManager: layoutManager, container: container, origin: origin)
        }
        storage.enumerateAttribute(.wispReminder, in: chars) { value, range, _ in
            guard let label = value as? TrailingLabel, range.length > 0 else { return }
            let last = ns.character(at: NSMaxRange(range) - 1)
            let lead = last == 0x20 || last == 0x09 ? "  " : "   "
            drawTrailing([lead + label.full, lead + label.short, " " + label.short], fitting: true, after: range,
                         font: bodyFont, layoutManager: layoutManager, container: container, origin: origin)
        }
    }

    private var bodyFont: NSFont { font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize) }

    /// Text drawn just past the end of `range`, on its baseline. With
    /// `fitting`, the first of `candidates` that fits before the visible
    /// edge, or none — a time cut off by the panel's edge would read as
    /// a different time.
    private func drawTrailing(
        _ candidates: [String], fitting: Bool = false, after range: NSRange, font: NSFont,
        layoutManager: NSLayoutManager, container: NSTextContainer, origin: NSPoint
    ) {
        let last = layoutManager.glyphIndexForCharacter(at: NSMaxRange(range) - 1)
        guard last < layoutManager.numberOfGlyphs else { return }
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: last, length: 1), in: container)
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: last, effectiveRange: nil)
        let baseline = fragment.minY + layoutManager.location(forGlyphAt: last).y
        let x = origin.x + glyphRect.maxX
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: answerColor]
        let room = visibleRect.maxX - x - 4
        guard let text = fitting
            ? candidates.first(where: { ($0 as NSString).size(withAttributes: attributes).width <= room })
            : candidates.first
        else { return }
        NSAttributedString(string: text, attributes: attributes)
            .draw(at: NSPoint(x: x, y: origin.y + baseline - font.ascender))
    }

    /// ⌥↑ / ⌥↓ move lines. Handled here, in the note's own text view,
    /// rather than as menu shortcuts: a menu takes the key before any
    /// text field sees it, which cost the find field its ⌥↑.
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == .option, !hasMarkedText(),
           let key = event.charactersIgnoringModifiers?.unicodeScalars.first?.value,
           key == UInt32(NSUpArrowFunctionKey) || key == UInt32(NSDownArrowFunctionKey) {
            if let edit = LineEditing.moveLines(
                in: string, selection: selectedRange(), up: key == UInt32(NSUpArrowFunctionKey)
            ) {
                LineEditing.apply(edit, to: self)
            }
            return
        }
        super.keyDown(with: event)
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        super.drawInsertionPoint(in: Self.caretRect(in: rect, font: caretFont), color: color, turnedOn: flag)
    }

    /// The font of the text the caret sits in: the character before it
    /// on the same line, else the one after. Typing attributes won't do
    /// — in a plain-text view they stay the body font, so a caret on a
    /// heading was cut to body height.
    private var caretFont: NSFont? {
        guard let storage = textStorage, storage.length > 0 else { return font }
        let ns = storage.string as NSString
        let location = min(selectedRange().location, storage.length)
        var index: Int?
        if location > 0, !"\n\r\u{2028}\u{2029}".utf16.contains(ns.character(at: location - 1)) {
            index = location - 1
        } else if location < storage.length {
            index = location
        }
        guard let index else { return font }
        return storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont ?? font
    }

    /// `rect` trimmed to the font's ascent plus descent, bottom-aligned
    /// (the view is flipped, so the bottom is maxY). Pure for tests.
    static func caretRect(in rect: NSRect, font: NSFont?) -> NSRect {
        guard let font else { return rect }
        let height = (font.ascender - font.descender).rounded(.up)
        guard height < rect.height else { return rect }
        return NSRect(x: rect.minX, y: rect.maxY - height, width: rect.width, height: height)
    }
}

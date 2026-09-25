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
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        super.drawInsertionPoint(in: Self.caretRect(in: rect, font: caretFont), color: color, turnedOn: flag)
    }

    private var caretFont: NSFont? {
        if let font = typingAttributes[.font] as? NSFont { return font }
        return font
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

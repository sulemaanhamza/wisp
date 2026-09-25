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

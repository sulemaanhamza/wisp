import AppKit

/// NSLayoutManager subclass that paints a full-width horizontal rule
/// over any line whose entire content is HR markers (`-` and/or `─`,
/// 3+ characters). The HR characters themselves are kept in storage
/// (so the file on disk stays plain markdown — `---`) but rendered
/// with `foregroundColor = .clear` from the styling pass, so the only
/// visible thing on the line is the rule we draw here.
///
/// The line spans the line fragment's full width, which means it
/// tracks panel-width changes for free — resize the window and the
/// rule grows/shrinks with it.
final class HorizontalRuleLayoutManager: NSLayoutManager {
    /// Color used when stroking the rule. The editor updates this on
    /// every theme flip via applyPalette.
    var ruleColor: NSColor = .secondaryLabelColor

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)

        guard let textStorage = textStorage,
              let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        let nsString = textStorage.string as NSString
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        var lineStart = charRange.location
        let charEnd = charRange.location + charRange.length
        while lineStart < charEnd {
            let lineRange = nsString.lineRange(for: NSRange(location: lineStart, length: 0))
            if Self.isHorizontalRuleLine(lineRange: lineRange, in: nsString) {
                let glyphRange = self.glyphRange(
                    forCharacterRange: lineRange,
                    actualCharacterRange: nil
                )
                if glyphRange.length > 0 {
                    let fragmentRect = lineFragmentRect(
                        forGlyphAt: glyphRange.location,
                        effectiveRange: nil
                    )
                    let cy = origin.y + fragmentRect.midY
                    let lineRect = CGRect(
                        x: origin.x + fragmentRect.minX,
                        y: cy - 0.5,
                        width: fragmentRect.width,
                        height: 1.0
                    )
                    context.saveGState()
                    context.setFillColor(ruleColor.cgColor)
                    context.fill(lineRect)
                    context.restoreGState()
                }
            }
            lineStart = lineRange.location + lineRange.length
        }
    }

    /// Pure: is the given line content (a line range in `nsString`)
    /// an HR-only line — at least three characters, all of which are
    /// either `-` (0x2D) or `─` (0x2500), with the trailing newline
    /// allowed. Public so SelfTests can exercise it.
    static func isHorizontalRuleLine(lineRange: NSRange, in nsString: NSString) -> Bool {
        var contentEnd = lineRange.location + lineRange.length
        if contentEnd > lineRange.location,
           nsString.character(at: contentEnd - 1) == 0x0A {
            contentEnd -= 1
        }
        let contentLength = contentEnd - lineRange.location
        if contentLength < 3 { return false }
        for i in 0..<contentLength {
            let c = nsString.character(at: lineRange.location + i)
            if c != 0x2D && c != 0x2500 { return false }
        }
        return true
    }

    /// Convenience for tests — takes a Swift String, treats the whole
    /// thing as the line content (no trailing newline expected).
    static func isHorizontalRuleLine(_ line: String) -> Bool {
        let ns = line as NSString
        return isHorizontalRuleLine(
            lineRange: NSRange(location: 0, length: ns.length),
            in: ns
        )
    }
}

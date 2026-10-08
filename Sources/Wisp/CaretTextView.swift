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
        // An answer follows its `=` like typed text, in the line's font.
        storage.enumerateAttribute(.wispMathAnswer, in: chars) { value, range, _ in
            guard let answer = value as? String, range.length > 0 else { return }
            let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? bodyFont
            if let place = placement([(range.length == 1 ? " " : "", answer)], symbol: nil, fitting: false,
                                     after: range, font: font) {
                draw(place, symbol: nil, font: font, strong: false)
            }
        }
        // A reminder's time stands a little apart, in the body font — the
        // line's last character may be an emoji or a code span.
        storage.enumerateAttribute(.wispReminder, in: chars) { value, range, _ in
            guard let label = value as? TrailingLabel, range.length > 0,
                  let (place, symbol) = reminderPlacement(label, after: range) else { return }
            draw(place, symbol: symbol, font: bodyFont, strong: hoveredTick == NSMaxRange(range))
        }
    }

    /// Where trailing text lands: the text chosen, where it starts, and
    /// the symbol's rect, if there is one.
    private struct Placement {
        let text: String
        let textOrigin: NSPoint
        let symbolRect: NSRect?
    }

    /// A reminder's label after `range`, the attribute's run on its line.
    /// Drawing and clicking both go through here, so the tick is clicked
    /// exactly where it's drawn.
    private func reminderPlacement(_ label: TrailingLabel, after range: NSRange) -> (Placement, NSImage?)? {
        guard let storage = textStorage, NSMaxRange(range) <= storage.length else { return nil }
        let last = (storage.string as NSString).character(at: NSMaxRange(range) - 1)
        let lead = last == 0x20 || last == 0x09 ? "  " : "   "
        let symbol = label.symbol.flatMap { symbolImage($0, font: bodyFont) }
        var candidates = [(lead, label.full), (lead, label.short), (" ", label.short)]
        // The symbol alone still says "set", or still offers the tick.
        if symbol != nil { candidates.append((" ", "")) }
        return placement(candidates, symbol: symbol, fitting: true, after: range, font: bodyFont).map { ($0, symbol) }
    }

    private var symbolCache: (key: String, image: NSImage)?

    /// An SF Symbol at the text's size, in the answer colour without its
    /// transparency — that's applied once, when drawing; in the colour
    /// itself it was applied twice and the bell came out fainter than
    /// the time beside it.
    private func symbolImage(_ name: String, font: NSFont) -> NSImage? {
        let key = "\(name) \(font.pointSize) \(answerColor)"
        if let cached = symbolCache, cached.key == key { return cached.image }
        let config = NSImage.SymbolConfiguration(pointSize: font.pointSize * 0.8, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [answerColor.withAlphaComponent(1)]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        symbolCache = (key, image)
        return image
    }

    private var bodyFont: NSFont { font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize) }

    /// Text placed just past the end of `range`, on its baseline: a lead
    /// of spaces, `symbol` if any, then the text. With `fitting`, the
    /// first of `candidates` that fits before the visible edge, or none
    /// — a time cut off by the panel's edge would read as a different
    /// time.
    private func placement(
        _ candidates: [(lead: String, text: String)], symbol: NSImage?, fitting: Bool,
        after range: NSRange, font: NSFont
    ) -> Placement? {
        guard let layoutManager, let container = textContainer, NSMaxRange(range) > 0 else { return nil }
        let origin = textContainerOrigin
        let last = layoutManager.glyphIndexForCharacter(at: NSMaxRange(range) - 1)
        guard last < layoutManager.numberOfGlyphs else { return nil }
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: last, length: 1), in: container)
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: last, effectiveRange: nil)
        let baseline = fragment.minY + layoutManager.location(forGlyphAt: last).y
        let x = origin.x + glyphRect.maxX
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        func width(_ text: String) -> CGFloat { (text as NSString).size(withAttributes: attributes).width }
        let space = width(" ")
        let symbolWidth = symbol.map { $0.size.width } ?? 0
        func total(_ c: (lead: String, text: String)) -> CGFloat {
            width(c.lead) + (symbol == nil ? 0 : symbolWidth + (c.text.isEmpty ? 0 : space)) + width(c.text)
        }
        let room = visibleRect.maxX - x - 4
        guard let chosen = fitting ? candidates.first(where: { total($0) <= room }) : candidates.first else { return nil }
        var at = x + width(chosen.lead)
        var symbolRect: NSRect?
        if let symbol {
            // Centred on the capitals, like the text beside it. The view
            // is flipped: down is +y.
            let middle = origin.y + baseline - font.capHeight / 2
            symbolRect = NSRect(x: at, y: middle - symbol.size.height / 2, width: symbol.size.width, height: symbol.size.height)
            at += symbolWidth + space
        }
        return Placement(text: chosen.text, textOrigin: NSPoint(x: at, y: origin.y + baseline - font.ascender), symbolRect: symbolRect)
    }

    /// `strong`: the symbol at full strength, under the pointer.
    private func draw(_ place: Placement, symbol: NSImage?, font: NSFont, strong: Bool) {
        if let symbol, let rect = place.symbolRect {
            symbol.draw(in: rect, from: .zero, operation: .sourceOver,
                        fraction: strong ? 1 : answerColor.alphaComponent, respectFlipped: true, hints: nil)
        }
        NSAttributedString(string: place.text, attributes: [.font: font, .foregroundColor: answerColor])
            .draw(at: place.textOrigin)
    }

    // MARK: The tick on a sent reminder

    /// The end of the label whose tick is under the pointer: drawn at
    /// full strength, with a pointing hand.
    private var hoveredTick: Int? {
        didSet {
            guard hoveredTick != oldValue else { return }
            needsDisplay = true
            toolTip = hoveredTick == nil ? nil : "Mark done"
        }
    }

    private var tickTracking: NSTrackingArea?

    /// The line whose reminder tick is under `point` — the range of its
    /// text, without the line break — or nil.
    func reminderTick(at point: NSPoint) -> NSRange? {
        tickHit(at: point)?.line
    }

    private func tickHit(at point: NSPoint) -> (line: NSRange, labelEnd: Int)? {
        guard let layoutManager, let container = textContainer, let storage = textStorage,
              storage.length > 0, layoutManager.numberOfGlyphs > 0 else { return nil }
        let origin = textContainerOrigin
        let glyph = layoutManager.glyphIndex(for: NSPoint(x: point.x - origin.x, y: point.y - origin.y), in: container)
        let ns = storage.string as NSString
        let index = min(layoutManager.characterIndexForGlyph(at: glyph), ns.length - 1)
        var start = 0, end = 0, contentsEnd = 0
        ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: index, length: 0))
        var hit: (NSRange, Int)?
        storage.enumerateAttribute(.wispReminder, in: NSRange(location: start, length: end - start)) { value, range, stop in
            guard let label = value as? TrailingLabel, label.ticksLine, range.length > 0,
                  let rect = reminderPlacement(label, after: range)?.0.symbolRect,
                  rect.insetBy(dx: -4, dy: -4).contains(point) else { return }
            hit = (NSRange(location: start, length: contentsEnd - start), NSMaxRange(range))
            stop.pointee = true
        }
        return hit
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tickTracking, trackingAreas.contains(tickTracking) { return }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        tickTracking = area
    }

    // After NSTextView's own handling, which sets the I-beam on every
    // move: over a tick, the pointing hand wins.
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        hoveredTick = tickHit(at: convert(event.locationInWindow, from: nil))?.labelEnd
        if hoveredTick != nil { NSCursor.pointingHand.set() }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hoveredTick = nil
    }

    override func didChangeText() {
        hoveredTick = nil
        super.didChangeText()
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

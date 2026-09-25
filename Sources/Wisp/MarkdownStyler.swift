import AppKit

extension NSAttributedString.Key {
    /// The URL a run of text points at. Deliberately not `.link`:
    /// NSTextView follows `.link` on a plain click, which would make the
    /// text of a URL impossible to click into and edit. ⌘-click opens it.
    static let wispLink = NSAttributedString.Key("wispLink")
}

/// The styling pass behind the editor: headings, emphasis, code, rules,
/// ticked items and links, all as attributes over plain markdown.
///
/// Everything here is line-local except fenced code blocks, whose
/// extent depends on every fence above a line. That's what makes
/// restyling only the edited paragraph safe: the fences are re-listed
/// on each pass (a substring search, well under a millisecond on a
/// large note), and if an edit changed which lines are inside a block
/// the whole document is restyled instead.
@MainActor
enum MarkdownStyler {
    nonisolated static let lineHeightMultiple: CGFloat = 1.35

    private static let boldPattern = try! NSRegularExpression(pattern: #"\*\*([^*\n]+)\*\*"#)
    private static let italicPattern = try! NSRegularExpression(pattern: #"\*([^*\n]+)\*"#)
    private static let codePattern = try! NSRegularExpression(pattern: #"`([^`\n]+)`"#)
    private static let headingPattern = try! NSRegularExpression(pattern: #"^(#{1,6})\s+\S"#)
    /// http(s) URLs, not ending on sentence punctuation. A pattern
    /// rather than NSDataDetector: the detector's answer for a line
    /// depends on the text around it, which a paragraph restyle can't
    /// reproduce.
    private static let linkPattern = try! NSRegularExpression(
        pattern: #"\bhttps?://[^\s<>"'`]*[^\s<>"'`.,;:!?)\]*]"#
    )

    nonisolated static func bodyParagraph() -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = lineHeightMultiple
        return paragraph
    }

    /// Restyle `storage`. With `edited`, only the paragraphs it touches
    /// are restyled, unless the edit moved a code-block boundary.
    static func restyle(
        _ storage: NSTextStorage,
        face: FontFace,
        size: FontSize,
        theme: Theme,
        transparency: Transparency,
        edited: NSRange? = nil
    ) {
        let ns = storage.string as NSString
        guard ns.length > 0 else { return }
        let fences = fenceLineStarts(in: ns)
        var range = NSRange(location: 0, length: ns.length)
        if let edited {
            let start = min(max(0, edited.location), ns.length)
            // One character past the edit: an edit ending in a newline
            // hands the next line a new start, and line-level styles
            // (heading, task, rule) depend on where a line starts.
            let end = min(max(start, NSMaxRange(edited)) + 1, ns.length)
            let dirty = ns.paragraphRange(for: NSRange(location: start, length: end - start))
            if blocksUnchanged(after: dirty, in: storage, fences: fences) {
                range = dirty
            }
        }
        guard range.length > 0 else { return }

        let style = Style(face: face, size: size, theme: theme, transparency: transparency)
        storage.beginEditing()
        defer { storage.endEditing() }
        // Replace, not add: anything a pass applied last time has to go,
        // or it outlives the text that justified it — a reopened
        // checkbox would stay struck through, a deleted fence would keep
        // its panel. The editor never restyles mid-composition, so
        // there's no input-method underline here to wipe.
        storage.setAttributes([
            .font: style.base,
            .foregroundColor: style.palette.text,
            .paragraphStyle: style.body,
        ], range: range)
        // One String for the regex passes. The storage's backing string
        // is mutable, so every `as String` is a full copy — done per
        // heading, that made a large note quadratic.
        let text = ns as String
        styleLines(in: range, storage: storage, ns: ns, text: text, fences: fences, style: style)
        styleInline(in: range, storage: storage, ns: ns, text: text, style: style)
    }

    // MARK: Lines

    private static func styleLines(
        in range: NSRange, storage: NSTextStorage, ns: NSString, text: String,
        fences: [Int], style: Style
    ) {
        var lineStart = range.location
        let end = NSMaxRange(range)
        while lineStart < end {
            let lineRange = ns.lineRange(for: NSRange(location: lineStart, length: 0))
            lineStart = NSMaxRange(lineRange)
            var content = lineRange
            if content.length > 0, ns.character(at: NSMaxRange(content) - 1) == 0x0A {
                content.length -= 1
            }

            let isFence = contains(fences, lineRange.location)
            if isFence || isInsideBlock(lineRange.location, fences: fences) {
                // The ground is drawn by HorizontalRuleLayoutManager from
                // .wispCodeBlock, full width; an attribute background
                // would stop at each line's last glyph.
                storage.addAttributes([.font: style.mono, .wispCodeBlock: true], range: lineRange)
                if isFence, content.length > 0 {
                    storage.addAttribute(.foregroundColor, value: style.syntax, range: content)
                }
                continue
            }
            guard content.length > 0 else { continue }

            if HorizontalRuleLayoutManager.isHorizontalRuleLine(lineRange: lineRange, in: ns) {
                // The rule itself is drawn by the layout manager.
                storage.addAttribute(.foregroundColor, value: NSColor.clear, range: content)
                continue
            }

            let first = ns.character(at: content.location)
            if first == 0x23,  // #
               let match = headingPattern.firstMatch(in: text, range: content) {
                let hashes = match.range(at: 1)
                storage.addAttributes([
                    .font: style.heading(level: hashes.length),
                    .paragraphStyle: style.headingParagraph,
                ], range: content)
                storage.addAttribute(.foregroundColor, value: style.syntax, range: hashes)
                continue
            }

            if mayBeTask(ns, content) {
                styleCheckedItem(content, storage: storage, ns: ns, style: style)
            }
        }
    }

    /// A ticked item reads as done: the whole line dims and the text
    /// after the box is struck through. The file still says `- [x]`.
    private static func styleCheckedItem(
        _ content: NSRange, storage: NSTextStorage, ns: NSString, style: Style
    ) {
        let line = ns.substring(with: content)
        guard Checkbox.isChecked(line), let box = Checkbox.boxRange(in: line) else { return }
        storage.addAttribute(.foregroundColor, value: style.done, range: content)
        let textStart = content.location + NSMaxRange(box)
        let textLength = NSMaxRange(content) - textStart
        guard textLength > 0 else { return }
        storage.addAttributes([
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .strikethroughColor: style.done,
        ], range: NSRange(location: textStart, length: textLength))
    }

    /// Cheap pre-check so ordinary lines never allocate a substring.
    private static func mayBeTask(_ ns: NSString, _ content: NSRange) -> Bool {
        var i = content.location
        let end = NSMaxRange(content)
        while i < end, ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 { i += 1 }
        guard i < end else { return false }
        let c = ns.character(at: i)
        return c == 0x2D || c == 0x2A || c == 0x2B
    }

    // MARK: Inline

    private static func styleInline(
        in range: NSRange, storage: NSTextStorage, ns: NSString, text: String, style: Style
    ) {
        func inCodeBlock(_ r: NSRange) -> Bool {
            storage.attribute(.wispCodeBlock, at: r.location, effectiveRange: nil) != nil
        }
        func dim(_ location: Int, _ length: Int) {
            storage.addAttribute(
                .foregroundColor, value: style.syntax,
                range: NSRange(location: location, length: length)
            )
        }

        boldPattern.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let r = match?.range, !inCodeBlock(r) else { return }
            let current = storage.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont
            storage.addAttribute(.font, value: style.adding(.bold, to: current), range: r)
            dim(r.location, 2)
            dim(NSMaxRange(r) - 2, 2)
        }
        italicPattern.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let r = match?.range, !inCodeBlock(r) else { return }
            // A `*` on either side means this is half of a **bold**.
            if r.location > 0, ns.character(at: r.location - 1) == 0x2A { return }
            if NSMaxRange(r) < ns.length, ns.character(at: NSMaxRange(r)) == 0x2A { return }
            let current = storage.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont
            storage.addAttribute(.font, value: style.adding(.italic, to: current), range: r)
            dim(r.location, 1)
            dim(NSMaxRange(r) - 1, 1)
        }
        codePattern.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let r = match?.range, !inCodeBlock(r) else { return }
            storage.addAttributes([.font: style.mono, .backgroundColor: style.codeBackground], range: r)
            dim(r.location, 1)
            dim(NSMaxRange(r) - 1, 1)
        }
        linkPattern.enumerateMatches(in: text, range: range) { match, _, _ in
            // Inline code is the one other place a URL is just text.
            guard let r = match?.range, !inCodeBlock(r),
                  storage.attribute(.backgroundColor, at: r.location, effectiveRange: nil) == nil,
                  let url = URL(string: ns.substring(with: r)) else { return }
            storage.addAttributes([
                .wispLink: url,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: style.syntax,
            ], range: r)
        }
    }

    // MARK: Fences

    /// Start offsets of every line that opens or closes a fenced block:
    /// optional leading whitespace, then three backticks. Ascending.
    static func fenceLineStarts(in ns: NSString) -> [Int] {
        var starts: [Int] = []
        var searchFrom = 0
        while searchFrom < ns.length {
            let hit = ns.range(
                of: "```", options: .literal,
                range: NSRange(location: searchFrom, length: ns.length - searchFrom)
            )
            guard hit.location != NSNotFound else { break }
            let line = ns.lineRange(for: NSRange(location: hit.location, length: 0))
            var i = line.location
            while i < hit.location, ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 {
                i += 1
            }
            if i == hit.location { starts.append(line.location) }
            searchFrom = NSMaxRange(line)
        }
        return starts
    }

    /// A non-fence line is inside a block when an odd number of fences
    /// open above it. An unclosed fence runs to the end of the document,
    /// so a block looks like code while you're still typing it.
    private static func isInsideBlock(_ lineStart: Int, fences: [Int]) -> Bool {
        countBelow(fences, lineStart) % 2 == 1
    }

    /// Would the lines after `dirty` still be styled correctly? Every
    /// one of them flips together when the fence count above changes,
    /// so checking the first ordinary line against its current
    /// attribute is enough.
    private static func blocksUnchanged(
        after dirty: NSRange, in storage: NSTextStorage, fences: [Int]
    ) -> Bool {
        let ns = storage.string as NSString
        var location = NSMaxRange(dirty)
        while location < ns.length {
            let line = ns.lineRange(for: NSRange(location: location, length: 0))
            if !contains(fences, line.location) {
                let expected = isInsideBlock(line.location, fences: fences)
                let actual = storage.attribute(.wispCodeBlock, at: line.location, effectiveRange: nil) != nil
                return expected == actual
            }
            location = NSMaxRange(line)
        }
        return true
    }

    private static func countBelow(_ sorted: [Int], _ value: Int) -> Int {
        var low = 0, high = sorted.count
        while low < high {
            let mid = (low + high) / 2
            if sorted[mid] < value { low = mid + 1 } else { high = mid }
        }
        return low
    }

    private static func contains(_ sorted: [Int], _ value: Int) -> Bool {
        let i = countBelow(sorted, value)
        return i < sorted.count && sorted[i] == value
    }

    // MARK: Fonts and colours for one pass

    @MainActor
    private struct Style {
        let base: NSFont
        let bold: NSFont
        let italic: NSFont
        let mono: NSFont
        let palette: Palette
        let syntax: NSColor
        let done: NSColor
        let codeBackground: NSColor
        let body: NSParagraphStyle
        let headingParagraph: NSParagraphStyle

        init(face: FontFace, size: FontSize, theme: Theme, transparency: Transparency) {
            base = MinimalTextEditor.makeFont(face: face, size: size.pointSize)
            bold = Self.trait(base, .bold)
            italic = Self.trait(base, .italic)
            mono = NSFont.monospacedSystemFont(ofSize: base.pointSize * 0.92, weight: .regular)
            palette = Palette.for(theme)
            syntax = palette.syntax
            done = palette.text.withAlphaComponent(0.4)
            codeBackground = Palette.codeBackground(for: theme, transparency: transparency)
            body = MarkdownStyler.bodyParagraph()
            let heading = NSMutableParagraphStyle()
            heading.lineHeightMultiple = MarkdownStyler.lineHeightMultiple
            heading.paragraphSpacingBefore = (base.pointSize * 0.4).rounded()
            headingParagraph = heading
        }

        /// H1 and H2 step up in size; H3 and below are bold at (nearly)
        /// body size, so a deep outline doesn't shout.
        func heading(level: Int) -> NSFont {
            let scale: CGFloat
            switch level {
            case 1: scale = 1.40
            case 2: scale = 1.20
            case 3: scale = 1.05
            default: scale = 1.0
            }
            let descriptor = base.fontDescriptor.withSymbolicTraits(.bold)
            return NSFont(descriptor: descriptor, size: (base.pointSize * scale).rounded()) ?? bold
        }

        func adding(_ traits: NSFontDescriptor.SymbolicTraits, to current: NSFont?) -> NSFont {
            guard let current, current != base else { return traits == .bold ? bold : italic }
            return Self.trait(current, traits)
        }

        static func trait(_ font: NSFont, _ traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
            let merged = font.fontDescriptor.symbolicTraits.union(traits)
            return NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(merged), size: font.pointSize) ?? font
        }
    }
}

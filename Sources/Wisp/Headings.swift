import Foundation

struct Heading: Identifiable, Equatable {
    let name: String
    let level: Int
    /// NSString character offset where the heading line starts, used for
    /// scrolling the text view to the section.
    let lineStart: Int

    var id: Int { lineStart }
}

extension String {
    /// Parse `#`-prefixed markdown headings out of the text. Returns one
    /// entry per heading line, in document order.
    ///
    /// This runs on every keystroke, over the whole note, so it reads
    /// UTF-16 units in place: a regex per heading line cost 6.5 ms a
    /// keystroke on a 100 KB note with a few hundred headings.
    func extractHeadings() -> [Heading] {
        let ns = self as NSString
        let total = ns.length
        guard total > 0 else { return [] }
        // One copy of the units, walked once. Asking NSString for each
        // line's range was most of what was left after the regex went.
        var units = [unichar](repeating: 0, count: total)
        ns.getCharacters(&units, range: NSRange(location: 0, length: total))
        var result: [Heading] = []
        var i = 0
        var atLineStart = true
        while i < total {
            let c = units[i]
            guard atLineStart, c == 0x23 else {  // #
                atLineStart = Self.isLineBreak(c)
                i += 1
                continue
            }
            let lineStart = i
            while i < total, units[i] == 0x23 { i += 1 }
            let level = i - lineStart
            var end = i
            while end < total, !Self.isLineBreak(units[end]) { end += 1 }
            // One to six, then at least one space before the name.
            if level <= 6, i < end, Self.isHeadingSpace(units[i]) {
                while i < end, Self.isHeadingSpace(units[i]) { i += 1 }
                // A vertical tab or form feed ends the name, as it did
                // when a regex read it.
                var nameEnd = i
                while nameEnd < end, units[nameEnd] != 0x0B, units[nameEnd] != 0x0C { nameEnd += 1 }
                let name = ns.substring(with: NSRange(location: i, length: nameEnd - i))
                    .trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    result.append(Heading(name: name, level: level, lineStart: lineStart))
                }
            }
            i = end
            atLineStart = false
        }
        return result
    }

    /// What the styler's `\s` takes for the gap after the hashes, so
    /// the top bar and the styling agree on what a heading is: space,
    /// tab, vertical tab, form feed and the Unicode space separators.
    /// Not zero-width characters.
    private static func isHeadingSpace(_ c: unichar) -> Bool {
        if c == 0x20 || c == 0x09 || c == 0x0B || c == 0x0C { return true }
        guard c > 0x7F, let scalar = UnicodeScalar(c) else { return false }
        return scalar.properties.generalCategory == .spaceSeparator
    }

    private static func isLineBreak(_ c: unichar) -> Bool {
        c == 0x0A || c == 0x0D || c == 0x85 || c == 0x2028 || c == 0x2029
    }
}

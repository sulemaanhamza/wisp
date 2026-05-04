import Foundation

enum SmartEditing {
    /// Plain-text horizontal rule, stored as the markdown-standard
    /// `---`. The visual full-width line is drawn by the custom layout
    /// manager (HorizontalRuleLayoutManager) — the on-disk text is
    /// just three dashes, so rendering tracks the panel's width and
    /// the file remains portable plain markdown.
    static let horizontalRule = "---"

    static func isHorizontalRuleTrigger(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == "---"
    }

    /// Given a line of text, return the marker to insert on the next line if
    /// this line is a list item. Returns `nil` if not a list, or the next
    /// marker (e.g. `"- "`, `"3. "`, `"B. "`). Returns an empty string when
    /// the current line is an empty list item — the caller should treat that
    /// as a signal to exit the list.
    static func nextListMarker(for line: String) -> String? {
        if let match = line.firstMatch(of: /^([-*+])\s/) {
            let bullet = String(match.1)
            if isEmptyAfter(match.range, in: line) { return "" }
            return "\(bullet) "
        }
        if let match = line.firstMatch(of: /^(\d+)\.\s/) {
            let n = Int(match.1) ?? 0
            if isEmptyAfter(match.range, in: line) { return "" }
            return "\(n + 1). "
        }
        if let match = line.firstMatch(of: /^([A-Z])\.\s/) {
            if isEmptyAfter(match.range, in: line) { return "" }
            let c = Character(String(match.1))
            guard c < "Z", let ascii = c.asciiValue else { return nil }
            return "\(Character(UnicodeScalar(ascii + 1))). "
        }
        if let match = line.firstMatch(of: /^([a-z])\.\s/) {
            if isEmptyAfter(match.range, in: line) { return "" }
            let c = Character(String(match.1))
            guard c < "z", let ascii = c.asciiValue else { return nil }
            return "\(Character(UnicodeScalar(ascii + 1))). "
        }
        return nil
    }

    private static func isEmptyAfter(_ range: Range<String.Index>, in line: String) -> Bool {
        line[range.upperBound...].trimmingCharacters(in: .whitespaces).isEmpty
    }
}

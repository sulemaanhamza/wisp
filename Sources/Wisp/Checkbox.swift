import Foundation

/// Markdown task list items: `- [ ] milk`, `- [x] milk`.
///
/// Stored exactly as markdown writes them, so the file stays portable.
/// Everything here is pure and UTF-16-indexed, matching NSTextView's
/// ranges, so the editor can hit-test a click against a box without
/// duplicating the parsing.
enum Checkbox {
    /// Range of the `[ ]` / `[x]` marker within a single line, or nil
    /// when the line isn't a task item. Leading whitespace is allowed
    /// so indented sub-tasks work.
    static func boxRange(in line: String) -> NSRange? {
        let ns = line as NSString
        var i = 0
        // Leading whitespace.
        while i < ns.length, ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 {
            i += 1
        }
        // Bullet marker.
        guard i < ns.length else { return nil }
        let bullet = ns.character(at: i)
        guard bullet == 0x2D || bullet == 0x2A || bullet == 0x2B else { return nil }  // - * +
        i += 1
        // Exactly one space between the bullet and the box.
        guard i < ns.length, ns.character(at: i) == 0x20 else { return nil }
        i += 1
        // The box itself: [ ], [x] or [X].
        guard i + 2 < ns.length, ns.character(at: i) == 0x5B else { return nil }      // [
        let state = ns.character(at: i + 1)
        guard state == 0x20 || state == 0x78 || state == 0x58 else { return nil }     // space x X
        guard ns.character(at: i + 2) == 0x5D else { return nil }                     // ]
        return NSRange(location: i, length: 3)
    }

    /// Is this line a task item that's been ticked off?
    static func isChecked(_ line: String) -> Bool {
        guard let box = boxRange(in: line) else { return false }
        let state = (line as NSString).character(at: box.location + 1)
        return state == 0x78 || state == 0x58
    }

    /// The line with its box flipped, or nil when there's no box.
    /// Only the character between the brackets changes, so the rest of
    /// the line — and the user's undo history — stays intact.
    static func toggling(_ line: String) -> String? {
        guard let box = boxRange(in: line) else { return nil }
        let ns = line as NSString
        let replacement = isChecked(line) ? " " : "x"
        return ns.replacingCharacters(
            in: NSRange(location: box.location + 1, length: 1),
            with: replacement
        )
    }
}

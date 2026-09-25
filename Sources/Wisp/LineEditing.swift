import AppKit

/// Whole-line edits bound to the keyboard: move lines up and down
/// (⌥↑ / ⌥↓) and turn a line into a task or tick it off (⌘L).
///
/// Each one is worked out as a pure `Edit` over the string and the
/// selection, UTF-16-indexed like NSTextView, so it's testable without
/// a text view; `apply` then routes it through the text view's normal
/// change path so it undoes like typing does.
enum LineEditing {
    struct Edit: Equatable {
        var range: NSRange
        var replacement: String
        var selection: NSRange
    }

    /// The lines a selection covers. A selection ending exactly at the
    /// start of a line doesn't take that line with it — that's how a
    /// triple-click selection of one line looks.
    static func lineRange(for selection: NSRange, in ns: NSString) -> NSRange {
        var covered = selection
        if covered.length > 0, NSMaxRange(covered) > 0,
           isLineBreak(ns.character(at: NSMaxRange(covered) - 1)) {
            covered.length -= 1
        }
        return ns.lineRange(for: covered)
    }

    /// Everything NSString.lineRange ends a line at: LF, CR (alone or
    /// before LF), and the Unicode line and paragraph separators — ⌃↩
    /// types U+2028, and a note edited on Windows arrives with CRLF.
    private static func isLineBreak(_ c: unichar) -> Bool {
        c == 0x0A || c == 0x0D || c == 0x2028 || c == 0x2029
    }

    /// A line split into its text and whatever ends it ("" for the last
    /// line of a note).
    static func splitTerminator(_ line: String) -> (body: String, terminator: String) {
        let ns = line as NSString
        var end = ns.length
        while end > 0, isLineBreak(ns.character(at: end - 1)) { end -= 1 }
        return (ns.substring(to: end), ns.substring(from: end))
    }

    static func moveLines(in text: String, selection: NSRange, up: Bool) -> Edit? {
        let ns = text as NSString
        let lines = lineRange(for: selection, in: ns)
        if up {
            guard lines.location > 0 else { return nil }
            let above = ns.lineRange(for: NSRange(location: lines.location - 1, length: 0))
            let (moved, other) = swapped(ns.substring(with: lines), ns.substring(with: above))
            return Edit(
                range: NSRange(location: above.location, length: above.length + lines.length),
                replacement: moved + other,
                selection: NSRange(
                    location: above.location + (selection.location - lines.location),
                    length: selection.length
                )
            )
        } else {
            guard NSMaxRange(lines) < ns.length else { return nil }
            let below = ns.lineRange(for: NSRange(location: NSMaxRange(lines), length: 0))
            let (other, moved) = swapped(ns.substring(with: below), ns.substring(with: lines))
            let shift = (other as NSString).length
            let replacement = other + moved
            // The last line may have gained a line break it's about to
            // give away; keep the selection inside the text either way.
            let end = lines.location + (replacement as NSString).length
            let location = min(lines.location + shift + (selection.location - lines.location), end)
            return Edit(
                range: NSRange(location: lines.location, length: lines.length + below.length),
                replacement: replacement,
                selection: NSRange(location: location, length: min(selection.length, end - location))
            )
        }
    }

    /// Put `first` before `second`. Only the last line of a document
    /// lacks a line break, so when it moves, the break that joined the
    /// two stays at the join — whichever kind of break it was.
    private static func swapped(_ first: String, _ second: String) -> (String, String) {
        let (body, terminator) = splitTerminator(first)
        guard terminator.isEmpty else { return (first, second) }
        let other = splitTerminator(second)
        return (body + other.terminator, other.body)
    }

    /// ⌘L: a plain line becomes `- [ ] line`, a bullet gains a box, and
    /// an existing box is ticked or unticked. Applied to every line the
    /// selection covers.
    static func toggleTask(in text: String, selection: NSRange) -> Edit {
        let ns = text as NSString
        let lines = lineRange(for: selection, in: ns)
        var out: [String] = []
        var firstDelta = 0
        var index = 0
        var location = lines.location
        while location < NSMaxRange(lines) || (index == 0 && lines.length == 0) {
            let line = ns.lineRange(for: NSRange(location: location, length: 0))
            let (content, terminator) = splitTerminator(ns.substring(with: line))
            let toggled = toggleTask(line: content)
            if index == 0 { firstDelta = (toggled as NSString).length - (content as NSString).length }
            out.append(toggled + terminator)
            index += 1
            if line.length == 0 { break }
            location = NSMaxRange(line)
        }
        let replacement = out.joined()
        let selectionOut: NSRange
        if selection.length == 0 {
            // Keep the caret on the same character of the line, never
            // letting it slip back into the marker.
            let lineStart = lines.location
            let offset = selection.location - lineStart
            let markerEnd = ((replacement as NSString).length > 0)
                ? taskTextStart(in: replacement) : 0
            selectionOut = NSRange(location: lineStart + max(offset + firstDelta, markerEnd), length: 0)
        } else {
            selectionOut = NSRange(location: lines.location, length: (replacement as NSString).length)
        }
        return Edit(range: lines, replacement: replacement, selection: selectionOut)
    }

    static func toggleTask(line: String) -> String {
        if let toggled = Checkbox.toggling(line) { return toggled }
        let ns = line as NSString
        let indentEnd = leadingWhitespace(ns)
        let indent = ns.substring(to: indentEnd)
        let rest = ns.substring(from: indentEnd)
        // A bullet keeps its marker; whatever separated it from the text
        // becomes the single space a task item needs.
        if let first = rest.first, "-*+".contains(first),
           rest.dropFirst().first == " " || rest.dropFirst().first == "\t" {
            let text = rest.dropFirst(2).drop { $0 == " " || $0 == "\t" }
            return indent + String(first) + " [ ] " + text
        }
        return indent + "- [ ] " + rest
    }

    /// Offset just past a task's `] `, within the first line of `text`.
    private static func taskTextStart(in text: String) -> Int {
        let ns = text as NSString
        let firstLine = splitTerminator(ns.substring(with: ns.lineRange(for: NSRange(location: 0, length: 0)))).body
        guard let box = Checkbox.boxRange(in: firstLine) else { return 0 }
        return min(NSMaxRange(box) + 1, (firstLine as NSString).length)
    }

    private static func leadingWhitespace(_ ns: NSString) -> Int {
        var i = 0
        while i < ns.length, ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 { i += 1 }
        return i
    }

    /// Route an edit through the text view so it's undoable and every
    /// text-change observer hears about it.
    @MainActor
    static func apply(_ edit: Edit, to textView: NSTextView) {
        guard textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textView.textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        // Selection first: didChangeText hands the text to observers
        // that read the caret, and it should already be where it lands.
        textView.setSelectedRange(edit.selection)
        textView.didChangeText()
        textView.scrollRangeToVisible(edit.selection)
    }
}

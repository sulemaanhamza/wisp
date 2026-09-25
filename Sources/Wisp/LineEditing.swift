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
           ns.character(at: NSMaxRange(covered) - 1) == 0x0A {
            covered.length -= 1
        }
        return ns.lineRange(for: covered)
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
            return Edit(
                range: NSRange(location: lines.location, length: lines.length + below.length),
                replacement: other + moved,
                selection: NSRange(
                    location: lines.location + shift + (selection.location - lines.location),
                    length: selection.length
                )
            )
        }
    }

    /// Put `first` before `second`. Only the last line of a document
    /// lacks a newline, so when it moves the newline has to move with
    /// the join rather than with the line.
    private static func swapped(_ first: String, _ second: String) -> (String, String) {
        guard !first.hasSuffix("\n") else { return (first, second) }
        return (first + "\n", String(second.dropLast()))
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
            var content = ns.substring(with: line)
            let newline = content.hasSuffix("\n")
            if newline { content.removeLast() }
            let toggled = toggleTask(line: content)
            if index == 0 { firstDelta = (toggled as NSString).length - (content as NSString).length }
            out.append(toggled + (newline ? "\n" : ""))
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
        let ns = line as NSString
        if let box = Checkbox.boxRange(in: line) {
            let state = ns.character(at: box.location + 1)
            return ns.replacingCharacters(
                in: NSRange(location: box.location + 1, length: 1),
                with: state == 0x20 ? "x" : " "
            )
        }
        let indentEnd = leadingWhitespace(ns)
        let indent = ns.substring(to: indentEnd)
        let rest = ns.substring(from: indentEnd)
        for bullet in ["- ", "* ", "+ "] where rest.hasPrefix(bullet) {
            return indent + bullet + "[ ] " + rest.dropFirst(bullet.count)
        }
        return indent + "- [ ] " + rest
    }

    /// Offset just past a task's `] `, within the first line of `text`.
    private static func taskTextStart(in text: String) -> Int {
        let firstLine = text.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
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
        textView.didChangeText()
        textView.setSelectedRange(edit.selection)
        textView.scrollRangeToVisible(edit.selection)
    }
}

import AppKit

@MainActor
enum EmojiReplace {
    /// Curated shortcode → emoji map. Tuple form (not a dict) so the order
    /// is stable and self-documenting. The third element is whether a word
    /// boundary at the start is required to trigger — true for word
    /// shortcodes that could otherwise match mid-word; false for ASCII
    /// smileys whose closer (`)` / `(`) is unambiguous in prose.
    private static let shortcodes: [(code: String, emoji: String, requiresBoundary: Bool)] = [
        (":rocket:",  "🚀", true),
        (":fire:",    "🔥", true),
        (":heart:",   "❤️", true),
        (":check:",   "✅", true),
        (":x:",       "❌", true),
        (":star:",    "⭐", true),
        (":bulb:",    "💡", true),
        (":warning:", "⚠️", true),
        (":)",        "🙂", false),
        (":(",        "🙁", false),
    ]

    static func replaceIfMatched(in textView: NSTextView) {
        let cursor = textView.selectedRange().location
        guard cursor > 0 else { return }
        let nsString = textView.string as NSString

        // Cap lookback at 12 chars (longest shortcode + a little).
        let lookback = min(cursor, 12)
        let preText = nsString.substring(with: NSRange(
            location: cursor - lookback,
            length: lookback
        ))

        for entry in shortcodes {
            guard preText.hasSuffix(entry.code) else { continue }

            let codeLen = (entry.code as NSString).length
            let codeStart = cursor - codeLen

            if entry.requiresBoundary, codeStart > 0 {
                let prev = nsString.character(at: codeStart - 1)
                if let scalar = UnicodeScalar(prev),
                   CharacterSet.alphanumerics.contains(scalar) {
                    continue
                }
            }

            let replaceRange = NSRange(location: codeStart, length: codeLen)
            guard textView.shouldChangeText(in: replaceRange, replacementString: entry.emoji) else { return }
            textView.textStorage?.replaceCharacters(in: replaceRange, with: entry.emoji)
            textView.didChangeText()
            let newCursor = codeStart + (entry.emoji as NSString).length
            textView.setSelectedRange(NSRange(location: newCursor, length: 0))
            return
        }
    }
}

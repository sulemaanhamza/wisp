import SwiftUI
import AppKit

private enum Palette {
    // Gruvbox-inspired warm cream on dark glass — easy on eyes for long writing sessions.
    static let text = NSColor(red: 0.92, green: 0.86, blue: 0.70, alpha: 1.0)        // #ebdbb2
    static let cursor = NSColor(red: 0.98, green: 0.95, blue: 0.78, alpha: 1.0)      // #fbf1c7
    static let selection = NSColor(red: 0.85, green: 0.75, blue: 0.55, alpha: 0.25)  // warm amber tint
}

struct MinimalTextEditor: NSViewRepresentable {
    @Binding var text: String
    var focusToken: Int
    var fontSize: FontSize

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.contentView.drawsBackground = false

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        let font = Self.makeFont(size: CGFloat(fontSize.rawValue))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.4

        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = font
        textView.textColor = Palette.text
        textView.insertionPointColor = Palette.cursor
        textView.selectedTextAttributes = [
            .backgroundColor: Palette.selection
        ]
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: Palette.text,
            .paragraphStyle: paragraph,
        ]
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindBar = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.string = text

        context.coordinator.lastFontSize = fontSize
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        if context.coordinator.lastFontSize != fontSize {
            context.coordinator.lastFontSize = fontSize
            applyFont(to: textView)
        }
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    private func applyFont(to textView: NSTextView) {
        let font = Self.makeFont(size: CGFloat(fontSize.rawValue))
        textView.font = font
        var attrs = textView.typingAttributes
        attrs[.font] = font
        textView.typingAttributes = attrs
        if let storage = textView.textStorage {
            let range = NSRange(location: 0, length: storage.length)
            storage.addAttributes([.font: font], range: range)
        }
    }

    private static func makeFont(size: CGFloat) -> NSFont {
        let baseDescriptor = NSFont.systemFont(ofSize: size).fontDescriptor
        let serifDescriptor = baseDescriptor.withDesign(.serif) ?? baseDescriptor
        return NSFont(descriptor: serifDescriptor, size: size) ?? NSFont.systemFont(ofSize: size)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var lastFocusToken: Int = 0
        var lastFontSize: FontSize = .medium

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                return handleEnter(in: textView)
            }
            return false
        }

        private func handleEnter(in textView: NSTextView) -> Bool {
            let s = textView.string as NSString
            let cursor = textView.selectedRange().location
            let lineRange = s.lineRange(for: NSRange(location: cursor, length: 0))
            var lineEnd = lineRange.location + lineRange.length
            if lineEnd > lineRange.location, s.character(at: lineEnd - 1) == 0x0A {
                lineEnd -= 1
            }
            let line = s.substring(with: NSRange(
                location: lineRange.location,
                length: lineEnd - lineRange.location
            ))

            guard let marker = SmartEditing.nextListMarker(for: line) else {
                return false
            }

            if marker.isEmpty {
                // Empty list item: strip the marker, drop a blank line, exit list.
                let stripRange = NSRange(
                    location: lineRange.location,
                    length: cursor - lineRange.location
                )
                replace(in: textView, range: stripRange, with: "\n")
            } else {
                // Continue the list with the next marker.
                let insert = "\n" + marker
                replace(in: textView, range: NSRange(location: cursor, length: 0), with: insert)
            }
            return true
        }

        private func replace(in textView: NSTextView, range: NSRange, with replacement: String) {
            guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
            textView.textStorage?.replaceCharacters(in: range, with: replacement)
            textView.didChangeText()
            let newCursor = range.location + (replacement as NSString).length
            textView.setSelectedRange(NSRange(location: newCursor, length: 0))
        }
    }
}

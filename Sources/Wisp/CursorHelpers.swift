import SwiftUI
import AppKit

extension View {
    /// Show the pointing-hand cursor while the user hovers this view.
    ///
    /// SwiftUI buttons on macOS don't change cursor by default, and a
    /// simple `.onHover { push/pop }` loses the race against AppKit
    /// tracking areas — NSTextView in particular keeps reasserting its
    /// I-beam cursor on every mouse move. So we use `onContinuousHover`
    /// to re-assert pointing-hand on every mouse position update inside
    /// the view, and `onHover` to flip back to arrow on exit.
    func pointerCursor() -> some View {
        modifier(PointerCursor())
    }

    /// Force the arrow cursor while hovering this view. Used to keep
    /// NSTextView's I-beam from bleeding through overlays placed on
    /// top of the editor — same `onContinuousHover` re-assert pattern
    /// as `pointerCursor`.
    func arrowCursor() -> some View {
        self.onContinuousHover { phase in
            if case .active = phase {
                NSCursor.arrow.set()
            }
        }
    }
}

/// The pointing hand is set a tick after each mouse move, not during
/// it. A button on a card sits over two other things that set a cursor
/// on the same move — the scrim behind the card (arrow) and the text
/// view under that (I-beam) — and whichever ran last won, which left
/// the card's buttons with an arrow. Going last settles it.
private struct PointerCursor: ViewModifier {
    @State private var inside = false

    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    inside = true
                    NSCursor.pointingHand.set()
                    DispatchQueue.main.async {
                        if inside { NSCursor.pointingHand.set() }
                    }
                case .ended:
                    inside = false
                    NSCursor.arrow.set()
                }
            }
    }
}

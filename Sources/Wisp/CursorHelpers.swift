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
        self
            .onContinuousHover { phase in
                if case .active = phase {
                    NSCursor.pointingHand.set()
                }
            }
            .onHover { hovering in
                if !hovering {
                    NSCursor.arrow.set()
                }
            }
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

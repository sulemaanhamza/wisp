import SwiftUI
import AppKit

extension View {
    /// Show the pointing-hand cursor while the user hovers this view.
    /// SwiftUI buttons on macOS don't change cursor by default, so any
    /// link-like interactive element needs this opt-in.
    func pointerCursor() -> some View {
        onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

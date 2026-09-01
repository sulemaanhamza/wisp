import AppKit

/// A borderless NSPanel that can still take keyboard focus.
/// NSPanel refuses to become key when it has no titlebar; overriding
/// `canBecomeKey` lets the embedded text editor accept input anyway.
final class FloatingPanel: NSPanel {
    /// Called when the user presses Esc. Return true if the cancel was
    /// handled (e.g., a help overlay was dismissed), false to fall
    /// through to the default behavior (orderOut the panel).
    var onCancel: (() -> Bool)?

    /// Performs the actual dismissal once Esc has gone unclaimed. The
    /// owner supplies this so every way out of the panel — Esc, the
    /// hotkey, the menu bar — runs the same save-and-checkpoint path.
    var onDismiss: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        if onCancel?() == true { return }
        if let onDismiss {
            onDismiss()
        } else {
            orderOut(nil)
        }
    }
}

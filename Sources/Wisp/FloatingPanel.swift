import AppKit

/// A borderless NSPanel that can still take keyboard focus.
/// NSPanel refuses to become key when it has no titlebar; overriding
/// `canBecomeKey` lets the embedded text editor accept input anyway.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

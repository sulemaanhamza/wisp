import AppKit

/// Persists the panel's frame (size + position) across launches so
/// summoning Wisp restores it where and how the user last left it,
/// instead of snapping back to default-centered every time.
///
/// The validation logic (is a saved frame still reachable on the
/// current screen arrangement?) is pure so it can be unit-tested
/// without a running NSApplication.
enum PanelFrameStore {
    static let key = "PanelFrame"

    /// A saved frame must keep at least this much of itself overlapping
    /// a screen, otherwise it's considered stranded (e.g., it was saved
    /// on an external monitor that's since been unplugged) and we fall
    /// back to centering. Enough that the user can always grab it.
    static let minVisible: CGFloat = 120

    /// Reject degenerate / absurd sizes from a corrupted default.
    static let minSize: CGFloat = 200

    static func save(_ frame: NSRect, defaults: UserDefaults = .standard) {
        defaults.set(NSStringFromRect(frame), forKey: key)
    }

    /// Pure: a frame that fits on `screen`, keeping the user's size and
    /// position wherever it already fits.
    ///
    /// A backstop, not a nicety. Whatever the cause — a stray resize, a
    /// screen that shrank, a bug like the one that let content grow the
    /// window — a panel taller than the display is unusable, and it
    /// persists, so every later launch is broken too. Clamping on both
    /// the way in and the way out means that state can't be reached.
    /// Pure: the screen a frame most belongs to — the one it overlaps
    /// most, or nil if it touches none. Restoring must clamp to *this*
    /// screen, not the main one; clamping to main dragged every panel
    /// kept on an external monitor back onto the laptop on each launch.
    static func bestScreen(for frame: NSRect, among screens: [NSRect]) -> NSRect? {
        var best: NSRect?
        var bestArea: CGFloat = 0
        for screen in screens {
            let overlap = frame.intersection(screen)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > bestArea {
                bestArea = area
                best = screen
            }
        }
        return best
    }

    static func clamped(_ frame: NSRect, to screen: NSRect) -> NSRect {
        var result = frame
        result.size.width = min(result.width, screen.width)
        result.size.height = min(result.height, screen.height)
        result.origin.x = min(max(result.minX, screen.minX), screen.maxX - result.width)
        result.origin.y = min(max(result.minY, screen.minY), screen.maxY - result.height)
        return result
    }

    static func load(defaults: UserDefaults = .standard) -> NSRect? {
        guard let s = defaults.string(forKey: key) else { return nil }
        let rect = NSRectFromString(s)
        if rect.isEmpty { return nil }
        return rect
    }

    /// Pure: is `frame` reachable given the current screens' visible
    /// frames? True when it's a sane size and overlaps some screen by
    /// at least `minVisible` in both dimensions.
    static func isUsable(_ frame: NSRect, onScreens screens: [NSRect]) -> Bool {
        guard frame.width >= minSize, frame.height >= minSize else { return false }
        for screen in screens {
            let overlap = frame.intersection(screen)
            if !overlap.isNull,
               overlap.width >= minVisible,
               overlap.height >= minVisible {
                return true
            }
        }
        return false
    }
}

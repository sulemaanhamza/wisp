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

    /// The smallest the panel can be dragged to. Below this the footer
    /// wraps and the text column is a few characters wide; at the
    /// extreme the panel could be narrowed until it all but vanished.
    static let smallest = NSSize(width: 440, height: 280)

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
        // Grown to the smallest usable size first (a frame saved before
        // there was one), then shrunk to the screen, which wins.
        result.size.width = min(max(result.width, smallest.width), screen.width)
        result.size.height = min(max(result.height, smallest.height), screen.height)
        result.origin.x = min(max(result.minX, screen.minX), screen.maxX - result.width)
        result.origin.y = min(max(result.minY, screen.minY), screen.maxY - result.height)
        return result
    }

    /// Pure: `frame` moved from one screen to another, at `size`, with
    /// its centre at the same fraction across and up the new screen as
    /// it was on the old one — centred stays centred — then fitted.
    static func carried(_ frame: NSRect, size: NSSize, from: NSRect, to: NSRect) -> NSRect {
        let fx = from.width > 0 ? (frame.midX - from.minX) / from.width : 0.5
        let fy = from.height > 0 ? (frame.midY - from.minY) / from.height : 0.5
        let center = NSPoint(x: to.minX + fx * to.width, y: to.minY + fy * to.height)
        let moved = NSRect(
            x: center.x - size.width / 2, y: center.y - size.height / 2,
            width: size.width, height: size.height
        )
        return clamped(moved, to: to)
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

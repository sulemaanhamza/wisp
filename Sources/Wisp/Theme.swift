import AppKit

enum Theme: String, CaseIterable {
    case dark
    case light

    var toggled: Theme {
        self == .dark ? .light : .dark
    }
}

struct Palette {
    let text: NSColor
    let cursor: NSColor
    let selection: NSColor
    /// Used for the horizontal-rule glyph run so it reads as a quieter
    /// hint than body text instead of competing with words.
    let divider: NSColor

    static func `for`(_ theme: Theme) -> Palette {
        switch theme {
        case .dark:
            // Warm off-white on dark glass — easy on eyes for long sessions.
            let text = NSColor(red: 0.95, green: 0.93, blue: 0.89, alpha: 1.0)
            return Palette(
                text: text,
                cursor: NSColor(red: 0.98, green: 0.97, blue: 0.93, alpha: 1.0),
                selection: NSColor(white: 1.0, alpha: 0.18),
                divider: text.withAlphaComponent(0.35)
            )
        case .light:
            // Clean white slate with near-black ink and a soft accent selection.
            let text = NSColor(white: 0.10, alpha: 1.0)
            return Palette(
                text: text,
                cursor: NSColor(white: 0.0, alpha: 1.0),
                selection: NSColor(red: 0.0, green: 0.40, blue: 1.0, alpha: 0.18),
                divider: text.withAlphaComponent(0.30)
            )
        }
    }
}

struct Chrome {
    let material: NSVisualEffectView.Material
    let tintColor: NSColor
    /// Color used for `panel.backgroundColor`. NSColor.clear doesn't produce
    /// a truly transparent panel bg — some default rendering happens at the
    /// corner gap (between rectangular window and rounded content). Using a
    /// solid color matching the rounded content surface makes the gap
    /// blend invisibly.
    let panelBackground: NSColor
    let appearance: NSAppearance.Name
    let borderColor: NSColor?
    let borderWidth: CGFloat

    static func `for`(_ theme: Theme) -> Chrome {
        switch theme {
        case .dark:
            return Chrome(
                material: .fullScreenUI,
                tintColor: NSColor(white: 0.0, alpha: 0.50),
                panelBackground: NSColor(white: 0.10, alpha: 1.0),
                appearance: .darkAqua,
                borderColor: nil,
                borderWidth: 0
            )
        case .light:
            return Chrome(
                material: .windowBackground,
                tintColor: NSColor.white,
                panelBackground: NSColor.white,
                appearance: .aqua,
                borderColor: NSColor(white: 0.0, alpha: 0.12),
                borderWidth: 1
            )
        }
    }
}

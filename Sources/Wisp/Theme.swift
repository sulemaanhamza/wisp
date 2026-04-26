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

    static func `for`(_ theme: Theme) -> Palette {
        switch theme {
        case .dark:
            // Warm off-white on dark glass — easy on eyes for long sessions.
            return Palette(
                text: NSColor(red: 0.95, green: 0.93, blue: 0.89, alpha: 1.0),
                cursor: NSColor(red: 0.98, green: 0.97, blue: 0.93, alpha: 1.0),
                selection: NSColor(white: 1.0, alpha: 0.18)
            )
        case .light:
            // Clean white slate with near-black ink and a soft accent selection.
            return Palette(
                text: NSColor(white: 0.10, alpha: 1.0),
                cursor: NSColor(white: 0.0, alpha: 1.0),
                selection: NSColor(red: 0.0, green: 0.40, blue: 1.0, alpha: 0.18)
            )
        }
    }
}

struct Chrome {
    let material: NSVisualEffectView.Material
    let tintColor: NSColor
    let appearance: NSAppearance.Name

    static func `for`(_ theme: Theme) -> Chrome {
        switch theme {
        case .dark:
            return Chrome(
                material: .fullScreenUI,
                tintColor: NSColor(white: 0.0, alpha: 0.50),
                appearance: .darkAqua
            )
        case .light:
            // Tint is fully opaque white, so the material underneath is
            // effectively hidden — the panel reads as a clean white card.
            return Chrome(
                material: .windowBackground,
                tintColor: NSColor.white,
                appearance: .aqua
            )
        }
    }
}

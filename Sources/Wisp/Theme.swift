import AppKit

enum Theme: String, CaseIterable {
    case dark
    case light
}

/// User-facing appearance preference. Persisted in UserDefaults under
/// the "Theme" key. Raw values "light"/"dark" are deliberately the same
/// as Theme's so a stored value from the pre-system-mode era still
/// loads correctly. `.system` resolves at runtime against
/// NSApp.effectiveAppearance.
enum ThemePreference: String, CaseIterable {
    case light
    case dark
    case system

    /// One-click cycle wired into the BottomBar button.
    var next: ThemePreference {
        switch self {
        case .light: return .dark
        case .dark: return .system
        case .system: return .light
        }
    }

    @MainActor func resolve() -> Theme {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system:
            let match = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
            return match == .darkAqua ? .dark : .light
        }
    }
}

/// Marks a run as belonging to a fenced code block, so the layout
/// manager can paint one full-width panel behind it instead of a
/// ragged background that stops at the end of each line.
extension NSAttributedString.Key {
    static let wispCodeBlock = NSAttributedString.Key("wispCodeBlock")
}

struct Palette {
    let text: NSColor
    let cursor: NSColor
    let selection: NSColor
    /// Used for the horizontal-rule glyph run so it reads as a quieter
    /// hint than body text instead of competing with words.
    let divider: NSColor
    /// Background drawn behind the current Find match (temporary layout
    /// attribute). Warm amber so it reads in both themes.
    let findHighlight: NSColor

    /// Ground behind `inline code` and fenced blocks.
    ///
    /// Deliberately a low-alpha overlay rather than a solid colour: it
    /// has to sit on a solid panel and a see-through one alike, and a
    /// solid swatch would punch a hole in the glass. It lifts as the
    /// panel gets more transparent, because the same 6% over a busy
    /// desktop reads as nothing at all.
    static func codeBackground(for theme: Theme, transparency: Transparency) -> NSColor {
        switch (theme, transparency) {
        case (.dark, .off):     return NSColor(white: 1.0, alpha: 0.08)
        case (.dark, .subtle):  return NSColor(white: 1.0, alpha: 0.10)
        case (.dark, .strong):  return NSColor(white: 1.0, alpha: 0.14)
        case (.light, .off):    return NSColor(white: 0.0, alpha: 0.055)
        case (.light, .subtle): return NSColor(white: 0.0, alpha: 0.07)
        case (.light, .strong): return NSColor(white: 0.0, alpha: 0.10)
        }
    }

    static func `for`(_ theme: Theme) -> Palette {
        switch theme {
        case .dark:
            // Warm off-white on dark glass — easy on eyes for long sessions.
            let text = NSColor(red: 0.95, green: 0.93, blue: 0.89, alpha: 1.0)
            return Palette(
                text: text,
                cursor: NSColor(red: 0.98, green: 0.97, blue: 0.93, alpha: 1.0),
                selection: NSColor(white: 1.0, alpha: 0.18),
                divider: text.withAlphaComponent(0.35),
                findHighlight: NSColor(red: 0.98, green: 0.78, blue: 0.28, alpha: 0.42)
            )
        case .light:
            // Clean white slate with near-black ink and a soft accent selection.
            let text = NSColor(white: 0.10, alpha: 1.0)
            return Palette(
                text: text,
                cursor: NSColor(white: 0.0, alpha: 1.0),
                selection: NSColor(red: 0.0, green: 0.40, blue: 1.0, alpha: 0.18),
                divider: text.withAlphaComponent(0.30),
                findHighlight: NSColor(red: 1.0, green: 0.82, blue: 0.18, alpha: 0.55)
            )
        }
    }
}

/// How much of the desktop shows through the panel. This is the useful
/// half of "add a settings screen": three steps on a menu rather than a
/// preferences window and a colour picker.
enum Transparency: String, CaseIterable {
    case off
    case subtle
    case strong

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .subtle: return "Subtle"
        case .strong: return "Strong"
        }
    }

    /// Opacity of the tint painted over the blur — 1.0 is a solid
    /// panel, lower lets the desktop through.
    ///
    /// The steps have to be far enough apart to actually see. A first
    /// cut used 0.92 for light/subtle to keep the light theme looking
    /// untouched, which made the whole control a no-op; `SelfTests`
    /// now asserts a minimum gap between the levels.
    func tintAlpha(for theme: Theme) -> CGFloat {
        switch (theme, self) {
        case (_, .off):           return 1.0
        case (.dark, .subtle):    return 0.50
        case (.dark, .strong):    return 0.22
        case (.light, .subtle):   return 0.72
        case (.light, .strong):   return 0.40
        }
    }

    /// Light text needs a darker ground and vice versa, so the tint is
    /// black in the dark theme and white in the light one. At `.off`
    /// the dark tint lifts off pure black — a solid panel, not a void.
    func tintColor(for theme: Theme) -> NSColor {
        switch theme {
        case .dark:
            return self == .off
                ? NSColor(white: 0.10, alpha: 1.0)
                : NSColor(white: 0.0, alpha: tintAlpha(for: theme))
        case .light:
            return NSColor(white: 1.0, alpha: tintAlpha(for: theme))
        }
    }
}

struct Chrome {
    let material: NSVisualEffectView.Material
    let tintColor: NSColor
    let appearance: NSAppearance.Name
    /// False for `.off`: no blur behind an opaque panel is wasted work.
    let usesVisualEffect: Bool

    static func `for`(_ theme: Theme, transparency: Transparency) -> Chrome {
        // One genuinely translucent material for both themes.
        // `.windowBackground` was the wrong choice for the light theme:
        // it's near-opaque by design, so no tint above it read as glass.
        Chrome(
            material: .fullScreenUI,
            tintColor: transparency.tintColor(for: theme),
            appearance: theme == .dark ? .darkAqua : .aqua,
            usesVisualEffect: transparency != .off
        )
    }
}

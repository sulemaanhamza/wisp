import AppKit
import Carbon.HIToolbox

/// A keyboard shortcut: Carbon-style keyCode + modifier mask.
struct HotKey: Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let `default` = HotKey(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey)
    )

    /// Human-readable string like "⌥Space" or "⌃⇧F".
    var displayString: String {
        var s = ""
        if (modifiers & UInt32(controlKey)) != 0 { s += "⌃" }
        if (modifiers & UInt32(optionKey))  != 0 { s += "⌥" }
        if (modifiers & UInt32(shiftKey))   != 0 { s += "⇧" }
        if (modifiers & UInt32(cmdKey))     != 0 { s += "⌘" }
        s += Self.keyName(for: keyCode)
        return s
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var c: UInt32 = 0
        if flags.contains(.command) { c |= UInt32(cmdKey) }
        if flags.contains(.option)  { c |= UInt32(optionKey) }
        if flags.contains(.shift)   { c |= UInt32(shiftKey) }
        if flags.contains(.control) { c |= UInt32(controlKey) }
        return c
    }

    private static let keyMap: [Int: String] = [
        kVK_Space: "Space",
        kVK_Return: "↩",
        kVK_Tab: "⇥",
        kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓",
        kVK_Home: "↖",
        kVK_End: "↘",
        kVK_PageUp: "⇞",
        kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Period: ".", kVK_ANSI_Comma: ",",
        kVK_ANSI_Slash: "/", kVK_ANSI_Backslash: "\\",
        kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'",
        kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Minus: "−", kVK_ANSI_Equal: "=",
        kVK_ANSI_Grave: "`",
    ]

    private static func keyName(for keyCode: UInt32) -> String {
        keyMap[Int(keyCode)] ?? "Key\(keyCode)"
    }
}

extension HotKey {
    private static let keyCodeKey = "HotKeyCode"
    private static let modifiersKey = "HotKeyMods"

    static func loadFromDefaults() -> HotKey? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: keyCodeKey) != nil else { return nil }
        let kc = UInt32(defaults.integer(forKey: keyCodeKey))
        let mods = UInt32(defaults.integer(forKey: modifiersKey))
        return HotKey(keyCode: kc, modifiers: mods)
    }

    func saveToDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(Int(keyCode), forKey: Self.keyCodeKey)
        defaults.set(Int(modifiers), forKey: Self.modifiersKey)
    }
}

import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let onClick: () -> Void
    private let currentFontFace: () -> FontFace
    private let onSelectFontFace: (FontFace) -> Void
    private let currentHotKey: () -> HotKey
    private let onSetHotKey: () -> Void

    init(
        onClick: @escaping () -> Void,
        currentFontFace: @escaping () -> FontFace,
        onSelectFontFace: @escaping (FontFace) -> Void,
        currentHotKey: @escaping () -> HotKey,
        onSetHotKey: @escaping () -> Void
    ) {
        self.onClick = onClick
        self.currentFontFace = currentFontFace
        self.onSelectFontFace = onSelectFontFace
        self.currentHotKey = currentHotKey
        self.onSetHotKey = onSetHotKey
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            // SF Symbol `wind` reads as "wisp" — a single curved stroke,
            // simpler and more on-brand than the default pencil glyph.
            let image = NSImage(systemSymbolName: "wind", accessibilityDescription: "Wisp")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(handleClick)
            // Receive right-click too so we can show a context menu with Quit.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func handleClick() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showContextMenu()
        } else {
            onClick()
        }
    }

    @objc private func openFromMenu() {
        onClick()
    }

    @objc private func selectFontFace(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let face = FontFace(rawValue: raw)
        else { return }
        onSelectFontFace(face)
    }

    @objc private func handleSetHotKey() {
        onSetHotKey()
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let openItem = NSMenuItem(
            title: "Open Wisp",
            action: #selector(openFromMenu),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        // Font submenu — current face shown with a checkmark.
        let fontMenuItem = NSMenuItem(title: "Font", action: nil, keyEquivalent: "")
        let fontMenu = NSMenu(title: "Font")
        let active = currentFontFace()
        for face in FontFace.allCases {
            let item = NSMenuItem(
                title: face.displayName,
                action: #selector(selectFontFace(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = face.rawValue
            item.state = (face == active) ? .on : .off
            fontMenu.addItem(item)
        }
        fontMenuItem.submenu = fontMenu
        menu.addItem(fontMenuItem)

        let hotKeyItem = NSMenuItem(
            title: "Set Shortcut…  (\(currentHotKey().displayString))",
            action: #selector(handleSetHotKey),
            keyEquivalent: ""
        )
        hotKeyItem.target = self
        menu.addItem(hotKeyItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: "Quit Wisp",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
}

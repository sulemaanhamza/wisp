import AppKit

@MainActor
final class MenuBarController: NSObject {
    /// Everything the menu can read or do. A struct rather than a
    /// dozen-plus init parameters — the menu kept growing and the call
    /// site had become impossible to read.
    struct Actions {
        var onOpen: () -> Void
        var onArchiveToInbox: () -> Void
        var currentFontFace: () -> FontFace
        var onSelectFontFace: (FontFace) -> Void
        var currentTransparency: () -> Transparency
        var onSelectTransparency: (Transparency) -> Void
        var currentHotKey: () -> HotKey
        var onSetHotKey: () -> Void
        var onShowAbout: () -> Void
        var currentLaunchAtLogin: () -> Bool
        var onToggleLaunchAtLogin: () -> Void
        var isStorageCustom: () -> Bool
        var onPickStorageLocation: () -> Void
        var onResetStorageLocation: () -> Void
        var onRevealScratchpad: () -> Void
        var onRevealInbox: () -> Void
        var onRevealHistory: () -> Void
    }

    private let statusItem: NSStatusItem
    private let actions: Actions

    init(actions: Actions) {
        self.actions = actions
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
            actions.onOpen()
        }
    }

    @objc private func openFromMenu() { actions.onOpen() }
    @objc private func handleArchive() { actions.onArchiveToInbox() }
    @objc private func handleSetHotKey() { actions.onSetHotKey() }
    @objc private func handleShowAbout() { actions.onShowAbout() }
    @objc private func handleToggleLaunchAtLogin() { actions.onToggleLaunchAtLogin() }
    @objc private func handlePickStorageLocation() { actions.onPickStorageLocation() }
    @objc private func handleResetStorageLocation() { actions.onResetStorageLocation() }
    @objc private func handleRevealScratchpad() { actions.onRevealScratchpad() }
    @objc private func handleRevealInbox() { actions.onRevealInbox() }
    @objc private func handleRevealHistory() { actions.onRevealHistory() }

    @objc private func selectFontFace(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let face = FontFace(rawValue: raw)
        else { return }
        actions.onSelectFontFace(face)
    }

    @objc private func selectTransparency(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let level = Transparency(rawValue: raw)
        else { return }
        actions.onSelectTransparency(level)
    }

    /// Built fresh on every right-click, so checkmarks and the shortcut
    /// label are always current without any menu-delegate bookkeeping.
    private func showContextMenu() {
        let menu = NSMenu()

        menu.addItem(item("Open Wisp", #selector(openFromMenu)))

        let archive = item("Archive to Inbox", #selector(handleArchive), key: "\r")
        archive.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(archive)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(submenu("Font", options: FontFace.allCases,
                             title: { $0.displayName },
                             value: { $0.rawValue },
                             isOn: { $0 == self.actions.currentFontFace() },
                             action: #selector(selectFontFace(_:))))

        menu.addItem(submenu("Transparency", options: Transparency.allCases,
                             title: { $0.displayName },
                             value: { $0.rawValue },
                             isOn: { $0 == self.actions.currentTransparency() },
                             action: #selector(selectTransparency(_:))))

        menu.addItem(item(
            "Set Shortcut…  (\(actions.currentHotKey().displayString))",
            #selector(handleSetHotKey)
        ))

        let launch = item("Launch at Login", #selector(handleToggleLaunchAtLogin))
        launch.state = actions.currentLaunchAtLogin() ? .on : .off
        menu.addItem(launch)

        menu.addItem(item("Storage Location…", #selector(handlePickStorageLocation)))
        if actions.isStorageCustom() {
            menu.addItem(item("Reset Storage Location", #selector(handleResetStorageLocation)))
        }

        // One submenu instead of three top-level "Reveal …" items.
        let revealItem = NSMenuItem(title: "Reveal in Finder", action: nil, keyEquivalent: "")
        let reveal = NSMenu(title: "Reveal in Finder")
        reveal.addItem(item("Scratchpad", #selector(handleRevealScratchpad)))
        reveal.addItem(item("Inbox", #selector(handleRevealInbox)))
        reveal.addItem(item("History", #selector(handleRevealHistory)))
        revealItem.submenu = reveal
        menu.addItem(revealItem)

        menu.addItem(item("About Wisp", #selector(handleShowAbout)))

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

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func submenu<T>(
        _ title: String,
        options: [T],
        title titleFor: (T) -> String,
        value: (T) -> String,
        isOn: (T) -> Bool,
        action: Selector
    ) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        for option in options {
            let child = item(titleFor(option), action)
            child.representedObject = value(option)
            child.state = isOn(option) ? .on : .off
            menu.addItem(child)
        }
        parent.submenu = menu
        return parent
    }
}

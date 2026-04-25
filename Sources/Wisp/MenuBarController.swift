import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let onClick: () -> Void

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "Wisp")
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
        menu.addItem(NSMenuItem(
            title: "Quit Wisp",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        // Standard pattern: temporarily install the menu so the system shows
        // it at the proper status-item location, then clear it so subsequent
        // left-clicks go back to the toggle action.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
}

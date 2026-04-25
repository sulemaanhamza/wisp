import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "Wisp")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(handleClick)
        }
    }

    @objc private func handleClick() {
        // Toggle wiring lands in a later commit.
    }
}

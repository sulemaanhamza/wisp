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
        }
    }

    @objc private func handleClick() {
        onClick()
    }
}

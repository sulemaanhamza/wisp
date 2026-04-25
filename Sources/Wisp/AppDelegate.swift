import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var panelController: PanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = PanelController()
        panelController = panel
        menuBarController = MenuBarController { [weak panel] in
            panel?.toggle()
        }
    }
}

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = EditorModel()
    private var menuBarController: MenuBarController?
    private var panelController: PanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenuBuilder.make(target: self)
        let panel = PanelController(model: model)
        panelController = panel
        menuBarController = MenuBarController { [weak panel] in
            panel?.toggle()
        }
    }

    @objc func setSmallFont(_ sender: Any?) { model.fontSize = .small }
    @objc func setMediumFont(_ sender: Any?) { model.fontSize = .medium }
    @objc func setLargeFont(_ sender: Any?) { model.fontSize = .large }
}

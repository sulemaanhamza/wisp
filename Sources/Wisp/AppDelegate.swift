import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = EditorModel()
    let updater = Updater()
    private var menuBarController: MenuBarController?
    private var panelController: PanelController?
    private let hotKey = HotKeyMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenuBuilder.make(target: self)
        let panel = PanelController(model: model, updater: updater)
        panelController = panel
        menuBarController = MenuBarController { [weak panel] in
            panel?.toggle()
        }
        // ⌥Space opens or dismisses the panel from anywhere.
        hotKey.register(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(optionKey)
        ) { [weak panel] in
            panel?.toggle()
        }
        Task { await updater.check() }
    }

    @objc func setSmallFont(_ sender: Any?) { model.fontSize = .small }
    @objc func setMediumFont(_ sender: Any?) { model.fontSize = .medium }
    @objc func setLargeFont(_ sender: Any?) { model.fontSize = .large }

    @objc func toggleBold(_ sender: Any?) {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        MarkdownWrap.toggle(in: textView, marker: "**")
    }

    @objc func toggleItalic(_ sender: Any?) {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        MarkdownWrap.toggle(in: textView, marker: "*")
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Flush any pending debounced save so quitting never loses the
        // last few keystrokes.
        model.flushSave()
    }
}

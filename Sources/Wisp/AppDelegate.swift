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
        menuBarController = MenuBarController(
            onClick: { [weak panel] in panel?.toggle() },
            currentFontFace: { [weak self] in self?.model.fontFace ?? .charter },
            onSelectFontFace: { [weak self] face in self?.model.fontFace = face },
            currentHotKey: { [weak self] in self?.model.hotKey ?? .default },
            onSetHotKey: { [weak self, weak panel] in
                panel?.openIfNeeded()
                self?.model.showHotKeyCapture = true
            },
            onShowAbout: { [weak self, weak panel] in
                // The Wisp panel is .floating-level so the standard
                // about panel (which opens at .normal) gets stuck
                // behind it. Dismissing first gives the about panel
                // the screen; user re-summons Wisp afterwards.
                panel?.dismiss()
                self?.showStandardAboutPanel()
            }
        )

        // Initial registration uses whatever the model loaded from
        // UserDefaults (or HotKey.default if it's a fresh install). If
        // even this fails — e.g. user's saved binding is now claimed by
        // some other app — we leave the app without a hotkey; the user
        // can rebind via the right-click menu.
        _ = registerHotKey(model.hotKey)

        // Mediator the capture overlay calls when the user picks a
        // combo. Tries Carbon registration; on failure we restore the
        // previous binding and surface a user-readable error.
        model.tryUpdateHotKey = { [weak self] hk in
            guard let self else { return "Internal error" }
            if self.registerHotKey(hk) {
                self.model.hotKey = hk
                return nil
            }
            // New binding rejected by Carbon — usually means another
            // app or macOS itself owns it. Re-register the previous
            // one so the user isn't left without any hotkey.
            _ = self.registerHotKey(self.model.hotKey)
            return "\(hk.displayString) is already used by another app or macOS. Try another combo."
        }

        Task { await updater.check() }
    }

    @discardableResult
    private func registerHotKey(_ hk: HotKey) -> Bool {
        hotKey.register(keyCode: hk.keyCode, modifiers: hk.modifiers) { [weak self] in
            self?.panelController?.toggle()
        }
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

    private func showStandardAboutPanel() {
        let credits = NSAttributedString(
            string: """
            A minimalist macOS scratchpad — open with one keypress, type, dismiss.

            MIT licensed. Source at github.com/sulemaanhamza/wisp.

            Body type set in Charter (default), Iowan Old Style, Hoefler Text, Palatino, Optima, or Avenir Next — all preinstalled on macOS.
            """,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Wisp",
            .applicationVersion: version,
            .credits: credits,
            .init(rawValue: "Copyright"): "© 2026 Suleman Hamza",
        ])
    }
}

import AppKit
import SwiftUI

private let panelSize = CGSize(width: 800, height: 640)
private let cornerRadius: CGFloat = 18

@MainActor
final class PanelController {
    private let panel: FloatingPanel
    private let model: EditorModel
    private let updater: Updater
    private let visualEffect: NSVisualEffectView
    private let tint: NSView
    private let inner: NSView
    private let outer: NSView
    private var frameObservers: [NSObjectProtocol] = []
    private var outsideClick: OutsideClickMonitor?
    /// Where "Open on Pointer's Screen" last put the panel. A frame
    /// Wisp chose isn't the user's placement, so it isn't saved.
    private var carriedFrame: NSRect?

    init(model: EditorModel, updater: Updater) {
        self.model = model
        self.updater = updater
        let contentRect = NSRect(origin: .zero, size: panelSize)
        panel = FloatingPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0)
        // System shadow follows the rendered alpha mask, so it shapes itself
        // around our rounded inner view automatically. Earlier we drew a
        // custom shadow on outer.layer with shadowPath — that one leaked
        // into the corner gap (between rectangular window bounds and
        // rounded content) and was the source of all the corner-bleed
        // through v0.1.23. Removing it entirely and using the system
        // shadow gave us back a clean rounded shadow with no corner leak.
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentMinSize = PanelFrameStore.smallest

        // Outer container: just hosts inner. No own shadow, no own bg.
        outer = NSView(frame: NSRect(origin: .zero, size: panelSize))
        outer.wantsLayer = true

        // Inner container: rounded clip via cornerRadius + masksToBounds.
        // No CAShapeLayer mask here — its fixed path didn't grow with
        // window resize, which hid the bottom bar when the user dragged
        // the panel larger. cornerRadius adapts automatically.
        inner = NSView()
        inner.wantsLayer = true
        inner.layer?.cornerRadius = cornerRadius
        inner.layer?.masksToBounds = true
        inner.translatesAutoresizingMaskIntoConstraints = false

        visualEffect = NSVisualEffectView()
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = cornerRadius
        visualEffect.layer?.masksToBounds = true
        visualEffect.translatesAutoresizingMaskIntoConstraints = false

        tint = NSView()
        tint.wantsLayer = true
        tint.layer?.cornerRadius = cornerRadius
        tint.layer?.masksToBounds = true
        tint.translatesAutoresizingMaskIntoConstraints = false

        let host = NSHostingView(rootView: EditorView(model: model, updater: updater))
        host.translatesAutoresizingMaskIntoConstraints = false
        // The panel's size is the user's business, never the content's.
        // Left at the default, the hosting view reports the SwiftUI
        // content's ideal height as an intrinsic size; because it's
        // pinned to the content view on all four edges with required
        // constraints, anything taller than the panel — the help
        // overlay — grew the window to fit, and the grown frame was
        // then persisted. That's how a panel ended up 2630pt tall on a
        // 1440pt screen.
        host.sizingOptions = []

        inner.addSubview(visualEffect)
        inner.addSubview(tint)
        inner.addSubview(host)
        outer.addSubview(inner)

        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: outer.topAnchor),
            inner.bottomAnchor.constraint(equalTo: outer.bottomAnchor),
            inner.leadingAnchor.constraint(equalTo: outer.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: outer.trailingAnchor),

            visualEffect.topAnchor.constraint(equalTo: inner.topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: inner.bottomAnchor),
            visualEffect.leadingAnchor.constraint(equalTo: inner.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: inner.trailingAnchor),

            tint.topAnchor.constraint(equalTo: inner.topAnchor),
            tint.bottomAnchor.constraint(equalTo: inner.bottomAnchor),
            tint.leadingAnchor.constraint(equalTo: inner.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: inner.trailingAnchor),

            host.topAnchor.constraint(equalTo: inner.topAnchor),
            host.bottomAnchor.constraint(equalTo: inner.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: inner.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: inner.trailingAnchor),
        ])

        panel.contentView = outer

        // Restore the user's last frame if it's still reachable on the
        // current screen layout; otherwise center at the default size.
        let screens = NSScreen.screens.map { $0.visibleFrame }
        if let saved = PanelFrameStore.load(),
           PanelFrameStore.isUsable(saved, onScreens: screens),
           let host = PanelFrameStore.bestScreen(for: saved, among: screens) {
            let fitted = PanelFrameStore.clamped(saved, to: host)
            panel.setFrame(fitted, display: false)
            // Write the correction straight back, so a frame saved by
            // an older build can't keep coming back after every quit.
            if fitted != saved { PanelFrameStore.save(fitted) }
        } else {
            panel.center()
        }

        applyChrome()
        model.onChromeChange = { [weak self] in self?.applyChrome() }

        // Persist size + position whenever the user moves or finishes
        // resizing the panel, so the next summon restores it. UserDefaults
        // writes are cheap; didMove/didEndLiveResize don't fire per-pixel.
        for name in [NSWindow.didMoveNotification, NSWindow.didEndLiveResizeNotification] {
            let token = NotificationCenter.default.addObserver(
                forName: name, object: panel, queue: .main
            ) { [weak self, weak panel] _ in
                // queue: .main guarantees this runs on the main actor;
                // assumeIsolated lets us touch panel.frame without a hop.
                MainActor.assumeIsolated {
                    guard let panel else { return }
                    if let carried = self?.carriedFrame {
                        if panel.frame == carried { return }
                        self?.carriedFrame = nil
                    }
                    guard let screen = panel.screen?.visibleFrame
                            ?? NSScreen.main?.visibleFrame else { return }
                    let fitted = PanelFrameStore.clamped(panel.frame, to: screen)
                    if fitted != panel.frame {
                        panel.setFrame(fitted, display: true)
                    }
                    PanelFrameStore.save(fitted)
                }
            }
            frameObservers.append(token)
        }

        // Esc closes any modal overlay first; falls through to the
        // panel's normal dismiss behavior only when nothing is open.
        panel.onCancel = { [weak self] in
            guard let self else { return false }
            if self.model.showFind {
                self.model.closeFind()
                return true
            }
            if self.model.showHotKeyCapture {
                self.model.showHotKeyCapture = false
                return true
            }
            if self.model.showTour {
                self.model.dismissTour()
                return true
            }
            if self.model.showHelp {
                self.model.closeHelp()
                return true
            }
            return false
        }

        panel.onDismiss = { [weak self] in self?.dismiss() }

        outsideClick = OutsideClickMonitor { [weak self] in
            guard let self, self.panel.isVisible else { return }
            // A click elsewhere while the user is mid-task in an overlay
            // — rebinding the shortcut, reading the tour — shouldn't
            // yank the panel away. Same set the Esc cascade protects.
            if self.model.showHotKeyCapture || self.model.showTour { return }
            // Mid-composition, a click on the input method's candidate
            // window or accent picker belongs to Wisp's own typing, even
            // though another process draws it.
            if let editor = self.panel.firstResponder as? NSTextView, editor.hasMarkedText() { return }
            self.dismiss()
        }
        model.onDismissPreferenceChange = { [weak self] in
            self?.syncOutsideClickMonitor()
        }
    }

    /// The monitor runs only while the panel is showing and the
    /// preference is on. Every other moment it's stopped, so Wisp
    /// isn't observing clicks it has no use for.
    private func syncOutsideClickMonitor() {
        guard let outsideClick else { return }
        if panel.isVisible && model.dismissOnOutsideClick {
            outsideClick.start()
        } else {
            outsideClick.stop()
        }
    }

    func openIfNeeded() {
        if !panel.isVisible {
            toggle()
        }
    }

    /// Every dismissal funnels through here: flush the pending save,
    /// checkpoint history, then hide.
    ///
    /// Hidden at once, not faded. A panel that's fading out is still
    /// the key window, so whatever the user types next — they've just
    /// dismissed it to type somewhere else — would land in the note.
    func dismiss() {
        guard panel.isVisible else { return }
        model.saveAndCheckpoint()
        panel.orderOut(nil)
        syncOutsideClickMonitor()
    }

    func toggle() {
        if panel.isVisible {
            dismiss()
        } else {
            moveToPointerScreenIfWanted()
            panel.alphaValue = 0
            // No re-centering — the panel keeps the size and position the
            // user last left it (restored from PanelFrameStore on launch,
            // kept fresh by the move/resize observers).
            panel.makeKeyAndOrderFront(nil)
            // A short fade rather than a pop. Fading is fine under
            // Reduce Motion — it's movement and scaling that setting
            // exists to stop — so there's no second path.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
                panel.animator().alphaValue = 1
            }
            applyChrome()
            syncOutsideClickMonitor()
            // Pick up changes another Mac wrote to scratchpad.md while
            // we were dismissed — covers the iCloud/Dropbox sync case.
            // Cheap (one stat + maybe one read), so safe to do every
            // open.
            model.reloadFromDiskIfChanged()
            model.requestFocus()
            model.refreshPlaceholder()
            // Reset the per-session dismissal so a previously "Later"d
            // update reappears on the next interaction. The check
            // itself is throttled inside Updater.
            model.updateDismissed = false
            Task { [weak self] in await self?.updater.check() }
            // Recompute shadow against current content alpha and force a
            // visual-effect re-render so the blur picks up the right
            // appearance on first show.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.visualEffect.state = .inactive
                self.visualEffect.state = .active
                self.panel.invalidateShadow()
            }
        }
    }

    /// With "Open on Pointer's Screen" on, carry the panel to the screen
    /// the pointer is on, at the same place relative to that screen.
    private func moveToPointerScreenIfWanted() {
        guard model.opensOnPointerScreen else { return }
        let pointer = NSEvent.mouseLocation
        guard let target = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }),
              let current = panel.screen,
              target != current else { return }
        // The size the user chose, not whatever a smaller screen last
        // squeezed it to.
        let size = PanelFrameStore.load()?.size ?? panel.frame.size
        let frame = PanelFrameStore.carried(
            panel.frame, size: size, from: current.visibleFrame, to: target.visibleFrame
        )
        carriedFrame = frame
        panel.setFrame(frame, display: false)
    }

    private func applyChrome() {
        let chrome = Chrome.for(model.theme, transparency: model.effectiveTransparency)
        panel.appearance = NSAppearance(named: chrome.appearance)
        visualEffect.material = chrome.material
        visualEffect.appearance = NSAppearance(named: chrome.appearance)
        visualEffect.isHidden = !chrome.usesVisualEffect
        tint.layer?.backgroundColor = chrome.tintColor.cgColor
        // Border is rendered by SwiftUI in EditorView via .overlay.
    }
}

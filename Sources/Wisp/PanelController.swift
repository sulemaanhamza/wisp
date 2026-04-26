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
        // panel.backgroundColor is set per-theme in applyTheme.
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        // Outer container: holds the drop shadow. cornerRadius rounds the
        // layer's own rendering area so the shadow casts from a rounded
        // shape rather than the rectangular bounds. masksToBounds stays
        // false so the shadow can still extend outside the rounded shape.
        // Outer container: holds the drop shadow. cornerRadius rounds the
        // layer's own rendering area; masksToBounds stays false so the
        // shadow extends outside the rounded shape.
        outer = NSView(frame: NSRect(origin: .zero, size: panelSize))
        outer.wantsLayer = true
        outer.layer?.cornerRadius = cornerRadius
        outer.layer?.masksToBounds = false
        outer.layer?.shadowColor = NSColor.black.cgColor
        outer.layer?.shadowOpacity = 0.20
        outer.layer?.shadowOffset = CGSize(width: 0, height: -6)
        outer.layer?.shadowRadius = 18
        outer.layer?.shadowPath = CGPath(
            roundedRect: CGRect(origin: .zero, size: panelSize),
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )

        // Inner container: holds the rounded clip. Both cornerRadius+
        // masksToBounds AND a CAShapeLayer mask for redundancy. Border
        // back to inner.layer.borderColor/borderWidth (the shape-layer
        // border experiment didn't fix the corner bleed and the user
        // wants the visible border restored).
        inner = NSView()
        inner.wantsLayer = true
        inner.layer?.cornerRadius = cornerRadius
        inner.layer?.masksToBounds = true
        inner.translatesAutoresizingMaskIntoConstraints = false
        let maskLayer = CAShapeLayer()
        maskLayer.frame = CGRect(origin: .zero, size: panelSize)
        maskLayer.path = CGPath(
            roundedRect: CGRect(origin: .zero, size: panelSize),
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        inner.layer?.mask = maskLayer

        // Visual effect view: clip its own layer to the rounded shape so
        // the blur output is rounded independent of inner's mask. Some
        // first-render cases the inner mask isn't applied to the
        // visualEffect's blur compositing; clipping at the visualEffect
        // layer itself makes sure dark blur material can't bleed through
        // the corner gap.
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
        panel.center()

        applyTheme(model.theme)
        model.onThemeChange = { [weak self] theme in
            self?.applyTheme(theme)
        }
    }

    func toggle() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.center()
            panel.makeKeyAndOrderFront(nil)
            applyTheme(model.theme)
            model.requestFocus()
            model.refreshPlaceholder()

            // Force a re-render of the visual effect blur and invalidate
            // any system shadow.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.visualEffect.state = .inactive
                self.visualEffect.state = .active
                self.visualEffect.needsDisplay = true
                self.panel.invalidateShadow()
            }
        }
    }

    private func applyTheme(_ theme: Theme) {
        let chrome = Chrome.for(theme)
        panel.appearance = NSAppearance(named: chrome.appearance)
        // Set the panel's own bg to match the content surface so the
        // corner gap (between rectangular window bounds and rounded
        // content) blends invisibly. NSColor.clear doesn't produce a
        // truly transparent panel — the diagnostic in v0.1.22 confirmed
        // panel bg renders in the corners regardless of alpha.
        panel.backgroundColor = chrome.panelBackground
        visualEffect.material = chrome.material
        visualEffect.appearance = NSAppearance(named: chrome.appearance)
        visualEffect.isHidden = (theme == .light)
        tint.layer?.backgroundColor = chrome.tintColor.cgColor
        // Border is rendered by SwiftUI in EditorView via .overlay.
    }
}

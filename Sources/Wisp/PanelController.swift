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
    private let borderShape: CAShapeLayer

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
        panel.backgroundColor = .clear
        // System shadow renders against the rectangular window bounds, which
        // leaves a visible gap at the rounded corners. We draw our own
        // shadow on the outer container with a shadowPath that matches the
        // rounded shape exactly.
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        // Outer container: holds the drop shadow. cornerRadius rounds the
        // layer's own rendering area so the shadow casts from a rounded
        // shape rather than the rectangular bounds (without this, the
        // shadow leaked into the corner gap between the rounded inner
        // mask and the rectangular outer bounds, showing as a soft dark
        // L). masksToBounds stays false so the shadow can still extend
        // outside the rounded shape.
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

        // Inner container: holds the rounded clip. Everything visible
        // (blur, tint, editor) lives inside and gets clipped to the
        // rounded shape. Border is set per-theme in applyTheme.
        //
        // Clipping uses an explicit CAShapeLayer mask rather than
        // cornerRadius+masksToBounds. The implicit mask was unreliable
        // for sublayers on first render (clipping to the rectangular
        // bounds instead of the rounded shape) — that produced the
        // first-launch corner bleed. cornerRadius stays so the light
        // theme's border still rounds correctly.
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

        // Border drawn as a CAShapeLayer sublayer rather than via
        // inner.layer.borderWidth/borderColor. The CALayer border draws at
        // the layer's rectangular bounds; on first render it leaks at the
        // corners before the rounded mask catches up, producing a hard
        // dark L-shape that only goes away after a re-render. A path-based
        // stroke skips the rectangular phase entirely.
        //
        // Path is inset by 0.5pt so the entire 1pt stroke (centered on the
        // path) sits inside the mask — otherwise the outer half would be
        // clipped, halving the visible thickness.
        borderShape = CAShapeLayer()
        borderShape.frame = CGRect(origin: .zero, size: panelSize)
        borderShape.path = CGPath(
            roundedRect: CGRect(
                x: 0.5,
                y: 0.5,
                width: panelSize.width - 1,
                height: panelSize.height - 1
            ),
            cornerWidth: cornerRadius - 0.5,
            cornerHeight: cornerRadius - 0.5,
            transform: nil
        )
        borderShape.fillColor = NSColor.clear.cgColor
        borderShape.strokeColor = NSColor.clear.cgColor
        borderShape.lineWidth = 0

        visualEffect = NSVisualEffectView()
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.translatesAutoresizingMaskIntoConstraints = false

        tint = NSView()
        tint.wantsLayer = true
        tint.translatesAutoresizingMaskIntoConstraints = false

        let host = NSHostingView(rootView: EditorView(model: model, updater: updater))
        host.translatesAutoresizingMaskIntoConstraints = false

        inner.addSubview(visualEffect)
        inner.addSubview(tint)
        inner.addSubview(host)
        // Border layer goes on top so the stroke sits above content.
        inner.layer?.addSublayer(borderShape)
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

            // Belt-and-suspenders: defer a redraw to the next runloop in
            // case the visualEffect material needs another tick to commit.
            // The CAShapeLayer mask should handle clipping reliably, but
            // this catches any other paint-cycle quirks for free.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.visualEffect.needsDisplay = true
            }
        }
    }

    private func applyTheme(_ theme: Theme) {
        let chrome = Chrome.for(theme)
        panel.appearance = NSAppearance(named: chrome.appearance)
        visualEffect.material = chrome.material
        visualEffect.appearance = NSAppearance(named: chrome.appearance)
        tint.layer?.backgroundColor = chrome.tintColor.cgColor
        borderShape.strokeColor = chrome.borderColor?.cgColor ?? NSColor.clear.cgColor
        borderShape.lineWidth = chrome.borderWidth
    }
}

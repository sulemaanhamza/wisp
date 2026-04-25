import AppKit
import SwiftUI

private let panelSize = CGSize(width: 800, height: 640)
private let cornerRadius: CGFloat = 18

@MainActor
final class PanelController {
    private let panel: FloatingPanel
    private let model: EditorModel

    init(model: EditorModel) {
        self.model = model
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
        panel.appearance = NSAppearance(named: .darkAqua)

        // Outer container: holds the drop shadow. No clipping (shadow is
        // drawn outside the layer bounds, so masksToBounds must stay false).
        let outer = NSView(frame: NSRect(origin: .zero, size: panelSize))
        outer.wantsLayer = true
        outer.layer?.shadowColor = NSColor.black.cgColor
        outer.layer?.shadowOpacity = 0.45
        outer.layer?.shadowOffset = CGSize(width: 0, height: -10)
        outer.layer?.shadowRadius = 28
        outer.layer?.shadowPath = CGPath(
            roundedRect: CGRect(origin: .zero, size: panelSize),
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )

        // Inner container: holds the rounded clip. Everything visible
        // (blur, tint, editor) lives inside and gets clipped to the
        // rounded shape.
        let inner = NSView()
        inner.wantsLayer = true
        inner.layer?.cornerRadius = cornerRadius
        inner.layer?.masksToBounds = true
        inner.translatesAutoresizingMaskIntoConstraints = false

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .fullScreenUI
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.translatesAutoresizingMaskIntoConstraints = false

        // Dark tint above the blur, below the content. 50% alpha guarantees
        // readable contrast on any background — glass still reads as glass
        // because the blur is still doing its job underneath.
        let tint = NSView()
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor(white: 0.0, alpha: 0.50).cgColor
        tint.translatesAutoresizingMaskIntoConstraints = false

        let host = NSHostingView(rootView: EditorView(model: model))
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
    }

    func toggle() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.center()
            panel.makeKeyAndOrderFront(nil)
            model.requestFocus()
        }
    }
}

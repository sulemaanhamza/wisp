import AppKit
import SwiftUI

@MainActor
final class PanelController {
    private let panel: FloatingPanel
    private let model: EditorModel

    init(model: EditorModel) {
        self.model = model
        let contentRect = NSRect(x: 0, y: 0, width: 800, height: 640)
        panel = FloatingPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.appearance = NSAppearance(named: .darkAqua)

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .fullScreenUI
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 18
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderWidth = 1
        visualEffect.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor

        // Dark tint above the blur, below the content. Guarantees readable
        // contrast even when the wallpaper or app behind is bright.
        let tint = NSView()
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor(white: 0.0, alpha: 0.30).cgColor
        tint.translatesAutoresizingMaskIntoConstraints = false

        let host = NSHostingView(rootView: EditorView(model: model))
        host.translatesAutoresizingMaskIntoConstraints = false

        visualEffect.addSubview(tint)
        visualEffect.addSubview(host)
        NSLayoutConstraint.activate([
            tint.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            tint.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            tint.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),

            host.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            host.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
        ])

        panel.contentView = visualEffect
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

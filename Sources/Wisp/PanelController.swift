import AppKit
import SwiftUI

@MainActor
final class PanelController {
    private let panel: FloatingPanel
    private let model = EditorModel()

    init() {
        let contentRect = NSRect(x: 0, y: 0, width: 680, height: 520)
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
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 16
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderWidth = 1
        visualEffect.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor

        let host = NSHostingView(rootView: EditorView(model: model))
        host.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(host)
        NSLayoutConstraint.activate([
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

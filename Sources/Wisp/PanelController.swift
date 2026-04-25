import AppKit
import SwiftUI

@MainActor
final class PanelController {
    private let panel: FloatingPanel

    init() {
        let contentRect = NSRect(x: 0, y: 0, width: 680, height: 480)
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

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 14
        visualEffect.layer?.masksToBounds = true

        let host = NSHostingView(rootView: EditorView())
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
        }
    }
}

import SwiftUI
import AppKit

/// The app's "there's something here" beacon: a solid accent dot under
/// a ring that expands and fades.
///
/// The motion is the whole point. A static dot small enough to be calm
/// in Wisp's chrome is simply not noticed — and a coloured word in its
/// place is louder than anything else on screen. An expanding ring
/// catches the eye at a size that stays quiet.
///
/// Drawn with Core Animation rather than a SwiftUI repeatForever: the
/// SwiftUI version re-ran layout and display every frame, about 5% of a
/// core for as long as the dot was up. A CA animation is handed to the
/// render server once and costs the app nothing after that.
struct PulsingDot: NSViewRepresentable {
    var dot: CGFloat = 8
    var ring: CGFloat = 18

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> PulseView {
        let view = PulseView(dot: dot, ring: ring)
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ view: PulseView, context: Context) {
        view.animates = !reduceMotion
    }

    final class PulseView: NSView {
        private let dotLayer = CAShapeLayer()
        private let ringLayer = CAShapeLayer()
        private let dot: CGFloat
        private let ring: CGFloat

        var animates = true {
            didSet { if animates != oldValue { restartPulse() } }
        }

        init(dot: CGFloat, ring: CGFloat) {
            self.dot = dot
            self.ring = ring
            super.init(frame: .zero)
            wantsLayer = true
            layer?.addSublayer(ringLayer)
            layer?.addSublayer(dotLayer)
            ringLayer.fillColor = nil
            ringLayer.lineWidth = 1
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override var intrinsicContentSize: NSSize { NSSize(width: ring, height: ring) }

        // Purely decorative: clicks belong to the SwiftUI button around it.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            for (shape, diameter) in [(dotLayer, dot), (ringLayer, ring)] {
                shape.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
                shape.position = center
                shape.path = CGPath(ellipseIn: shape.bounds, transform: nil)
            }
            applyColors()
        }

        // The accent colour can change under a running app, and CGColors
        // don't follow it on their own.
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            applyColors()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            restartPulse()
        }

        private func applyColors() {
            var accent = NSColor.controlAccentColor.cgColor
            effectiveAppearance.performAsCurrentDrawingAppearance {
                accent = NSColor.controlAccentColor.cgColor
            }
            dotLayer.fillColor = accent
            ringLayer.strokeColor = accent.copy(alpha: 0.5)
        }

        /// Held still, and left visible, when the system asks for
        /// reduced motion — an infinite pulse is exactly what that
        /// setting exists to stop.
        private func restartPulse() {
            ringLayer.removeAllAnimations()
            guard window != nil, animates else {
                ringLayer.opacity = 0.6
                ringLayer.transform = CATransform3DIdentity
                return
            }
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.9
            scale.toValue = 1.6
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.9
            fade.toValue = 0
            let pulse = CAAnimationGroup()
            pulse.animations = [scale, fade]
            pulse.duration = 1.6
            pulse.timingFunction = CAMediaTimingFunction(name: .easeOut)
            pulse.repeatCount = .infinity
            ringLayer.opacity = 0
            ringLayer.add(pulse, forKey: "pulse")
        }
    }
}

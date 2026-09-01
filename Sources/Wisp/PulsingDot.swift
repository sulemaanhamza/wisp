import SwiftUI

/// The app's "there's something here" beacon: a solid accent dot under
/// a ring that expands and fades.
///
/// The motion is the whole point. A static dot small enough to be calm
/// in Wisp's chrome is simply not noticed — and a coloured word in its
/// place is louder than anything else on screen. An expanding ring
/// catches the eye at a size that stays quiet.
struct PulsingDot: View {
    var dot: CGFloat = 8
    var ring: CGFloat = 18

    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Held still, and left visible, when the system asks for
            // reduced motion — an infinite pulse is exactly what that
            // setting exists to stop.
            Circle()
                .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
                .frame(width: ring, height: ring)
                .scaleEffect(pulsing ? 1.6 : 0.9)
                .opacity(reduceMotion ? 0.6 : (pulsing ? 0 : 0.9))
            Circle()
                .fill(Color.accentColor)
                .frame(width: dot, height: dot)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}

import SwiftUI

/// Small pulsing dot shown at the top-right of the panel until the
/// user has seen the first-run tour. Click it to open the tour.
struct FirstRunDot: View {
    let onTap: () -> Void

    @State private var pulsing = false

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Outer breathing ring — fades out as it expands.
                Circle()
                    .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
                    .frame(width: 18, height: 18)
                    .scaleEffect(pulsing ? 1.6 : 0.9)
                    .opacity(pulsing ? 0 : 0.9)
                // Solid dot.
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
            }
            // Hit area larger than the visible glow so clicks land
            // anywhere near the dot — the breathing ring expands
            // beyond 18pt and users perceive the bigger glow as the
            // target.
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help("Quick tour")
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}

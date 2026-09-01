import SwiftUI

/// Small pulsing dot shown at the top-right of the panel until the
/// user has seen the first-run tour. Click it to open the tour.
struct FirstRunDot: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            PulsingDot()
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
    }
}

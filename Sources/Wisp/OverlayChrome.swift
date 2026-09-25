import SwiftUI

/// The two surfaces every overlay is built from, so they read as one
/// family: a scrim that dims the note without hiding it, and a card
/// that holds a short decision or message. Help is the exception — a
/// long reference reads better as a full sheet — and uses `sheet`.
struct OverlayScrim: View {
    let theme: Theme
    /// Near-opaque, for content long enough to need the whole panel.
    var sheet = false
    var onTap: (() -> Void)?

    var body: some View {
        Rectangle()
            .fill(fill)
            .contentShape(Rectangle())
            .onTapGesture { onTap?() }
            .arrowCursor()
    }

    private var fill: Color {
        switch (theme, sheet) {
        case (.dark, true): return Color(white: 0.08).opacity(0.96)
        case (.light, true): return Color.white.opacity(0.97)
        case (.dark, false): return Color(white: 0.05).opacity(0.55)
        case (.light, false): return Color(white: 1.0).opacity(0.55)
        }
    }
}

extension View {
    func overlayCard(theme: Theme, maxWidth: CGFloat = 360) -> some View {
        self
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme == .dark ? Color(white: 0.13) : Color(white: 0.99))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                theme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.18), radius: 18, y: 6)
            )
            .frame(maxWidth: maxWidth)
    }
}

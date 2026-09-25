import SwiftUI

/// First-run welcome card. Three essential tips and a single "Got it"
/// (Return works too). Dismisses on a click outside the card or Esc.
struct TourOverlay: View {
    let theme: Theme
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            OverlayScrim(theme: theme, onTap: onDismiss)

            VStack(alignment: .leading, spacing: 16) {
                Text("Welcome to Wisp")
                    .font(.system(size: 17, weight: .semibold))

                tip("⌥Space", "summon Wisp from anywhere")
                tip("Menu bar icon", "right-click for fonts, transparency, and your shortcut")
                tip("?", "in the footer, for every shortcut and format")

                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Text("Got it")
                            .frame(minWidth: 72)
                    }
                    .keyboardShortcut(.defaultAction)
                    .pointerCursor()
                }
                .padding(.top, 8)
            }
            .overlayCard(theme: theme, maxWidth: 400)
        }
    }

    @ViewBuilder
    private func tip(_ key: String, _ description: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .leading)
            Text(description)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

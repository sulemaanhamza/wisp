import SwiftUI

/// First-run welcome overlay. Shows three essential tips and a single
/// "Got it" affordance. Dismisses on click anywhere or Esc.
struct TourOverlay: View {
    let theme: Theme
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(theme == .dark
                      ? Color(white: 0.08).opacity(0.96)
                      : Color.white.opacity(0.98))
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            VStack(alignment: .leading, spacing: 18) {
                Text("Welcome to Wisp")
                    .font(.system(size: 20, weight: .medium))
                    .padding(.bottom, 4)

                tip("⌥Space", "summon Wisp from anywhere on macOS")
                tip("Right-click the menu bar icon", "for font, shortcut, and about")
                tip("Click the ? in the footer", "for shortcuts and formatting")

                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Text("Got it")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(.tertiary, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                }
                .padding(.top, 12)
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 36)
            .frame(maxWidth: 460, alignment: .leading)
        }
    }

    @ViewBuilder
    private func tip(_ key: String, _ description: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 160, alignment: .leading)
            Text(description)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
        }
    }
}

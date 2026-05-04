import SwiftUI

struct HelpOverlay: View {
    let theme: Theme
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Tap-anywhere-to-dismiss surface. Near-opaque so the help
            // text is clearly readable; the editor fades to barely
            // visible behind, which signals "modal mode" without
            // competing for attention.
            Rectangle()
                .fill(theme == .dark
                      ? Color(white: 0.08).opacity(0.96)
                      : Color.white.opacity(0.98))
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            VStack(alignment: .leading, spacing: 18) {
                section("Open / dismiss", items: [
                    ("⌥Space", "summon or dismiss the panel"),
                    ("Esc", "dismiss"),
                    ("⌘Q", "quit Wisp"),
                ])
                section("Format", items: [
                    ("⌘B  /  ⌘I", "bold  /  italic (toggle)"),
                    ("⌘1  /  ⌘2  /  ⌘3", "text size"),
                ])
                section("Smart editing — type and press Enter", items: [
                    ("-   *   +", "unordered list, auto-continues"),
                    ("1.    A.    a.", "ordered list, auto-increments"),
                    ("# / ## / ###", "headings (jump from top bar)"),
                    ("---", "horizontal rule (no Enter needed)"),
                ])
                section("Emoji shortcodes", items: [
                    (":)   :(", "🙂  🙁"),
                    (":rocket:   :fire:   :heart:", "🚀  🔥  ❤️"),
                    (":check:   :x:   :star:", "✅  ❌  ⭐"),
                    (":bulb:   :warning:", "💡  ⚠️"),
                ])
                section("Settings — right-click the menu bar icon", items: [
                    ("Font", "pick from six preinstalled fonts"),
                    ("Set Shortcut…", "rebind the global hotkey"),
                    ("Launch at Login", "start automatically at login"),
                    ("Storage Location…", "any folder — iCloud Drive, Dropbox for sync"),
                    ("About Wisp", "version + credits"),
                ])

                Text("Click anywhere or press Esc to close.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 36)
            .frame(maxWidth: 560, alignment: .leading)
        }
    }

    @ViewBuilder
    private func section(_ title: String, items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .tracking(0.6)
                .padding(.bottom, 2)
            ForEach(items, id: \.0) { item in
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(item.0)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 180, alignment: .leading)
                    Text(item.1)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}

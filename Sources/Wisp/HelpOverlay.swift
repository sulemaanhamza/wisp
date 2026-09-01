import SwiftUI

struct HelpOverlay: View {
    let theme: Theme
    /// Things this user hasn't been shown, pinned above everything
    /// else. Empty once they've looked.
    var newTips: [Tip] = []
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
                if !newTips.isEmpty {
                    section(
                        "New",
                        items: newTips.map { ($0.keys, $0.what) },
                        accent: true
                    )
                }
                section("Open / dismiss", items: [
                    ("⌥Space", "summon or dismiss the panel"),
                    ("⌘F", "find in your notes (↵ / ⇧↵ to step)"),
                    ("⇧⌘↩", "file this note in the Inbox, start fresh"),
                    ("Esc", "dismiss"),
                    ("⌘Q", "quit Wisp"),
                ])
                section("Format", items: [
                    ("⌘B  /  ⌘I", "bold  /  italic (toggle)"),
                    ("⌘1  /  ⌘2  /  ⌘3", "text size"),
                ])
                section("Smart editing — type and press Enter", items: [
                    ("-   *   +", "unordered list, auto-continues"),
                    ("- [ ]", "checklist — click a box to tick it off"),
                    ("1.    A.    a.", "ordered list, auto-increments"),
                    ("# / ## / ###", "headings (jump from top bar)"),
                    ("`code`   ```", "monospace, inline or fenced"),
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
                    ("Transparency", "how much desktop shows through"),
                    ("Set Shortcut…", "rebind the global hotkey"),
                    ("Launch at Login", "start automatically at login"),
                    ("Storage Location…", "any folder — iCloud Drive, Dropbox for sync"),
                    ("Reveal in Finder", "scratchpad, Inbox, or version history"),
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
    private func section(
        _ title: String, items: [(String, String)], accent: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(accent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
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

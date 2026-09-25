import SwiftUI

/// Everything the help overlay lists, as data. Each row reads "what you
/// want" on the left, "how" on the right — the way a menu reads — and the
/// kind of "how" decides how it's drawn: keys as keycaps, markdown as code,
/// menu items as plain text.
enum HelpContent {
    enum Kind { case keys, syntax, menu }

    struct Row: Identifiable {
        let what: String
        let how: [String]
        let kind: Kind
        var id: String { what }
        /// What a `Tip` names to flag this row as new.
        var tipKey: String { how.joined(separator: " ") }
    }

    struct Section: Identifiable {
        let title: String
        let rows: [Row]
        var id: String { title }
    }

    static func sections(hotKey: String) -> [Section] {
        [
            Section(title: "Panel", rows: [
                Row(what: "Show or hide Wisp", how: [hotKey], kind: .keys),
                Row(what: "Close", how: ["Esc"], kind: .keys),
                Row(what: "Find", how: ["⌘F"], kind: .keys),
                Row(what: "Next or previous match", how: ["↵", "⇧↵"], kind: .keys),
                Row(what: "File in the Inbox, start fresh", how: ["⇧⌘↩"], kind: .keys),
                Row(what: "Quit", how: ["⌘Q"], kind: .keys),
            ]),
            Section(title: "Editing", rows: [
                Row(what: "Bold, italic", how: ["⌘B", "⌘I"], kind: .keys),
                Row(what: "Make a task, or tick it off", how: ["⌘L"], kind: .keys),
                Row(what: "Move the line up or down", how: ["⌥↑", "⌥↓"], kind: .keys),
                Row(what: "Open a link", how: ["⌘-click"], kind: .keys),
                Row(what: "Text size", how: ["⌘-", "⌘=", "⌘0"], kind: .keys),
            ]),
            Section(title: "Markdown", rows: [
                Row(what: "Heading, listed in the top bar", how: ["#", "##", "###"], kind: .syntax),
                Row(what: "List, continues on Enter", how: ["-", "1."], kind: .syntax),
                Row(what: "Checklist, click a box to tick", how: ["- [ ]"], kind: .syntax),
                Row(what: "Bold, italic", how: ["**bold**", "*italic*"], kind: .syntax),
                Row(what: "Code, inline or fenced", how: ["`code`", "```"], kind: .syntax),
                Row(what: "Divider", how: ["---"], kind: .syntax),
                Row(what: "Emoji", how: [":rocket:", ":check:", ":bulb:"], kind: .syntax),
            ]),
            Section(title: "Menu bar icon, right-click", rows: [
                Row(what: "Eight fonts, serif and sans", how: ["Font"], kind: .menu),
                Row(what: "How much desktop shows through", how: ["Transparency"], kind: .menu),
                Row(what: "Change the shortcut", how: ["Set Shortcut…"], kind: .menu),
                Row(what: "Start with your Mac", how: ["Launch at Login"], kind: .menu),
                Row(what: "Close on a click elsewhere", how: ["Close When Clicking Outside"], kind: .menu),
                Row(what: "Follow the pointer across displays", how: ["Open on Pointer's Screen"], kind: .menu),
                Row(what: "Sync with iCloud Drive or Dropbox", how: ["Storage Location…"], kind: .menu),
                Row(what: "Earlier versions, the Inbox", how: ["Reveal in Finder"], kind: .menu),
            ]),
        ]
    }
}

struct HelpOverlay: View {
    let theme: Theme
    /// The summon shortcut as the user has it, not the default.
    var hotKey: String = HotKey.default.displayString
    /// Things this user hasn't been shown yet; their rows get a tag.
    var newTips: [Tip] = []
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Tap-anywhere-to-dismiss surface. Near-opaque so the help
            // text is clearly readable; the editor fades to barely
            // visible behind, which signals "modal mode" without
            // competing for attention.
            OverlayScrim(theme: theme, sheet: true, onTap: onDismiss)

            // Scrolls when it doesn't fit. The list only ever grows,
            // and a panel the user has made small is still theirs.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Shortcuts")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text("Esc or click to close")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    // Two columns when there's room, one when there isn't.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 40) {
                            column(sections.prefix(2))
                            column(sections.suffix(2))
                        }
                        column(sections[...])
                    }
                }
                .padding(32)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var sections: [HelpContent.Section] {
        HelpContent.sections(hotKey: hotKey)
    }

    private func column(_ sections: ArraySlice<HelpContent.Section>) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(Array(sections)) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                        .tracking(0.6)
                    ForEach(section.rows) { row in
                        HelpRowView(row: row, isNew: newTips.contains { $0.keys == row.tipKey })
                    }
                }
            }
        }
        .frame(width: 320, alignment: .leading)
    }
}

private struct HelpRowView: View {
    let row: HelpContent.Row
    let isNew: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(row.what)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if isNew {
                    Text("New")
                        .font(.system(size: 9, weight: .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(Color.accentColor)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                ForEach(row.how, id: \.self) { item in
                    switch row.kind {
                    case .keys: Keycap(text: item)
                    case .syntax: SyntaxChip(text: item)
                    case .menu:
                        Text(item)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .fixedSize()
        }
    }
}

/// A key as it's printed on the keyboard: a small raised cap.
private struct Keycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(minWidth: 22)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
            )
    }
}

/// Markdown you type, set as code so it can't be mistaken for a key.
private struct SyntaxChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
    }
}

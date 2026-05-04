import SwiftUI

struct BottomBar: View {
    let wordCount: Int
    let fontSize: FontSize
    let onCycleFontSize: () -> Void
    let theme: Theme
    let onToggleTheme: () -> Void
    let updateState: UpdateState
    let onUpdateClick: () -> Void
    let onHelpClick: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text(wordsLabel)
                .monospacedDigit()
            Spacer()
            updateIndicator
            Button(action: onHelpClick) {
                Image(systemName: "questionmark")
                    .font(.system(size: 11, weight: .regular))
                    .frame(width: 24, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .help("Keyboard shortcuts and formatting")
            Button(action: onToggleTheme) {
                Image(systemName: theme == .dark ? "sun.max" : "moon")
                    .font(.system(size: 11, weight: .regular))
                    .frame(width: 24, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .help("Switch to \(theme == .dark ? "light" : "dark") theme")
            Button(action: onCycleFontSize) {
                Text("Aa")
                    .font(.system(size: indicatorSize, weight: .medium, design: .serif))
                    .frame(width: 30, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .help("Cycle text size (⌘1 / ⌘2 / ⌘3)")
            Text("esc to close")
        }
        .font(.system(size: 11, weight: .regular))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var updateIndicator: some View {
        switch updateState {
        case .idle:
            EmptyView()
        case .available(let version, _):
            Button(action: onUpdateClick) {
                Text("↑ v\(version)")
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .help("New version available")
        case .downloading(let version):
            Text("↓ downloading v\(version)…")
        case .pending(let version):
            Button(action: onUpdateClick) {
                Text("↻ v\(version) ready — restart to apply")
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .help("Restart Wisp to apply the update")
        }
    }

    private var indicatorSize: CGFloat {
        switch fontSize {
        case .small: return 9
        case .medium: return 11
        case .large: return 13
        }
    }

    private var wordsLabel: String {
        wordCount == 1 ? "1 word" : "\(wordCount) words"
    }
}

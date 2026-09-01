import SwiftUI

struct BottomBar: View {
    let wordCount: Int
    let saveFailed: Bool
    let fontSize: FontSize
    let onCycleFontSize: () -> Void
    let themePreference: ThemePreference
    let onCycleTheme: () -> Void
    let updateState: UpdateState
    let onUpdateClick: () -> Void
    /// Something in the help overlay is new to this user.
    let hasUnseenTips: Bool
    let onHelpClick: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text(wordsLabel)
                .monospacedDigit()
            if saveFailed {
                Text("couldn't save")
                    .foregroundStyle(.orange)
                    .help("Wisp can't write to its storage folder. Your text is still here — pick another folder from the menu bar icon.")
            }
            Spacer()
            updateIndicator
            Button(action: onHelpClick) {
                // Same beacon as the first-run dot, footer-sized. The
                // two never appear together: unseen tips are only
                // flagged for someone who has already dismissed the
                // tour.
                HStack(spacing: 4) {
                    if hasUnseenTips {
                        PulsingDot(dot: 5, ring: 11)
                            .frame(width: 16, height: 16)
                    }
                    Image(systemName: "questionmark")
                        .font(.system(size: 11, weight: .regular))
                }
                .frame(minWidth: 24, minHeight: 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .help(hasUnseenTips
                  ? "Shortcuts and formatting — something new in here"
                  : "Keyboard shortcuts and formatting")
            .accessibilityLabel(hasUnseenTips
                  ? "Keyboard shortcuts and formatting, new items"
                  : "Keyboard shortcuts and formatting")
            Button(action: onCycleTheme) {
                Image(systemName: themeIconName)
                    .font(.system(size: 11, weight: .regular))
                    .frame(width: 24, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .help(themeButtonHelp)
            .accessibilityLabel(themeButtonHelp)
            Button(action: onCycleFontSize) {
                Text("Aa")
                    .font(.system(size: indicatorSize, weight: .medium, design: .serif))
                    .frame(width: 30, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .help("Cycle text size (⌘1 / ⌘2 / ⌘3)")
            .accessibilityLabel("Cycle text size")
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
        case .failed(let version):
            Button(action: onUpdateClick) {
                Text("↗ v\(version) — download manually")
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .help("Wisp couldn't replace itself. Opens the download page.")
        }
    }

    private var themeIconName: String {
        switch themePreference {
        case .light: return "sun.max"
        case .dark: return "moon"
        case .system: return "circle.lefthalf.filled"
        }
    }

    private var themeButtonHelp: String {
        switch themePreference.next {
        case .light: return "Switch to light theme"
        case .dark: return "Switch to dark theme"
        case .system: return "Follow system appearance"
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

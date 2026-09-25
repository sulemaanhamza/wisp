import SwiftUI

struct BottomBar: View {
    let wordCount: Int
    let notice: String?
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

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 16) {
            // The notice stands in for the count briefly, so the footer
            // never grows a second line of chrome.
            ZStack(alignment: .leading) {
                if let notice {
                    Text(notice)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                } else if wordCount > 0 {
                    Text(wordsLabel)
                        .monospacedDigit()
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: notice)
            if saveFailed {
                Text("couldn't save")
                    .foregroundStyle(.orange)
                    .help("Wisp can't write to its storage folder. Your text is still here — pick another folder from the menu bar icon.")
            }
            Spacer()
            updateIndicator
            QuietButton(
                action: onHelpClick,
                help: hasUnseenTips
                    ? "Shortcuts and formatting — something new in here"
                    : "Keyboard shortcuts and formatting"
            ) {
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
            }
            QuietButton(action: onCycleTheme, help: themeButtonHelp) {
                Image(systemName: themeIconName)
                    .font(.system(size: 11, weight: .regular))
                    .frame(width: 24, height: 20)
            }
            QuietButton(action: onCycleFontSize, help: "Text size (⌘- / ⌘=)") {
                Text("Aa")
                    .font(.system(size: indicatorSize, weight: .medium, design: .serif))
                    .frame(width: 30, height: 20)
            }
            Text("esc to close")
        }
        .font(.system(size: 11, weight: .regular))
        .foregroundStyle(contrast == .increased ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var updateIndicator: some View {
        switch updateState {
        case .idle:
            EmptyView()
        case .available(let version, _):
            QuietButton(action: onUpdateClick, help: "New version available") {
                Label("v\(version)", systemImage: "arrow.up.circle")
            }
        case .downloading(let version):
            Label("downloading v\(version)…", systemImage: "arrow.down.circle")
        case .pending(let version):
            QuietButton(action: onUpdateClick, help: "Restart Wisp to apply the update") {
                Label("v\(version) ready — restart to apply", systemImage: "arrow.clockwise.circle")
            }
        case .failed(let version):
            QuietButton(action: onUpdateClick, help: "Wisp couldn't replace itself. Opens the download page.") {
                Label("v\(version) — download manually", systemImage: "arrow.up.forward.square")
            }
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
        case .extraLarge: return 15
        }
    }

    private var wordsLabel: String {
        wordCount == 1 ? "1 word" : "\(wordCount) words"
    }
}

/// Chrome controls sit at tertiary until hovered, then lift a step, so
/// they read as quiet text until the pointer shows they're buttons.
struct QuietButton<Content: View>: View {
    let action: () -> Void
    let help: String
    @ViewBuilder let content: () -> Content

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            content().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(style)
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) { hovering = inside }
        }
        .pointerCursor()
        .help(help)
        .accessibilityLabel(help)
    }

    private var style: AnyShapeStyle {
        switch (hovering, contrast == .increased) {
        case (false, false): return AnyShapeStyle(.tertiary)
        case (true, false), (false, true): return AnyShapeStyle(.secondary)
        case (true, true): return AnyShapeStyle(.primary)
        }
    }
}

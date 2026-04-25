import SwiftUI

struct BottomBar: View {
    let wordCount: Int
    let fontSize: FontSize
    let onCycleFontSize: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text(wordsLabel)
                .monospacedDigit()
            Spacer()
            Button(action: onCycleFontSize) {
                Text("Aa")
                    .font(.system(size: indicatorSize, weight: .medium, design: .serif))
                    .frame(width: 22, alignment: .center)
            }
            .buttonStyle(.plain)
            .help("Cycle text size (⌘1 / ⌘2 / ⌘3)")
            Text("esc to close")
        }
        .font(.system(size: 11, weight: .regular))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
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

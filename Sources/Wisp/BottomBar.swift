import SwiftUI

struct BottomBar: View {
    let wordCount: Int

    var body: some View {
        HStack(spacing: 0) {
            Text(wordsLabel)
                .monospacedDigit()
            Spacer()
            Text("esc to close")
        }
        .font(.system(size: 11, weight: .regular))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
    }

    private var wordsLabel: String {
        wordCount == 1 ? "1 word" : "\(wordCount) words"
    }
}

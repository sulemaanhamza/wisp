import SwiftUI

@MainActor
final class EditorModel: ObservableObject {
    @Published var text: String = ""
    @Published var focusToken: Int = 0

    func requestFocus() {
        focusToken &+= 1
    }
}

struct EditorView: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            MinimalTextEditor(text: $model.text, focusToken: model.focusToken)
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 4)
            BottomBar(wordCount: wordCount)
        }
    }

    private var wordCount: Int {
        var count = 0
        let text = model.text
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { _, _, _, _ in
            count += 1
        }
        return count
    }
}

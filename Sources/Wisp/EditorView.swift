import SwiftUI

enum FontSize: Int, CaseIterable {
    case small = 14
    case medium = 17
    case large = 22

    var next: FontSize {
        let all = FontSize.allCases
        let idx = all.firstIndex(of: self) ?? 0
        return all[(idx + 1) % all.count]
    }
}

@MainActor
final class EditorModel: ObservableObject {
    @Published var text: String = ""
    @Published var focusToken: Int = 0
    @Published var fontSize: FontSize = .medium

    func requestFocus() {
        focusToken &+= 1
    }

    func cycleFontSize() {
        fontSize = fontSize.next
        requestFocus()
    }
}

struct EditorView: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            MinimalTextEditor(
                text: $model.text,
                focusToken: model.focusToken,
                fontSize: model.fontSize
            )
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 4)
            BottomBar(
                wordCount: wordCount,
                fontSize: model.fontSize,
                onCycleFontSize: { model.cycleFontSize() }
            )
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

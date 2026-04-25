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
        MinimalTextEditor(text: $model.text, focusToken: model.focusToken)
            .padding(.horizontal, 28)
            .padding(.vertical, 28)
    }
}

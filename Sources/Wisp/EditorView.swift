import SwiftUI

@MainActor
final class EditorModel: ObservableObject {
    @Published var focusToken: Int = 0

    func requestFocus() {
        focusToken &+= 1
    }
}

struct EditorView: View {
    @ObservedObject var model: EditorModel
    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 16))
            .lineSpacing(6)
            .padding(24)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .focused($isFocused)
            .onAppear { isFocused = true }
            .onChange(of: model.focusToken) { _ in
                isFocused = true
            }
    }
}

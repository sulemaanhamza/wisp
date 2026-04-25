import SwiftUI

struct EditorView: View {
    @State private var text: String = ""

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 16))
            .lineSpacing(6)
            .padding(24)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
    }
}

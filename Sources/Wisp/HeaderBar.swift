import SwiftUI

struct HeaderBar: View {
    let headings: [Heading]
    let onJump: (Heading) -> Void

    var body: some View {
        if headings.isEmpty {
            // Nothing to show — keep the slot empty so the panel just looks
            // like before the headings feature existed.
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(headings.enumerated()), id: \.element.id) { index, heading in
                        if index > 0 {
                            Text("·")
                                .foregroundStyle(.quaternary)
                                .padding(.horizontal, 10)
                        }
                        QuietButton(action: { onJump(heading) }, help: "Jump to “\(heading.name)”") {
                            Text(heading.name)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
            }
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(.tertiary)
        }
    }
}

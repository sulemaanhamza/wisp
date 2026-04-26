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
                        Button(action: { onJump(heading) }) {
                            Text(heading.name)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .help("Jump to “\(heading.name)”")
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
            }
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(.tertiary)
        }
    }
}

import Foundation

struct Heading: Identifiable, Equatable {
    let name: String
    let level: Int
    /// NSString character offset where the heading line starts, used for
    /// scrolling the text view to the section.
    let lineStart: Int

    var id: Int { lineStart }
}

extension String {
    /// Parse `#`-prefixed markdown headings out of the text. Returns one
    /// entry per heading line, in document order.
    func extractHeadings() -> [Heading] {
        let ns = self as NSString
        let total = ns.length
        var result: [Heading] = []
        var lineStart = 0
        while lineStart < total {
            let lineRange = ns.lineRange(for: NSRange(location: lineStart, length: 0))
            let raw = ns.substring(with: lineRange)
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
            if let match = line.firstMatch(of: /^(#{1,6})\s+(.+)/) {
                let name = String(match.2).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    result.append(Heading(
                        name: name,
                        level: match.1.count,
                        lineStart: lineRange.location
                    ))
                }
            }
            lineStart = lineRange.location + lineRange.length
        }
        return result
    }
}

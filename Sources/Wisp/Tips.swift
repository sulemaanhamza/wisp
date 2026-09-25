import Foundation

/// One thing Wisp can do that you'd never guess it could do.
struct Tip: Identifiable, Equatable {
    /// The release that introduced it. Anyone whose stored marker is
    /// older than this hasn't been shown the tip yet.
    let version: String
    /// The help row this flags as new: its `how`, joined by spaces
    /// (`HelpContent.Row.tipKey`). The self-tests hold every tip to a
    /// real row, so a renamed row can't silently orphan one.
    let keys: String

    var id: String { keys + version }
}

/// Feature discovery.
///
/// Wisp's features are invisible by construction: unguessable syntax
/// and shortcuts on a surface with no chrome to hang hints off. Release
/// notes are read once and forgotten, so the question isn't "what
/// shipped last week" but "what has this person never been shown" —
/// someone still on the habits they formed at 0.1.20 doesn't know about
/// find either.
///
/// So: a quiet dot on the `?` whenever this list has moved past the
/// marker stored for them. Clicking it opens the help overlay, which is
/// where the answers already live. To add a tip later, append it here
/// with its release — `version` and the dot follow on their own.
enum Tips {
    static let seenKey = "SeenTipsVersion"

    static let all: [Tip] = [
        Tip(version: "0.1.44", keys: "⌘L"),
        Tip(version: "0.1.44", keys: "⌥↑ ⌥↓"),
        Tip(version: "0.1.44", keys: "⌘-click"),
        Tip(version: "0.1.44", keys: "⌘- ⌘= ⌘0"),
        Tip(version: "0.1.44", keys: "Font"),
        Tip(version: "0.1.42", keys: "- [ ]"),
        Tip(version: "0.1.42", keys: "⇧⌘↩"),
        Tip(version: "0.1.41", keys: "⌘F"),
        Tip(version: "0.1.42", keys: "`code` ```"),
        Tip(version: "0.1.42", keys: "Transparency"),
        Tip(version: "0.1.42", keys: "Reveal in Finder"),
    ]

    /// Newest version in the list. Derived, so adding a tip is the only
    /// step — there's no constant to forget to bump.
    static var version: String {
        all.map(\.version).max(by: isOlder) ?? "0"
    }

    /// Tips newer than the marker stored for this user. A missing
    /// marker means someone who updated into this feature, so they get
    /// everything — including the older entries they may well have
    /// never found.
    static func unseen(since seen: String?, limit: Int = .max) -> [Tip] {
        guard let seen else { return Array(all.prefix(limit)) }
        return Array(all.filter { isOlder(seen, $0.version) }.prefix(limit))
    }

    /// Pure numeric version compare: is `a` older than `b`?
    static func isOlder(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedAscending
    }
}

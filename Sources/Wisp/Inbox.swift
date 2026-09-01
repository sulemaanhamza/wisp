import Foundation
import AppKit

/// "Drop the thought and move on." Files the current note into an
/// `Inbox/` folder under a timestamped name and leaves the scratchpad
/// empty for the next one.
///
/// The folder sits beside scratchpad.md in whatever folder the user
/// chose, so archived notes sync with everything else and any other
/// notes app can pick them up — which is the whole point of the
/// request. Plain markdown, one file per thought, no index.
enum Inbox {
    static let folderName = "Inbox"
    static let suffix = ".md"

    static var folder: URL {
        StorageLocation.currentFolder.appendingPathComponent(folderName)
    }

    /// Sortable, wall-clock filename: `2026-08-30-142200.md`. Same
    /// shape as the history snapshots, so the two folders read alike.
    static func filename(at date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return "\(f.string(from: date))\(suffix)"
    }

    /// Pure: is there anything worth filing? Whitespace-only notes
    /// aren't thoughts.
    static func isWorthArchiving(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Write `text` to a new file in the Inbox. Returns where it went.
    @discardableResult
    static func archive(text: String, at date: Date = Date()) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = filename(at: date)
        var url = folder.appendingPathComponent(base)
        var n = 1
        // Two thoughts filed in the same second are rare but shouldn't
        // silently overwrite each other.
        while FileManager.default.fileExists(atPath: url.path) {
            let stem = String(base.dropLast(suffix.count))
            url = folder.appendingPathComponent("\(stem)-\(n)\(suffix)")
            n += 1
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func revealInFinder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }
}

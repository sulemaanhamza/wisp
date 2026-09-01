import Foundation
import AppKit

/// Lightweight local history for the scratchpad. Keeps timestamped `.md`
/// copies in a `History/` folder, so an accidental wipe or overwrite is
/// recoverable by opening the folder.
///
/// No in-app restore UI by design — recovery is "open the folder, find
/// the version, copy what you need." That keeps it in the file-based
/// spirit of the app. The timing/shrink/prune decisions are pure so
/// they're unit-testable; only the recording entry points touch disk.
enum Snapshots {
    static let folderName = "History"
    static let prefix = "scratchpad-"
    static let suffix = ".md"
    /// How many snapshots to keep. Each is a full copy, but scratchpads
    /// are small, so the ring can be generous.
    static let keep = 30

    /// History always lives in Wisp's own Application Support folder,
    /// never inside a user-chosen sync folder. A safety net kept inside
    /// the thing it protects isn't much of a net: two Macs would write
    /// into one ring, and every version would sync everywhere.
    static var folder: URL {
        StorageLocation.defaultFolder.appendingPathComponent(folderName)
    }

    /// All disk work is serialised here. Without it two snapshots taken
    /// in the same instant race, and the loser is whichever one the
    /// filesystem wrote first — which can be the shrink guard's copy.
    private static let queue = DispatchQueue(label: "com.sulemaanhamza.wisp.snapshots")

    // MARK: - Pure helpers (unit-tested)

    /// Did the text just collapse from something substantial to a
    /// fraction of itself (or nothing)? This is the "I accidentally
    /// selected all and deleted/replaced" case — worth preserving the
    /// old version immediately, before the save overwrites it.
    static func isDrasticShrink(old: String, new: String) -> Bool {
        let o = old.count
        guard o >= 40 else { return false }     // nothing substantial to protect
        let n = new.count
        if n == 0 { return true }               // wiped entirely
        return Double(n) < Double(o) * 0.5      // lost more than half
    }

    /// Given all filenames in the history folder, return the snapshot
    /// files to delete to keep only the newest `keep`. Names embed a
    /// sortable timestamp, so lexicographic order is chronological.
    static func filesToPrune(_ names: [String], keep: Int) -> [String] {
        let snaps = names
            .filter { $0.hasPrefix(prefix) && $0.hasSuffix(suffix) }
            .sorted()
        guard snaps.count > keep else { return [] }
        return Array(snaps.prefix(snaps.count - keep))
    }

    /// Sortable, wall-clock filename: `scratchpad-2026-06-13-143022-481.md`.
    /// Milliseconds are in the name because a checkpoint and a shrink
    /// guard firing in the same second would otherwise collide, and the
    /// second write would replace the copy the first one just saved.
    static func filename(at date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss-SSS"
        return "\(prefix)\(f.string(from: date))\(suffix)"
    }

    // MARK: - Disk operations

    /// Snapshot the current content at a natural boundary — launch,
    /// panel dismiss, or quit. Deduped against the most recent snapshot,
    /// so repeatedly dismissing without changes won't pile up copies.
    /// This is the main path: it captures complete content when you
    /// step away, rather than mid-keystroke.
    static func recordCheckpoint(text: String) {
        guard !text.isEmpty else { return }
        queue.sync { writeIfNew(content: text, now: Date()) }
    }

    /// Big-shrink guard, called from the save path. If the text just
    /// collapsed from substantial to a fraction, preserve the OLD
    /// version immediately — before the save overwrites it — instead of
    /// waiting for the next checkpoint.
    static func recordOnSave(old: String, new: String) {
        guard isDrasticShrink(old: old, new: new) else { return }
        queue.sync { writeIfNew(content: old, now: Date()) }
    }

    static func revealInFinder() {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    // MARK: - Internals

    /// Must be called on `queue`.
    private static func writeIfNew(content: String, now: Date) {
        guard !content.isEmpty else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)

        // Dedupe: never write a copy identical to the most recent one.
        if let recent = mostRecentSnapshot(),
           let recentContent = try? String(contentsOf: recent, encoding: .utf8),
           recentContent == content {
            return
        }

        try? content.write(to: freeURL(at: now), atomically: true, encoding: .utf8)
        prune()
    }

    /// A destination that doesn't exist yet. Milliseconds make a clash
    /// unlikely; the counter makes it impossible.
    private static func freeURL(at now: Date) -> URL {
        let base = filename(at: now)
        var candidate = folder.appendingPathComponent(base)
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let stem = String(base.dropLast(suffix.count))
            candidate = folder.appendingPathComponent("\(stem)-\(n)\(suffix)")
            n += 1
        }
        return candidate
    }

    private static func mostRecentSnapshot() -> URL? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        guard let latest = names
            .filter({ $0.hasPrefix(prefix) && $0.hasSuffix(suffix) })
            .sorted()
            .last
        else { return nil }
        return folder.appendingPathComponent(latest)
    }

    private static func prune() {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in filesToPrune(names, keep: keep) {
            try? fm.removeItem(at: folder.appendingPathComponent(name))
        }
    }
}

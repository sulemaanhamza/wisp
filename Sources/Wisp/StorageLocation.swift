import Foundation

/// Where `scratchpad.md` lives on disk.
///
/// Default: `~/Library/Application Support/Wisp/scratchpad.md`. The user
/// can pick any folder via the right-click menu — putting it inside
/// `~/Library/Mobile Documents/com~apple~CloudDocs/...` (iCloud Drive),
/// `~/Dropbox/...`, or any sync tool's folder makes Wisp's scratchpad
/// follow the user across machines for free, since macOS handles that
/// folder's syncing for us.
///
/// Tradeoff: file-system sync isn't conflict-aware. Typing on two Macs
/// at the same instant can produce a `scratchpad (Mac-X's conflicted
/// copy).md` file that Wisp doesn't merge automatically. The single-
/// person-many-Macs case rarely hits this.
enum StorageLocation {
    static let folderKey = "ScratchpadFolder"
    static let scratchpadFilename = "scratchpad.md"
    static let backupPrefix = "scratchpad-local-backup-"

    /// `~/Library/Application Support/Wisp/`
    static var defaultFolder: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("Wisp")
    }

    /// User's chosen folder, or default if none set.
    static var currentFolder: URL {
        if let path = UserDefaults.standard.string(forKey: folderKey),
           !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return defaultFolder
    }

    static var currentURL: URL {
        scratchpadURL(in: currentFolder)
    }

    static var isCustom: Bool {
        guard let path = UserDefaults.standard.string(forKey: folderKey) else {
            return false
        }
        return !path.isEmpty
    }

    /// Pure: compose the scratchpad file URL inside a given folder.
    static func scratchpadURL(in folder: URL) -> URL {
        folder.appendingPathComponent(scratchpadFilename)
    }

    /// Pure: timestamped backup filename used when a folder switch
    /// would otherwise overwrite the user's local text.
    static func backupFilename(at date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime]
        let stamp = formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
        return "\(backupPrefix)\(stamp).md"
    }

    /// Outcome of switching folders. Drives the UI (whether to swap
    /// the in-memory text for the loaded existing file, and whether to
    /// surface a backup-was-saved message).
    struct SwitchResult {
        let newText: String
        let backupURL: URL?
        let loadedExisting: Bool
    }

    /// Switch to a new folder. Two paths:
    /// - destination is empty → move local text there
    /// - destination has its own scratchpad.md → save a timestamped
    ///   backup of the local text in the old folder, then load the
    ///   existing file (the "Mac B joining iCloud sync" case)
    static func setFolder(_ folder: URL, currentText: String) throws -> SwitchResult {
        let fm = FileManager.default
        let oldURL = currentURL
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let newURL = scratchpadURL(in: folder)

        // Same folder — nothing to do.
        if (newURL.standardizedFileURL.path) == (oldURL.standardizedFileURL.path) {
            return SwitchResult(newText: currentText, backupURL: nil, loadedExisting: false)
        }

        if fm.fileExists(atPath: newURL.path) {
            let backupURL = oldURL.deletingLastPathComponent()
                .appendingPathComponent(backupFilename())
            try? currentText.write(to: backupURL, atomically: true, encoding: .utf8)
            let loaded = (try? String(contentsOf: newURL, encoding: .utf8)) ?? currentText
            // Stop pointing at the old file; remove it so the old
            // location doesn't keep getting stale writes.
            try? fm.removeItem(at: oldURL)
            UserDefaults.standard.set(folder.path, forKey: folderKey)
            return SwitchResult(newText: loaded, backupURL: backupURL, loadedExisting: true)
        } else {
            try currentText.write(to: newURL, atomically: true, encoding: .utf8)
            try? fm.removeItem(at: oldURL)
            UserDefaults.standard.set(folder.path, forKey: folderKey)
            return SwitchResult(newText: currentText, backupURL: nil, loadedExisting: false)
        }
    }

    /// Switch back to the default folder. Copies current text to the
    /// default location and clears the custom path. The custom-folder
    /// file is *not* deleted — other Macs may still be syncing through
    /// it, and removing it here would yank their content too.
    static func resetToDefault(currentText: String) throws {
        guard isCustom else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: defaultFolder, withIntermediateDirectories: true)
        let defaultURL = scratchpadURL(in: defaultFolder)
        try currentText.write(to: defaultURL, atomically: true, encoding: .utf8)
        UserDefaults.standard.removeObject(forKey: folderKey)
    }
}

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

    // MARK: - iCloud placeholders

    /// iCloud stands a hidden `.<name>.icloud` stub in for a file it
    /// hasn't downloaded to this Mac yet. Pure so it's testable.
    static func placeholderFilename(for filename: String) -> String {
        ".\(filename).icloud"
    }

    static func placeholderURL(in folder: URL) -> URL {
        folder.appendingPathComponent(placeholderFilename(for: scratchpadFilename))
    }

    /// True when a folder already holds a scratchpad — the real file,
    /// or a stub standing in for one still up in the cloud. Both count:
    /// writing over the stub is how a second Mac silently replaces the
    /// note it was about to receive.
    static func hasScratchpad(in folder: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: scratchpadURL(in: folder).path)
            || fm.fileExists(atPath: placeholderURL(in: folder).path)
    }

    /// True when the stub is all there is.
    static func hasUndownloadedScratchpad(in folder: URL) -> Bool {
        let fm = FileManager.default
        return !fm.fileExists(atPath: scratchpadURL(in: folder).path)
            && fm.fileExists(atPath: placeholderURL(in: folder).path)
    }

    /// Ask iCloud to pull the file down. No-op when there's no stub.
    @discardableResult
    static func startDownloadIfPlaceholder(
        in folder: URL = StorageLocation.currentFolder
    ) -> Bool {
        guard hasUndownloadedScratchpad(in: folder) else { return false }
        try? FileManager.default.startDownloadingUbiquitousItem(
            at: scratchpadURL(in: folder)
        )
        return true
    }

    /// Raised when the destination folder's scratchpad is still in the
    /// cloud. Better to stop and let the user retry than to guess.
    enum SwitchError: LocalizedError {
        case destinationNotDownloaded

        var errorDescription: String? {
            "That folder's scratchpad hasn't downloaded from iCloud yet."
        }
        var recoverySuggestion: String? {
            "Wisp has asked iCloud for it. Try again in a moment."
        }
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
    static func setFolder(
        _ folder: URL,
        currentText: String,
        from oldURL: URL = currentURL,
        ownFolder: URL = defaultFolder,
        defaults: UserDefaults = .standard
    ) throws -> SwitchResult {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let newURL = scratchpadURL(in: folder)

        // Same folder — nothing to do.
        if (newURL.standardizedFileURL.path) == (oldURL.standardizedFileURL.path) {
            return SwitchResult(newText: currentText, backupURL: nil, loadedExisting: false)
        }

        // A stub means the real content exists, just not here yet.
        // Adopting the folder now would write over it.
        if hasUndownloadedScratchpad(in: folder) {
            startDownloadIfPlaceholder(in: folder)
            throw SwitchError.destinationNotDownloaded
        }

        if fm.fileExists(atPath: newURL.path) {
            // Read first, and let a failure stop the switch: carrying on
            // would point Wisp at a note it then writes over.
            let loaded = try String(contentsOf: newURL, encoding: .utf8)
            // Nothing to back up when the local note is empty or already
            // says the same thing.
            var backupURL: URL?
            if !currentText.isEmpty, currentText != loaded {
                let url = oldURL.deletingLastPathComponent()
                    .appendingPathComponent(backupFilename())
                // Not `try?`: the local note is about to leave the screen,
                // and the user is told it was saved here.
                try currentText.write(to: url, atomically: true, encoding: .utf8)
                backupURL = url
            }
            removeOldCopy(oldURL, ownFolder: ownFolder)
            defaults.set(folder.path, forKey: folderKey)
            return SwitchResult(newText: loaded, backupURL: backupURL, loadedExisting: true)
        } else {
            try currentText.write(to: newURL, atomically: true, encoding: .utf8)
            removeOldCopy(oldURL, ownFolder: ownFolder)
            defaults.set(folder.path, forKey: folderKey)
            return SwitchResult(newText: currentText, backupURL: nil, loadedExisting: false)
        }
    }

    /// The copy left behind is removed only from Wisp's own folder. Any
    /// other folder may be one other Macs sync through, and deleting the
    /// note there deletes it for all of them.
    private static func removeOldCopy(_ oldURL: URL, ownFolder: URL) {
        guard oldURL.deletingLastPathComponent().standardizedFileURL.path
                == ownFolder.standardizedFileURL.path else { return }
        try? FileManager.default.removeItem(at: oldURL)
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

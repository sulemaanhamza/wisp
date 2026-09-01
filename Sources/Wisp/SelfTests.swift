import AppKit
import Carbon.HIToolbox

/// In-process smoke tests for the pure-logic parts of Wisp.
///
/// Run with: `swift run Wisp --test`
///
/// Why hand-rolled instead of XCTest / Swift Testing: both need Xcode-
/// bundled SDKs, which means anyone with just Command Line Tools can't
/// run them. This harness needs only the Swift toolchain.
///
/// Coverage is limited to types that don't need a running NSApplication:
/// SmartEditing, Headings parsing, HotKey display + Carbon-modifier
/// conversion, and the Theme / FontFace / FontSize enums. Anything that
/// touches NSTextView, Carbon hotkey registration, or the panel needs
/// integration / UI testing — out of scope here.
enum SelfTests {
    // @MainActor so the suite can exercise the AppKit-touching pure
    // functions too — the styling passes are isolated by way of
    // NSViewRepresentable. main.swift's top-level code is already on
    // the main actor, so the call site needs nothing.
    @MainActor
    static func run() -> Never {
        var passed = 0
        var failures: [String] = []

        func check(_ name: String, _ assertion: @autoclosure () -> Bool) {
            if assertion() {
                passed += 1
            } else {
                failures.append(name)
                print("✗ \(name)")
            }
        }

        // MARK: - SmartEditing: horizontal rule trigger

        check("HR trigger '---'", SmartEditing.isHorizontalRuleTrigger("---"))
        check("HR trigger '  ---  '", SmartEditing.isHorizontalRuleTrigger("  ---  "))
        check("HR not '--'", !SmartEditing.isHorizontalRuleTrigger("--"))
        check("HR not '----'", !SmartEditing.isHorizontalRuleTrigger("----"))
        check("HR not '--- hello'", !SmartEditing.isHorizontalRuleTrigger("--- hello"))
        check("HR not 'hello ---'", !SmartEditing.isHorizontalRuleTrigger("hello ---"))
        check("HR not ''", !SmartEditing.isHorizontalRuleTrigger(""))

        // MARK: - SmartEditing: list markers (unordered)

        check("list '- foo' → '- '",  SmartEditing.nextListMarker(for: "- foo") == "- ")
        check("list '* foo' → '* '",  SmartEditing.nextListMarker(for: "* foo") == "* ")
        check("list '+ foo' → '+ '",  SmartEditing.nextListMarker(for: "+ foo") == "+ ")
        check("list '- ' (empty) → ''", SmartEditing.nextListMarker(for: "- ") == "")

        // MARK: - SmartEditing: list markers (ordered numeric)

        check("list '1. foo' → '2. '",  SmartEditing.nextListMarker(for: "1. foo") == "2. ")
        check("list '9. foo' → '10. '", SmartEditing.nextListMarker(for: "9. foo") == "10. ")
        check("list '99. foo' → '100. '", SmartEditing.nextListMarker(for: "99. foo") == "100. ")
        check("list '1. ' (empty) → ''", SmartEditing.nextListMarker(for: "1. ") == "")

        // MARK: - SmartEditing: list markers (ordered alphabetic)

        check("list 'A. foo' → 'B. '", SmartEditing.nextListMarker(for: "A. foo") == "B. ")
        check("list 'Y. foo' → 'Z. '", SmartEditing.nextListMarker(for: "Y. foo") == "Z. ")
        check("list 'Z. foo' → nil",   SmartEditing.nextListMarker(for: "Z. foo") == nil)
        check("list 'a. foo' → 'b. '", SmartEditing.nextListMarker(for: "a. foo") == "b. ")
        check("list 'y. foo' → 'z. '", SmartEditing.nextListMarker(for: "y. foo") == "z. ")
        check("list 'z. foo' → nil",   SmartEditing.nextListMarker(for: "z. foo") == nil)

        // MARK: - SmartEditing: non-list lines

        check("list 'plain' → nil",  SmartEditing.nextListMarker(for: "Just some text") == nil)
        check("list '' → nil",       SmartEditing.nextListMarker(for: "") == nil)
        check("list '-foo' → nil",   SmartEditing.nextListMarker(for: "-foo") == nil)

        // MARK: - SmartEditing: HR constant

        check("horizontalRule = '---'", SmartEditing.horizontalRule == "---")

        // MARK: - HorizontalRuleLayoutManager.isHorizontalRuleLine

        check("isHRLine '---' → true",
              HorizontalRuleLayoutManager.isHorizontalRuleLine("---"))
        check("isHRLine '----' → true",
              HorizontalRuleLayoutManager.isHorizontalRuleLine("----"))
        check("isHRLine '─' x 40 → true (legacy)",
              HorizontalRuleLayoutManager.isHorizontalRuleLine(
                String(repeating: "─", count: 40)))
        check("isHRLine '---' + '─' x 5 → true (mixed)",
              HorizontalRuleLayoutManager.isHorizontalRuleLine(
                "---" + String(repeating: "─", count: 5)))
        check("isHRLine '--' → false (only 2 chars)",
              !HorizontalRuleLayoutManager.isHorizontalRuleLine("--"))
        check("isHRLine '' → false",
              !HorizontalRuleLayoutManager.isHorizontalRuleLine(""))
        check("isHRLine '---x' → false (trailing char)",
              !HorizontalRuleLayoutManager.isHorizontalRuleLine("---x"))
        check("isHRLine 'x---' → false (leading char)",
              !HorizontalRuleLayoutManager.isHorizontalRuleLine("x---"))
        check("isHRLine '-- -' → false (space inside)",
              !HorizontalRuleLayoutManager.isHorizontalRuleLine("-- -"))

        // MARK: - Headings parser

        check("headings '' → []", "".extractHeadings().isEmpty)
        check("headings prose only → []", "hello world\nno headings".extractHeadings().isEmpty)

        let single = "# Hello".extractHeadings()
        check("'# Hello' count == 1", single.count == 1)
        check("'# Hello' name = Hello", single.first?.name == "Hello")
        check("'# Hello' level = 1", single.first?.level == 1)
        check("'# Hello' lineStart = 0", single.first?.lineStart == 0)

        let nested = "# A\n## B\n### C".extractHeadings()
        check("nested count == 3", nested.count == 3)
        check("nested levels", nested.map(\.level) == [1, 2, 3])
        check("nested names",  nested.map(\.name) == ["A", "B", "C"])

        check("'#NoSpace' → []", "#NoSpace".extractHeadings().isEmpty)
        check("'# ' empty title → []", "# ".extractHeadings().isEmpty)
        check("'##  ' empty title → []", "##  ".extractHeadings().isEmpty)

        let mixed = """
        # First
        some prose
        ## Second
        more prose
        # Third
        """.extractHeadings()
        check("mixed names", mixed.map(\.name) == ["First", "Second", "Third"])
        check("mixed levels", mixed.map(\.level) == [1, 2, 1])

        let h6 = "###### Six".extractHeadings()
        check("six hashes level=6", h6.first?.level == 6)
        check("six hashes name=Six", h6.first?.name == "Six")

        let dupTitles = "# A\n# B\n# C".extractHeadings()
        check("ids unique by lineStart", Set(dupTitles.map(\.id)).count == 3)

        // MARK: - HotKey

        check("HotKey.default keyCode = Space",
              HotKey.default.keyCode == UInt32(kVK_Space))
        check("HotKey.default modifiers = option",
              HotKey.default.modifiers == UInt32(optionKey))
        check("HotKey.default display = '⌥Space'",
              HotKey.default.displayString == "⌥Space")

        let cmdShiftP = HotKey(
            keyCode: UInt32(kVK_ANSI_P),
            modifiers: UInt32(cmdKey | shiftKey)
        )
        check("⇧⌘P display", cmdShiftP.displayString == "⇧⌘P")

        let allMods = HotKey(
            keyCode: UInt32(kVK_ANSI_F),
            modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey)
        )
        check("⌃⌥⇧⌘F display order", allMods.displayString == "⌃⌥⇧⌘F")

        let unknown = HotKey(keyCode: 9999, modifiers: UInt32(cmdKey))
        check("unknown keyCode falls back",
              unknown.displayString == "⌘Key9999")

        check("carbonModifiers cmd",
              HotKey.carbonModifiers(from: [.command]) == UInt32(cmdKey))
        check("carbonModifiers option+shift",
              HotKey.carbonModifiers(from: [.option, .shift])
              == UInt32(optionKey | shiftKey))
        check("carbonModifiers all",
              HotKey.carbonModifiers(from: [.command, .option, .shift, .control])
              == UInt32(cmdKey | optionKey | shiftKey | controlKey))
        check("carbonModifiers empty",
              HotKey.carbonModifiers(from: []) == 0)

        // MARK: - FontSize

        check("FontSize.small  → 17pt", FontSize.small.pointSize == 17)
        check("FontSize.medium → 20pt", FontSize.medium.pointSize == 20)
        check("FontSize.large  → 24pt", FontSize.large.pointSize == 24)
        check("FontSize cycles small→medium",  FontSize.small.next == .medium)
        check("FontSize cycles medium→large",  FontSize.medium.next == .large)
        check("FontSize cycles large→small",   FontSize.large.next == .small)
        check("FontSize.small.rawValue", FontSize.small.rawValue == "small")
        check("FontSize.medium.rawValue", FontSize.medium.rawValue == "medium")
        check("FontSize.large.rawValue", FontSize.large.rawValue == "large")

        // MARK: - FontFace

        for face in FontFace.allCases {
            check("FontFace \(face.displayName) familyName == displayName",
                  face.familyName == face.displayName)
        }
        check("FontFace count = 6", FontFace.allCases.count == 6)
        check("FontFace.charter.rawValue", FontFace.charter.rawValue == "charter")
        check("FontFace.iowanOldStyle.rawValue",
              FontFace.iowanOldStyle.rawValue == "iowanOldStyle")
        check("FontFace.hoeflerText.rawValue",
              FontFace.hoeflerText.rawValue == "hoeflerText")
        check("FontFace.palatino.rawValue", FontFace.palatino.rawValue == "palatino")
        check("FontFace.optima.rawValue", FontFace.optima.rawValue == "optima")
        check("FontFace.avenirNext.rawValue", FontFace.avenirNext.rawValue == "avenirNext")

        // MARK: - Theme

        check("Theme.dark.rawValue",  Theme.dark.rawValue == "dark")
        check("Theme.light.rawValue", Theme.light.rawValue == "light")

        check("ThemePreference.light.next is dark",
              ThemePreference.light.next == .dark)
        check("ThemePreference.dark.next is system",
              ThemePreference.dark.next == .system)
        check("ThemePreference.system.next is light",
              ThemePreference.system.next == .light)
        // Raw values stay compatible with the pre-system-mode storage
        // format so existing "Theme" defaults still load.
        check("ThemePreference.light.rawValue",
              ThemePreference.light.rawValue == "light")
        check("ThemePreference.dark.rawValue",
              ThemePreference.dark.rawValue == "dark")
        check("ThemePreference.system.rawValue",
              ThemePreference.system.rawValue == "system")

        // MARK: - LaunchAtLogin
        // Smoke-only: SMAppService talks to a system daemon and `swift
        // run` can't actually register, so we verify the API contract
        // (returns a Bool, idempotent no-op for current state) without
        // mutating real state.

        let launchBefore = LaunchAtLogin.isEnabled
        check("LaunchAtLogin.isEnabled is bool",
              launchBefore == true || launchBefore == false)
        LaunchAtLogin.setEnabled(launchBefore)
        check("LaunchAtLogin.setEnabled(current) is no-op",
              LaunchAtLogin.isEnabled == launchBefore)

        // MARK: - LaunchSource

        check("LaunchSource: nil userInfo → user-initiated (fallback)",
              LaunchSource.isUserInitiated(launchUserInfo: nil))
        check("LaunchSource: empty userInfo → user-initiated (fallback)",
              LaunchSource.isUserInitiated(launchUserInfo: [:]))
        check("LaunchSource: isDefault=true → user-initiated",
              LaunchSource.isUserInitiated(
                  launchUserInfo: [LaunchSource.isDefaultLaunchKey: true]))
        check("LaunchSource: isDefault=false → not user-initiated",
              !LaunchSource.isUserInitiated(
                  launchUserInfo: [LaunchSource.isDefaultLaunchKey: false]))
        check("LaunchSource: NSNumber(true) bridges → user-initiated",
              LaunchSource.isUserInitiated(
                  launchUserInfo: [LaunchSource.isDefaultLaunchKey: NSNumber(value: true)]))
        check("LaunchSource: NSNumber(false) bridges → not user-initiated",
              !LaunchSource.isUserInitiated(
                  launchUserInfo: [LaunchSource.isDefaultLaunchKey: NSNumber(value: false)]))
        check("LaunchSource: unrelated key → falls back to user-initiated",
              LaunchSource.isUserInitiated(launchUserInfo: ["SomeOtherKey": false]))

        // MARK: - Updater throttle

        let now = Date()
        check("Updater.shouldCheck nil lastChecked → true",
              Updater.shouldCheck(now: now, lastCheckedAt: nil, throttle: 60))
        check("Updater.shouldCheck just-now → false",
              !Updater.shouldCheck(
                now: now, lastCheckedAt: now, throttle: 60))
        check("Updater.shouldCheck 30s ago, 60s throttle → false",
              !Updater.shouldCheck(
                now: now,
                lastCheckedAt: now.addingTimeInterval(-30),
                throttle: 60))
        check("Updater.shouldCheck 60s ago, 60s throttle → true",
              Updater.shouldCheck(
                now: now,
                lastCheckedAt: now.addingTimeInterval(-60),
                throttle: 60))
        check("Updater.shouldCheck 120s ago, 60s throttle → true",
              Updater.shouldCheck(
                now: now,
                lastCheckedAt: now.addingTimeInterval(-120),
                throttle: 60))

        // MARK: - Updater.buttonAction

        let stubURL = URL(string: "https://example.com/wisp.zip")!
        check("buttonAction(.idle) = noop",
              Updater.buttonAction(for: .idle) == .noop)
        check("buttonAction(.available) = startDownload",
              Updater.buttonAction(for: .available(version: "0.1.36", zipURL: stubURL))
                == .startDownload)
        check("buttonAction(.downloading) = noop",
              Updater.buttonAction(for: .downloading(version: "0.1.36"))
                == .noop)
        check("buttonAction(.pending) = applyAndRestart",
              Updater.buttonAction(for: .pending(version: "0.1.36"))
                == .applyAndRestart)

        // MARK: - StorageLocation

        check("StorageLocation.scratchpadFilename = scratchpad.md",
              StorageLocation.scratchpadFilename == "scratchpad.md")
        check("StorageLocation.backupPrefix = scratchpad-local-backup-",
              StorageLocation.backupPrefix == "scratchpad-local-backup-")

        let probeFolder = URL(fileURLWithPath: "/tmp/wisp-probe")
        let composed = StorageLocation.scratchpadURL(in: probeFolder)
        check("scratchpadURL(in:) ends with scratchpad.md",
              composed.lastPathComponent == "scratchpad.md")
        check("scratchpadURL(in:) is inside the chosen folder",
              composed.deletingLastPathComponent().standardizedFileURL.path
                == probeFolder.standardizedFileURL.path)

        check("defaultFolder ends with /Wisp",
              StorageLocation.defaultFolder.lastPathComponent == "Wisp")

        // Backup filename: deterministic by date input, no colons (so it
        // works on filesystems that disallow them), starts with the
        // shared prefix.
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let backup = StorageLocation.backupFilename(at: fixedDate)
        check("backupFilename starts with prefix",
              backup.hasPrefix(StorageLocation.backupPrefix))
        check("backupFilename ends with .md",
              backup.hasSuffix(".md"))
        check("backupFilename contains no colons",
              !backup.contains(":"))

        // MARK: - PanelFrameStore.isUsable

        let mainScreen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let extScreen = NSRect(x: 1440, y: 0, width: 1920, height: 1080)

        check("frame fully on screen → usable",
              PanelFrameStore.isUsable(
                NSRect(x: 100, y: 100, width: 800, height: 640),
                onScreens: [mainScreen]))
        check("frame on second screen → usable",
              PanelFrameStore.isUsable(
                NSRect(x: 1600, y: 100, width: 800, height: 640),
                onScreens: [mainScreen, extScreen]))
        check("frame on now-missing screen → not usable",
              !PanelFrameStore.isUsable(
                NSRect(x: 1600, y: 100, width: 800, height: 640),
                onScreens: [mainScreen]))
        check("frame mostly off-screen but >minVisible showing → usable",
              PanelFrameStore.isUsable(
                NSRect(x: 1300, y: 100, width: 800, height: 640),
                onScreens: [mainScreen]))
        check("frame with only a sliver on-screen → not usable",
              !PanelFrameStore.isUsable(
                NSRect(x: 1380, y: 100, width: 800, height: 640),
                onScreens: [mainScreen]))
        check("degenerate tiny frame → not usable",
              !PanelFrameStore.isUsable(
                NSRect(x: 100, y: 100, width: 50, height: 50),
                onScreens: [mainScreen]))
        check("no screens at all → not usable",
              !PanelFrameStore.isUsable(
                NSRect(x: 100, y: 100, width: 800, height: 640),
                onScreens: []))

        // MARK: - TextSearch

        check("search empty query → no matches",
              TextSearch.matches(in: "hello world", query: "").isEmpty)
        check("search no match → empty",
              TextSearch.matches(in: "hello world", query: "zzz").isEmpty)

        let oneHit = TextSearch.matches(in: "hello world", query: "world")
        check("search single match count", oneHit.count == 1)
        check("search single match location", oneHit.first?.location == 6)
        check("search single match length", oneHit.first?.length == 5)

        let manyHits = TextSearch.matches(in: "the cat sat on the mat", query: "at")
        check("search 'at' → 3 matches", manyHits.count == 3)
        check("search 'at' locations",
              manyHits.map(\.location) == [5, 9, 20])

        check("search is case-insensitive",
              TextSearch.matches(in: "Hello HELLO hello", query: "hello").count == 3)

        // Overlapping pattern advances correctly (no infinite loop, no
        // double-count): "aa" in "aaaa" → matches at 0 and 2.
        let overlap = TextSearch.matches(in: "aaaa", query: "aa")
        check("search overlapping 'aa' in 'aaaa' → 2", overlap.count == 2)
        check("search overlapping locations", overlap.map(\.location) == [0, 2])

        // MARK: - ReleaseNotes highlights

        let body1 = """
        - ⌘F to find in your notes
        - Wisp remembers its window size and position

        <!--wisp:more-->

        Update via the in-app card, or `brew upgrade --cask wisp`.
        - this bullet is below the marker and must be ignored
        """
        let h1 = ReleaseNotes.highlights(from: body1)
        check("notes: two highlights above marker", h1.count == 2)
        check("notes: first bullet stripped",
              h1.first == "⌘F to find in your notes")
        check("notes: second bullet stripped",
              h1.last == "Wisp remembers its window size and position")

        check("notes: intro prose (non-bullet) ignored",
              ReleaseNotes.highlights(from: "Some intro line\n- only this\n").count == 1)

        check("notes: old verbose body with no bullets → empty",
              ReleaseNotes.highlights(from: "Just a paragraph of prose.\nMore prose.").isEmpty)

        check("notes: empty body → empty", ReleaseNotes.highlights(from: "").isEmpty)

        check("notes: '*' bullets supported",
              ReleaseNotes.highlights(from: "* one\n* two").count == 2)

        let capped = (1...10).map { "- item \($0)" }.joined(separator: "\n")
        check("notes: capped at maxHighlights",
              ReleaseNotes.highlights(from: capped).count == ReleaseNotes.maxHighlights)

        // MARK: - Snapshots: big-shrink guard

        check("shrink: full → empty is drastic",
              Snapshots.isDrasticShrink(old: String(repeating: "a", count: 100), new: ""))
        check("shrink: lost more than half is drastic",
              Snapshots.isDrasticShrink(
                old: String(repeating: "a", count: 100),
                new: String(repeating: "a", count: 40)))
        check("shrink: small trim is not drastic",
              !Snapshots.isDrasticShrink(
                old: String(repeating: "a", count: 100),
                new: String(repeating: "a", count: 80)))
        check("shrink: tiny old content never drastic",
              !Snapshots.isDrasticShrink(old: "short", new: ""))
        check("shrink: growth is not a shrink",
              !Snapshots.isDrasticShrink(old: String(repeating: "a", count: 100),
                                         new: String(repeating: "a", count: 200)))

        // MARK: - Snapshots: prune ring

        let snapNames = (1...25).map { String(format: "scratchpad-2026-06-13-%06d.md", $0) }
        let toPrune = Snapshots.filesToPrune(snapNames, keep: 20)
        check("prune: keeps newest 20 of 25", toPrune.count == 5)
        check("prune: drops the oldest",
              toPrune.first == "scratchpad-2026-06-13-000001.md")
        check("prune: nothing to do under the cap",
              Snapshots.filesToPrune(snapNames, keep: 30).isEmpty)
        check("prune: ignores non-snapshot files",
              Snapshots.filesToPrune(["scratchpad.md", "notes.txt", ".DS_Store"], keep: 1).isEmpty)

        // MARK: - Snapshots: filename

        let snapName = Snapshots.filename(at: Date(timeIntervalSince1970: 1_700_000_000))
        check("snapshot filename prefix", snapName.hasPrefix("scratchpad-"))
        check("snapshot filename suffix", snapName.hasSuffix(".md"))
        check("snapshot filename is sortable by time",
              Snapshots.filename(at: Date(timeIntervalSince1970: 1_000))
                < Snapshots.filename(at: Date(timeIntervalSince1970: 2_000)))

        // MARK: - Reload decision (the save/reload revert)

        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 2_000)
        check("reload: first read with no baseline",
              EditorModel.decideReload(
                fileMTime: t0, lastLoadedMTime: nil,
                text: "", lastSavedText: "") == .reload)
        check("reload: our own write is not newer",
              EditorModel.decideReload(
                fileMTime: t0, lastLoadedMTime: t0,
                text: "a", lastSavedText: "a") == .skipNotNewer)
        check("reload: someone else's write is picked up",
              EditorModel.decideReload(
                fileMTime: t1, lastLoadedMTime: t0,
                text: "a", lastSavedText: "a") == .reload)
        check("reload: never discards unsaved edits",
              EditorModel.decideReload(
                fileMTime: t1, lastLoadedMTime: t0,
                text: "typed but not saved", lastSavedText: "a") == .skipUnsavedEdits)
        check("reload: unsaved edits win even without a baseline",
              EditorModel.decideReload(
                fileMTime: t1, lastLoadedMTime: nil,
                text: "typed", lastSavedText: "") == .skipUnsavedEdits)

        // MARK: - HotKey binding rules

        check("hotkey: shift alone is not enough",
              !HotKey.hasRequiredModifier(UInt32(shiftKey)))
        check("hotkey: nothing is not enough",
              !HotKey.hasRequiredModifier(0))
        check("hotkey: option counts", HotKey.hasRequiredModifier(UInt32(optionKey)))
        check("hotkey: command counts", HotKey.hasRequiredModifier(UInt32(cmdKey)))
        check("hotkey: control counts", HotKey.hasRequiredModifier(UInt32(controlKey)))
        check("hotkey: shift plus option counts",
              HotKey.hasRequiredModifier(UInt32(shiftKey) | UInt32(optionKey)))

        check("hotkey: ⌘C is reserved",
              HotKey.reservedReason(
                for: HotKey(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey))) != nil)
        check("hotkey: ⌘Q is reserved",
              HotKey.reservedReason(
                for: HotKey(keyCode: UInt32(kVK_ANSI_Q), modifiers: UInt32(cmdKey))) != nil)
        check("hotkey: ⌘Space is reserved",
              HotKey.reservedReason(
                for: HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey))) != nil)
        check("hotkey: ⌥⌘C is fine",
              HotKey.reservedReason(
                for: HotKey(keyCode: UInt32(kVK_ANSI_C),
                            modifiers: UInt32(cmdKey) | UInt32(optionKey))) == nil)
        check("hotkey: the default ⌥Space is fine",
              HotKey.reservedReason(for: .default) == nil)

        // MARK: - StorageLocation: iCloud placeholders

        check("placeholder name for scratchpad.md",
              StorageLocation.placeholderFilename(for: "scratchpad.md")
                == ".scratchpad.md.icloud")
        check("placeholder URL is hidden in the folder",
              StorageLocation.placeholderURL(in: URL(fileURLWithPath: "/tmp/wisp-probe"))
                .lastPathComponent == ".scratchpad.md.icloud")

        // MARK: - Updater: asset digest parsing

        let goodDigest = "sha256:" + String(repeating: "a", count: 64)
        check("digest: sha256 field parses",
              Updater.sha256Hex(fromDigestField: goodDigest)
                == String(repeating: "a", count: 64))
        check("digest: nil field → nil",
              Updater.sha256Hex(fromDigestField: nil) == nil)
        check("digest: wrong algorithm → nil",
              Updater.sha256Hex(fromDigestField: "md5:" + String(repeating: "a", count: 32)) == nil)
        check("digest: short hex → nil",
              Updater.sha256Hex(fromDigestField: "sha256:abc") == nil)
        check("digest: non-hex → nil",
              Updater.sha256Hex(fromDigestField: "sha256:" + String(repeating: "z", count: 64)) == nil)
        check("buttonAction(.failed) = openReleases",
              Updater.buttonAction(for: .failed(version: "0.1.41")) == .openReleases)

        // MARK: - Checkboxes

        check("checkbox: unticked box found",
              Checkbox.boxRange(in: "- [ ] milk") == NSRange(location: 2, length: 3))
        check("checkbox: ticked box found",
              Checkbox.boxRange(in: "- [x] milk") == NSRange(location: 2, length: 3))
        check("checkbox: capital X counts",
              Checkbox.boxRange(in: "- [X] milk") != nil)
        check("checkbox: indented item found",
              Checkbox.boxRange(in: "    - [ ] milk") == NSRange(location: 6, length: 3))
        check("checkbox: asterisk bullet counts",
              Checkbox.boxRange(in: "* [ ] milk") != nil)
        check("checkbox: plus bullet counts",
              Checkbox.boxRange(in: "+ [ ] milk") != nil)
        check("checkbox: plain bullet is not a box",
              Checkbox.boxRange(in: "- milk") == nil)
        check("checkbox: bare brackets are not a box",
              Checkbox.boxRange(in: "[ ] milk") == nil)
        check("checkbox: other letters are not a state",
              Checkbox.boxRange(in: "- [y] milk") == nil)
        check("checkbox: prose is not a box",
              Checkbox.boxRange(in: "see - [ ] later") == nil)
        check("checkbox: empty line is not a box",
              Checkbox.boxRange(in: "") == nil)
        check("checkbox: truncated line is not a box",
              Checkbox.boxRange(in: "- [") == nil)

        check("checkbox: isChecked true", Checkbox.isChecked("- [x] milk"))
        check("checkbox: isChecked false", !Checkbox.isChecked("- [ ] milk"))
        check("checkbox: isChecked on a non-item", !Checkbox.isChecked("milk"))

        check("checkbox: toggling ticks",
              Checkbox.toggling("- [ ] milk") == "- [x] milk")
        check("checkbox: toggling unticks",
              Checkbox.toggling("- [x] milk") == "- [ ] milk")
        check("checkbox: toggling capital X unticks",
              Checkbox.toggling("- [X] milk") == "- [ ] milk")
        check("checkbox: toggling keeps indentation",
              Checkbox.toggling("  - [ ] milk") == "  - [x] milk")
        check("checkbox: nothing to toggle",
              Checkbox.toggling("- milk") == nil)

        // MARK: - SmartEditing: task list continuation

        check("list '- [ ] foo' → '- [ ] '",
              SmartEditing.nextListMarker(for: "- [ ] foo") == "- [ ] ")
        check("list '- [x] foo' → '- [ ] ' (new items start unticked)",
              SmartEditing.nextListMarker(for: "- [x] foo") == "- [ ] ")
        check("list '* [ ] foo' keeps its bullet",
              SmartEditing.nextListMarker(for: "* [ ] foo") == "* [ ] ")
        check("list '- [ ] ' (empty) exits the list",
              SmartEditing.nextListMarker(for: "- [ ] ") == "")
        check("list '- foo' still plain",
              SmartEditing.nextListMarker(for: "- foo") == "- ")

        // MARK: - Inbox

        check("inbox: whitespace isn't worth filing",
              !Inbox.isWorthArchiving("   \n\t \n"))
        check("inbox: empty isn't worth filing", !Inbox.isWorthArchiving(""))
        check("inbox: a thought is worth filing", Inbox.isWorthArchiving("call the bank"))
        let inboxName = Inbox.filename(at: Date(timeIntervalSince1970: 1_700_000_000))
        check("inbox: filename ends .md", inboxName.hasSuffix(".md"))
        check("inbox: filename sorts by time",
              Inbox.filename(at: Date(timeIntervalSince1970: 1_000))
                < Inbox.filename(at: Date(timeIntervalSince1970: 2_000)))

        // MARK: - Transparency

        check("transparency: off is fully opaque in both themes",
              Transparency.off.tintAlpha(for: .dark) == 1.0
                && Transparency.off.tintAlpha(for: .light) == 1.0)
        // The bug this pins: light/subtle was 0.92 over a near-opaque
        // material, so every setting looked identical. Each step has to
        // be far enough from its neighbour to actually see.
        let minStep: CGFloat = 0.15
        for theme in Theme.allCases {
            check("transparency: off → subtle is visible (\(theme.rawValue))",
                  Transparency.off.tintAlpha(for: theme)
                    - Transparency.subtle.tintAlpha(for: theme) >= minStep)
            check("transparency: subtle → strong is visible (\(theme.rawValue))",
                  Transparency.subtle.tintAlpha(for: theme)
                    - Transparency.strong.tintAlpha(for: theme) >= minStep)
            check("transparency: strong still leaves a readable ground (\(theme.rawValue))",
                  Transparency.strong.tintAlpha(for: theme) >= 0.2)
            check("transparency: off paints a solid tint (\(theme.rawValue))",
                  Transparency.off.tintColor(for: theme).alphaComponent == 1.0)
            check("transparency: off skips the blur view (\(theme.rawValue))",
                  !Chrome.for(theme, transparency: .off).usesVisualEffect)
            check("transparency: subtle uses the blur view (\(theme.rawValue))",
                  Chrome.for(theme, transparency: .subtle).usesVisualEffect)
            check("transparency: both themes use a translucent material (\(theme.rawValue))",
                  Chrome.for(theme, transparency: .subtle).material == .fullScreenUI)
        }
        // whiteComponent, not brightnessComponent: these are grayscale
        // colors and asking an NSColor for a component its colorspace
        // doesn't have raises.
        check("transparency: dark off isn't pure black",
              Transparency.off.tintColor(for: .dark).whiteComponent > 0.0)
        check("transparency: raw values persist",
              Transparency(rawValue: "subtle") == .subtle)

        // MARK: - Code background

        for theme in Theme.allCases {
            let off = Palette.codeBackground(for: theme, transparency: .off).alphaComponent
            let subtle = Palette.codeBackground(for: theme, transparency: .subtle).alphaComponent
            let strong = Palette.codeBackground(for: theme, transparency: .strong).alphaComponent
            check("code bg: lifts as the panel gets more transparent (\(theme.rawValue))",
                  off < subtle && subtle < strong)
            check("code bg: stays an overlay, never a solid block (\(theme.rawValue))",
                  strong < 0.25)
        }
        check("code bg: dark theme lightens the ground",
              Palette.codeBackground(for: .dark, transparency: .subtle).whiteComponent > 0.5)
        check("code bg: light theme darkens the ground",
              Palette.codeBackground(for: .light, transparency: .subtle).whiteComponent < 0.5)

        // MARK: - Restyle clears what it applies

        let storage = NSTextStorage(string: "- [x] done\n\n```\ncode\n```\n\nsee `inline` here\n")
        func runs(_ key: NSAttributedString.Key, in storage: NSTextStorage) -> Int {
            var found = 0
            storage.enumerateAttribute(
                key, in: NSRange(location: 0, length: storage.length)
            ) { value, _, _ in
                if value != nil { found += 1 }
            }
            return found
        }
        MinimalTextEditor.restyle(
            storage, face: .charter, size: .medium, theme: .dark, transparency: .subtle
        )
        check("restyle: a ticked item is struck through",
              runs(.strikethroughStyle, in: storage) > 0)
        check("restyle: a fenced block is marked for the layout manager",
              runs(.wispCodeBlock, in: storage) > 0)
        check("restyle: an inline span gets a ground",
              runs(.backgroundColor, in: storage) > 0)

        // Untick the box and drop the fence; a second pass has to take
        // the old attributes away, not just add new ones.
        storage.replaceCharacters(in: NSRange(location: 3, length: 1), with: " ")
        MinimalTextEditor.restyle(
            storage, face: .charter, size: .medium, theme: .dark, transparency: .subtle
        )
        check("restyle: unticking clears the strikethrough",
              runs(.strikethroughStyle, in: storage) == 0)

        let plain = NSTextStorage(string: "just words, nothing special\n")
        MinimalTextEditor.restyle(
            plain, face: .charter, size: .medium, theme: .light, transparency: .off
        )
        check("restyle: plain prose gets no code marks",
              runs(.wispCodeBlock, in: plain) == 0 && runs(.backgroundColor, in: plain) == 0)

        // MARK: - Tips

        check("tips: numeric compare, not lexicographic",
              Tips.isOlder("0.1.9", "0.1.10"))
        check("tips: equal versions aren't older",
              !Tips.isOlder("0.1.42", "0.1.42"))
        check("tips: newer isn't older",
              !Tips.isOlder("0.1.42", "0.1.41"))
        check("tips: version is the newest entry in the list",
              Tips.all.allSatisfy { !Tips.isOlder(Tips.version, $0.version) })
        check("tips: version matches some tip",
              Tips.all.contains { $0.version == Tips.version })

        check("tips: no marker shows everything",
              Tips.unseen(since: nil).count == min(Tips.all.count, 6))
        check("tips: current marker shows nothing",
              Tips.unseen(since: Tips.version).isEmpty)
        check("tips: a marker from the future shows nothing",
              Tips.unseen(since: "99.0.0").isEmpty)
        check("tips: an old marker shows the newest ones",
              Tips.unseen(since: "0.1.41").allSatisfy { $0.version == "0.1.42" })
        check("tips: an old marker doesn't re-show what they've seen",
              !Tips.unseen(since: "0.1.41").contains { $0.version == "0.1.41" })
        check("tips: a very old marker shows the lot",
              Tips.unseen(since: "0.1.20").count == min(Tips.all.count, 6))
        check("tips: the limit is respected",
              Tips.unseen(since: nil, limit: 2).count == 2)
        check("tips: every tip says something",
              Tips.all.allSatisfy { !$0.keys.isEmpty && !$0.what.isEmpty })
        check("tips: ids are unique",
              Set(Tips.all.map(\.id)).count == Tips.all.count)

        // MARK: - PanelFrameStore.clamped

        let screen = NSRect(x: 0, y: 0, width: 2560, height: 1400)
        check("clamp: a frame that fits is left alone",
              PanelFrameStore.clamped(
                NSRect(x: 100, y: 100, width: 800, height: 640), to: screen)
                == NSRect(x: 100, y: 100, width: 800, height: 640))
        // The frame that actually shipped: 2630pt tall on a 1440pt display.
        let poisoned = PanelFrameStore.clamped(
            NSRect(x: 838, y: -1746, width: 1203, height: 2630), to: screen)
        check("clamp: an over-tall frame is cut to the screen",
              poisoned.height == 1400)
        check("clamp: and pulled back on screen",
              poisoned.minY >= screen.minY && poisoned.maxY <= screen.maxY)
        check("clamp: width is capped too",
              PanelFrameStore.clamped(
                NSRect(x: 0, y: 0, width: 9999, height: 400), to: screen).width == 2560)
        check("clamp: a window off the right edge comes back",
              PanelFrameStore.clamped(
                NSRect(x: 5000, y: 100, width: 800, height: 640), to: screen).maxX <= screen.maxX)
        check("clamp: a window off the left edge comes back",
              PanelFrameStore.clamped(
                NSRect(x: -900, y: 100, width: 800, height: 640), to: screen).minX >= screen.minX)
        check("clamp: the result always fits",
              PanelFrameStore.clamped(
                NSRect(x: -3000, y: -3000, width: 9999, height: 9999), to: screen)
                == screen)

        // MARK: - Summary

        let total = passed + failures.count
        print("\n\(passed)/\(total) passed")
        if !failures.isEmpty {
            print("\(failures.count) failure(s):")
            for f in failures { print("  · \(f)") }
            exit(1)
        }
        exit(0)
    }
}

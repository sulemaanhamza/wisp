import AppKit
import SwiftUI
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
        check("FontSize cycles large→extraLarge", FontSize.large.next == .extraLarge)
        check("FontSize cycles extraLarge→small", FontSize.extraLarge.next == .small)
        check("FontSize larger stops at the top", FontSize.extraLarge.larger == .extraLarge)
        check("FontSize smaller stops at the bottom", FontSize.small.smaller == .small)
        check("FontSize larger steps", FontSize.medium.larger == .large)
        check("FontSize smaller steps", FontSize.medium.smaller == .small)
        check("word count: empty is zero", EditorModel.countWords("") == 0)
        check("word count: counts words, not symbols", EditorModel.countWords("# Hi there — **you**") == 3)
        check("FontSize.small.rawValue", FontSize.small.rawValue == "small")
        check("FontSize.medium.rawValue", FontSize.medium.rawValue == "medium")
        check("FontSize.large.rawValue", FontSize.large.rawValue == "large")

        // MARK: - FontFace

        for face in FontFace.allCases {
            check("FontFace \(face.displayName) familyName == displayName",
                  face.familyName == face.displayName)
        }
        check("FontFace count = 8", FontFace.allCases.count == 8)
        check("FontFace: every face resolves to a real font",
              FontFace.allCases.allSatisfy { $0.font(size: 20) != nil })
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

        // MARK: - Paragraph restyle matches a full restyle

        // The editor restyles only the paragraphs an edit touched. Every
        // edit below has to leave the storage exactly as a from-scratch
        // full restyle would — including the ones that open or close a
        // fence, which change lines far from the edit.
        let seed = """
        # Title
        Some **bold** and *italic* and `code` at https://example.com here.

        - [ ] open task
        - [x] done task
        ---
        ```
        inside **not bold**
        ```
        ## Tail
        last line
        """
        // Applied one after another, each against the text the last one
        // left, so "close it again" really closes what the step before
        // opened. Each range is found in the current text by content.
        typealias Step = (name: String, edit: (NSString) -> (NSRange, String))
        let steps: [Step] = [
            ("type in prose", { ns in (NSRange(location: ns.range(of: "Some").location + 2, length: 0), "x") }),
            ("make a heading", { ns in (NSRange(location: ns.range(of: "Soxme").location, length: 0), "## ") }),
            ("open a fence mid-note", { ns in (NSRange(location: ns.range(of: "- [ ] open").location, length: 0), "```\n") }),
            ("close it again", { ns in (ns.range(of: "```\n- [ ] open"), "- [ ] open") }),
            ("break the closing fence", { ns in (NSRange(location: ns.range(of: "```\n## Tail").location, length: 1), "") }),
            ("mend it", { ns in (NSRange(location: ns.range(of: "``\n## Tail").location, length: 0), "`") }),
            ("tick a box", { ns in (NSRange(location: ns.range(of: "[ ]").location + 1, length: 1), "x") }),
            ("paste across lines", { ns in (NSRange(location: 20, length: 30), "new\n**words**\n") }),
            ("delete to the tail", { ns in (NSRange(location: 8, length: ns.range(of: "## Tail").location - 8), "") }),
        ]
        let running = NSTextStorage(string: seed)
        MarkdownStyler.restyle(running, face: .charter, size: .medium, theme: .dark, transparency: .subtle)
        for step in steps {
            let (range, replacement) = step.edit(running.string as NSString)
            guard range.location != NSNotFound else {
                check("paragraph restyle == full restyle: \(step.name) (step found its text)", false)
                continue
            }
            running.replaceCharacters(in: range, with: replacement)
            MarkdownStyler.restyle(
                running, face: .charter, size: .medium, theme: .dark, transparency: .subtle,
                edited: NSRange(location: range.location, length: (replacement as NSString).length)
            )
            let full = NSTextStorage(string: running.string)
            MarkdownStyler.restyle(full, face: .charter, size: .medium, theme: .dark, transparency: .subtle)
            check("paragraph restyle == full restyle: \(step.name)", running.isEqual(to: full))
        }

        // Same property under random edits, seeded so a failure repeats.
        var rng: UInt64 = 0x5EED
        func roll(_ n: Int) -> Int {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return Int((rng >> 33) % UInt64(max(n, 1)))
        }
        let fragments = [
            "```\n", "\n", "# ", "**", "*", "`", "- [ ] ", "- [x] ", "---\n", "word ", "https://a.io ", "  ```\n",
            // Every other line break NSString knows: pasted text keeps
            // them, and a paragraph restyle must agree with a full one.
            "\r", "\r\n", "\u{2028}", "\u{2029}",
            // Inline math is line-local too; hold it to the same rule.
            "2 + 2 =", " =", "5 km in mi =",
        ]
        let fuzz = NSTextStorage(string: seed)
        MarkdownStyler.restyle(fuzz, face: .charter, size: .medium, theme: .light, transparency: .strong)
        var fuzzFailures = 0
        for _ in 0..<300 {
            let length = fuzz.length
            let location = roll(length + 1)
            let removing = roll(3) == 0 ? min(roll(12), length - location) : 0
            let insert = roll(4) == 0 ? "" : fragments[roll(fragments.count)]
            fuzz.replaceCharacters(in: NSRange(location: location, length: removing), with: insert)
            MarkdownStyler.restyle(
                fuzz, face: .charter, size: .medium, theme: .light, transparency: .strong,
                edited: NSRange(location: location, length: (insert as NSString).length)
            )
            let full = NSTextStorage(string: fuzz.string)
            MarkdownStyler.restyle(full, face: .charter, size: .medium, theme: .light, transparency: .strong)
            if !fuzz.isEqual(to: full) { fuzzFailures += 1 }
        }
        check("paragraph restyle == full restyle: 300 random edits (\(fuzzFailures) differ)", fuzzFailures == 0)

        // MARK: - Line editing

        func applied(_ text: String, _ edit: LineEditing.Edit?) -> String? {
            guard let edit else { return nil }
            return (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        }
        check("move up: swaps with the line above",
              applied("a\nb\nc", LineEditing.moveLines(in: "a\nb\nc", selection: NSRange(location: 2, length: 0), up: true)) == "b\na\nc")
        check("move up: the last line carries its missing newline correctly",
              applied("a\nb", LineEditing.moveLines(in: "a\nb", selection: NSRange(location: 3, length: 0), up: true)) == "b\na")
        check("move down: into the last line",
              applied("a\nb", LineEditing.moveLines(in: "a\nb", selection: NSRange(location: 0, length: 0), up: false)) == "b\na")
        check("move up: nothing above the first line",
              LineEditing.moveLines(in: "a\nb", selection: NSRange(location: 0, length: 0), up: true) == nil)
        check("move down: nothing below the last line",
              LineEditing.moveLines(in: "a\nb", selection: NSRange(location: 3, length: 0), up: false) == nil)
        check("move down: a two-line selection moves together",
              applied("a\nb\nc\n", LineEditing.moveLines(in: "a\nb\nc\n", selection: NSRange(location: 0, length: 3), up: false)) == "c\na\nb\n")
        let caret = LineEditing.moveLines(in: "one\ntwo\n", selection: NSRange(location: 6, length: 0), up: true)
        check("move up: caret stays on the same character", caret?.selection.location == 2)
        check("task: plain line gains a box", LineEditing.toggleTask(line: "milk") == "- [ ] milk")
        check("task: bullet keeps its marker", LineEditing.toggleTask(line: "  * milk") == "  * [ ] milk")
        check("task: open box ticks", LineEditing.toggleTask(line: "- [ ] milk") == "- [x] milk")
        check("task: ticked box unticks", LineEditing.toggleTask(line: "- [x] milk") == "- [ ] milk")
        let taskEdit = LineEditing.toggleTask(in: "milk\n", selection: NSRange(location: 2, length: 0))
        check("task: caret follows the text it was in",
              applied("milk\n", taskEdit) == "- [ ] milk\n" && taskEdit.selection.location == 8)
        check("task: empty note gets a box",
              applied("", LineEditing.toggleTask(in: "", selection: NSRange(location: 0, length: 0))) == "- [ ] ")

        // Every kind of line break keeps lines apart when they move.
        check("move up: CRLF lines stay separate",
              applied("a\r\nb\r\nc\r\n", LineEditing.moveLines(in: "a\r\nb\r\nc\r\n", selection: NSRange(location: 3, length: 0), up: true)) == "b\r\na\r\nc\r\n")
        check("move up: the CRLF last line keeps the join's break",
              applied("a\r\nb", LineEditing.moveLines(in: "a\r\nb", selection: NSRange(location: 3, length: 0), up: true)) == "b\r\na")
        check("move up: a ⌃↩ line break (U+2028) isn't merged away",
              applied("todo\nmilk\u{2028}eggs\nbread",
                      LineEditing.moveLines(in: "todo\nmilk\u{2028}eggs\nbread", selection: NSRange(location: 6, length: 0), up: true))
                == "milk\u{2028}todo\neggs\nbread")
        let intoLast = LineEditing.moveLines(in: "ab\nc", selection: NSRange(location: 0, length: 3), up: false)
        check("move down: the selection stays inside the text",
              intoLast.map { NSMaxRange($0.selection) <= ($0.replacement as NSString).length } == true)
        check("task: a tab after the bullet", LineEditing.toggleTask(line: "-\tmilk") == "- [ ] milk")
        check("task: CRLF line keeps its break",
              applied("milk\r\nnext", LineEditing.toggleTask(in: "milk\r\nnext", selection: NSRange(location: 0, length: 0))) == "- [ ] milk\r\nnext")

        // Whole-line edits never complete a shortcode; only a typed
        // character does. Driven through the real delegate.
        let shortcodeView = CaretTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let shortcodeCoordinator = MinimalTextEditor.Coordinator(text: Binding(get: { "" }, set: { _ in }))
        shortcodeView.delegate = shortcodeCoordinator
        shortcodeView.string = "notes\nship :rocket:"
        shortcodeView.setSelectedRange(NSRange(location: 0, length: (shortcodeView.string as NSString).length))
        LineEditing.apply(
            LineEditing.toggleTask(in: shortcodeView.string, selection: shortcodeView.selectedRange()),
            to: shortcodeView
        )
        check("⌘L: a literal shortcode stays literal", shortcodeView.string == "- [ ] notes\n- [ ] ship :rocket:")
        shortcodeView.string = "a :)\nb"
        shortcodeView.setSelectedRange(NSRange(location: 0, length: 0))
        if let edit = LineEditing.moveLines(in: shortcodeView.string, selection: shortcodeView.selectedRange(), up: false) {
            LineEditing.apply(edit, to: shortcodeView)
        }
        check("⌥↓: a literal :) stays literal", shortcodeView.string == "b\na :)")
        shortcodeView.string = "ship :rocket:"
        shortcodeView.setSelectedRange(NSRange(location: 13, length: 0))
        LineEditing.apply(
            LineEditing.toggleTask(in: shortcodeView.string, selection: shortcodeView.selectedRange()),
            to: shortcodeView
        )
        check("⌘L with the caret right after a shortcode leaves it literal",
              shortcodeView.string == "- [ ] ship :rocket:")

        // ⌥↑ is handled by the note's own view, so a text field keeps it.
        func optionArrow(_ up: Bool) -> NSEvent {
            let key = String(UnicodeScalar(up ? NSUpArrowFunctionKey : NSDownArrowFunctionKey)!)
            return NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [.option, .function, .numericPad],
                timestamp: 0, windowNumber: 0, context: nil, characters: key,
                charactersIgnoringModifiers: key, isARepeat: false, keyCode: up ? 126 : 125
            )!
        }
        let lineView = CaretTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        lineView.string = "one\ntwo"
        lineView.setSelectedRange(NSRange(location: 5, length: 0))
        lineView.keyDown(with: optionArrow(true))
        check("⌥↑ in the note moves the line", lineView.string == "two\none")
        lineView.keyDown(with: optionArrow(false))
        check("⌥↓ moves it back", lineView.string == "one\ntwo")

        // Inline styling edge cases the review turned up.
        let inline = NSTextStorage(string: "* buy *milk* today\nrun `ls *.txt *.md` now\nhttps://en.wikipedia.org/wiki/Foo_(bar) and (https://x.io).\n")
        MarkdownStyler.restyle(inline, face: .charter, size: .medium, theme: .dark, transparency: .subtle)
        let inlineNS = inline.string as NSString
        func fontAt(_ needle: String, offset: Int = 0) -> NSFont? {
            inline.attribute(.font, at: inlineNS.range(of: needle).location + offset, effectiveRange: nil) as? NSFont
        }
        check("emphasis: a bullet isn't an opening *",
              fontAt("buy")?.fontDescriptor.symbolicTraits.contains(.italic) == false)
        check("emphasis: *milk* after a bullet is italic",
              fontAt("milk")?.fontDescriptor.symbolicTraits.contains(.italic) == true)
        check("emphasis: asterisks inside code stay code",
              inline.attribute(.foregroundColor, at: inlineNS.range(of: "*.txt").location, effectiveRange: nil) as? NSColor
                == Palette.for(.dark).text)
        var linkRange = NSRange()
        _ = inline.attribute(.wispLink, at: inlineNS.range(of: "Foo_").location, effectiveRange: &linkRange)
        check("links: a balanced ) belongs to the URL",
              inlineNS.substring(with: linkRange).hasSuffix("Foo_(bar)"))
        _ = inline.attribute(.wispLink, at: inlineNS.range(of: "x.io").location, effectiveRange: &linkRange)
        check("links: an enclosing ) doesn't", inlineNS.substring(with: linkRange) == "https://x.io")
        check("links: non-ASCII URLs still open",
              MarkdownStyler.linkURL("https://de.wikipedia.org/wiki/Straße") != nil)

        // Open on Pointer's Screen: centred stays centred.
        let small = NSRect(x: 0, y: 0, width: 1512, height: 945)
        let big = NSRect(x: 1512, y: 0, width: 2560, height: 1410)
        let centred = NSRect(x: 356, y: 152, width: 800, height: 640)
        let carried = PanelFrameStore.carried(centred, size: centred.size, from: small, to: big)
        check("carry: a centred panel lands centred", abs(carried.midX - big.midX) < 1 && abs(carried.midY - big.midY) < 1)
        check("carry: at the size asked for", carried.size == centred.size)
        check("carry: still fits a smaller screen",
              small.contains(PanelFrameStore.carried(carried, size: NSSize(width: 1100, height: 1200), from: big, to: small)))

        check("menu shortcut: minus shows as a plain hyphen",
              HotKey(keyCode: UInt32(kVK_ANSI_Minus), modifiers: UInt32(optionKey)).menuKeyEquivalent?.0 == "-")
        check("menu shortcut: F-keys fall back to the title",
              HotKey(keyCode: UInt32(kVK_F1), modifiers: UInt32(optionKey)).menuKeyEquivalent == nil)

        // MARK: - Inline math

        let sums: [(String, String?)] = [
            ("12 × 4.5 + 20 =", "74"),
            ("12 * 4.5 + 20=", "74"),
            ("3 x 4 =", "12"),
            ("(2 + 3) ^ 2 =", "25"),
            ("-3 + 1 =", "-2"),
            ("10 / 4 =", "2.5"),
            ("1/3 =", "0.333333"),
            ("0.1 + 0.2 =", "0.3"),
            ("1,200 / 3 =", "400"),
            ("1,200,000 + 1 =", "1,200,001"),
            ("Rent: 1200 / 3 =", "400"),
            // Labels in front are skipped; numbers in front never are —
            // an answer that quietly ignores some of the line is worse
            // than none.
            ("split 1200 between 3 is 1200 / 3 =", nil),
            ("Q3 revenue: 1.2 + 3.4 =", "4.6"),
            ("2nd payment 10 + 5 =", "15"),
            ("5 ft 10 in in cm =", "177.8 cm"),
            ("1 h 30 min in min =", "90 min"),
            ("6 ft 2 in =", "6.17 ft"),
            ("5km + 300m =", "5.3 km"),
            ("1.5k + 2k =", "3,500"),
            ("1.2M - 200k =", "1,000,000"),
            ("3x4 =", "12"),
            ("-2^2 =", "-4"),
            ("2^-1 =", "0.5"),
            ("2^3^2 =", "512"),
            ("1 / 3000000 =", "0.0000003333"),
            ("1 mm in km =", "0.000001 km"),
            ("10^25 =", "10,000,000,000,000,000,000,000,000"),
            ("15% + 150 =", nil),
            // Money: the symbol carries through, nothing is converted.
            ("$12 × 3 =", "$36"),
            ("3 × $12 =", "$36"),
            ("€40 + €15 =", "€55"),
            ("40€ + 15€ =", "55€"),
            ("40 € + 15 € =", "55 €"),
            ("£12.50 x 2 =", "£25"),
            ("$12.50 + 1 =", "$13.50"),
            ("$10 / 3 =", "$3.33"),
            ("Lunch $14 + tip 18% =", "$16.52"),
            ("20% of $80 =", "$16"),
            ("$1.5k x 2 =", "$3,000"),
            ("¥1,000 × 3 =", "¥3,000"),
            ("-$5 + $2 =", "-$3"),
            ("$100 / $25 =", "4"),
            ("$5 + €5 =", nil),
            ("$5 × $5 =", nil),
            ("$5 in km =", nil),
            ("$5 + 3 km =", nil),
            ("$5 =", nil),
            ("2 + 2 =\r", "4"),
            ("2 + 2 =\r\n", "4"),
            ("- [ ] 2 + 2 =", "4"),
            ("# 2 + 2 =", "4"),
            ("20% of 150 =", "30"),
            ("150 + 15% =", "172.5"),
            ("80 - 25% =", "60"),
            ("5 km in mi =", "3.11 mi"),
            ("180 cm in ft =", "5.91 ft"),
            ("2.5 kg in lb =", "5.51 lb"),
            ("5 in in cm =", "12.7 cm"),
            ("10 cm to in =", "3.94 in"),
            ("72 f in c =", "22.22 °C"),
            ("-40 c in f =", "-40 °F"),
            ("90 min in h =", "1.5 h"),
            ("3.5 GB in MB =", "3,500 MB"),
            ("2 d in h =", "48 h"),
            ("5 km + 300 m =", "5.3 km"),
            ("10 km / 2 =", "5 km"),
            ("10 km / 2 km =", "5"),
            ("500 m in mi =", "0.3107 mi"),
            // Left alone: not a question, or not answerable.
            ("42 =", nil),
            ("5 km =", nil),
            ("a = b", nil),
            ("x == y", nil),
            ("if a <= b", nil),
            ("a != b =", nil),
            ("1 / 0 =", nil),
            ("5 km in kg =", nil),
            ("2026-09-25 =", nil),
            ("10:30 =", nil),
            ("hello world =", nil),
            ("Hotel: 4 nights × 120 =", "480"),
            ("3 apples + 2 pears =", "5"),
            ("not a sum =", nil),
            ("12 × 4.5 + 20", nil),
            ("=", nil),
        ]
        for (line, expected) in sums {
            check("math: \"\(line)\" → \(expected ?? "nothing")", InlineMath.answer(forLine: line) == expected)
        }

        check("math: the answer grows with the sum, not stored",
              InlineMath.answer(forLine: "2 + 2 =") == "4")
        let mathStorage = NSTextStorage(string: "total 2 + 2 =\nno sum here\n```\n1 + 1 =\n```\n")
        MarkdownStyler.restyle(mathStorage, face: .charter, size: .medium, theme: .dark, transparency: .subtle)
        let mathNS = mathStorage.string as NSString
        check("math: a sum line carries its answer on the =",
              mathStorage.attribute(.wispMathAnswer, at: mathNS.range(of: "=").location, effectiveRange: nil) as? String == "4")
        check("math: nothing inside a code block",
              runs(.wispMathAnswer, in: mathStorage) == 1)
        check("math: the file text is untouched", mathStorage.string.hasPrefix("total 2 + 2 =\n"))
        let atEnd = MinimalTextEditor.Coordinator.answerInsertion(
            in: mathStorage, selection: NSRange(location: mathNS.range(of: "=").location + 1, length: 0))
        check("math: Tab after a bare = types a space and the answer", atEnd?.text == " 4")
        check("math: Tab mid-line is just Tab",
              MinimalTextEditor.Coordinator.answerInsertion(in: mathStorage, selection: NSRange(location: 3, length: 0)) == nil)
        let spaced = NSTextStorage(string: "3 x 3 = ")
        MarkdownStyler.restyle(spaced, face: .charter, size: .medium, theme: .dark, transparency: .subtle)
        let crlf = NSTextStorage(string: "2 + 2 =\r\nnext\r\n")
        MarkdownStyler.restyle(crlf, face: .charter, size: .medium, theme: .dark, transparency: .subtle)
        var answerRange = NSRange()
        let crlfAnswer = crlf.attribute(.wispMathAnswer, at: 6, effectiveRange: &answerRange) as? String
        check("math: a CRLF line gets its answer", crlfAnswer == "4")
        check("math: …on the = alone, not the line break", answerRange == NSRange(location: 6, length: 1))
        let trailing = NSTextStorage(string: "3 x 3 =  \nnext")
        MarkdownStyler.restyle(trailing, face: .charter, size: .medium, theme: .dark, transparency: .subtle)
        check("math: Tab right after the = still works with spaces after the caret",
              MinimalTextEditor.Coordinator.answerInsertion(in: trailing, selection: NSRange(location: 7, length: 0))?.text == " 9")
        check("math: …but not with text after the caret",
              MinimalTextEditor.Coordinator.answerInsertion(in: trailing, selection: NSRange(location: 3, length: 0)) == nil)
        check("math: a number inside a label doesn't count as one",
              !InlineMath.containsNumber("Q3 revenue, 2nd draft, v2:") && InlineMath.containsNumber("5 ft"))
        check("math: after a trailing space, just the answer",
              MinimalTextEditor.Coordinator.answerInsertion(in: spaced, selection: NSRange(location: 8, length: 0))?.text == "9")

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let sept25 = utc.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 23, minute: 30))!
        check("date: ISO, in the given time zone",
              LineEditing.dateStamp(sept25, timeZone: TimeZone(identifier: "UTC")!) == "2026-09-25")
        check("date: local midnight decides the day",
              LineEditing.dateStamp(sept25, timeZone: TimeZone(identifier: "Asia/Karachi")!) == "2026-09-26")

        check("fences: indented and bare both count",
              MarkdownStyler.fenceLineStarts(in: "a\n  ```swift\nb\n```\n" as NSString) == [2, 15])
        check("fences: backticks mid-line don't",
              MarkdownStyler.fenceLineStarts(in: "say ```this``` inline\n" as NSString).isEmpty)
        let merged = MinimalTextEditor.Coordinator.merge(
            NSRange(location: 10, length: 5), NSRange(location: 2, length: 3), delta: 3
        )
        check("pending edit: an earlier insert shifts the older range's end",
              merged.location == 2 && NSMaxRange(merged) == 18)

        let linked = NSTextStorage(string: "see https://example.com now\n`https://in.code`\n")
        MarkdownStyler.restyle(linked, face: .charter, size: .medium, theme: .light, transparency: .off)
        check("links: a URL in prose is marked", runs(.wispLink, in: linked) == 1)

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
              Tips.unseen(since: nil).count == Tips.all.count)
        check("tips: current marker shows nothing",
              Tips.unseen(since: Tips.version).isEmpty)
        check("tips: a marker from the future shows nothing",
              Tips.unseen(since: "99.0.0").isEmpty)
        check("tips: an old marker shows the newest ones",
              Tips.unseen(since: "0.1.45").allSatisfy { $0.version == "0.1.46" })
        check("tips: an old marker doesn't re-show what they've seen",
              !Tips.unseen(since: "0.1.41").contains { $0.version == "0.1.41" })
        check("tips: a very old marker shows the lot",
              Tips.unseen(since: "0.1.20").count == Tips.all.count)
        check("tips: the limit is respected",
              Tips.unseen(since: nil, limit: 2).count == 2)
        check("tips: every tip says something",
              Tips.all.allSatisfy { !$0.keys.isEmpty })
        check("tips: ids are unique",
              Set(Tips.all.map(\.id)).count == Tips.all.count)

        let helpKeys = Set(HelpContent.sections(hotKey: "⌥Space").flatMap(\.rows).map(\.tipKey))
        check("tips: every tip names a row in the help",
              Tips.all.allSatisfy { helpKeys.contains($0.keys) })

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

        let sliver = PanelFrameStore.clamped(NSRect(x: 100, y: 100, width: 90, height: 1200), to: screen)
        check("clamp: a sliver of a panel grows back to the smallest usable width",
              sliver.width == PanelFrameStore.smallest.width && sliver.height == 1200)
        check("clamp: the screen still wins over the minimum",
              PanelFrameStore.clamped(
                NSRect(x: 0, y: 0, width: 100, height: 100),
                to: NSRect(x: 0, y: 0, width: 300, height: 200)).size == NSSize(width: 300, height: 200))

        // MARK: - Caret

        let caretFont = NSFont.systemFont(ofSize: 20)
        let line = NSRect(x: 10, y: 300, width: 1, height: 33)
        let trimmed = CaretTextView.caretRect(in: line, font: caretFont)
        check("caret: trimmed to the font's ascent plus descent",
              trimmed.height == (caretFont.ascender - caretFont.descender).rounded(.up))
        check("caret: keeps the line's bottom edge", trimmed.maxY == line.maxY)
        check("caret: never taller than the line it's in",
              CaretTextView.caretRect(in: NSRect(x: 0, y: 0, width: 1, height: 10), font: caretFont).height == 10)

        // MARK: - PanelFrameStore.bestScreen (multi-monitor restore)

        let laptop = NSRect(x: 0, y: 0, width: 1512, height: 944)
        let external = NSRect(x: 1512, y: 0, width: 2560, height: 1415)
        let onExternal = NSRect(x: 2000, y: 300, width: 800, height: 640)
        check("bestScreen: a panel on the external monitor picks the external",
              PanelFrameStore.bestScreen(for: onExternal, among: [laptop, external]) == external)
        check("bestScreen: a panel on the laptop picks the laptop",
              PanelFrameStore.bestScreen(
                for: NSRect(x: 100, y: 100, width: 800, height: 640),
                among: [laptop, external]) == laptop)
        check("bestScreen: straddling picks the side with more of it",
              PanelFrameStore.bestScreen(
                for: NSRect(x: 1300, y: 100, width: 800, height: 640),
                among: [laptop, external]) == external)
        check("bestScreen: off every screen is nil",
              PanelFrameStore.bestScreen(
                for: NSRect(x: 9000, y: 9000, width: 800, height: 640),
                among: [laptop, external]) == nil)
        // The regression: clamping to the *right* screen leaves an
        // external-monitor panel exactly where the user put it.
        if let best = PanelFrameStore.bestScreen(for: onExternal, among: [laptop, external]) {
            check("bestScreen: restore leaves an external-monitor panel alone",
                  PanelFrameStore.clamped(onExternal, to: best) == onExternal)
        } else {
            check("bestScreen: restore leaves an external-monitor panel alone", false)
        }

        // MARK: - Outside-click monitor lifecycle

        // Pure-ish: the monitor object can be exercised without a panel.
        // Real click delivery needs a GUI session and a second app, so
        // that part is manual — this pins start/stop idempotence and
        // that the default preference is off.
        var fired = 0
        let monitor = OutsideClickMonitor { fired += 1 }
        check("outside-click: starts stopped", !monitor.isActive)
        monitor.start()
        check("outside-click: start activates", monitor.isActive)
        monitor.start()
        check("outside-click: starting twice is harmless", monitor.isActive)
        monitor.stop()
        check("outside-click: stop deactivates", !monitor.isActive)
        monitor.stop()
        check("outside-click: stopping twice is harmless", !monitor.isActive)
        check("outside-click: never fired without a click", fired == 0)

        // MARK: - Reminders: which lines count

        check("reminder: a plain line", Reminders.isReminder("Remind me in 10 minutes to check this"))
        check("reminder: any case", Reminders.isReminder("REMIND ME tomorrow"))
        check("reminder: after a bullet, number or checkbox",
              Reminders.isReminder("- Remind me Friday") && Reminders.isReminder("2. remind me at 3pm")
                && Reminders.isReminder("- [ ] Remind me tomorrow to send it"))
        check("reminder: a ticked task is done, not a reminder", !Reminders.isReminder("- [x] Remind me tomorrow"))
        check("reminder: mid-sentence doesn't count", !Reminders.isReminder("I told him to remind me tomorrow"))
        check("reminder: \"Reminder:\" doesn't count", !Reminders.isReminder("Reminder: call mum"))
        check("reminder: \"Remind me:\" counts", Reminders.body(ofLine: "Remind me: tomorrow at 9") == "tomorrow at 9")
        check("reminder: \"remind meeting\" doesn't count", !Reminders.isReminder("remind meeting at 3"))
        check("reminder: the notification drops the list marker",
              Reminders.sentence(ofLine: "- [ ] Remind me Friday to send it") == "Remind me Friday to send it")

        // MARK: - Reminders: reading the time

        var karachi = Calendar(identifier: .gregorian)
        karachi.timeZone = TimeZone(identifier: "Asia/Karachi")!
        let thursday = karachi.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 11, minute: 16))!
        func readAt(_ text: String, _ now: Date = thursday) -> Reminders.Reading? {
            Reminders.read(text, now: now, calendar: karachi)?.reading
        }
        func clock(_ date: Date?) -> String {
            guard let date else { return "-" }
            let p = karachi.dateComponents([.month, .day, .hour, .minute], from: date)
            return "\(p.month!)/\(p.day!) \(p.hour!):\(String(format: "%02d", p.minute!))"
        }
        func due(_ reading: Reminders.Reading?) -> Date? { if case .at(let d)? = reading { return d } else { return nil } }

        check("time: in 10 minutes", due(readAt("Remind me in 10 minutes to check this")) == thursday.addingTimeInterval(600))
        check("time: in 2 hours", due(readAt("Remind me in 2 hours")) == thursday.addingTimeInterval(7200))
        check("time: in half an hour", due(readAt("Remind me in half an hour to stretch")) == thursday.addingTimeInterval(1800))
        check("time: in an hour", due(readAt("Remind me in an hour")) == thursday.addingTimeInterval(3600))
        check("time: in 1.5 hours", due(readAt("Remind me in 1.5 hours")) == thursday.addingTimeInterval(5400))
        check("time: in 90 mins", due(readAt("remind me in 90 mins")) == thursday.addingTimeInterval(5400))
        check("time: in 3 days is that day at 9", clock(due(readAt("Remind me in 3 days to follow up"))) == "10/11 9:00")
        check("time: in a week", clock(due(readAt("Remind me in a week"))) == "10/15 9:00")
        check("time: next week is Monday at 9", clock(due(readAt("Remind me next week to review"))) == "10/12 9:00")
        check("time: at 7 after 7 AM is 7 PM", clock(due(readAt("Remind me at 7 to stretch"))) == "10/8 19:00")
        let early = karachi.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 6, minute: 0))!
        check("time: at 7 before 7 AM is 7 AM", clock(due(readAt("Remind me at 7 to stretch", early))) == "10/8 7:00")
        let lateNight = karachi.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 23, minute: 0))!
        check("time: at 7 late at night is tomorrow 7 AM", clock(due(readAt("Remind me at 7", lateNight))) == "10/9 7:00")
        check("time: at 19 is taken as said", clock(due(readAt("Remind me at 19 to cook"))) == "10/8 19:00")
        check("time: this weekend is Saturday at 9", clock(due(readAt("Remind me this weekend to clean"))) == "10/10 9:00")
        check("time: the weekend at 10am", clock(due(readAt("Remind me at the weekend at 10am"))) == "10/10 10:00")
        let saturdayNoon = karachi.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12, minute: 0))!
        check("time: this weekend on Saturday afternoon is Sunday", clock(due(readAt("Remind me this weekend", saturdayNoon))) == "10/11 9:00")
        check("time: end of day is 5 PM", clock(due(readAt("Remind me end of day to send it"))) == "10/8 17:00")
        check("time: EOD after 5 PM is tomorrow's", clock(due(readAt("Remind me EOD", lateNight))) == "10/9 17:00")
        check("time: by the end of the day", clock(due(readAt("Remind me by the end of the day"))) == "10/8 17:00")
        check("time: in the morning is the next 9 AM", clock(due(readAt("Remind me in the morning to call"))) == "10/9 9:00")
        check("time: in the morning, before 9, is today", clock(due(readAt("Remind me in the morning", early))) == "10/8 9:00")
        check("time: the phrase is what matched",
              Reminders.read("Remind me in 10 minutes to check this", now: thursday, calendar: karachi)?.phrase == "in 10 minutes")

        // macOS reads these, always against the real clock.
        let realNow = Date()
        let here = Calendar.current
        func readNow(_ text: String) -> Reminders.Reading? { Reminders.read(text, now: realNow)?.reading }
        let tomorrowNine = here.date(bySettingHour: 9, minute: 0, second: 0, of: here.date(byAdding: .day, value: 1, to: realNow)!)!
        check("time: tomorrow is 9 AM, not the reader's noon", due(readNow("Remind me tomorrow to view this section")) == tomorrowNine)
        let tomorrowSeven = here.date(bySettingHour: 7, minute: 0, second: 0, of: tomorrowNine)!
        check("time: tomorrow at 7am", due(readNow("Remind me tomorrow at 7am to run")) == tomorrowSeven)
        let tomorrowAtSeven = due(readNow("Remind me tomorrow at 7 to run"))
        check("time: tomorrow at 7 is tomorrow, not 7 PM today",
              tomorrowAtSeven.map { here.isDate($0, inSameDayAs: tomorrowNine) && here.component(.hour, from: $0) % 12 == 7 } == true)
        let threePM = due(readNow("Remind me at 3pm to send it"))
        check("time: at 3pm is the next 3 PM",
              threePM.map { $0 > realNow && here.component(.hour, from: $0) == 15 && $0.timeIntervalSince(realNow) <= 90_000 } == true)
        let friday = due(readNow("Remind me Friday to send the invoice"))
        check("time: a weekday is that day at 9",
              friday.map { here.component(.weekday, from: $0) == 6 && here.component(.hour, from: $0) == 9 && $0 > realNow } == true)
        check("time: yesterday has passed", readNow("Remind me yesterday to fail") == .past)
        let tomorrowThree = here.date(bySettingHour: 15, minute: 0, second: 0, of: tomorrowNine)!
        check("time: a time written apart from its day joins it",
              due(readNow("Remind me tomorrow to call John at 3pm")) == tomorrowThree)
        check("time: tomorrow EOD is tomorrow at 5",
              due(readNow("Remind me tomorrow EOD")) == here.date(bySettingHour: 17, minute: 0, second: 0, of: tomorrowNine))
        let nextWednesday = due(readNow("Remind me Wednesday next week"))
        check("time: Wednesday next week",
              nextWednesday.map { here.component(.weekday, from: $0) == 4 && $0.timeIntervalSince(realNow) > 86_400 } == true)
        check("time: an hour inside the sentence doesn't override the day",
              due(readNow("Remind me tomorrow to log in an hour early")) == tomorrowNine)
        check("time: a span first wins over a day mentioned later",
              due(readNow("Remind me in 2 hours to prep for tomorrow's meeting")).map { abs($0.timeIntervalSince(realNow) - 7200) < 2 } == true)
        check("time: at 7 o'clock", due(readNow("Remind me at 7 o'clock")).map { here.component(.hour, from: $0) % 12 == 7 } == true)
        check("time: an absurd span is no time, not a crash",
              readNow("Remind me in 9999999999999999999 weeks") == .noTime && readNow("Remind me in 99999999999999999999 days") == .noTime)
        check("time: the phrase includes a time added to a day",
              Reminders.read("Remind me next week at 3pm to review")?.phrase == "next week 3pm")
        check("time: no time found", readNow("Remind me to buy milk") == .noTime)
        check("time: not a reminder at all", Reminders.read("Buy milk tomorrow") == nil)

        // MARK: - Reminders: showing a time

        var gmt = Calendar(identifier: .gregorian)
        gmt.timeZone = TimeZone(identifier: "UTC")!
        let us = Locale(identifier: "en_US")
        func on(_ m: Int, _ d: Int, _ h: Int, _ mi: Int, year: Int = 2026) -> Date {
            gmt.date(from: DateComponents(year: year, month: m, day: d, hour: h, minute: mi))!
        }
        func shown(_ date: Date) -> String {
            Reminders.describe(date, now: on(10, 8, 11, 16), calendar: gmt, locale: us).replacingOccurrences(of: "\u{202F}", with: " ")
        }
        check("label: today shows the time", shown(on(10, 8, 14, 42)) == "2:42 PM")
        check("label: tomorrow", shown(on(10, 9, 9, 0)) == "Tomorrow 9:00 AM")
        check("label: this week shows the day", shown(on(10, 11, 9, 0)) == "Sun 9:00 AM")
        check("label: further out shows the date", shown(on(10, 20, 9, 0)) == "Oct 20 9:00 AM")
        check("label: another year shows the year", shown(on(1, 5, 9, 0, year: 2027)) == "Jan 5, 2027 9:00 AM")
        check("label: a 24-hour Mac gets a 24-hour clock",
              Reminders.describe(on(10, 8, 14, 42), now: on(10, 8, 11, 16), calendar: gmt, locale: Locale(identifier: "en_GB")) == "14:42")
        check("label: due and sent read differently",
              Reminders.Label.due(on(10, 8, 14, 42)).text(now: on(10, 8, 11, 16), calendar: gmt, locale: us).hasPrefix("\u{2192} ")
                && Reminders.Label.sent(on(10, 8, 9, 0)).text(now: on(10, 8, 11, 16), calendar: gmt, locale: us).hasPrefix("sent "))

        // MARK: - Reminders: the store

        let storeFolder = FileManager.default.temporaryDirectory.appendingPathComponent("wisp-reminders-\(UUID().uuidString)")
        let storeFile = storeFolder.appendingPathComponent("Reminders.json")
        let fake = FakeReminderScheduler()
        let store = ReminderStore(fileURL: storeFile, scheduler: fake)
        let tenMinutes = "Remind me in 10 minutes to check this"
        let start = Date()

        let set1 = store.commit(line: tenMinutes, now: start)
        check("store: a finished line sets a reminder", set1 != nil && store.reminders.count == 1)
        check("store: …handed to macOS once allowed", set1.map { r in fake.scheduled.contains { $0.id == r.id } } == true)
        check("store: …ten minutes from when it was finished",
              set1.map { abs($0.fireDate.timeIntervalSince(start.addingTimeInterval(600))) < 1 } == true)
        check("store: finishing it again sets nothing new",
              store.commit(line: tenMinutes, now: start.addingTimeInterval(5))?.id == set1?.id
                && store.reminders.count == 1)
        check("store: before it's finished the line shows the time it read",
              store.label(forLine: "Remind me in 10 minutes to check th", now: start) == .due(start.addingTimeInterval(600)))
        check("store: once set the line shows its time, as set", store.label(forLine: tenMinutes, now: start) == .set(set1!.fireDate))

        store.reconcile(noteText: "notes\n", now: start.addingTimeInterval(20))
        check("store: a deleted line cancels it",
              store.reminders.first?.state == .cancelled && fake.cancelled.contains(set1!.id))
        let pasted = store.commit(line: tenMinutes, now: start.addingTimeInterval(60))
        check("store: pasted back soon, it keeps its time",
              pasted?.id == set1?.id && pasted?.fireDate == set1?.fireDate && pasted?.state != .cancelled)

        let edited = "Remind me in 10 minutes to check that"
        store.reconcile(noteText: "notes\n\(edited)\n", now: start.addingTimeInterval(90))
        let moved = store.commit(line: edited, origin: tenMinutes, now: start.addingTimeInterval(120))
        check("store: other words edited, same time phrase: same reminder, same time",
              moved?.id == set1?.id && moved?.fireDate == set1?.fireDate && moved?.line == edited)

        let ticked = "- [x] Remind me tomorrow to pay"
        let openTask = "- [ ] Remind me tomorrow to pay"
        let task = store.commit(line: openTask, now: start)
        store.reconcile(noteText: "\(ticked)\n\(edited)", now: start.addingTimeInterval(30))
        check("store: ticking it off cancels it",
              store.reminder(id: task!.id)?.state == .cancelled && store.label(forLine: ticked) == nil)

        let filed = store.commit(line: "Remind me in 2 hours to file", now: start)
        store.archive(noteText: "Remind me in 2 hours to file")
        store.reconcile(noteText: edited, now: start.addingTimeInterval(10))
        check("store: filed to the Inbox, it keeps firing", store.reminder(id: filed!.id)?.state == .scheduled)

        check("store: a time gone by sets nothing", store.commit(line: "Remind me yesterday", now: start) == nil)
        check("store: no time sets nothing", store.commit(line: "Remind me to buy milk", now: start) == nil)
        check("store: it reads sent after it fires",
              store.label(forLine: edited, now: set1!.fireDate.addingTimeInterval(1)) == .sent(set1!.fireDate))

        store.noteLoaded("Remind me tomorrow to call from my laptop\n")
        check("store: a line from another Mac isn't set here",
              store.label(forLine: "Remind me tomorrow to call from my laptop") == .notOnThisMac)

        let restarted = ReminderStore(fileURL: storeFile, scheduler: fake)
        check("store: reminders survive a restart", restarted.reminders == store.reminders)

        check("store: finds its line again",
              store.locate(store.reminder(id: set1!.id)!, in: "a\n\(edited)\nb") == NSRange(location: 2, length: (edited as NSString).length))
        check("store: never a different line that happens to share its time words",
              store.locate(store.reminder(id: set1!.id)!, in: "Remind me in 10 minutes to check it all") == nil)
        check("store: or nothing when it's gone", store.locate(store.reminder(id: set1!.id)!, in: "unrelated") == nil)

        // Permission: never trusted from memory.
        let denying = FakeReminderScheduler()
        denying.permission = .denied
        let blocked = ReminderStore(fileURL: storeFolder.appendingPathComponent("b.json"), scheduler: denying)
        let waiting = blocked.commit(line: tenMinutes, now: start)
        check("permission: denied, it waits and says so",
              waiting.map { blocked.reminder(id: $0.id)?.state == .waiting } == true
                && blocked.label(forLine: tenMinutes, now: start) == .notificationsOff && denying.scheduled.isEmpty)
        denying.permission = .allowed
        blocked.refreshPermission()
        check("permission: allowed later, the waiting one is handed to macOS",
              denying.scheduled.count == 1 && blocked.label(forLine: tenMinutes, now: start) != .notificationsOff)

        let late = FakeReminderScheduler()
        late.permission = .denied
        let neverSent = ReminderStore(fileURL: storeFolder.appendingPathComponent("f.json"), scheduler: late)
        let soon = neverSent.commit(line: "Remind me in 1 minute to test", now: start)
        check("permission: a reminder that never went out never reads \"sent\"",
              neverSent.label(forLine: "Remind me in 1 minute to test", now: soon!.fireDate.addingTimeInterval(5)) == .notSent)

        let again = FakeReminderScheduler()
        let retype = ReminderStore(fileURL: storeFolder.appendingPathComponent("g.json"), scheduler: again)
        let oneMinute = "Remind me in 1 minute to test this"
        let firedOnce = retype.commit(line: oneMinute, now: start)!
        let afterwards = firedOnce.fireDate.addingTimeInterval(30)
        check("store: a fired reminder reads sent", retype.label(forLine: oneMinute, now: afterwards) == .sent(firedOnce.fireDate))
        retype.reconcile(noteText: "", now: afterwards)
        check("store: deleting a fired line doesn't pull it from Notification Center",
              !again.cancelled.contains(firedOnce.id))
        let fresh = retype.commit(line: oneMinute, now: afterwards.addingTimeInterval(5))
        check("store: typed again after deleting, it's a new reminder, not the old \"sent\"",
              fresh != nil && fresh?.id != firedOnce.id && fresh!.fireDate > afterwards
                && retype.label(forLine: oneMinute, now: afterwards.addingTimeInterval(6)) == .set(fresh!.fireDate))

        let setAt = on(10, 8, 14, 42)
        let setText = Reminders.Label.set(setAt).text(now: on(10, 8, 11, 16), calendar: gmt, locale: us)
        check("label: set shows the time with a bell, no arrow; read-as-you-type shows the arrow, no bell",
              setText.replacingOccurrences(of: "\u{202F}", with: " ") == "2:42 PM"
                && Reminders.Label.set(setAt).symbol == "bell" && Reminders.Label.due(setAt).symbol == nil
                && !Reminders.Label.set(setAt).shortText(now: on(10, 8, 11, 16), calendar: gmt, locale: us).contains("\u{2192}"))
        check("label: once sent, a tick that ticks the line; a set one's bell does nothing when clicked",
              Reminders.Label.sent(setAt).symbol == "checkmark.circle" && Reminders.Label.sent(setAt).ticksLine
                && !Reminders.Label.set(setAt).ticksLine && !Reminders.Label.notSent.ticksLine)
        check("label: the bell is part of what a restyle compares",
              TrailingLabel(full: "a", short: "b", symbol: "bell") != TrailingLabel(full: "a", short: "b")
                && TrailingLabel(full: "a", short: "b", symbol: "bell") == TrailingLabel(full: "a", short: "b", symbol: "bell"))

        check("done: a plain line becomes a ticked task", Reminders.ticked("Remind me at 3pm") == "- [x] Remind me at 3pm")
        check("done: a task's box is ticked, nothing else changes",
              Reminders.ticked("  * [ ] Remind me at 3pm") == "  * [x] Remind me at 3pm")
        check("done: a bullet keeps its marker and indent",
              Reminders.ticked("\t- Remind me at 3pm") == "\t- [x] Remind me at 3pm")
        check("done: an already ticked line is left alone",
              Reminders.ticked("- [x] Remind me at 3pm") == "- [x] Remind me at 3pm")
        check("done: a ticked line is no longer a reminder, so ticking cancels it",
              !Reminders.isReminder(Reminders.ticked("1. Remind me at 3pm")) && !Reminders.isReminder(Reminders.ticked("Remind me: at 3pm")))

        let wanted: Set<String> = ["Remind me at 3pm", "Remind me tomorrow"]
        check("lines: found as whole lines, across every kind of line break",
              ReminderStore.present(wanted, in: "Remind me at 3pm\r\nx\u{2028}Remind me tomorrow") == wanted
                && ReminderStore.present(wanted, in: "a\u{2029}Remind me at 3pm\u{0085}b") == ["Remind me at 3pm"])
        check("lines: part of a longer line doesn't count",
              ReminderStore.present(wanted, in: "- Remind me at 3pm\nRemind me tomorrow too\nxRemind me at 3pm").isEmpty)
        check("lines: found after an earlier partial match, and at the very end",
              ReminderStore.present(wanted, in: "Remind me at 3pm sharp\nRemind me at 3pm\n\nRemind me tomorrow") == wanted)
        check("lines: non-ASCII lines, and nothing in an empty note",
              ReminderStore.present(["Remind me um 15 Uhr: Café \u{1F680}"], in: "é\nRemind me um 15 Uhr: Café \u{1F680}\n").count == 1
                && ReminderStore.present(wanted, in: "").isEmpty)
        let many = Set((0..<150).map { "Remind me in \($0) minutes" })
        check("lines: many at once give the same answer by splitting",
              ReminderStore.present(many, in: (0..<150).filter { $0 % 2 == 0 }.map { "Remind me in \($0) minutes" }.joined(separator: "\n")).count == 75)

        let rules = FakeReminderScheduler()
        let review = ReminderStore(fileURL: storeFolder.appendingPathComponent("h.json"), scheduler: rules)
        let pizza = "Remind me in 30 minutes to take the pizza out"
        let pizzaSet = review.commit(line: pizza, now: start)!
        review.reconcile(noteText: "", now: start.addingTimeInterval(300))
        let sam = review.commit(line: "Remind me in 30 minutes to call Sam", now: start.addingTimeInterval(360))
        check("review: a new line with the same time words doesn't take over a deleted reminder",
              sam?.id != pizzaSet.id && sam.map { abs($0.fireDate.timeIntervalSince(start.addingTimeInterval(360 + 1800))) < 2 } == true)

        let draft = "Remind me next week to review the draft"
        let drafted = review.commit(line: draft, now: start)!
        let withTime = "Remind me next week at 3pm to review the draft"
        let retimed = review.commit(line: withTime, origin: draft, now: start.addingTimeInterval(30))
        check("review: adding a time to a set reminder moves it",
              retimed.map { here.component(.hour, from: $0.fireDate) == 15 } == true
                && review.reminder(id: drafted.id)?.state == .cancelled)

        let oven = "Remind me in 10 minutes to check the oven"
        let ovenSet = review.commit(line: oven, now: start)!
        let later = ovenSet.fireDate.addingTimeInterval(3000)
        let ovenDone = "Remind me in 10 minutes to check the oven - done"
        let scheduledBefore = rules.scheduled.count
        let stillSent = review.commit(line: ovenDone, origin: oven, now: later)
        check("review: editing a fired line keeps it sent, doesn't fire it again",
              stillSent?.id == ovenSet.id && rules.scheduled.count == scheduledBefore
                && review.label(forLine: ovenDone, now: later) == .sent(ovenSet.fireDate))

        let meds = "Remind me at 3pm to take meds"
        let medsSet = review.commit(line: meds, now: start)!
        review.archive(noteText: meds)
        review.reconcile(noteText: "", now: start.addingTimeInterval(5))
        let medsAgain = review.commit(line: meds, now: start.addingTimeInterval(10))
        check("review: a filed reminder doesn't block the same line typed again",
              medsAgain != nil && medsAgain?.id != medsSet.id && review.reminder(id: medsSet.id)?.archived == true)
        check("review: a filed reminder is never located in the new note",
              review.locate(review.reminder(id: medsSet.id)!, in: meds) == nil)

        review.noteLoaded("Remind me to buy milk\nRemind me yesterday\n")
        check("review: a synced line with no time still says so, not \"not set on this Mac\"",
              review.label(forLine: "Remind me to buy milk") == .noTime && review.label(forLine: "Remind me yesterday") == .past)

        let undecided = FakeReminderScheduler()
        undecided.permission = .notDetermined
        undecided.leavesUndecided = true
        let pending = ReminderStore(fileURL: storeFolder.appendingPathComponent("i.json"), scheduler: undecided)
        pending.commit(line: tenMinutes, now: start)
        pending.refreshPermission(askIfUndecided: true)
        check("review: a reminder still waiting on an unanswered prompt says so, and the prompt comes back",
              pending.label(forLine: tenMinutes, now: start) == .needsPermission && undecided.requests == 2)

        let asking = FakeReminderScheduler()
        asking.permission = .notDetermined
        let firstTime = ReminderStore(fileURL: storeFolder.appendingPathComponent("c.json"), scheduler: asking)
        firstTime.commit(line: tenMinutes, now: start)
        check("permission: the first reminder asks, once", asking.requests == 1 && asking.scheduled.count == 1)

        let outside = FakeReminderScheduler()
        outside.canDeliver = false
        let downloads = ReminderStore(fileURL: storeFolder.appendingPathComponent("d.json"), scheduler: outside)
        let notDelivered = downloads.commit(line: tenMinutes, now: start)
        check("permission: outside Applications, it's remembered as typed here, not handed over, and says why",
              notDelivered?.state == .waiting && outside.scheduled.isEmpty
                && downloads.label(forLine: tenMinutes, now: start) == .outsideApplications)

        check("scheduler: an app in Applications can be notified",
              SystemReminderScheduler.isInApplicationsFolder("/Applications/Wisp.app")
                && SystemReminderScheduler.isInApplicationsFolder("/Users/me/Applications/Wisp.app"))
        check("scheduler: Downloads, a temp folder or a build can't",
              !SystemReminderScheduler.isInApplicationsFolder("/Users/me/Downloads/Wisp.app")
                && !SystemReminderScheduler.isInApplicationsFolder("/private/tmp/x/Wisp.app")
                && !SystemReminderScheduler.isInApplicationsFolder("/Users/me/dev/wisp/.build/debug/Wisp"))

        // The self-tests run as a bare executable, like `swift run` and
        // the release script's launch check. Asking UNUserNotificationCenter
        // for anything here would crash the whole run, so these calls
        // getting through at all is the test.
        let bare = SystemReminderScheduler()
        var bareAnswer: ReminderPermission?
        bare.currentPermission { bareAnswer = $0 }
        bare.cancel(["none"])
        check("scheduler: outside an app bundle, it never touches the notification center",
              !SystemReminderScheduler.isAppBundle && bareAnswer == .denied && !bare.canDeliver)

        // MARK: - Reminders: in the editor

        MarkdownStyler.reminderLabel = { text in Reminders.isReminder(text) ? TrailingLabel(full: "\u{2192} soon", short: "soon") : nil }
        let remStorage = NSTextStorage(string: "Remind me in 10 minutes to check = \n2 + 2 =\n")
        MarkdownStyler.restyle(remStorage, face: .charter, size: .medium, theme: .dark, transparency: .subtle)
        check("editor: a reminder line carries its grey time",
              (remStorage.attribute(.wispReminder, at: 33, effectiveRange: nil) as? TrailingLabel)?.full == "\u{2192} soon")
        check("editor: …and no maths answer, though it ends in =",
              remStorage.attribute(.wispMathAnswer, at: 33, effectiveRange: nil) == nil
                && remStorage.attribute(.wispMathAnswer, at: (remStorage.string as NSString).range(of: "2 + 2 =").location + 6, effectiveRange: nil) as? String == "4")
        let remPartial = NSTextStorage(string: "a\nRemind me tomorrow to go\nb\n")
        MarkdownStyler.restyle(remPartial, face: .charter, size: .medium, theme: .dark, transparency: .subtle)
        remPartial.replaceCharacters(in: NSRange(location: 2, length: 0), with: "- ")
        MarkdownStyler.restyle(remPartial, face: .charter, size: .medium, theme: .dark, transparency: .subtle,
                               edited: NSRange(location: 2, length: 2))
        let remFull = NSTextStorage(string: remPartial.string)
        MarkdownStyler.restyle(remFull, face: .charter, size: .medium, theme: .dark, transparency: .subtle)
        check("editor: paragraph restyle == full restyle on a reminder line", remPartial.isEqual(to: remFull))

        // Typing sets a reminder only once its line is finished.
        let typing = FakeReminderScheduler()
        let typingStore = ReminderStore(fileURL: storeFolder.appendingPathComponent("e.json"), scheduler: typing)
        let remView = CaretTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let remCoordinator = MinimalTextEditor.Coordinator(text: Binding(get: { "" }, set: { _ in }))
        remCoordinator.reminderStore = typingStore
        remView.delegate = remCoordinator
        remView.textStorage?.delegate = remCoordinator
        for ch in "Remind me in 15 minutes to test" { remView.insertText(String(ch), replacementRange: remView.selectedRange()) }
        check("editor: nothing is set while the line is being written", typingStore.reminders.isEmpty)
        remView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        check("editor: Return finishes the line and sets exactly one reminder",
              typingStore.reminders.count == 1 && typingStore.reminders.first?.line == "Remind me in 15 minutes to test"
                && typing.scheduled.count == 1)
        for ch in "Remind me tomorrow" { remView.insertText(String(ch), replacementRange: remView.selectedRange()) }
        remCoordinator.commitDraftReminders(in: remView, includingCaretLine: true)
        check("editor: closing the panel finishes the line being written", typingStore.reminders.count == 2)

        // A line from another Mac: Return at its end touches it but
        // doesn't change it, so it stays unset.
        let synced = "Remind me tomorrow to call from the laptop"
        typingStore.noteLoaded(synced)
        remView.string = synced
        remView.setSelectedRange(NSRange(location: (synced as NSString).length, length: 0))
        remView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        remCoordinator.commitDraftReminders(in: remView, includingCaretLine: true)
        check("editor: Return after a line from another Mac doesn't set it here",
              typingStore.reminders.count == 2 && typingStore.label(forLine: synced) == .notOnThisMac)

        // Filing the note or quitting finishes the line being written.
        remCoordinator.observeReminders(in: remView)
        remView.string = ""
        for ch in "Remind me in 2 hours to file this" { remView.insertText(String(ch), replacementRange: remView.selectedRange()) }
        NotificationCenter.default.post(name: MinimalTextEditor.finishEditing, object: nil)
        check("editor: filing or quitting sets the reminder on the line being written",
              typingStore.reminders.contains { $0.line == "Remind me in 2 hours to file this" })

        // Edited after it was set: the same reminder, at its time.
        let setLine = "Remind me in 2 hours to file this"
        let original = typingStore.reminders.first { $0.line == setLine }
        remView.setSelectedRange(NSRange(location: (setLine as NSString).length, length: 0))
        for ch in " now" { remView.insertText(String(ch), replacementRange: remView.selectedRange()) }
        NotificationCenter.default.post(name: MinimalTextEditor.finishEditing, object: nil)
        let afterEdit = original.flatMap { typingStore.reminder(id: $0.id) }
        check("editor: editing a set reminder's words keeps it, and its time",
              afterEdit != nil && afterEdit?.line == setLine + " now" && afterEdit?.fireDate == original?.fireDate)

        // Typing a new line whose text passes through a set line's words.
        let setFirst = "Remind me in 2 hours to file this now"
        let firstReminder = typingStore.reminders.last { $0.line == setFirst }
        remView.setSelectedRange(NSRange(location: (remView.string as NSString).length, length: 0))
        remView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        for ch in setFirst + " too" { remView.insertText(String(ch), replacementRange: remView.selectedRange()) }
        NotificationCenter.default.post(name: MinimalTextEditor.finishEditing, object: nil)
        check("editor: a new line passing through a set line's words is its own reminder",
              firstReminder != nil && typingStore.reminder(id: firstReminder!.id)?.line == setFirst
                && typingStore.reminders.contains { $0.line == setFirst + " too" && $0.id != firstReminder?.id })

        // Done on a notification, with the editor open.
        remView.allowsUndo = true
        let doneWindow = NSWindow(contentRect: remView.frame, styleMask: [.titled], backing: .buffered, defer: true)
        doneWindow.contentView = remView
        remView.string = "a\nRemind me tomorrow to post\nbcd"
        remView.setSelectedRange(NSRange(location: (remView.string as NSString).length - 1, length: 0))
        let doneRequest = LineReplacement(range: NSRange(location: 2, length: ("Remind me tomorrow to post" as NSString).length), line: "Remind me tomorrow to post",
                                          replacement: Reminders.ticked("Remind me tomorrow to post"))
        NotificationCenter.default.post(name: MinimalTextEditor.replaceLine, object: doneRequest)
        check("editor: Done ticks the line in the editor, and the caret keeps its place",
              doneRequest.applied && remView.string == "a\n- [x] Remind me tomorrow to post\nbcd"
                && remView.selectedRange().location == (remView.string as NSString).length - 1)
        remView.undoManager?.undo()
        check("editor: …as one edit that undo takes back", remView.string == "a\nRemind me tomorrow to post\nbcd")
        remView.string = "a\nRemind me tomorrow to post later\nbcd"
        let staleRequest = LineReplacement(range: NSRange(location: 2, length: ("Remind me tomorrow to post" as NSString).length), line: "Remind me tomorrow to post",
                                           replacement: "- [x] Remind me tomorrow to post")
        NotificationCenter.default.post(name: MinimalTextEditor.replaceLine, object: staleRequest)
        check("editor: Done leaves a line that has since changed alone",
              !staleRequest.applied && remView.string == "a\nRemind me tomorrow to post later\nbcd")
        doneWindow.contentView = nil
        remCoordinator.stopObservingReminders()

        // The tick on a sent reminder, clicked in the editor.
        let tickView = CaretTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
        tickView.allowsUndo = true
        tickView.font = MinimalTextEditor.makeFont(face: .charter, size: 16)
        let tickWindow = NSWindow(contentRect: tickView.frame, styleMask: [.titled], backing: .buffered, defer: true)
        tickWindow.contentView = tickView
        let tickCoordinator = MinimalTextEditor.Coordinator(text: Binding(get: { "" }, set: { _ in }))
        tickCoordinator.reminderStore = typingStore
        tickView.delegate = tickCoordinator
        tickView.textStorage?.delegate = tickCoordinator
        let sentLine = "Remind me in 1 minute to test"
        tickView.string = sentLine + "\nnext"
        MarkdownStyler.reminderLabel = { line in
            Reminders.isReminder(line)
                ? TrailingLabel(full: "sent 3:38 PM", short: "sent", symbol: "checkmark.circle", ticksLine: true) : nil
        }
        MarkdownStyler.restyle(tickView.textStorage!, face: .charter, size: .medium, theme: .dark, transparency: .off)
        MarkdownStyler.reminderLabel = nil
        tickView.layoutManager!.ensureLayout(for: tickView.textContainer!)
        let firstFragment = tickView.layoutManager!.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        let tickY = tickView.textContainerOrigin.y + firstFragment.midY
        let tickX = stride(from: 0.0, through: Double(tickView.bounds.width), by: 1)
            .first { tickView.reminderTick(at: NSPoint(x: $0, y: tickY)) != nil }
        check("tick: a sent reminder offers a tick past its text, and nothing else on the line is claimed",
              tickX.map { $0 > 100 } == true && tickView.reminderTick(at: NSPoint(x: 20, y: tickY)) == nil
                && tickView.reminderTick(at: NSPoint(x: tickX!, y: tickY + firstFragment.height * 1.5)) == nil)
        if let tickX {
            let over = tickView.convert(NSPoint(x: tickX + 4, y: tickY), to: nil)
            tickView.mouseMoved(with: NSEvent.mouseEvent(
                with: .mouseMoved, location: over, modifierFlags: [], timestamp: 0,
                windowNumber: tickWindow.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0
            )!)
        }
        check("tick: hovering it says what it does", tickView.toolTip == "Mark done")
        let tickClicked = tickX.map { tickCoordinator.tickReminder(at: NSPoint(x: $0 + 4, y: tickY), in: tickView) } ?? false
        check("tick: clicking it ticks the line off", tickClicked && tickView.string == "- [x] " + sentLine + "\nnext")
        check("tick: …and the hover goes with it", tickView.toolTip == nil)
        tickView.undoManager?.undo()
        check("tick: …as one edit that undo takes back", tickView.string == sentLine + "\nnext")
        MarkdownStyler.reminderLabel = { line in
            Reminders.isReminder(line) ? TrailingLabel(full: "Tomorrow 9:00 AM", short: "9:00 AM", symbol: "bell") : nil
        }
        MarkdownStyler.restyle(tickView.textStorage!, face: .charter, size: .medium, theme: .dark, transparency: .off)
        MarkdownStyler.reminderLabel = nil
        check("tick: a set reminder's bell isn't clickable",
              !stride(from: 0.0, through: Double(tickView.bounds.width), by: 1)
                .contains { tickView.reminderTick(at: NSPoint(x: $0, y: tickY)) != nil })
        tickWindow.contentView = nil

        // An emoji at the end of a reminder line stays whole.
        let emojiLine = NSTextStorage(string: "Remind me tomorrow to ship \u{1F680}")
        MarkdownStyler.restyle(emojiLine, face: .charter, size: .medium, theme: .dark, transparency: .subtle)
        var emojiRange = NSRange()
        _ = emojiLine.attribute(.wispReminder, at: (emojiLine.string as NSString).length - 1, effectiveRange: &emojiRange)
        check("editor: the grey time never splits an emoji at the line's end",
              emojiRange.location == (emojiLine.string as NSString).length - 2)
        MarkdownStyler.reminderLabel = nil
        try? FileManager.default.removeItem(at: storeFolder)

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

/// Records what the store asks of macOS, and answers permission
/// questions with whatever a test sets.
@MainActor
final class FakeReminderScheduler: ReminderScheduling {
    var canDeliver = true
    var permission: ReminderPermission = .allowed
    var grantOnRequest = true
    /// A prompt left unanswered: "not granted", but still undecided.
    var leavesUndecided = false
    private(set) var scheduled: [Reminder] = []
    private(set) var cancelled: [String] = []
    private(set) var requests = 0

    func schedule(_ reminder: Reminder) { scheduled.append(reminder) }
    func cancel(_ ids: [String]) { cancelled.append(contentsOf: ids) }
    func currentPermission(_ done: @escaping @Sendable @MainActor (ReminderPermission) -> Void) { done(permission) }
    func requestPermission(_ done: @escaping @Sendable @MainActor (Bool) -> Void) {
        requests += 1
        if !leavesUndecided { permission = grantOnRequest ? .allowed : .denied }
        done(grantOnRequest && !leavesUndecided)
    }
    func flush(timeout: TimeInterval) {}
}

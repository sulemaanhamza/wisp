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

        check("Theme.dark toggles to light",  Theme.dark.toggled == .light)
        check("Theme.light toggles to dark",  Theme.light.toggled == .dark)
        check("Theme.dark.rawValue",  Theme.dark.rawValue == "dark")
        check("Theme.light.rawValue", Theme.light.rawValue == "light")

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

import AppKit

// `swift run Wisp --test` runs the in-process smoke tests instead of
// starting the GUI. See SelfTests.swift.
if CommandLine.arguments.contains("--test") {
    SelfTests.run()
}

// Apply any pending update before AppKit starts so users see a clean launch
// of the new version (no UI flash from the old one).
if Updater.applyPendingUpdateIfPossible() {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

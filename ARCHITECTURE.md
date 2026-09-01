# Architecture

Wisp is a menu-bar app: a borderless `NSPanel` hosting a SwiftUI view,
which wraps a custom `NSTextView`. About 4,500 lines of Swift, no
dependencies, no Xcode project.

## Shape of it

- **Swift 6**, SwiftPM **executable** target, macOS 13+. It builds with
  bare Command Line Tools, and that constraint drives several decisions
  below.
- **AppKit + SwiftUI hybrid.** AppKit owns the window, the menu bar and
  the text view; SwiftUI draws everything inside the panel.
- **Carbon `RegisterEventHotKey`** for the global shortcut. The modern
  alternative, `NSEvent.addGlobalMonitorForEvents`, needs Accessibility
  permission. Carbon doesn't, so Wisp asks for nothing on first launch.
- **One file on disk**, plain markdown. No database, no index, no
  document model.

## The files

| File | What it does |
| --- | --- |
| `main.swift` | Entry point. `--test` runs the self-tests; otherwise applies any pending update, then starts an `.accessory` app. |
| `AppDelegate.swift` | Wires the model, updater, hotkey, menu bar and panel together. Owns the storage-folder picker and the launch-source gating. |
| `PanelController.swift` | The panel and its layers: outer → inner (rounded clip) → `NSVisualEffectView` → tint → `NSHostingView`. Every dismissal goes through `dismiss()`. |
| `FloatingPanel.swift` | `NSPanel` subclass that can take focus while borderless, and hands Esc back to the controller. |
| `EditorView.swift` | `EditorModel` (the app's state and the only code that writes the scratchpad) plus the SwiftUI root. |
| `MinimalTextEditor.swift` | `NSViewRepresentable` around `NSTextView`. All the styling passes live here. |
| `HorizontalRuleLayoutManager.swift` | Draws `---` lines as a full-width rule that tracks the panel's width. |
| `Snapshots.swift` | Local version history. |
| `StorageLocation.swift` | Where `scratchpad.md` lives, and moving it. |
| `Inbox.swift`, `Checkbox.swift`, `SmartEditing.swift`, `Headings.swift`, `TextSearch.swift`, `MarkdownWrap.swift`, `EmojiReplace.swift`, `ReleaseNotes.swift`, `Tips.swift`, `LaunchSource.swift`, `PanelFrameStore.swift` | Pure logic, no AppKit state. This is what the self-tests cover. |
| `Updater.swift` | GitHub Releases → background download → bundle swap on next launch. |
| `SelfTests.swift` | The suite. |

## Rules worth knowing

**One writer.** `EditorModel.saveNow()` is the only path that writes
`scratchpad.md`. It records the resulting modification time, which is how
Wisp tells its own saves apart from a change synced in from another Mac.
Skipping that is what once made the app revert your last keystrokes.

**Text is plain; formatting is attributes.** Headings, bold, italic,
code, checkboxes and rules are `NSTextStorage` attributes applied over
the raw markdown. The characters stay visible and the file stays
portable. `MinimalTextEditor.restyle` is the single entry point; call it
after any programmatic change to the text, because assigning
`textView.string` drops every attribute.

**Pure logic gets its own type.** If a rule can be written without
AppKit, it should be, so the self-tests can pin it.

**Discovery is a list, not a release note.** `Tips.all` is the set of
things a person would never guess Wisp can do. Append to it with the
release that introduced the feature; the dot on the `?`, the "New"
group in the help overlay and the stored marker all follow from that.
There is no constant to remember to bump.

## Incidents (don't re-debug these)

1. **The corner-bleed marathon, v0.1.0–v0.1.23.** A dark L-shape leaked
   into the panel's rounded corners in the light theme. Nine releases of
   geometric guesses. The cause was a custom shadow drawn on the outer
   layer, leaking into the gap between the rectangular window bounds and
   the rounded content. The fix was to delete all custom shadow code and
   set `panel.hasShadow = true`, so the system shadow follows the
   rendered alpha mask. *Lesson: when chasing a geometric mystery, paint
   everything visible a garish colour before guessing again.*
2. **A `CAShapeLayer` mask broke resizing** — its path was a fixed size
   and didn't grow with the window, which hid the bottom bar. Use
   `cornerRadius` + `masksToBounds`; they adapt for free.
3. **`panel.backgroundColor = .clear` rendered dark.**
   `NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0)` renders actually
   transparent. Calibrated colour space.
4. **The About panel opened behind Wisp.** The panel is `.floating`; the
   standard About panel is `.normal`. Wisp dismisses itself first.
5. **The pointer cursor wouldn't stick over buttons.** `NSTextView`
   reasserts its I-beam on every mouse move. `pointerCursor()` uses
   `onContinuousHover` to re-assert on each move.
6. **`NSImage.lockFocus()` fails in headless scripts** — the icon
   generator uses CGContext, CoreText and ImageIO directly.
7. **`--arch arm64 --arch x86_64` needs Xcode's xcbuild.** The universal
   build is two `--triple` builds plus `lipo`, which works with Command
   Line Tools.

## Releasing

`./scripts/release.sh <version> [notes-file]` runs the self-tests
(refusing to continue if any fail), builds the universal bundle, zips it,
tags, creates the GitHub release, uploads the zip, and bumps the Homebrew
cask.

Release notes start with a few one-line bullets, then a `<!--wisp:more-->`
marker, then the longer prose. The app shows only the bullets above the
marker in its update card; the marker is an HTML comment, so readers on
GitHub see the whole thing.

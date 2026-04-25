# Wisp

A dead-simple macOS scratchpad. Lives in your menu bar, opens with one click, gives you a clean surface to dump a thought, and gets out of the way.

Not a notes app. Not a todo app. Just a place for the thing you need to write down *right now*, before it's gone.

## Install

Grab the latest `Wisp-X.Y.Z.zip` from [Releases](https://github.com/sulemaanhamza/wisp/releases), unzip, and drag `Wisp.app` to `/Applications`.

Wisp is unsigned (no Apple Developer account), so the first launch needs one of:

- Right-click `Wisp.app` → **Open** → confirm in the dialog, **or**
- `xattr -d com.apple.quarantine /Applications/Wisp.app`

After that it opens normally.

## Usage

Click the pencil icon in the menu bar to summon the panel. Type. Press **Esc** to dismiss — the panel disappears, your text stays for next time.

### Keyboard shortcuts

| Action               | Shortcut         |
| -------------------- | ---------------- |
| Smaller text         | ⌘1               |
| Default text         | ⌘2               |
| Larger text          | ⌘3               |
| Cut / Copy / Paste   | ⌘X / ⌘C / ⌘V    |
| Select All           | ⌘A               |
| Undo / Redo          | ⌘Z / ⇧⌘Z         |
| Quit Wisp            | ⌘Q               |
| Dismiss panel        | Esc              |

### Smart editing

- **Lists auto-continue.** Start a line with `- `, `* `, `+ `, `1. `, `A. `, or `a. ` and press Enter — the next marker appears on the new line. Pressing Enter on an empty list item exits the list.
- **Horizontal rule.** Type `---` on its own line and press Enter to get a clean divider.

## Why

Existing notes apps (Obsidian, Notion, Bear, even Apple Notes) all ask you to think about *where* a note belongs before you can start writing. That friction kills fleeting thoughts. Wisp removes the choice — open, type, close.

## Design principles

- **One click to open, Esc to dismiss.**
- **Empty by default.** The window is a blank surface, not a dashboard.
- **Invisible chrome.** No toolbars, no menus — just a tiny word count and dismiss hint at the bottom.
- **Minimal resources.** Native Swift / AppKit, sleeps when hidden.

## Build from source

Requires macOS 13+ and Swift 6.0+ (full Xcode not required — Command Line Tools is enough).

```bash
git clone https://github.com/sulemaanhamza/wisp.git
cd wisp
./scripts/build-app.sh 0.1.0
open build/Wisp.app
```

Or run directly without bundling:

```bash
swift run
```

## Status

Early but usable. Roadmap:

- Global hotkey to summon (currently menu bar click only)
- Persistence (text resets when the app quits)
- Optional auto-save to a markdown file

## License

MIT — see [LICENSE](LICENSE).

# Wisp

A dead-simple macOS scratchpad. Lives in your menu bar, opens with one keypress, gives you a clean surface to dump a thought, and gets out of the way.

Not a notes app. Not a todo app. Just a place for the thing you need to write down *right now*, before it's gone.

## Why

Existing notes apps (Obsidian, Notion, Bear, even Apple Notes) all ask you to think about *where* a note belongs before you can start writing. That friction kills fleeting thoughts. Wisp removes the choice — open, type, close. Everything auto-saves to a single rolling file you can search later if you need to, but the UI never makes you organise anything.

## Design principles

- **One keypress to open, one to dismiss.** No clicks if you don't want them.
- **Empty by default.** The window is a blank surface, not a dashboard.
- **Invisible chrome.** No toolbars, no menus, no buttons in your face.
- **Minimal resources.** Native Swift/AppKit, sleeps when hidden, ~20MB RAM idle.
- **Your text is yours.** Plain markdown files on disk, not a proprietary database.

## Status

Early development. See commits for progress.

## Requirements

- macOS 13 (Ventura) or later
- Swift 6.0+ to build

## Build & run

```bash
swift run
```

The app will appear in your menu bar.

## License

MIT — see [LICENSE](LICENSE).

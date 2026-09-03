# Changelog

Notable changes to Wisp. Newest first.

## Unreleased

### Fixed

- **A panel kept on an external monitor was dragged back to the laptop screen on every launch.** 0.1.43 started keeping the restored window inside the screen, but it used the main screen rather than the one the panel was actually on. It now restores to the screen it was saved on.

### Changed

- The release script refuses release notes the in-app update card can't render safely, removes the built app bundle after uploading so it can't be mistaken for the installed one, and measures the panel's size after launch. Three guards for the three things that went wrong in 0.1.42.

## 0.1.43 — 2026-09-01

### Fixed

- **The panel could open far taller than the screen.** Whatever was drawn inside the window was allowed to push the window bigger, and the enlarged size was then saved — so it came back on every launch, and resizing it by hand didn't stick. This had been happening quietly since long before this release: the panel was being forced to about 1164 points tall no matter what. A release with longer notes made it dramatic rather than merely wrong, growing the window to several times the height of the screen.

  Three changes: the content can no longer size the window at all; any window is now kept within the screen it's on, both when saved and when restored, so a bad size can't survive a restart; and the help overlay scrolls instead of demanding room the panel may not have.

## 0.1.42 — 2026-09-01

### Fixed

- **Dismissing and re-summoning could lose your last keystrokes.** Wisp saves 800 ms after you stop typing. If you dismissed the panel and brought it back inside that window, it reloaded the previous save from disk and the newest words went with it. Dismissing now finishes the save first, and Wisp keeps track of the files it writes itself so it can tell its own saves apart from a change synced in from another Mac.
- **Version history missed the case it was built for.** A snapshot of the old text is now taken whenever the note collapses to a fraction of its former size — including when you keep typing straight afterwards, and when you quit. Snapshots are written one at a time with millisecond-stamped names, so two taken in the same instant can't overwrite each other.
- **Version history moved out of the sync folder.** It lives in `~/Library/Application Support/Wisp/History` regardless of where your scratchpad is kept. A backup that syncs through the same service it protects you from isn't a backup.
- **Failed saves are no longer silent.** If Wisp can't write to its folder — ejected drive, a permission change — the footer says "couldn't save" instead of letting you type into nothing. Your text stays in the editor and the next change retries.
- **Return works again while the find bar is open.** The bar used to swallow Return everywhere; clicking back into your note and pressing it did nothing. ⌘B and ⌘I no longer wrap the *search query* in asterisks either.
- **A second Mac won't overwrite a note iCloud hasn't downloaded yet.** Wisp recognises iCloud's placeholder files, asks for the download, and declines to adopt the folder until the real file has landed.
- **Shortcuts you'd regret are refused.** Shift on its own no longer counts as a modifier (⇧A would have fired on every capital A you typed anywhere), and ⌘C, ⌘Q, ⌘Space and friends can't be bound.
- **A failed update explains itself.** If Wisp can't replace its own bundle it now says so and links to the download, instead of quietly offering the same update on every open. Downloads are checked against the SHA-256 GitHub publishes before anything is unpacked.
- Notes reloaded from disk keep their formatting — no more literal `---` and flat headings until the next keystroke.
- Running from source no longer shows an update card, and typing a shortcode like `:)` inside text such as `(10:)` no longer turns it into an emoji.

### Added

- **Checklists.** `- [ ] milk` continues on Enter, and clicking a box ticks it. Done items dim and strike through. Plain markdown on disk. ([#7](https://github.com/sulemaanhamza/wisp/issues/7))
- **Archive to Inbox (⇧⌘↩).** Files the current note into `Inbox/2026-08-30-142200.md` next to your scratchpad and leaves you a clean pad for the next thought. ([#6](https://github.com/sulemaanhamza/wisp/issues/6))
- **Transparency.** Right-click the menu bar icon → Transparency → Off, Subtle, or Strong, for how much of the desktop shows through the panel. The light theme is translucent now too — it was always opaque before — so if you prefer the solid white panel, set it to Off. ([#1](https://github.com/sulemaanhamza/wisp/issues/1))
- **Intel Macs are supported.** Releases now ship a universal binary. ([#8](https://github.com/sulemaanhamza/wisp/issues/8))
- **A pulsing dot on the `?` when there's something you haven't seen.** Wisp's features are invisible by design — unguessable syntax and shortcuts — so release notes you read once aren't much help. The same quiet beacon as the first-run dot now appears beside the `?` in the footer whenever the tip list has moved on since you last looked, and the help overlay opens with a **New** group at the top. Look once and it's gone. People who updated in also get the older entries they may never have found, like ⌘F.
- Monospace for `inline code` and ``` fenced blocks.
- Reveal in Finder submenu: scratchpad, Inbox, or version history.
- Continuous integration on macOS 14 and 15, and contributor docs — `CONTRIBUTING.md`, `ARCHITECTURE.md`, this changelog.

## 0.1.41 — 2026-06-08

- Find in your notes with ⌘F. Return and Shift-Return step through matches, Esc closes.
- The panel reopens at the size and position you left it, instead of snapping back to the middle.

## 0.1.40 — 2026-06-01

- The caret stays visible when you press Enter at the bottom of a long note. Contributed by [@sessbach](https://github.com/sessbach).

## 0.1.39 — 2026-05-18

- The theme button cycles light → dark → system. On system, Wisp follows macOS and switches live. Fresh installs default to system; existing preferences load unchanged. Contributed by [@sessbach](https://github.com/sessbach).

## 0.1.38 — 2026-05-04

- Horizontal rules stretch to the panel's width and track it as you resize. Stored as `---` so the file stays portable markdown; older box-drawing dividers still render.
- Bigger hit areas for the footer icons.
- The help overlay lists every right-click menu item and what it does.

## 0.1.37 — 2026-05-04

- **Storage Location…** — keep `scratchpad.md` in any folder. Point it at iCloud Drive, Dropbox or Syncthing and the note follows you across Macs. Reset Storage Location copies it back to the default without deleting the synced file.

## 0.1.36 — 2026-05-03

- New versions announce themselves with a card over the editor when you summon Wisp: Update & Restart, or Later. The check is throttled to once a minute.

## 0.1.35 — 2026-05-03

- **Launch at Login** toggle in the right-click menu.
- Launching Wisp from Applications or Spotlight opens the panel instead of only adding the menu bar icon. Login launches stay quiet.

## 0.1.34 — 2026-05-02

- About Wisp no longer opens behind the panel.
- Added the in-process test harness: `swift run Wisp --test`.

## 0.1.33 — 2026-05-02

- Simplified the README.

## 0.1.32 — 2026-04-27

- First-run tour behind a pulsing dot at the top right.
- The pointing-hand cursor is reliable over every button.

## 0.1.31 — 2026-04-27

- **About Wisp** in the right-click menu.

## 0.1.30 — 2026-04-27

- **Set Shortcut…** — rebind the global hotkey. Combos already claimed by macOS are reported inline, and your previous binding is kept.

## 0.1.29 — 2026-04-27

- **Font** submenu: Charter, Iowan Old Style, Hoefler Text, Palatino, Optima, Avenir Next.

## 0.1.28 — 2026-04-27

- The `?` in the footer opens a reference card of every shortcut, editing rule and emoji shortcode.

## 0.1.27 — 2026-04-26

- The pointing-hand cursor on clickable header and footer elements.

## 0.1.0 – 0.1.26 — 2026-04-25 to 2026-04-26

The first releases: the floating panel, ⌥Space to summon, markdown on disk, light and dark themes, smart lists, headings, emoji shortcodes, auto-update, the Homebrew cask, and a long fight with a dark L-shape leaking into the panel's rounded corners — see `ARCHITECTURE.md` for how that one ended.

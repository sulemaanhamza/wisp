# Wisp

A dead-simple macOS scratchpad. ⌥Space to summon, type, Esc to dismiss.

<p align="center">
  <img src="docs/screenshot.png" width="720" alt="Wisp">
</p>

## Install

**Homebrew**

```sh
brew tap sulemaanhamza/wisp
brew install --cask wisp
xattr -d com.apple.quarantine /Applications/Wisp.app
```

**Direct download**

Grab the latest zip from [Releases](https://github.com/sulemaanhamza/wisp/releases), unzip, drag `Wisp.app` to `/Applications`, then:

```sh
xattr -d com.apple.quarantine /Applications/Wisp.app
```

The `xattr` step is needed because Wisp isn't signed with an Apple Developer ID — it tells macOS the app is safe to open.

## Features

- **⌥Space** to summon from anywhere (rebindable)
- **Light / dark** theme toggle
- **Six fonts** to pick from (Charter, Iowan Old Style, Hoefler Text, Palatino, Optima, Avenir Next)
- **Smart editing** — lists auto-continue, `---` becomes a divider, `**bold**` and `*italic*` render inline
- **Headings** — `#`, `##`, `###` render styled with click-to-jump navigation
- **Emoji shortcodes** — `:rocket:` `:fire:` `:heart:` `:check:` and more
- **Bold / Italic** — ⌘B / ⌘I
- **Auto-update** — downloads new versions in the background
- **Plain markdown on disk** at `~/Library/Application Support/Wisp/scratchpad.md`

Click the `?` in the footer for the full keyboard shortcut list.

## Build from source

```sh
git clone https://github.com/sulemaanhamza/wisp.git
cd wisp
swift run
```

## Contributing

Run the test suite before sending a pull request:

```sh
swift run Wisp --test
```

## License

MIT — see [LICENSE](LICENSE).

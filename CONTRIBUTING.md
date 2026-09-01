# Contributing to Wisp

Thanks for being here. Wisp is a small app on purpose, and the bar for
changes reflects that — but bug reports, fixes and well-argued features
are all welcome.

## Build and run

You need macOS 13+ and a Swift toolchain. Xcode is **not** required —
Command Line Tools are enough, and everything here is meant to keep it
that way.

```sh
git clone https://github.com/sulemaanhamza/wisp.git
cd wisp
swift run
```

That launches the app straight from source. It puts its own icon in the
menu bar, so if you also have a released Wisp running you'll see two.

A couple of things behave differently when you run from source rather
than from a built `.app`:

- **Preferences live in a different place.** `swift run` writes under the
  `Wisp` defaults domain; the shipped app writes under
  `com.sulemaanhamza.wisp`. To test a fresh install, clear the right one:
  `defaults delete Wisp` or `defaults delete com.sulemaanhamza.wisp`.
- **Launch at Login does nothing.** `SMAppService` needs a real bundle.
- **The updater stays quiet**, because there's no bundle to replace.

To build the actual app bundle:

```sh
./scripts/build-app.sh 0.1.42     # → build/Wisp.app, universal
```

## Tests

```sh
swift run Wisp --test
```

These are hand-rolled assertions in `Sources/Wisp/SelfTests.swift`, not
XCTest or Swift Testing. Both of those need Xcode-bundled SDKs, which
would mean contributors with only Command Line Tools couldn't run the
suite — so the harness needs nothing but the toolchain. It's plain and it
works.

**Every pull request must keep them passing**, and new pure logic should
come with assertions. `scripts/release.sh` refuses to ship if anything
fails, and CI runs them on macOS 14 and 15 for every push and PR.

Anything that needs a running `NSApplication` — the text view, Carbon
hotkey registration, the panel — is out of scope for the harness. Test
those by hand and say what you did in the PR.

## What gets merged

Wisp is one note, one keypress, no accounts. The hard part of maintaining
it is saying no, so:

- **Fixes**: yes, always. Especially anything that risks someone's text.
- **Features**: the question isn't "is this useful?" — plenty of things
  are. It's "is this worth the UI it costs?" A feature that adds a
  setting, a button and a mode is a much harder sell than one that
  disappears into an existing gesture. Say in the PR what it earns.
- **Not planned**: multiple notes or tabs, a preferences window, sync
  built into the app (point Storage Location at iCloud Drive instead), a
  plugin system. If that's the app you want, fork it — the licence is MIT
  and at least one fork has gone that way already.

## House style

- Comments explain **why**, not what — invariants, surprising
  constraints, the reason a workaround exists. `ARCHITECTURE.md` has the
  incidents worth knowing about before you start moving layers around.
- No backwards-compatibility shims or dead code left behind. Change the
  code.
- Pure logic goes in its own type where it can be tested, away from
  AppKit.
- No emoji in code or UI.

## Reporting a bug

Open an issue with your Wisp version (right-click the menu bar icon →
About Wisp), your macOS version and Mac, and what you did. If it involves
losing text, mention whether your storage folder is synced — that's where
the sharp edges are.

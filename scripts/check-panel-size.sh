#!/usr/bin/env bash
# Launches the debug build against a throwaway folder and measures the
# panel. Fails if it isn't the size we asked for.
#
# This exists because 257 unit tests passed while the app shipped with a
# window that grew to several times the height of the screen. Nothing
# measured the window. Now something does.
#
# Honest scope: the fix for that bug has three independent layers
# (content can't size the window; frames are clamped to the screen; the
# help overlay scrolls), and removing any one of them alone doesn't
# reproduce it. So this is a smoke test that the app launches and holds
# the size it was given — not proof of any single line. If it ever
# fails, something has gone badly wrong; if it passes, the window is at
# least the right size on launch.
#
# Needs a logged-in GUI session; skipped (exit 0) on headless CI.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! swift -e 'import AppKit; exit(NSScreen.main == nil ? 1 : 0)' >/dev/null 2>&1; then
    echo "check-panel-size: no display, skipping"
    exit 0
fi

WANT_W=800; WANT_H=640
BOX="$(mktemp -d)/wisp-size-check"
mkdir -p "$BOX"
# Tall enough that the content's ideal height far exceeds the panel —
# that's the condition under which the old bug grew the window. A
# short note passes even on broken code, which would make this check
# meaningless.
{ printf '# Heading\n\n- [ ] item\n\n```\ncode\n```\n'; for i in $(seq 1 120); do printf 'Line %d of a note long enough to matter.\n' "$i"; done; } > "$BOX/scratchpad.md"

# The debug build uses the bare "Wisp" defaults domain. Save the
# developer's own values and put them back afterwards.
SAVED_FOLDER="$(defaults read Wisp ScratchpadFolder 2>/dev/null || true)"
SAVED_FRAME="$(defaults read Wisp PanelFrame 2>/dev/null || true)"
restore() {
    if [[ -n "$SAVED_FOLDER" ]]; then defaults write Wisp ScratchpadFolder "$SAVED_FOLDER"; else defaults delete Wisp ScratchpadFolder 2>/dev/null || true; fi
    if [[ -n "$SAVED_FRAME"  ]]; then defaults write Wisp PanelFrame -string "$SAVED_FRAME";     else defaults delete Wisp PanelFrame 2>/dev/null || true; fi
    rm -rf "$BOX"
}
trap restore EXIT

defaults write Wisp ScratchpadFolder "$BOX"
defaults write Wisp PanelFrame -string "{{300, 300}, {$WANT_W, $WANT_H}}"

swift build --package-path "$ROOT" >/dev/null
BIN="$(swift build --package-path "$ROOT" --show-bin-path)/Wisp"
"$BIN" >/dev/null 2>&1 &
PID=$!
sleep 5

GOT="$(swift - "$PID" <<'SWIFT'
import CoreGraphics
import Foundation
let pid = Int32(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list {
    guard let owner = w[kCGWindowOwnerPID as String] as? Int32, owner == pid,
          let b = w[kCGWindowBounds as String] as? [String: CGFloat],
          let width = b["Width"], width > 300 else { continue }
    print("\(Int(width)) \(Int(b["Height"]!))")
    exit(0)
}
print("none")
SWIFT
)"
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true

if [[ "$GOT" == "$WANT_W $WANT_H" ]]; then
    echo "check-panel-size: ok (${WANT_W}x${WANT_H})"
else
    echo "check-panel-size: FAIL — asked for ${WANT_W}x${WANT_H}, got ${GOT}" >&2
    exit 1
fi

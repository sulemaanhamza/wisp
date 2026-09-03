#!/usr/bin/env bash
# One-command Wisp release.
#
# Usage:
#   ./scripts/release.sh <version> [notes-file]
#
# Examples:
#   ./scripts/release.sh 0.1.27
#   ./scripts/release.sh 0.1.27 release-notes.md
#
# What it does, in order:
#   1. Run self-tests — refuses to release on any failure
#   2. Build Wisp.app at the given version (via build-app.sh)
#   3. Zip it (build/Wisp-<version>.zip)
#   4. Create + push annotated git tag v<version>
#   5. Create GitHub release with notes (from file or default)
#   6. Upload the zip as a release asset
#   7. Bump the homebrew tap (via bump-tap.sh)
#
# Assumes you're on a clean working tree at the commit you want to ship,
# and you've already pushed those commits to main. If anything fails
# mid-way, partial state may be left behind — re-run after fixing.

set -euo pipefail

VERSION="${1:-}"
NOTES_FILE="${2:-}"

if [[ -z "$VERSION" ]]; then
    echo "Usage: $0 <version> [notes-file]" >&2
    echo "Example: $0 0.1.27 release-notes.md" >&2
    exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="Wisp"
TAG="v$VERSION"
ZIP_NAME="$NAME-$VERSION.zip"
ZIP_PATH="$ROOT/build/$ZIP_NAME"

cd "$ROOT"

# Refuse if the tag already exists locally or remotely.
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "Error: tag $TAG already exists locally" >&2
    exit 1
fi
if git ls-remote --tags origin "refs/tags/$TAG" | grep -q "$TAG"; then
    echo "Error: tag $TAG already exists on origin" >&2
    exit 1
fi

# The changelog is the record of what shipped; a release without an
# entry is a release nobody can look up later.
if ! grep -q "^## $VERSION" CHANGELOG.md; then
    echo "Error: CHANGELOG.md has no '## $VERSION' section." >&2
    echo "Rename the Unreleased heading, or add one, then re-run." >&2
    exit 1
fi

# The in-app update card renders the bullets above <!--wisp:more-->.
# Every 0.1.41 install still lets that card grow the window without
# limit, and six long bullets once took it to 4777pt on a 1440pt
# screen. Two short lines is the envelope that release shipped with
# and survived. Refuse anything bigger — it's not a style preference.
if [[ -n "$NOTES_FILE" ]]; then
    [[ -f "$NOTES_FILE" ]] || { echo "Error: $NOTES_FILE not found" >&2; exit 1; }
    HEAD="$(sed '/<!--wisp:more-->/,$d' "$NOTES_FILE")"
    if ! grep -q '<!--wisp:more-->' "$NOTES_FILE"; then
        echo "Error: $NOTES_FILE has no <!--wisp:more--> marker; the whole body would render in the update card." >&2
        exit 1
    fi
    BULLETS="$(printf '%s\n' "$HEAD" | grep -E '^[-*•] ' || true)"
    COUNT="$(printf '%s\n' "$BULLETS" | grep -c . || true)"
    if (( COUNT > 2 )); then
        echo "Error: $COUNT bullets above the marker; the update card is safe with at most 2." >&2
        exit 1
    fi
    LONGEST="$(printf '%s\n' "$BULLETS" | awk '{ n = length($0) - 2; if (n > m) m = n } END { print m + 0 }')"
    if (( LONGEST > 50 )); then
        echo "Error: a card bullet is $LONGEST characters; keep each under 50." >&2
        exit 1
    fi
fi

echo "==> 1/7 Running self-tests..."
swift run Wisp --test
./scripts/check-panel-size.sh

echo "==> 2/7 Building $NAME $VERSION..."
./scripts/build-app.sh "$VERSION"

echo "==> 3/7 Zipping..."
rm -f "$ZIP_PATH"
(cd "$ROOT/build" && /usr/bin/ditto -c -k --keepParent "$NAME.app" "$ZIP_NAME")

echo "==> 4/7 Tagging and pushing $TAG..."
git tag -a "$TAG" -m "$TAG"
git push origin "$TAG"

echo "==> 5/7 Creating GitHub release..."
if [[ -n "$NOTES_FILE" ]]; then
    [[ -f "$NOTES_FILE" ]] || { echo "Error: $NOTES_FILE not found" >&2; exit 1; }
    gh release create "$TAG" --title "$TAG" --notes-file "$NOTES_FILE"
else
    gh release create "$TAG" --title "$TAG" --notes "Release $TAG. Edit these notes on GitHub for a proper changelog."
fi

echo "==> 6/7 Uploading $ZIP_NAME..."
gh release upload "$TAG" "$ZIP_PATH"

echo "==> 7/7 Bumping homebrew tap..."
./scripts/bump-tap.sh "$VERSION"

# The built bundle shares its identifier with the installed app, so
# LaunchServices may start resolving com.sulemaanhamza.wisp to it —
# and then "open Wisp" launches the build tree, sharing the real
# preferences. Unregister and remove it now that the zip is uploaded.
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREG" -u "$ROOT/build/$NAME.app" >/dev/null 2>&1 || true
rm -rf "$ROOT/build/$NAME.app"

echo ""
echo "Released $VERSION."
echo "  Release: https://github.com/sulemaanhamza/wisp/releases/tag/$TAG"
echo "  Tap:     https://github.com/sulemaanhamza/homebrew-wisp"

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

echo "==> 1/7 Running self-tests..."
swift run Wisp --test

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

echo ""
echo "Released $VERSION."
echo "  Release: https://github.com/sulemaanhamza/wisp/releases/tag/$TAG"
echo "  Tap:     https://github.com/sulemaanhamza/homebrew-wisp"

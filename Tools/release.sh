#!/bin/bash
# Publishes the current version of NotchTunes as a GitHub release, which is
# what Check for Updates looks for.  Usage:
#
#   ./Tools/release.sh "What's new in this version"
#
# Before running it:
#   1. Raise CFBundleShortVersionString in Resources/Info.plist (and
#      CFBundleVersion by one) — the app only offers a version higher than
#      its own.
#   2. Commit and push.
#
# It builds a fresh copy in a temporary folder — the copy you're using is
# left running — zips it as NotchTunes.zip, and attaches that to a release
# tagged v<version>.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
TAG="v$VERSION"
NOTES="${1:-}"

if [ -n "$(git status --porcelain)" ]; then
  echo "error: there are uncommitted changes — commit them first, so the release matches the code." >&2
  exit 1
fi
git fetch -q origin
if [ "$(git rev-parse HEAD)" != "$(git rev-parse '@{u}')" ]; then
  echo "error: this isn't what's on GitHub — push first." >&2
  exit 1
fi
if gh release view "$TAG" >/dev/null 2>&1; then
  echo "error: $TAG is already released. Raise CFBundleShortVersionString in Resources/Info.plist." >&2
  exit 1
fi

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

echo "Building NotchTunes $VERSION..."
INSTALL_DIR="$OUT" RELEASE_BUILD=1 ./build.sh >/dev/null

# ditto keeps the app bundle intact inside the zip, which plain zip doesn't
# always: symlinks and extended attributes.
( cd "$OUT" && /usr/bin/ditto -c -k --keepParent NotchTunes.app NotchTunes.zip )

echo "Publishing $TAG..."
gh release create "$TAG" "$OUT/NotchTunes.zip" \
  --title "NotchTunes $VERSION" \
  --notes "$NOTES" \
  --target "$(git rev-parse HEAD)"

echo "Released $TAG. Check for Updates will now offer it to older copies."

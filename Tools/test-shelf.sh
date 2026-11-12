#!/bin/bash
# Tests the clipboard: what a drop turns into, merging, and clearing. Uses
# made-up drops and its own temporary folder — nothing on screen, and nothing
# the running app has stored is touched.
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp Tools/TestShelf.swift "$STAGE/main.swift"
swiftc -sdk "$SDK" -target arm64-apple-macosx14.0 \
  Sources/Shelf.swift "$STAGE/main.swift" -o "$STAGE/test"
"$STAGE/test" "$STAGE"

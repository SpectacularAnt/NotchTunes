#!/bin/bash
# Runs the hold-to-quit tests. Builds nothing but the detector and the tests —
# no app, no window, nothing that appears on screen.
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp Tools/TestHoldToQuit.swift "$STAGE/main.swift"
swiftc -sdk "$SDK" -target arm64-apple-macosx14.0 \
  Sources/HoldToQuit.swift "$STAGE/main.swift" -o "$STAGE/test"
"$STAGE/test"

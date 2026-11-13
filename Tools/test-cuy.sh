#!/bin/bash
# Tests the cuy: which mood it's in for a given hour and memory use, and that
# the memory reading is sensible. Nothing appears on screen.
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp Tools/TestCuy.swift "$STAGE/main.swift"
SOURCES=$(ls Sources/*.swift | grep -v '/main.swift$')
swiftc -sdk "$SDK" -target arm64-apple-macosx14.0 $SOURCES "$STAGE/main.swift" -o "$STAGE/test"
"$STAGE/test"

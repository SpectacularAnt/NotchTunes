#!/bin/bash
# Tests Check for Updates' version comparison. Nothing is downloaded.
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp Tools/TestUpdater.swift "$STAGE/main.swift"
swiftc -sdk "$SDK" -target arm64-apple-macosx14.0 \
  Sources/Updater.swift Sources/Diagnostics.swift "$STAGE/main.swift" -o "$STAGE/test"
"$STAGE/test"

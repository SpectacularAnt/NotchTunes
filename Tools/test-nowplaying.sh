#!/bin/bash
# Tests matching a song between Music and macOS's Now Playing, used to borrow
# a cover Music won't hand over. Nothing is asked of any app.
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp Tools/TestNowPlaying.swift "$STAGE/main.swift"
# Everything but main.swift and the app's own entry points.
SOURCES=$(ls Sources/*.swift | grep -v '/main.swift$')
swiftc -sdk "$SDK" -target arm64-apple-macosx14.0 $SOURCES "$STAGE/main.swift" -o "$STAGE/test"
"$STAGE/test"

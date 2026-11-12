#!/bin/bash
# Tests Study Mode's readings: the battery, and where the Dock is. Reads only —
# nothing is covered, and nothing appears on screen.
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp Tools/TestStudy.swift "$STAGE/main.swift"
swiftc -sdk "$SDK" -target arm64-apple-macosx14.0 \
  Sources/StudyMode.swift Sources/HoldToQuit.swift Sources/Settings.swift Sources/Diagnostics.swift \
  Sources/NotchGeometry.swift Sources/AudioTap.swift Sources/BandAnalyser.swift "$STAGE/main.swift" -o "$STAGE/test"
"$STAGE/test"

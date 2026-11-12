#!/bin/bash
# Tests the band analyser with made-up tones: does a bass note light the bass
# bar, a high note the treble one, and silence nothing? Pure arithmetic — no
# audio is recorded or played.
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp Tools/TestBands.swift "$STAGE/main.swift"
swiftc -sdk "$SDK" -target arm64-apple-macosx14.0 \
  Sources/BandAnalyser.swift "$STAGE/main.swift" -o "$STAGE/test"
"$STAGE/test"

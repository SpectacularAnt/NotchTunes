#!/bin/bash
# Renders the expanded notch to a PNG so a layout change can be looked at
# without running the app.  Usage: ./Tools/preview-panel.sh [out.png] [hold|settings|study|study-start|permissions|permissions-new|repeat1|airplay|collapsed|shelf|shelf-only|shelf-bar|drop|cuy|cuy-bar|cuy-room|viz-cover|viz-bars]
set -euo pipefail
cd "$(dirname "$0")/.."

SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# Everything except main.swift, whose top-level code would clash with the
# preview's own entry point.
SOURCES=$(ls Sources/*.swift | grep -v '/main.swift$')
cp Tools/PreviewPanel.swift "$STAGE/main.swift"

swiftc -sdk "$SDK" -target arm64-apple-macosx14.0 \
  $SOURCES "$STAGE/main.swift" -o "$STAGE/preview"

OUT="${1:-panel-preview.png}"
MODE="${2:-}"     # optional: hold | settings | study | study-start | permissions | permissions-new | repeat1 | airplay | collapsed | shelf | shelf-only | shelf-bar | drop | cuy | cuy-bar | cuy-room | viz-cover | viz-bars

"$STAGE/preview" "$OUT" "$MODE"

# A second image with the knobs forced on, showing what you get under the
# cursor. Only meaningful for the panel itself.
if [ -z "$MODE" ]; then
  NOTCHTUNES_SHOW_KNOBS=1 "$STAGE/preview" "${OUT%.png}-hover.png"
fi

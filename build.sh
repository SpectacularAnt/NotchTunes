#!/bin/bash
# Builds NotchTunes and installs it into /Applications.  Usage: ./build.sh
#
# The app deliberately does not stay in this folder: it belongs where you'd
# normally look for your apps.  Set INSTALL_DIR to put it somewhere else, e.g.
#   INSTALL_DIR=~/Applications ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

APP="NotchTunes.app"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
DEST="$INSTALL_DIR/$APP"

# The Command Line Tools ship a Swift 6.3 compiler next to a macOS 27 SDK that
# wants 6.4, so those two refuse to work together.  The macOS 26 SDK is the
# newest one this compiler accepts, and it has everything we use.
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
if [ ! -d "$SDK" ]; then
  echo "error: no macOS 26 SDK at $SDK" >&2
  exit 1
fi

# The bundle is assembled and signed in a temporary folder, then copied into
# place with ditto.  This started as a workaround for iCloud Drive, which kept
# attaching file attributes that codesign refuses to sign around; it is still
# the right shape, because it means a failed build never leaves a half-written
# app where the finished one should be.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$STAGE/$APP"

echo "Compiling..."
mkdir -p "$BUNDLE/Contents/MacOS"

swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macosx14.0 \
  -O \
  -o "$BUNDLE/Contents/MacOS/NotchTunes" \
  Sources/*.swift

cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"

# The Now Playing helper, for Podcasts: a small library plus the perl script
# that loads it. See Helper/NowPlayingHelper.m for why it's built this way.
mkdir -p "$BUNDLE/Contents/Resources"
clang -dynamiclib -fobjc-arc -O2 \
  -target arm64-apple-macos14.0 -isysroot "$SDK" \
  -framework Foundation -framework AppKit \
  -o "$BUNDLE/Contents/Resources/NowPlayingHelper.dylib" \
  Helper/NowPlayingHelper.m
cp Helper/NowPlayingHelper.pl "$BUNDLE/Contents/Resources/NowPlayingHelper.pl"

# The icon. Regenerate it with Tools/make-icon.sh if the artwork changes; this
# only copies what that produced.
if [ -f Resources/AppIcon.icns ]; then
  mkdir -p "$BUNDLE/Contents/Resources"
  cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
else
  echo "warning: Resources/AppIcon.icns is missing — run Tools/make-icon.sh" >&2
fi

# An ad-hoc signature is enough for macOS to remember the Automation permission
# between launches.
codesign --force --sign - --identifier local.notchtunes "$BUNDLE"

if [ ! -w "$INSTALL_DIR" ]; then
  echo "error: $INSTALL_DIR is not writable." >&2
  echo "       Try: INSTALL_DIR=~/Applications ./build.sh" >&2
  exit 1
fi

# The copy being replaced can't be running.
if pgrep -x NotchTunes >/dev/null; then
  echo "Quitting the running copy..."
  pkill -x NotchTunes || true
  sleep 0.5
fi

echo "Installing to $DEST..."
rm -rf "$DEST"
ditto --noextattr --norsrc "$BUNDLE" "$DEST"

codesign --verify --deep "$DEST" && echo "signature verifies"

# Tell macOS about the new copy, so Finder and Spotlight don't keep showing the
# old icon or the old path.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true

echo "Installed $DEST"
echo "Open it with:  open -a NotchTunes"

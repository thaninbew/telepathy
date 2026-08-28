#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-debug}"
APP="$ROOT/build/Telepathy.app"

swift build --package-path "$ROOT" -c "$CONFIGURATION"
BIN_PATH="$(swift build --package-path "$ROOT" -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/Telepathy" "$APP/Contents/MacOS/Telepathy"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c \
  "Set :CFBundleIdentifier app.telepathy.macos.development" \
  "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c \
  "Set :CFBundleName Telepathy Development" \
  "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"

echo "$APP"

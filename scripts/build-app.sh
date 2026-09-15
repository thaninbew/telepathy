#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-debug}"
BUILD_ROOT="$ROOT/build"
BUILD_DIR="$BUILD_ROOT/Telepathy Development.noindex"
APP="$BUILD_DIR/Telepathy Development.app"
INDEXED_APP="$BUILD_ROOT/Telepathy Development.app"
LEGACY_APP="$BUILD_ROOT/Telepathy.app"
SIGNING_IDENTITY="${TELEPATHY_CODESIGN_IDENTITY:--}"

mkdir -p "$BUILD_DIR"
touch "$BUILD_DIR/.metadata_never_index"

swift build --package-path "$ROOT" -c "$CONFIGURATION"
BIN_PATH="$(swift build --package-path "$ROOT" -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP" "$INDEXED_APP" "$LEGACY_APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/Telepathy" "$APP/Contents/MacOS/Telepathy"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c \
  "Set :CFBundleIdentifier app.telepathy.macos.development" \
  "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c \
  "Set :CFBundleName Telepathy Development" \
  "$APP/Contents/Info.plist"
codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP"

echo "$APP"

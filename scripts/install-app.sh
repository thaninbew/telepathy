#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/build/Telepathy.app"
DESTINATION="${TELEPATHY_INSTALL_PATH:-$HOME/Applications/Telepathy.app}"
STAGING="${DESTINATION}.installing"

"$ROOT/scripts/build-app.sh" release

osascript -e 'tell application id "app.telepathy.macos" to quit' 2>/dev/null || true
for _ in {1..30}; do
  pgrep -x Telepathy >/dev/null || break
  sleep 0.1
done
if pgrep -x Telepathy >/dev/null; then
  echo "Telepathy did not quit; installation stopped without replacing it." >&2
  exit 1
fi
rm -rf "$STAGING"
mkdir -p "$(dirname "$DESTINATION")"
ditto "$SOURCE" "$STAGING"
cp "$ROOT/Resources/Info.plist" "$STAGING/Contents/Info.plist"
codesign --force --deep --sign - "$STAGING"
codesign --verify --deep --strict "$STAGING"
rm -rf "$DESTINATION"
mv "$STAGING" "$DESTINATION"

open -na "$DESTINATION"
echo "Installed and opened $DESTINATION"

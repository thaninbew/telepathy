#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/build/Telepathy Development.app"
DESTINATION="$HOME/Applications/Telepathy.app"
STAGING="${DESTINATION}.installing"
DEFAULT_SIGNING_IDENTITY="Telepathy Local Development"
SIGNING_IDENTITY="${TELEPATHY_CODESIGN_IDENTITY:-}"
AVAILABLE_IDENTITIES="$(security find-identity -v -p codesigning || true)"

if [[ -z "$SIGNING_IDENTITY" ]] \
  && grep -Fq "\"$DEFAULT_SIGNING_IDENTITY\"" <<< "$AVAILABLE_IDENTITIES"
then
  SIGNING_IDENTITY="$DEFAULT_SIGNING_IDENTITY"
fi

if [[ -z "$SIGNING_IDENTITY" || "$SIGNING_IDENTITY" == "-" ]]; then
  echo "A stable code-signing identity is required for the installed app." >&2
  echo "Run ./scripts/setup-local-signing.sh once, then rerun this installer." >&2
  echo "Telepathy was not rebuilt or replaced, so Accessibility access is unchanged." >&2
  exit 1
fi

"$ROOT/scripts/build-app.sh" release

rm -rf "$STAGING"
mkdir -p "$(dirname "$DESTINATION")"
ditto "$SOURCE" "$STAGING"
cp "$ROOT/Resources/Info.plist" "$STAGING/Contents/Info.plist"
codesign --force --deep --sign "$SIGNING_IDENTITY" "$STAGING"
codesign --verify --deep --strict "$STAGING"

CANONICAL_EXECUTABLE="$DESTINATION/Contents/MacOS/Telepathy"
canonical_pids=()
for pid in $(pgrep -x Telepathy || true); do
  if [[ "$(ps -p "$pid" -o command=)" == "$CANONICAL_EXECUTABLE" ]]; then
    canonical_pids+=("$pid")
  fi
done

if (( ${#canonical_pids[@]} > 0 )); then
  kill "${canonical_pids[@]}"
fi
for _ in {1..30}; do
  still_running=false
  for pid in "${canonical_pids[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      still_running=true
      break
    fi
  done
  $still_running || break
  sleep 0.1
done
for pid in "${canonical_pids[@]}"; do
  if ! kill -0 "$pid" 2>/dev/null; then
    continue
  fi
  echo "Telepathy did not quit; installation stopped without replacing it." >&2
  exit 1
done

rm -rf "$DESTINATION"
mv "$STAGING" "$DESTINATION"

open "$DESTINATION"
for _ in {1..30}; do
  launched_pids="$(pgrep -f "^$CANONICAL_EXECUTABLE$" || true)"
  [[ -n "$launched_pids" ]] && break
  sleep 0.1
done
if [[ -z "${launched_pids:-}" ]]; then
  echo "Telepathy was installed but did not remain running." >&2
  exit 1
fi
if [[ "$(wc -w <<< "$launched_pids" | tr -d ' ')" != "1" ]]; then
  echo "Telepathy launched more than one canonical process." >&2
  exit 1
fi

echo "Installed and opened $DESTINATION"

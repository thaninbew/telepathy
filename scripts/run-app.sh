#!/bin/zsh
set -euo pipefail

APP="${TELEPATHY_APP_PATH:-$HOME/Applications/Telepathy.app}"

if [[ ! -d "$APP" ]]; then
  echo "Telepathy is not installed at $APP" >&2
  echo "Run ./scripts/install-app.sh once, then open Telepathy normally." >&2
  exit 1
fi

open "$APP"

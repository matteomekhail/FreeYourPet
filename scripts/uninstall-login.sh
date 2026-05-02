#!/bin/zsh
set -euo pipefail

PLIST="$HOME/Library/LaunchAgents/pet.freeyour.app.plist"

if [[ -f "$PLIST" ]]; then
  /bin/launchctl unload "$PLIST" >/dev/null 2>&1 || true
  rm "$PLIST"
  echo "Removed login agent: $PLIST"
else
  echo "No login agent found at $PLIST"
fi

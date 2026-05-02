#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_EXECUTABLE="$ROOT_DIR/build/AlwaysPet.app/Contents/MacOS/AlwaysPet"
PLIST="$HOME/Library/LaunchAgents/local.alwayspet.plist"

"$ROOT_DIR/scripts/build.sh"
mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>local.alwayspet</string>
  <key>ProgramArguments</key>
  <array>
    <string>$APP_EXECUTABLE</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>
  <key>StandardOutPath</key>
  <string>$ROOT_DIR/build/alwayspet.log</string>
  <key>StandardErrorPath</key>
  <string>$ROOT_DIR/build/alwayspet.err.log</string>
</dict>
</plist>
PLIST

/bin/launchctl unload "$PLIST" >/dev/null 2>&1 || true
/bin/launchctl load "$PLIST"

echo "Installed login agent: $PLIST"
echo "AlwaysPet will start now and again whenever you log in."

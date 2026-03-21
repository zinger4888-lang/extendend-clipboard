#!/bin/zsh
set -euo pipefail

APP_PATH="/Applications/Extended Clipboard.app"
AGENT_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$AGENT_DIR/com.zinger.extended-clipboard.plist"
LABEL="com.zinger.extended-clipboard"
UID_VALUE="$(id -u)"

if [ ! -d "$APP_PATH" ]; then
  echo "Install the app to /Applications first." >&2
  exit 1
fi

mkdir -p "$AGENT_DIR"

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-gj</string>
    <string>$APP_PATH</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
</dict>
</plist>
EOF

launchctl bootout "gui/$UID_VALUE" "$PLIST_PATH" 2>/dev/null || true
launchctl bootstrap "gui/$UID_VALUE" "$PLIST_PATH"
launchctl kickstart -k "gui/$UID_VALUE/$LABEL"

echo "Autostart enabled:"
echo "$PLIST_PATH"

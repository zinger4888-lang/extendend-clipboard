#!/bin/zsh
set -euo pipefail

PLIST_PATH="$HOME/Library/LaunchAgents/com.zinger.extended-clipboard.plist"
LABEL="com.zinger.extended-clipboard"
UID_VALUE="$(id -u)"

launchctl bootout "gui/$UID_VALUE" "$PLIST_PATH" 2>/dev/null || true
rm -f "$PLIST_PATH"

echo "Autostart disabled:"
echo "$PLIST_PATH"

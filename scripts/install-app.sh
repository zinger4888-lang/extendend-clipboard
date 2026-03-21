#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="$ROOT_DIR/dist/Extended Clipboard.app"
TARGET_DIR="/Applications"
TARGET_APP="$TARGET_DIR/Extended Clipboard.app"

if [ ! -d "$SOURCE_APP" ]; then
  echo "Build the app first with ./scripts/build-app.sh" >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"
rm -rf "$TARGET_APP"
ditto "$SOURCE_APP" "$TARGET_APP"

echo "Installed:"
echo "$TARGET_APP"

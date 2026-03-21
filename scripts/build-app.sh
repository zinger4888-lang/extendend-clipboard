#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_ROOT="$ROOT_DIR/dist/Extended Clipboard.app"
CONTENTS_DIR="$APP_ROOT/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SWIFTPM_HOME="$ROOT_DIR/.swiftpm-local"
CLANG_CACHE_DIR="$SWIFTPM_HOME/clang-module-cache"
SWIFT_MODULE_CACHE_DIR="$SWIFTPM_HOME/swift-module-cache"

mkdir -p "$CLANG_CACHE_DIR" "$SWIFT_MODULE_CACHE_DIR"
export CLANG_MODULE_CACHE_PATH="$CLANG_CACHE_DIR"
export SWIFTPM_MODULECACHE_OVERRIDE="$SWIFT_MODULE_CACHE_DIR"

echo "Building release binary..."
cd "$ROOT_DIR"
swift build -c release --disable-sandbox

echo "Creating app bundle..."
rm -rf "$APP_ROOT"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/App/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$BUILD_DIR/ExtendedClipboard" "$MACOS_DIR/ExtendedClipboard"
chmod +x "$MACOS_DIR/ExtendedClipboard"

if command -v codesign >/dev/null 2>&1; then
  if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    echo "Applying Developer ID signature..."
    codesign --force --deep --options runtime --sign "$CODESIGN_IDENTITY" "$APP_ROOT" >/dev/null
  else
    echo "Applying default ad-hoc code signature..."
    codesign --force --deep --sign - "$APP_ROOT" >/dev/null
  fi
fi

echo "App bundle ready:"
echo "$APP_ROOT"

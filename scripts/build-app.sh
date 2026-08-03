#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$ROOT_DIR/scripts/generate-app-icon.py" "$ROOT_DIR/Resources/AppIcon-1024.png"
"$ROOT_DIR/scripts/build-icon.sh" >/dev/null
swift build --package-path "$ROOT_DIR" -c release --product Tack
swift build --package-path "$ROOT_DIR" -c release --product TackWidgets
BIN_DIR="$(swift build --package-path "$ROOT_DIR" -c release --show-bin-path)"
APP_DIR="$ROOT_DIR/build/Tack.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/PlugIns/TackWidgets.appex/Contents/MacOS"
cp "$BIN_DIR/Tack" "$APP_DIR/Contents/MacOS/Tack"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$BIN_DIR/TackWidgets" "$APP_DIR/Contents/PlugIns/TackWidgets.appex/Contents/MacOS/TackWidgets"
cp "$ROOT_DIR/Resources/TackWidgets-Info.plist" "$APP_DIR/Contents/PlugIns/TackWidgets.appex/Contents/Info.plist"
codesign --force --sign - "$APP_DIR/Contents/PlugIns/TackWidgets.appex" >/dev/null 2>&1 || true
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
echo "$APP_DIR"

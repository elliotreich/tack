#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
BUILD_NUMBER="${TACK_BUILD_NUMBER:-1}"
SIGNING_IDENTITY="${TACK_SIGNING_IDENTITY:--}"

if [[ -z "$VERSION" ]]; then
    echo "VERSION is empty" >&2
    exit 1
fi

python3 "$ROOT_DIR/scripts/generate-app-icon.py" "$ROOT_DIR/Resources/AppIcon-1024.png"
"$ROOT_DIR/scripts/build-icon.sh" >/dev/null
swift build --package-path "$ROOT_DIR" -c release --product Tack
swift build --package-path "$ROOT_DIR" -c release --product TackWidgets
BIN_DIR="$(swift build --package-path "$ROOT_DIR" -c release --show-bin-path)"
APP_DIR="$ROOT_DIR/build/Tack.app"
WIDGET_APP="$APP_DIR/Contents/PlugIns/TackWidgets.appex"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/PlugIns/TackWidgets.appex/Contents/MacOS"
cp "$BIN_DIR/Tack" "$APP_DIR/Contents/MacOS/Tack"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$BIN_DIR/TackWidgets" "$APP_DIR/Contents/PlugIns/TackWidgets.appex/Contents/MacOS/TackWidgets"
cp "$ROOT_DIR/Resources/TackWidgets-Info.plist" "$APP_DIR/Contents/PlugIns/TackWidgets.appex/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP_DIR/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$WIDGET_APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$WIDGET_APP/Contents/Info.plist"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    codesign --force --sign - --entitlements "$ROOT_DIR/Resources/TackWidgets.entitlements" "$WIDGET_APP"
    codesign --force --sign - --entitlements "$ROOT_DIR/Resources/Tack.entitlements" "$APP_DIR"
else
    codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp \
        --entitlements "$ROOT_DIR/Resources/TackWidgets.entitlements" "$WIDGET_APP"
    codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp \
        --entitlements "$ROOT_DIR/Resources/Tack.entitlements" "$APP_DIR"
fi

codesign --verify --deep --strict "$APP_DIR"
echo "$APP_DIR"

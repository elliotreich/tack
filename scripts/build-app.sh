#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
BUILD_NUMBER="${TACK_BUILD_NUMBER:-1}"
SIGNING_IDENTITY="${TACK_SIGNING_IDENTITY:-}"

if [[ -z "$VERSION" ]]; then
    echo "VERSION is empty" >&2
    exit 1
fi

if [[ -z "$SIGNING_IDENTITY" || "$SIGNING_IDENTITY" == "-" ]]; then
    echo "Tack's team-scoped App Group requires a non-ad-hoc signature from Team YAU948K7T5." >&2
    echo "Set TACK_SIGNING_IDENTITY to a valid Apple Development or Developer ID identity for that team." >&2
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

codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp \
    --entitlements "$ROOT_DIR/Resources/TackWidgets.entitlements" "$WIDGET_APP"
codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp \
    --entitlements "$ROOT_DIR/Resources/Tack.entitlements" "$APP_DIR"

codesign --verify --deep --strict "$APP_DIR"
TEAM_ID_WIDGET="$(codesign -dv --verbose=4 "$WIDGET_APP" 2>&1 | sed -n 's/^TeamIdentifier=//p' | head -n 1)"
TEAM_ID_HOST="$(codesign -dv --verbose=4 "$APP_DIR" 2>&1 | sed -n 's/^TeamIdentifier=//p' | head -n 1)"
if [[ "$TEAM_ID_WIDGET" != "YAU948K7T5" || "$TEAM_ID_HOST" != "YAU948K7T5" ]]; then
    echo "Tack and TackWidgets must both be signed by Team YAU948K7T5 (actual IDs: host='${TEAM_ID_HOST:-missing}', widget='${TEAM_ID_WIDGET:-missing}')." >&2
    echo "Set TACK_SIGNING_IDENTITY to an Apple Development or Developer ID identity for Team YAU948K7T5." >&2
    exit 1
fi

ENTITLEMENTS_DIR="$(mktemp -d)"
trap 'rm -rf "$ENTITLEMENTS_DIR"' EXIT
codesign -d --entitlements :- "$APP_DIR" > "$ENTITLEMENTS_DIR/host.plist" 2>/dev/null
codesign -d --entitlements :- "$WIDGET_APP" > "$ENTITLEMENTS_DIR/widget.plist" 2>/dev/null
python3 - "$ENTITLEMENTS_DIR/host.plist" "$ENTITLEMENTS_DIR/widget.plist" <<'PY'
import plistlib
import sys

expected_group = "YAU948K7T5.app.tack"
with open(sys.argv[1], "rb") as host_file, open(sys.argv[2], "rb") as widget_file:
    entitlements = [plistlib.load(host_file), plistlib.load(widget_file)]

if entitlements[1].get("com.apple.security.app-sandbox") is not True:
    raise SystemExit("TackWidgets must be signed with App Sandbox enabled")

for target, target_entitlements in zip(("Tack", "TackWidgets"), entitlements):
    groups = target_entitlements.get("com.apple.security.application-groups", [])
    if expected_group not in groups:
        raise SystemExit(f"{target} must include the {expected_group} shared app group entitlement")
PY
echo "$APP_DIR"

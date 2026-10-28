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
BUILD_TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_TEMP_DIR"' EXIT

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

# SwiftPM compiles the AppIntents declarations, but it doesn't run Xcode's
# App Intents metadata build phase. WidgetKit needs Metadata.appintents in the
# extension bundle to display the note selector in Edit Widget.
DEVELOPER_DIR_FOR_INTENTS="${DEVELOPER_DIR:-$(xcode-select -p)}"
if [[ "$DEVELOPER_DIR_FOR_INTENTS" == *CommandLineTools* ]]; then
    echo "App Intents metadata requires full Xcode; set DEVELOPER_DIR to Xcode.app/Contents/Developer." >&2
    exit 1
fi
WIDGET_OBJECT_DIR="$(find "$ROOT_DIR/.build/out/Intermediates.noindex/Tack.build/Release/TackWidgets-p.build/Objects-normal" -mindepth 2 -maxdepth 2 -name 'TackWidgets-primary.swiftconstvalues' -print -quit)"
if [[ -z "$WIDGET_OBJECT_DIR" ]]; then
    echo "SwiftPM did not emit TackWidgets App Intents metadata inputs." >&2
    exit 1
fi
WIDGET_OBJECT_DIR="$(dirname "$WIDGET_OBJECT_DIR")"
CONST_VALUES_FILE="$WIDGET_OBJECT_DIR/TackWidgets-primary.swiftconstvalues"
SOURCE_FILE_LIST="$WIDGET_OBJECT_DIR/TackWidgets.SwiftFileList"
if [[ ! -s "$CONST_VALUES_FILE" || ! -s "$SOURCE_FILE_LIST" ]]; then
    echo "TackWidgets App Intents metadata inputs are missing or empty." >&2
    exit 1
fi
printf '%s\n' "$CONST_VALUES_FILE" > "$BUILD_TEMP_DIR/swift-const-values.list"
SDK_ROOT="$(DEVELOPER_DIR="$DEVELOPER_DIR_FOR_INTENTS" xcrun --sdk macosx --show-sdk-path)"
XCODE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :DTXcode' "$DEVELOPER_DIR_FOR_INTENTS/../Info.plist")"
TARGET_ARCH="$(uname -m)"
TARGET_TRIPLE="$TARGET_ARCH-apple-macosx15.0"
DEVELOPER_DIR="$DEVELOPER_DIR_FOR_INTENTS" xcrun appintentsmetadataprocessor \
    --output "$WIDGET_APP/Contents/Resources" \
    --toolchain-dir "$DEVELOPER_DIR_FOR_INTENTS/Toolchains/XcodeDefault.xctoolchain" \
    --module-name TackWidgets \
    --sdk-root "$SDK_ROOT" \
    --xcode-version "$XCODE_VERSION" \
    --platform-family macOS \
    --deployment-target 15.0 \
    --target-triple "$TARGET_TRIPLE" \
    --source-file-list "$SOURCE_FILE_LIST" \
    --swift-const-vals-list "$BUILD_TEMP_DIR/swift-const-values.list"
python3 - "$WIDGET_APP/Contents/Resources/Metadata.appintents/extract.actionsdata" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as metadata_file:
    metadata = json.load(metadata_file)

required_items = {
    "actions": "SelectTackNoteIntent",
    "entities": "TackPinnedNoteEntity",
    "queries": "TackPinnedNoteEntityQuery",
}
for category, name in required_items.items():
    if name not in metadata.get(category, {}):
        raise SystemExit(f"TackWidgets App Intents metadata is missing {category[:-1]} {name}")
PY

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

ENTITLEMENTS_DIR="$BUILD_TEMP_DIR/entitlements"
mkdir -p "$ENTITLEMENTS_DIR"
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

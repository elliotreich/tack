#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ICONSET_DIR="$ROOT_DIR/build/AppIcon.iconset"
SOURCE="$ROOT_DIR/Resources/AppIcon-1024.png"
OUTPUT="$ROOT_DIR/Resources/AppIcon.icns"

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

for SIZE in 16 32 128 256 512; do
    SMALL_NAME="icon_"$SIZE"x"$SIZE".png"
    DOUBLE_SIZE=$((SIZE * 2))
    LARGE_NAME="icon_"$SIZE"x"$SIZE"@2x.png"
    sips -z "$SIZE" "$SIZE" "$SOURCE" --out "$ICONSET_DIR/$SMALL_NAME" >/dev/null
    sips -z "$DOUBLE_SIZE" "$DOUBLE_SIZE" "$SOURCE" --out "$ICONSET_DIR/$LARGE_NAME" >/dev/null
done

iconutil -c icns "$ICONSET_DIR" --output "$OUTPUT"
echo "$OUTPUT"

#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
DIST_DIR="$ROOT_DIR/dist"
ARCHIVE="$DIST_DIR/Tack-$VERSION-macOS.zip"

"$ROOT_DIR/scripts/build-app.sh"
mkdir -p "$DIST_DIR"
rm -f "$ARCHIVE"
ditto -c -k --norsrc --keepParent "$ROOT_DIR/build/Tack.app" "$ARCHIVE"
shasum -a 256 "$ARCHIVE"
echo "$ARCHIVE"

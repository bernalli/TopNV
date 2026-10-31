#!/usr/bin/env bash
# Packs build/topNV.app into build/topNV.dmg: a compressed disk image with the app and a
# link to /Applications, so it can be installed by dragging the icon.
#
# Usage: scripts/make-dmg.sh [output.dmg]
# Run scripts/bundle.sh first.
set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly APP_NAME="topNV"
readonly APP_DIR="$ROOT/build/$APP_NAME.app"
readonly DMG_PATH="${1:-$ROOT/build/$APP_NAME.dmg}"

if [[ ! -d "$APP_DIR" ]]; then
  echo "error: $APP_DIR not found, run scripts/bundle.sh first" >&2
  exit 1
fi

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP_DIR" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

mkdir -p "$(dirname "$DMG_PATH")"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING" \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$DMG_PATH" > /dev/null
hdiutil verify "$DMG_PATH" > /dev/null

echo "$DMG_PATH"

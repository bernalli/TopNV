#!/usr/bin/env bash
# Builds topNV in release mode and assembles an ad-hoc signed build/topNV.app.
#
# Usage: scripts/bundle.sh [extra swift build flags]
# Set TOPNV_EXECUTABLE to the path of an already built release executable to skip the
# SwiftPM build (for example one produced by xcodebuild).
# Set TOPNV_VERSION and TOPNV_BUILD_NUMBER to override the bundle version (used by the release
# workflow). Pass "--arch arm64 --arch x86_64" to build a universal app.
set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly APP_NAME="topNV"
readonly BUNDLE_ID="io.github.bernalli.topnv"
readonly VERSION="${TOPNV_VERSION:-1.1.0}"
readonly BUILD_NUMBER="${TOPNV_BUILD_NUMBER:-1}"
readonly MIN_MACOS="14.0"
readonly APP_DIR="$ROOT/build/$APP_NAME.app"
# The author's name lives only in AUTHORS, the single source of attribution.
readonly AUTHOR="$(head -n 1 "$ROOT/AUTHORS")"
if [[ -z "$AUTHOR" ]]; then
  echo "error: AUTHORS is empty" >&2
  exit 1
fi

cd "$ROOT"
if [[ -n "${TOPNV_EXECUTABLE:-}" ]]; then
  EXECUTABLE="$TOPNV_EXECUTABLE"
else
  swift build -c release --product TopNV "$@"
  EXECUTABLE="$(swift build -c release --show-bin-path "$@")/TopNV"
fi
if [[ ! -x "$EXECUTABLE" ]]; then
  echo "error: executable not found: $EXECUTABLE" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT/Assets/AppIcon.icns" "$ROOT/Assets/MenuBarIcon.png" "$ROOT/Assets/MenuBarIcon@2x.png" \
  "$APP_DIR/Contents/Resources/"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>NSHumanReadableCopyright</key>
  <string>© 2026 $AUTHOR</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_MACOS</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

plutil -lint "$APP_DIR/Contents/Info.plist" > /dev/null
codesign --force --sign - --timestamp=none "$APP_DIR"
codesign --verify --strict "$APP_DIR"

echo "$APP_DIR"

#!/usr/bin/env bash
# Builds TopNV in release mode and assembles an ad-hoc signed build/TopNV.app.
#
# Usage: scripts/bundle.sh [extra swift build flags]
# Set TOPNV_EXECUTABLE to the path of an already built release executable to skip the
# SwiftPM build (for example one produced by xcodebuild).
# Set TOPNV_VERSION and TOPNV_BUILD_NUMBER to override the bundle version (used by the release
# workflow). Pass "--arch arm64 --arch x86_64" to build a universal app.
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly SCRIPT_ROOT
readonly ROOT="${TOPNV_TEST_ROOT-$SCRIPT_ROOT}"
readonly APP_NAME="TopNV"
readonly BUNDLE_ID="io.github.bernalli.topnv"
readonly VERSION="${TOPNV_VERSION-1.1.0}"
readonly BUILD_NUMBER="${TOPNV_BUILD_NUMBER-1}"
readonly MIN_MACOS="14.0"
readonly APP_DIR="$ROOT/build/$APP_NAME.app"
readonly FEED_URL="${TOPNV_FEED_URL-https://github.com/bernalli/TopNV/releases/latest/download/appcast.xml}"
python3 "$SCRIPT_ROOT/scripts/bundle-metadata.py" inputs "$ROOT"
PUBLIC_KEY="$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).read_text().rstrip())' "$ROOT/Assets/SparklePublicEDKey.txt")"
# The author's name lives only in AUTHORS, the single source of attribution.
AUTHOR="$(head -n 1 "$ROOT/AUTHORS")"
AUTHOR="$(printf '%s' "$AUTHOR" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
if [[ -z "$AUTHOR" ]]; then
  echo "error: AUTHORS is empty" >&2
  exit 1
fi
AUTHOR_XML="$(printf '%s' "$AUTHOR" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')"
readonly AUTHOR AUTHOR_XML

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

FRAMEWORK="$(dirname "$EXECUTABLE")/Sparkle.framework"
[[ -d "$FRAMEWORK" ]] || { echo "error: Sparkle.framework missing beside executable" >&2; exit 1; }
# Remove only this worktree output after all input checks.
python3 -c 'import shutil,sys; from pathlib import Path; p=Path(sys.argv[1]); p.unlink() if p.is_symlink() else shutil.rmtree(p, ignore_errors=True)' "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
mkdir -p "$APP_DIR/Contents/Frameworks" "$APP_DIR/Contents/Resources/Licenses"
cp -R "$FRAMEWORK" "$APP_DIR/Contents/Frameworks/"
cp "$ROOT/Licenses/Sparkle.txt" "$APP_DIR/Contents/Resources/Licenses/Sparkle.txt"
cp "$ROOT/LICENSE" "$APP_DIR/Contents/Resources/Licenses/TopNV.txt"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT/Assets/AppIcon.icns" "$ROOT/Assets/MenuBarIcon.png" "$ROOT/Assets/MenuBarIcon@2x.png" \
  "$ROOT/Assets/GitHubMark.png" "$ROOT/Assets/GitHubMark@2x.png" \
  "$APP_DIR/Contents/Resources/"

# Capture first: grep -q stops reading early, and under pipefail the SIGPIPE to otool reads as failure.
LOAD_COMMANDS="$(otool -l "$APP_DIR/Contents/MacOS/$APP_NAME")"
if [[ "$LOAD_COMMANDS" != *"path @executable_path/../Frameworks (offset "* ]]; then
  install_name_tool -add_rpath @executable_path/../Frameworks "$APP_DIR/Contents/MacOS/$APP_NAME"
fi

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
  <string>Copyright (c) 2026 $AUTHOR_XML</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_MACOS</string>
  <key>LSUIElement</key>
  <true/>
  <key>SUFeedURL</key><string>$FEED_URL</string>
  <key>SUPublicEDKey</key><string>$PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key><false/>
  <key>SUAllowsAutomaticUpdates</key><false/>
  <key>SUVerifyUpdateBeforeExtraction</key><true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

plutil -lint "$APP_DIR/Contents/Info.plist" > /dev/null
codesign --force --sign - --timestamp=none "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "$APP_DIR"

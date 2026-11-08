#!/usr/bin/env bash
# Independent bundle checks; reports every failed invariant.
set -uo pipefail
SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${TOPNV_TEST_ROOT-$SCRIPT_ROOT}"
[[ $# == 1 ]] || { echo 'usage: verify-bundle.sh <app>' >&2; exit 1; }
APP=$1
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
failed=0
fail() { echo "$1" >&2; failed=1; }
plutil -lint "$APP/Contents/Info.plist" >/dev/null 2>&1 || fail 'V0: invalid plist'
python3 "$SCRIPT_ROOT/scripts/bundle-metadata.py" verify "$ROOT" "$APP" || failed=1
if [[ ! -f "$FRAMEWORK/Versions/B/Sparkle" ]] || ! python3 - "$FRAMEWORK/Versions/B/Resources/Info.plist" <<'PY'
import plistlib,sys
try:
    assert plistlib.load(open(sys.argv[1], 'rb'))['CFBundleShortVersionString'] == '2.10.1'
except Exception:
    sys.exit(1)
PY
then fail 'V5: invalid framework version or binary'; fi
for entry in Versions/Current Sparkle Autoupdate Updater.app XPCServices Resources Headers Modules PrivateHeaders; do
  [[ -L "$FRAMEWORK/$entry" && -e "$FRAMEWORK/$entry" ]] || fail "V6: invalid symlink $entry"
done
otool -l "$APP/Contents/MacOS/TopNV" 2>/dev/null | grep -Fq 'path @executable_path/../Frameworks (offset ' || fail 'V7: missing rpath'
codesign --verify --deep --strict "$APP" >/dev/null 2>&1 || fail 'V8: signature verification failed'
SIGNATURE=$(codesign -dv --verbose=4 "$APP" 2>&1) || fail 'V9: signature metadata unavailable'
if [[ "$SIGNATURE" != *'Signature=adhoc'* || "$SIGNATURE" == *runtime* ]]; then fail 'V9: outer signature must be ad hoc without runtime'; fi
if [[ ${TOPNV_EXPECT_UNIVERSAL-0} == 1 ]]; then
  for binary in "$APP/Contents/MacOS/TopNV" "$FRAMEWORK/Versions/B/Sparkle"; do
    ARCHS=$(lipo -archs "$binary" 2>/dev/null) || ARCHS=''
    [[ " $ARCHS " == *' arm64 '* && " $ARCHS " == *' x86_64 '* ]] || fail 'V10: missing universal slices'
  done
fi
[[ $failed == 0 ]] && echo 'V0-V13: passed'
exit "$failed"

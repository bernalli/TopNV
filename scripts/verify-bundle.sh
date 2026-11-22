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
# Capture first: grep -q stops reading early, and under pipefail the SIGPIPE to otool reads as failure.
load_commands="$(otool -l "$APP/Contents/MacOS/TopNV" 2>/dev/null)" || load_commands=''
[[ "$load_commands" == *'path @executable_path/../Frameworks (offset '* ]] || fail 'V7: missing rpath'
codesign --verify --deep --strict "$APP" >/dev/null 2>&1 || fail 'V8: signature verification failed'
SIGNATURE=$(codesign -dv --verbose=4 "$APP" 2>&1) || fail 'V9: signature metadata unavailable'
# Line-anchored reads of codesign -dv output.
has_line() {
  printf '%s\n' "$1" | python3 -c '
import sys
prefix = sys.argv[1]
values = [line[len(prefix):] for line in sys.stdin.read().splitlines()
          if line.startswith(prefix)]
sys.exit(0 if len(values) == 1 and values[0].strip() else 1)
' "$2"
}
has_runtime() {
  printf '%s\n' "$1" | python3 -c '
import re, sys
rows = [line for line in sys.stdin.read().splitlines()
        if line.startswith("CodeDirectory ")]
if len(rows) != 1:
    sys.exit(1)
flags = re.findall(
    r"(?:^|\s)flags=0x([0-9a-fA-F]{1,8})\(([^)]*)\)(?=\s|$)",
    rows[0])
if len(flags) != 1:
    sys.exit(1)
number, labels = flags[0]
sys.exit(0 if int(number, 16) & 0x10000
         and labels.split(",").count("runtime") == 1 else 1)
'
}
team_of() {
  printf '%s\n' "$1" | python3 -c '
import re, sys
values = [line.partition("=")[2]
          for line in sys.stdin.read().splitlines()
          if line.startswith("TeamIdentifier=")]
if len(values) != 1 or not re.fullmatch(r"[A-Z0-9]{10}", values[0]):
    sys.exit(1)
print(values[0], end="")
'
}
# No default: the caller states which signature it built (DP-7).
case "${TOPNV_EXPECT_SIGNATURE-}" in
  adhoc)
    if [[ "$SIGNATURE" != *'Signature=adhoc'* || "$SIGNATURE" == *runtime* ]]; then fail 'V9: outer signature must be ad hoc without runtime'; fi ;;
  developer-id)
    TEAM=$(team_of "$SIGNATURE") || TEAM=''
    if [[ "$SIGNATURE" == *'Signature=adhoc'* || -z "$TEAM" ]] || ! has_line "$SIGNATURE" 'Authority=Developer ID Application: ' \
      || ! has_runtime "$SIGNATURE" || ! has_line "$SIGNATURE" 'Timestamp='; then
      fail 'V9: outer signature must be Developer ID with runtime, secure timestamp and team'
    fi
    # The five components that bundle.sh signs, inside out.
    components=("$FRAMEWORK/Versions/B/XPCServices/Installer.xpc" "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
      "$FRAMEWORK/Versions/B/Autoupdate" "$FRAMEWORK/Versions/B/Updater.app" "$FRAMEWORK")
    for component in "${components[@]}"; do
      DETAILS=$(codesign -dv --verbose=4 "$component" 2>&1) || DETAILS=''
      if ! has_runtime "$DETAILS" || [[ -z "$TEAM" || "$(team_of "$DETAILS")" != "$TEAM" ]]; then
        fail "V14: $(basename "$component") needs runtime and the app team"
      fi
    done ;;
  *) fail 'V9: TOPNV_EXPECT_SIGNATURE must be adhoc or developer-id' ;;
esac
if [[ ${TOPNV_EXPECT_UNIVERSAL-0} == 1 ]]; then
  for binary in "$APP/Contents/MacOS/TopNV" "$FRAMEWORK/Versions/B/Sparkle"; do
    ARCHS=$(lipo -archs "$binary" 2>/dev/null) || ARCHS=''
    [[ " $ARCHS " == *' arm64 '* && " $ARCHS " == *' x86_64 '* ]] || fail 'V10: missing universal slices'
  done
fi
[[ $failed == 0 ]] && echo 'V0-V20: passed'
exit "$failed"

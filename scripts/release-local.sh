#!/usr/bin/env bash
# Local Developer ID release: build, sign, notarize, staple, check Gatekeeper, sign the appcast
# with the EdDSA key in the Keychain, then publish through the same transaction as the workflow.
#
# Usage: scripts/release-local.sh <version> <build>
# Run on a clean main equal to origin/main. TOPNV_SIGN_IDENTITY overrides the signing identity
# (default "Developer ID Application"); notarytool uses the Keychain profile "notary".
set -euo pipefail
# The EdDSA key comes only from the Keychain here: a key exported in the shell reaches no child.
unset SPARKLE_ED_PRIVATE_KEY
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT
readonly MOUNT=build/release-mount
cd "$ROOT"

step() { echo "== $1 =="; }
die() { echo "error: $1" >&2; exit 1; }
APP_PID=''
MOUNTED=0
cleanup() {
  if [[ -n $APP_PID ]]; then kill "$APP_PID" 2>/dev/null || true; fi
  if [[ $MOUNTED == 1 ]]; then hdiutil detach "$MOUNT" >/dev/null || true; fi
}
trap cleanup EXIT
# Line-anchored reads of an spctl assessment.
accepted() {
  [[ $'\n'"$1"$'\n' == *": accepted"$'\n'* && $'\n'"$1"$'\n' == *$'\n'"source=Notarized Developer ID"$'\n'* ]]
}

step '0 guards'
[[ $# == 2 ]] || die 'usage: scripts/release-local.sh <version> <build>'
readonly VERSION=$1 BUILD=$2
TOPNV_VERSION="$VERSION" scripts/validate-version.sh
[[ $BUILD =~ ^[1-9][0-9]{0,9}$ ]] || die 'build must be a positive integer of at most ten digits'
STATUS="$(git status --porcelain)"
[[ -z $STATUS ]] || die 'working tree is not clean'
BRANCH="$(git symbolic-ref --quiet --short HEAD)" || die 'HEAD is detached; check out main'
[[ $BRANCH == main ]] || die "releases come only from main, not $BRANCH"
git fetch origin main
HEAD_SHA="$(git rev-parse --verify HEAD)"
MAIN_SHA="$(git rev-parse --verify 'origin/main^{commit}')"
[[ $HEAD_SHA == "$MAIN_SHA" ]] || die 'HEAD differs from origin/main'
TOPNV_RELEASE_NOTES="release-notes/$VERSION.md" scripts/require-release-notes.sh
[[ -d Localization ]] || die 'Localization is missing'
pending=0
grep -rq PENDING-MONOPODS Localization || pending=$?
case $pending in
  0) die 'Localization still contains PENDING-MONOPODS markers' ;;
  1) ;;
  *) die 'cannot read Localization' ;;
esac

step '1 release-check'
ID="${TOPNV_SIGN_IDENTITY:-Developer ID Application}"
readonly ID
swift build -c release --product release-check

step '2 bundle'
TOPNV_VERSION="$VERSION" TOPNV_BUILD_NUMBER="$BUILD" TOPNV_SIGN_IDENTITY="$ID" scripts/bundle.sh --arch arm64 --arch x86_64

step '3 verify'
TOPNV_EXPECT_SIGNATURE=developer-id TOPNV_EXPECT_UNIVERSAL=1 scripts/verify-bundle.sh build/TopNV.app

step '4 smoke'
build/TopNV.app/Contents/MacOS/TopNV &
APP_PID=$!
sleep 3
kill -0 "$APP_PID" 2>/dev/null || die 'the app did not keep running for three seconds'
kill "$APP_PID"
wait "$APP_PID" 2>/dev/null || true
APP_PID=''

step '5 dmg'
readonly DMG="build/TopNV-$VERSION.dmg"
scripts/make-dmg.sh "$DMG"
codesign --force --sign "$ID" --timestamp "$DMG"

step '6 notarize'
notary_status=0
NOTARY_JSON="$(xcrun notarytool submit "$DMG" --keychain-profile notary --wait --output-format json)" || notary_status=$?
echo "$NOTARY_JSON"
NOTARY_FIELDS="$(printf '%s' "$NOTARY_JSON" | python3 -c '
import json, sys
try: data = json.load(sys.stdin)
except ValueError: data = {}
if not isinstance(data, dict): data = {}
print(str(data.get("id", "")) + "\t" + str(data.get("status", "")))')"
NOTARY_ID="${NOTARY_FIELDS%%$'\t'*}"
NOTARY_RESULT="${NOTARY_FIELDS#*$'\t'}"
if [[ $notary_status != 0 || $NOTARY_RESULT != Accepted ]]; then
  echo "error: notarization status '${NOTARY_RESULT:-unknown}' for submission ${NOTARY_ID:-unknown}" >&2
  if [[ $NOTARY_ID =~ ^[0-9A-Fa-f-]{36}$ ]]; then
    xcrun notarytool log "$NOTARY_ID" --keychain-profile notary || true
  fi
  exit 1
fi

step '7 staple'
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

step '8 gatekeeper'
dmg_status=0
ASSESSMENT="$(spctl -a -t open --context context:primary-signature -vv "$DMG" 2>&1)" || dmg_status=$?
echo "$ASSESSMENT"
if [[ $dmg_status != 0 ]] || ! accepted "$ASSESSMENT"; then die "Gatekeeper did not accept $DMG as notarized"; fi
mkdir -p "$MOUNT"
hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT" "$DMG" >/dev/null
MOUNTED=1
app_status=0
ASSESSMENT="$(spctl -a -vv "$MOUNT/TopNV.app" 2>&1)" || app_status=$?
echo "$ASSESSMENT"
hdiutil detach "$MOUNT" >/dev/null
MOUNTED=0
if [[ $app_status != 0 ]] || ! accepted "$ASSESSMENT"; then die 'Gatekeeper did not accept the app inside the disk image as notarized'; fi

step '9 appcast'
# After stapling: the ticket changes the bytes that the EdDSA signature covers.
TOPNV_SPARKLE_KEY=keychain TOPNV_VERSION="$VERSION" \
  TOPNV_DOWNLOAD_PREFIX="https://github.com/bernalli/TopNV/releases/download/v$VERSION/" \
  TOPNV_RELEASE_NOTES="release-notes/$VERSION.md" scripts/sign-release.sh

step '10 publish'
# The publisher runs as a workflow_dispatch from main would.
PUBLISH_ENV=(GITHUB_EVENT_NAME=workflow_dispatch GITHUB_REF=refs/heads/main INPUT_VERSION="$VERSION" INPUT_CHANNEL=stable
  GITHUB_SHA="$(git rev-parse --verify HEAD)" GITHUB_RUN_NUMBER="$BUILD" GITHUB_RUN_ID="local-$VERSION-$BUILD")
if ! env "${PUBLISH_ENV[@]}" scripts/publish-release.sh publish; then
  echo 'error: publication failed; recovering this run' >&2
  env "${PUBLISH_ENV[@]}" scripts/publish-release.sh recover || echo 'error: recovery failed; check the draft release on GitHub' >&2
  exit 1
fi
echo '___RELEASE_END ok___'

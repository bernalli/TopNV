#!/usr/bin/env bash
set +x
set -euo pipefail
if [[ ${TOPNV_SPARKLE_KEY-} == keychain ]]; then
  unset SPARKLE_ED_PRIVATE_KEY
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# TOPNV_SPARKLE_KEY=keychain: generate_appcast reads the EdDSA key from the login Keychain (local
# release), under the topnv account where scripts create it; the tool default (ed25519) is not ours.
# Before signing, the public key of that account must be the key every installed TopNV trusts
# (Assets/SparklePublicEDKey.txt): an appcast signed with another key is refused by every install.
# Unset: the key comes from SPARKLE_ED_PRIVATE_KEY through stdin only (hosted release).
case "${TOPNV_SPARKLE_KEY-}" in
  '') scripts/require-signing-key.sh ;;
  keychain) ;;
  *) echo 'error: TOPNV_SPARKLE_KEY must be keychain or unset' >&2; exit 1 ;;
esac
scripts/validate-version.sh
scripts/require-release-notes.sh
python3 - <<'PY'
import base64, binascii, os, pathlib, shutil, subprocess, sys, tempfile
root=pathlib.Path.cwd(); tool=root/'.build/artifacts/sparkle/Sparkle/bin/generate_appcast'
if not tool.is_file() or not os.access(tool,os.X_OK): sys.exit('error: pinned generate_appcast unavailable')
version=os.environ['TOPNV_VERSION']; prefix=os.environ['TOPNV_DOWNLOAD_PREFIX']
if prefix not in [f'https://github.com/bernalli/TopNV/releases/download/v{version}/','https://github.com/bernalli/TopNV/releases/download/update-proof/']:
    sys.exit('error: invalid download prefix')
keychain=os.environ.get('TOPNV_SPARKLE_KEY')=='keychain'
key=None if keychain else os.environ['SPARKLE_ED_PRIVATE_KEY'].encode()
env=dict(os.environ); env.pop('SPARKLE_ED_PRIVATE_KEY',None)
if keychain:
    # The account key must be the published one. Neither key nor the tool output is printed.
    lookup_tool=root/'.build/artifacts/sparkle/Sparkle/bin/generate_keys'
    if not lookup_tool.is_file() or not os.access(lookup_tool,os.X_OK): sys.exit('error: pinned generate_keys unavailable')
    try: trusted=(root/'Assets/SparklePublicEDKey.txt').read_text(encoding='utf-8').rstrip()
    except (OSError,UnicodeDecodeError): sys.exit('error: Assets/SparklePublicEDKey.txt is missing or unreadable')
    try: valid=len(base64.b64decode(trusted,validate=True))==32
    except (binascii.Error,ValueError): valid=False
    if not valid: sys.exit('error: Assets/SparklePublicEDKey.txt does not hold an EdDSA public key')
    lookup=subprocess.run([str(lookup_tool),'--account','topnv','-p'],env=env,stdin=subprocess.DEVNULL,capture_output=True)
    account_key=lookup.stdout.decode('utf-8','replace').strip()
    if lookup.returncode or not account_key: sys.exit('error: cannot read the public key of the topnv Keychain account; output withheld')
    if account_key!=trusted: sys.exit('error: the topnv Keychain account holds a different key than Assets/SparklePublicEDKey.txt; appcast not signed')
source={'stdin':subprocess.DEVNULL} if keychain else {'input':key+b'\n'}
with tempfile.TemporaryDirectory(prefix='sign-',dir=root/'build') as tmp:
    folder=pathlib.Path(tmp)
    shutil.copy2(root/f'build/TopNV-{version}.dmg',folder)
    shutil.copy2(os.environ['TOPNV_RELEASE_NOTES'],folder/f'TopNV-{version}.md')
    result=subprocess.run([str(tool),*(['--account','topnv'] if keychain else ['--ed-key-file','-']),'--embed-release-notes','--download-url-prefix',prefix,'-o',str(root/'build/appcast.xml'),str(folder)],env=env,capture_output=True,**source)
    if result.returncode or (key and (key in result.stdout or key in result.stderr)): sys.exit('error: appcast signing failed; output withheld')
PY

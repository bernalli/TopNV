#!/usr/bin/env bash
set +x
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
scripts/require-signing-key.sh
scripts/validate-version.sh
scripts/require-release-notes.sh
python3 - <<'PY'
import os, pathlib, shutil, subprocess, sys, tempfile
root=pathlib.Path.cwd(); tool=root/'.build/artifacts/sparkle/Sparkle/bin/generate_appcast'
if not tool.is_file() or not os.access(tool,os.X_OK): sys.exit('error: pinned generate_appcast unavailable')
version=os.environ['TOPNV_VERSION']; prefix=os.environ['TOPNV_DOWNLOAD_PREFIX']
if prefix not in [f'https://github.com/bernalli/TopNV/releases/download/v{version}/','https://github.com/bernalli/TopNV/releases/download/update-proof/']:
    sys.exit('error: invalid download prefix')
key=os.environ['SPARKLE_ED_PRIVATE_KEY'].encode()
env=dict(os.environ); env.pop('SPARKLE_ED_PRIVATE_KEY',None)
with tempfile.TemporaryDirectory(prefix='sign-',dir=root/'build') as tmp:
    folder=pathlib.Path(tmp)
    shutil.copy2(root/f'build/TopNV-{version}.dmg',folder)
    shutil.copy2(os.environ['TOPNV_RELEASE_NOTES'],folder/f'TopNV-{version}.md')
    result=subprocess.run([str(tool),'--ed-key-file','-','--embed-release-notes','--download-url-prefix',prefix,'-o',str(root/'build/appcast.xml'),str(folder)],input=key+b'\n',env=env,capture_output=True)
    if result.returncode or key in result.stdout or key in result.stderr: sys.exit('error: appcast signing failed; output withheld')
PY

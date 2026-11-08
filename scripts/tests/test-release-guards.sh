#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
python3 - "$ROOT" <<'PY'
import base64, os, pathlib, subprocess, sys, tempfile
root=pathlib.Path(sys.argv[1])
def call(script, env):
    return subprocess.run(['bash',str(root/'scripts'/script)],env=dict(os.environ,**env),capture_output=True)
for value in ['', ' ', '!', base64.b64encode(bytes(31)).decode(), base64.b64encode(bytes(33)).decode(), base64.b64encode(bytes(32)).decode()+'\n']:
    result=call('require-signing-key.sh',{'SPARKLE_ED_PRIVATE_KEY':value})
    assert result.returncode != 0
    if len(value)>3: assert value.encode() not in result.stdout+result.stderr
value=base64.b64encode(bytes(32)).decode()
result=call('require-signing-key.sh',{'SPARKLE_ED_PRIVATE_KEY':value}); assert result.returncode==0 and value.encode() not in result.stdout+result.stderr
for value in ['', '1', '1.0', 'v1.1.0', '1.1.0\n', '1.0.0-beta', '9223372036854775808.0.0']:
    assert call('validate-version.sh',{'TOPNV_VERSION':value}).returncode != 0
assert call('validate-version.sh',{'TOPNV_VERSION':'1.1.0'}).returncode == 0
with tempfile.TemporaryDirectory(dir=root/'build/test-tmp') as tmp:
    path=pathlib.Path(tmp)/'notes.md'
    assert call('require-release-notes.sh',{'TOPNV_RELEASE_NOTES':str(path)}).returncode != 0
    for text in ['', ' \n\t', 'Valid notes']:
        path.write_text(text)
        assert (call('require-release-notes.sh',{'TOPNV_RELEASE_NOTES':str(path)}).returncode==0)==bool(text.strip())
print('PASS release guards; no private material persisted')
PY

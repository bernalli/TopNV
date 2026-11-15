#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
python3 - "$ROOT" <<'PY'
import base64, json, os, pathlib, shutil, subprocess, sys, tempfile
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
# Appcast signing, on a copy of the scripts with a recording generate_appcast.
with tempfile.TemporaryDirectory(dir=root/'build/test-tmp') as tmp:
    copy=pathlib.Path(tmp)
    shutil.copytree(root/'scripts',copy/'scripts',ignore=shutil.ignore_patterns('__pycache__','tests'))
    tool=copy/'.build/artifacts/sparkle/Sparkle/bin/generate_appcast'; tool.parent.mkdir(parents=True)
    tool.write_text('#!/usr/bin/env python3\nimport json,os,pathlib,sys\n'
                    "pathlib.Path(sys.argv[sys.argv.index('-o')+1]).write_text('feed')\n"
                    "json.dump({'argv':sys.argv[1:],'stdin':sys.stdin.read(),'env':'SPARKLE_ED_PRIVATE_KEY' in os.environ},open(os.environ['FAKE_RECORD'],'w'))\n")
    tool.chmod(0o755)
    (copy/'build').mkdir(); (copy/'build/TopNV-1.2.0.dmg').write_bytes(b'dmg')
    notes=copy/'notes.md'; notes.write_text('Notes'); record=copy/'record.json'
    key=base64.b64encode(bytes(range(32))).decode()
    prefix='https://github.com/bernalli/TopNV/releases/download/v1.2.0/'
    base={k:v for k,v in os.environ.items() if k not in ('SPARKLE_ED_PRIVATE_KEY','TOPNV_SPARKLE_KEY')}
    base.update(TOPNV_VERSION='1.2.0',TOPNV_DOWNLOAD_PREFIX=prefix,TOPNV_RELEASE_NOTES=str(notes),FAKE_RECORD=str(record))
    def sign(**values):
        record.unlink(missing_ok=True)
        result=subprocess.run(['bash',str(copy/'scripts/sign-release.sh')],env=dict(base,**values),stdin=subprocess.DEVNULL,capture_output=True)
        return result,(json.loads(record.read_text()) if record.exists() else None)
    tail=['--embed-release-notes','--download-url-prefix',prefix,'-o',str(copy/'build/appcast.xml')]
    # Without TOPNV_SPARKLE_KEY: today's flow, the key from the environment through stdin only.
    result,seen=sign(SPARKLE_ED_PRIVATE_KEY=key)
    assert result.returncode==0,result
    assert seen['argv'][:len(tail)+2]==['--ed-key-file','-']+tail and seen['stdin']==key+'\n' and not seen['env'],seen
    assert '--account' not in seen['argv'],seen
    for values in ({},{'SPARKLE_ED_PRIVATE_KEY':'!'},{'TOPNV_SPARKLE_KEY':'','SPARKLE_ED_PRIVATE_KEY':''}):
        result,seen=sign(**values); assert result.returncode!=0 and seen is None,(values,result)
    # keychain: the key of the topnv Keychain account; no key validation, no --ed-key-file, no key in
    # stdin, argv or the tool environment.
    for values in ({},{'SPARKLE_ED_PRIVATE_KEY':'!'},{'SPARKLE_ED_PRIVATE_KEY':key}):
        result,seen=sign(TOPNV_SPARKLE_KEY='keychain',**values)
        assert result.returncode==0,(values,result)
        assert seen['argv'][:len(tail)+2]==['--account','topnv']+tail and len(seen['argv'])==len(tail)+3,seen
        assert '--ed-key-file' not in seen['argv'],seen
        assert seen['stdin']=='' and not seen['env'],seen
        assert key.encode() not in result.stdout+result.stderr
    # keychain: an exported key reaches no child at all, not only generate_appcast.
    spy=copy/'spy'; spy.mkdir(); children_log=copy/'children.log'; real_bash=shutil.which('bash')
    for name in ('bash','dirname','python3'):
        (spy/name).write_text('#!/bin/bash\nprintf "%s %s\\n" '+name+' "${SPARKLE_ED_PRIVATE_KEY+leaked}" >> "$FAKE_CHILDREN"\n'
                              'exec '+shutil.which(name)+' "$@"\n')
        (spy/name).chmod(0o755)
    result=subprocess.run([real_bash,str(copy/'scripts/sign-release.sh')],stdin=subprocess.DEVNULL,capture_output=True,
                          env=dict(base,PATH=str(spy)+':'+base['PATH'],FAKE_CHILDREN=str(children_log),
                                   TOPNV_SPARKLE_KEY='keychain',SPARKLE_ED_PRIVATE_KEY=key))
    assert result.returncode==0,result
    children=children_log.read_text().splitlines()
    assert {c.split()[0] for c in children}=={'bash','dirname','python3'},children
    assert [c for c in children if c.endswith('leaked')]==[],children
    for mode in ('Keychain','file','keychain '):
        result,seen=sign(TOPNV_SPARKLE_KEY=mode,SPARKLE_ED_PRIVATE_KEY=key)
        assert result.returncode!=0 and seen is None and b'TOPNV_SPARKLE_KEY' in result.stderr,(mode,result)
print('PASS release guards; no private material persisted; appcast key from environment or keychain')
PY

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
# Appcast signing, on a copy of the scripts with a recording generate_appcast and generate_keys.
with tempfile.TemporaryDirectory(dir=root/'build/test-tmp') as tmp:
    copy=pathlib.Path(tmp)
    shutil.copytree(root/'scripts',copy/'scripts',ignore=shutil.ignore_patterns('__pycache__','tests'))
    tool=copy/'.build/artifacts/sparkle/Sparkle/bin/generate_appcast'; tool.parent.mkdir(parents=True)
    # Like the real tool, the fake keeps the items of an output feed that already exists.
    tool.write_text('#!/usr/bin/env python3\nimport json,os,pathlib,sys\n'
                    "out=pathlib.Path(sys.argv[sys.argv.index('-o')+1]); old=out.read_text() if out.exists() else ''\n"
                    "out.write_text(old+'<item>new</item>\\n')\n"
                    "json.dump({'argv':sys.argv[1:],'stdin':sys.stdin.read(),'env':'SPARKLE_ED_PRIVATE_KEY' in os.environ},open(os.environ['FAKE_RECORD'],'w'))\n")
    tool.chmod(0o755)
    # The public key lookup of the Keychain account: records its call and prints FAKE_KEYS_OUT.
    lookup=tool.parent/'generate_keys'
    lookup.write_text('#!/usr/bin/env python3\nimport json,os,sys\n'
                      "json.dump({'argv':sys.argv[1:],'stdin':sys.stdin.read(),'env':'SPARKLE_ED_PRIVATE_KEY' in os.environ},open(os.environ['FAKE_KEYS_RECORD'],'w'))\n"
                      "sys.stdout.write(os.environ.get('FAKE_KEYS_OUT',''))\n"
                      "sys.stderr.write(os.environ.get('FAKE_KEYS_ERR',''))\n"
                      "sys.exit(int(os.environ.get('FAKE_KEYS_EXIT','0')))\n")
    lookup.chmod(0o755)
    (copy/'build').mkdir(); (copy/'build/TopNV-1.2.0.dmg').write_bytes(b'dmg')
    public=base64.b64encode(bytes(range(32,64))).decode(); other=base64.b64encode(bytes(range(64,96))).decode()
    trusted=copy/'Assets/SparklePublicEDKey.txt'; trusted.parent.mkdir(); trusted.write_text(public+'\n')
    notes=copy/'notes.md'; notes.write_text('Notes'); record=copy/'record.json'; looked_up=copy/'keys.json'
    key=base64.b64encode(bytes(range(32))).decode()
    prefix='https://github.com/bernalli/TopNV/releases/download/v1.2.0/'
    base={k:v for k,v in os.environ.items() if k not in ('SPARKLE_ED_PRIVATE_KEY','TOPNV_SPARKLE_KEY')}
    base.update(TOPNV_VERSION='1.2.0',TOPNV_DOWNLOAD_PREFIX=prefix,TOPNV_RELEASE_NOTES=str(notes),FAKE_RECORD=str(record),
                FAKE_KEYS_RECORD=str(looked_up),FAKE_KEYS_OUT=public+'\n')
    def read(path):
        return json.loads(path.read_text()) if path.exists() else None
    def sign(**values):
        record.unlink(missing_ok=True); looked_up.unlink(missing_ok=True)
        result=subprocess.run(['bash',str(copy/'scripts/sign-release.sh')],env=dict(base,**values),stdin=subprocess.DEVNULL,capture_output=True)
        return result,read(record),read(looked_up)
    tail=['--embed-release-notes','--download-url-prefix',prefix,'-o']
    # A feed left by an earlier release must never reach generate_appcast: the tool writes into
    # a new folder, and build/appcast.xml holds only the item of this release afterwards.
    appcast=copy/'build/appcast.xml'; appcast.write_text('<item>1.1.0</item>\n')
    def written(seen,keys):
        argv=seen['argv']
        assert argv[:len(keys)+len(tail)]==keys+tail and len(argv)==len(keys)+len(tail)+2,seen
        out,folder=pathlib.Path(argv[-2]),pathlib.Path(argv[-1])
        assert out!=appcast and out.parent!=folder and out.parent.parent==copy/'build',seen
        assert appcast.read_text()=='<item>new</item>\n',appcast.read_text()
        assert sorted(p.name for p in (copy/'build').iterdir())==['TopNV-1.2.0.dmg','appcast.xml']
    # Without TOPNV_SPARKLE_KEY: today's flow, the key from the environment through stdin only.
    result,seen,asked=sign(SPARKLE_ED_PRIVATE_KEY=key)
    assert result.returncode==0,result
    written(seen,['--ed-key-file','-'])
    assert seen['stdin']==key+'\n' and not seen['env'],seen
    assert '--account' not in seen['argv'],seen
    # The hosted flow never asks the Keychain, not even when the account would fail.
    assert asked is None,asked
    result,seen,asked=sign(SPARKLE_ED_PRIVATE_KEY=key,FAKE_KEYS_EXIT='1',FAKE_KEYS_OUT=other)
    assert result.returncode==0 and seen is not None and asked is None,(result,asked)
    for values in ({},{'SPARKLE_ED_PRIVATE_KEY':'!'},{'TOPNV_SPARKLE_KEY':'','SPARKLE_ED_PRIVATE_KEY':''}):
        result,seen,asked=sign(**values); assert result.returncode!=0 and seen is None and asked is None,(values,result)
    # keychain: the key of the topnv Keychain account; no key validation, no --ed-key-file, no key in
    # stdin, argv or the tool environment; the account key is looked up first, without input.
    for values in ({},{'SPARKLE_ED_PRIVATE_KEY':'!'},{'SPARKLE_ED_PRIVATE_KEY':key}):
        result,seen,asked=sign(TOPNV_SPARKLE_KEY='keychain',**values)
        assert result.returncode==0,(values,result)
        assert asked=={'argv':['--account','topnv','-p'],'stdin':'','env':False},asked
        written(seen,['--account','topnv'])
        assert '--ed-key-file' not in seen['argv'],seen
        assert seen['stdin']=='' and not seen['env'],seen
        assert key.encode() not in result.stdout+result.stderr
    # keychain: whitespace around the printed key is not part of the key.
    for out in (public,public+'\r\n','  '+public+'\n\n','\n'+public+'\t\n'):
        result,seen,asked=sign(TOPNV_SPARKLE_KEY='keychain',FAKE_KEYS_OUT=out)
        assert result.returncode==0 and seen is not None,(repr(out),result)
    # keychain: any other answer stops before generate_appcast, and no key reaches the output.
    def refused(message,**values):
        result,seen,asked=sign(TOPNV_SPARKLE_KEY='keychain',SPARKLE_ED_PRIVATE_KEY=key,**values)
        assert result.returncode!=0 and seen is None,(values,result)
        assert message in result.stderr,(values,result.stderr)
        for secret in (key,public,other,'FAKE-SECRET-OUTPUT'):
            assert secret.encode() not in result.stdout+result.stderr,(values,secret)
        return asked
    for out in (other+'\n',public[:-2]+'\n',public+public+'\n',public+'\n'+public+'\n',public[:20]+' '+public[20:]+'\n','ERROR: No existing signing key found!\n'):
        assert refused(b'different key',FAKE_KEYS_OUT=out) is not None,out
    for out in ('',' ','\n','\t\r\n'):
        refused(b'cannot read the public key',FAKE_KEYS_OUT=out)
    for code in ('1','2','255'):
        refused(b'cannot read the public key',FAKE_KEYS_EXIT=code)
        refused(b'cannot read the public key',FAKE_KEYS_EXIT=code,FAKE_KEYS_OUT='FAKE-SECRET-OUTPUT',FAKE_KEYS_ERR='FAKE-SECRET-OUTPUT')
    refused(b'different key',FAKE_KEYS_OUT='FAKE-SECRET-OUTPUT\n',FAKE_KEYS_ERR='FAKE-SECRET-OUTPUT')
    # keychain: a missing or malformed published key stops before the Keychain is asked.
    for content,message in ((None,b'missing or unreadable'),(b'\xff\xfe\n',b'missing or unreadable'),
                            (b'',b'does not hold'),(b'\n',b'does not hold'),(b'!'*44+b'\n',b'does not hold'),
                            (base64.b64encode(bytes(31))+b'\n',b'does not hold'),
                            (base64.b64encode(bytes(33))+b'\n',b'does not hold'),
                            (b' '+public.encode()+b'\n',b'does not hold')):
        if content is None: trusted.unlink()
        else: trusted.write_bytes(content)
        assert refused(message) is None,content
    # Trailing blank lines of the published key are ignored, as bundle.sh does.
    trusted.write_text(public+'\n\n')
    result,seen,asked=sign(TOPNV_SPARKLE_KEY='keychain'); assert result.returncode==0 and seen is not None,result
    trusted.write_text(public+'\n')
    # keychain: without the pinned lookup tool nothing is signed and nothing is asked.
    lookup.chmod(0o644); assert refused(b'generate_keys unavailable') is None; lookup.chmod(0o755)
    saved=lookup.read_bytes(); lookup.unlink(); assert refused(b'generate_keys unavailable') is None
    lookup.write_bytes(saved); lookup.chmod(0o755)
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
        result,seen,asked=sign(TOPNV_SPARKLE_KEY=mode,SPARKLE_ED_PRIVATE_KEY=key)
        assert result.returncode!=0 and seen is None and asked is None and b'TOPNV_SPARKLE_KEY' in result.stderr,(mode,result)
print('PASS release guards; no private material persisted; appcast key from environment or keychain; keychain key checked against the published key')
PY

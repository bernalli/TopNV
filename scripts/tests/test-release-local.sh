#!/usr/bin/env bash
# Exercise release-local.sh on a throwaway git repository: every guard stops before any build,
# and the full sequence runs in order with platform tools and release scripts replaced.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
python3 - "$ROOT" <<'PY'
import json, os, pathlib, shutil, subprocess, sys, tempfile
root=pathlib.Path(sys.argv[1])
ID='2efe2717-52ef-43a5-96dc-0797e4ca1041'
RECORDER='#!/usr/bin/env python3\nimport json,os,sys\nKEYS={keys!r}\n' \
    "with open(os.environ['FAKE_LOG'],'a') as f: f.write(json.dumps({{'tool':{name!r},'args':sys.argv[1:],'env':{{k:os.environ[k] for k in KEYS if k in os.environ}}}})+'\\n')\n"
def fake(path,keys=(),body=''):
    path.write_text(RECORDER.format(name=path.name,keys=list(keys))+body); path.chmod(0o755)
with tempfile.TemporaryDirectory(dir=root/'build/test-tmp') as tmp:
    tmp=pathlib.Path(tmp).resolve(); repo=tmp/'repo'; bindir=tmp/'bin'; log=tmp/'calls.jsonl'
    # The throwaway repository sits inside this checkout: never let git climb into it.
    git_env=dict(os.environ,GIT_CEILING_DIRECTORIES=str(tmp),GIT_CONFIG_GLOBAL='/dev/null',GIT_CONFIG_NOSYSTEM='1',
                 XDG_CONFIG_HOME=str(tmp/'xdg'),GIT_AUTHOR_NAME='Test',GIT_AUTHOR_EMAIL='test@example.invalid',
                 GIT_COMMITTER_NAME='Test',GIT_COMMITTER_EMAIL='test@example.invalid')
    for name in [k for k in git_env if k.startswith(('GITHUB_','INPUT_','TOPNV_','FAKE_'))]: del git_env[name]
    def git(*args):
        result=subprocess.run(['git',*args],cwd=repo,env=git_env,capture_output=True,text=True)
        assert result.returncode==0,(args,result.stderr)
        return result.stdout.strip()
    subprocess.run(['git','init','-q','--bare','--template=',str(tmp/'origin.git')],env=git_env,check=True)
    repo.mkdir()
    subprocess.run(['git','init','-q','--template=','-b','main','--separate-git-dir',str(tmp/'repo.git'),str(repo)],env=git_env,check=True)
    assert git('rev-parse','--show-toplevel')==str(repo)
    (repo/'scripts').mkdir()
    for name in ('release-local.sh','validate-version.sh','require-release-notes.sh'):
        shutil.copy2(root/'scripts'/name,repo/'scripts'/name)
    fake(repo/'scripts/bundle.sh',('TOPNV_VERSION','TOPNV_BUILD_NUMBER','TOPNV_SIGN_IDENTITY'),
         "app=os.path.join('build','TopNV.app','Contents','MacOS'); os.makedirs(app,exist_ok=True)\n"
         "p=os.path.join(app,'TopNV'); open(p,'w').write('#!/bin/bash\\n'+('exit 0' if os.environ.get('FAKE_APP_EXITS') else 'exec sleep 30')+'\\n'); os.chmod(p,0o755)\n")
    fake(repo/'scripts/verify-bundle.sh',('TOPNV_EXPECT_SIGNATURE','TOPNV_EXPECT_UNIVERSAL'))
    fake(repo/'scripts/make-dmg.sh',(),"open(sys.argv[1],'wb').write(b'dmg')\n")
    fake(repo/'scripts/sign-release.sh',('TOPNV_SPARKLE_KEY','TOPNV_VERSION','TOPNV_DOWNLOAD_PREFIX','TOPNV_RELEASE_NOTES','SPARKLE_ED_PRIVATE_KEY'))
    publish_keys=('GITHUB_EVENT_NAME','GITHUB_REF','INPUT_VERSION','INPUT_CHANNEL','GITHUB_SHA','GITHUB_RUN_NUMBER','GITHUB_RUN_ID')
    fake(repo/'scripts/publish-release.sh',publish_keys,"sys.exit(1 if os.environ.get('FAKE_PUBLISH_FAILS') and sys.argv[1]=='publish' else 0)\n")
    (repo/'release-notes').mkdir(); (repo/'release-notes/1.2.0.md').write_text('Notes\n'); (repo/'release-notes/1.3.0.md').write_text(' \n')
    (repo/'Localization/en.lproj').mkdir(parents=True); (repo/'Localization/en.lproj/Localizable.strings').write_text('"Later" = "Later";\n')
    (repo/'.gitignore').write_text('build/\n')
    git('add','-A'); git('commit','-qm','initial'); git('remote','add','origin',str(tmp/'origin.git')); git('push','-q','origin','main')
    bindir.mkdir()
    fake(bindir/'swift'); fake(bindir/'codesign')
    fake(bindir/'xcrun',(),
         "if sys.argv[1:3]==['notarytool','submit']:\n"
         "    if os.environ.get('FAKE_NOTARY')=='garbage': print('not json'); sys.exit(1)\n"
         f"    print(json.dumps({{'id':'{ID}','status':os.environ.get('FAKE_NOTARY','Accepted'),'message':'Processing complete'}}))\n")
    fake(bindir/'spctl',(),
         "target=sys.argv[-1]; mode=os.environ.get('FAKE_SPCTL','')\n"
         "if mode=='reject-dmg' and target.endswith('.dmg') or mode=='reject-app' and target.endswith('.app'):\n"
         "    sys.stderr.write(target+': rejected\\nsource=Unnotarized Developer ID\\n'); sys.exit(3)\n"
         "source='Developer ID' if mode=='plain-source' and target.endswith('.app') else 'Notarized Developer ID'\n"
         "sys.stderr.write(target+': accepted\\nsource='+source+'\\norigin=Developer ID Application: Example Developer (ABCDE12345)\\n')\n")
    fake(bindir/'hdiutil',(),"if sys.argv[1]=='attach': os.makedirs(sys.argv[sys.argv.index('-mountpoint')+1],exist_ok=True)\n")
    run_env=dict(git_env,PATH=str(bindir)+':'+os.environ['PATH'],FAKE_LOG=str(log))
    def release(*args,**values):
        log.write_text('')
        result=subprocess.run(['bash',str(repo/'scripts/release-local.sh'),*args],cwd=repo,env=dict(run_env,**values),
                              stdin=subprocess.DEVNULL,capture_output=True,text=True,timeout=120)
        return result,[json.loads(line) for line in log.read_text().splitlines()]
    def refused(*args,**values):
        result,calls=release(*args,**values)
        assert result.returncode!=0,(args,values,result)
        assert calls==[] and '== 1 ' not in result.stdout and '___RELEASE_END' not in result.stdout,(args,values,result,calls)
        assert result.stderr.strip(),(args,values,result)
    # Step 0: every guard refuses before the first build (no swift call, no other tool).
    for args in ((),('1.2.0',),('1.2.0','6','7')): refused(*args)
    for version in ('1.2','v1.2.0','1.2.0-beta',''): refused(version,'6')
    for build in ('0','-1','x','1.5','','01','12345678901'): refused('1.2.0',build)
    (repo/'stray').write_text('x'); refused('1.2.0','6'); (repo/'stray').unlink()
    notes=repo/'release-notes/1.2.0.md'; notes.write_text('Changed\n'); refused('1.2.0','6'); git('checkout','--','release-notes/1.2.0.md')
    git('checkout','-q','-b','other'); refused('1.2.0','6'); git('checkout','-q','main'); git('branch','-qD','other')
    git('checkout','-q','--detach'); refused('1.2.0','6'); git('checkout','-q','main')
    git('commit','-q','--allow-empty','-m','ahead'); refused('1.2.0','6')
    git('push','-q','origin','main'); git('reset','-q','--hard','HEAD~1'); refused('1.2.0','6')
    git('reset','-q','--hard','origin/main')
    refused('9.9.9','6'); refused('1.3.0','6')
    marker=repo/'Localization/en.lproj/Localizable.strings'; saved=marker.read_text()
    marker.write_text('/* PENDING-MONOPODS */\n'+saved); git('commit','-qam','pending'); git('push','-q','origin','main')
    refused('1.2.0','6')
    marker.write_text(saved); git('commit','-qam','resolved'); git('push','-q','origin','main')
    head=git('rev-parse','HEAD')
    dmg='build/TopNV-1.2.0.dmg'
    names=['0 guards','1 release-check','2 bundle','3 verify','4 smoke','5 dmg','6 notarize','7 staple','8 gatekeeper','9 appcast','10 publish']
    publish_env={'GITHUB_EVENT_NAME':'workflow_dispatch','GITHUB_REF':'refs/heads/main','INPUT_VERSION':'1.2.0','INPUT_CHANNEL':'stable',
                 'GITHUB_SHA':head,'GITHUB_RUN_NUMBER':'6','GITHUB_RUN_ID':'local-1.2.0-6'}
    def expected(identity):
        return [('swift',['build','-c','release','--product','release-check'],{}),
                ('bundle.sh',['--arch','arm64','--arch','x86_64'],{'TOPNV_VERSION':'1.2.0','TOPNV_BUILD_NUMBER':'6','TOPNV_SIGN_IDENTITY':identity}),
                ('verify-bundle.sh',['build/TopNV.app'],{'TOPNV_EXPECT_SIGNATURE':'developer-id','TOPNV_EXPECT_UNIVERSAL':'1'}),
                ('make-dmg.sh',[dmg],{}),
                ('codesign',['--force','--sign',identity,'--timestamp',dmg],{}),
                ('xcrun',['notarytool','submit',dmg,'--keychain-profile','notary','--wait','--output-format','json'],{}),
                ('xcrun',['stapler','staple',dmg],{}),
                ('xcrun',['stapler','validate',dmg],{}),
                ('spctl',['-a','-t','open','--context','context:primary-signature','-vv',dmg],{}),
                ('hdiutil',['attach','-nobrowse','-readonly','-mountpoint','build/release-mount',dmg],{}),
                ('spctl',['-a','-vv','build/release-mount/TopNV.app'],{}),
                ('hdiutil',['detach','build/release-mount'],{}),
                ('sign-release.sh',[],{'TOPNV_SPARKLE_KEY':'keychain','TOPNV_VERSION':'1.2.0','TOPNV_RELEASE_NOTES':'release-notes/1.2.0.md',
                                       'TOPNV_DOWNLOAD_PREFIX':'https://github.com/bernalli/TopNV/releases/download/v1.2.0/'}),
                ('publish-release.sh',['publish'],publish_env)]
    def flat(calls): return [(c['tool'],c['args'],c['env']) for c in calls]
    # The full sequence, with the default identity and with an explicit one.
    for values,identity in (({},'Developer ID Application'),
                            ({'TOPNV_SIGN_IDENTITY':'Developer ID Application: Example Developer (ABCDE12345)','SPARKLE_ED_PRIVATE_KEY':'unused'},
                             'Developer ID Application: Example Developer (ABCDE12345)')):
        result,calls=release('1.2.0','6',**values)
        assert result.returncode==0,(result,calls)
        assert [l[3:-3] for l in result.stdout.splitlines() if l.startswith('== ') and l.endswith(' ==')]==names,result.stdout
        assert result.stdout.splitlines()[-1]=='___RELEASE_END ok___',result.stdout
        assert flat(calls)==expected(identity),flat(calls)
    def failed(stop,**values):
        result,calls=release('1.2.0','6',**values)
        assert result.returncode!=0 and '___RELEASE_END' not in result.stdout,(values,result)
        assert result.stderr.strip(),(values,result)
        tools=[(c['tool'],c['args'][:2]) for c in calls]
        assert stop not in tools,(values,tools)
        return result,calls,tools
    # Failures after the build stop the release before the next irreversible step.
    failed(('make-dmg.sh',[dmg]),FAKE_APP_EXITS='1')
    for status in ('Invalid','Rejected','In Progress','garbage'):
        result,calls,tools=failed(('xcrun',['stapler','staple']),FAKE_NOTARY=status)
        logs=[c['args'] for c in calls if c['args'][:2]==['notarytool','log']]
        assert logs==([] if status=='garbage' else [['notarytool','log',ID,'--keychain-profile','notary']]),logs
        if status!='garbage': assert ID in result.stdout+result.stderr
    result,calls,tools=failed(('hdiutil',['attach','-nobrowse']),FAKE_SPCTL='reject-dmg')
    for mode in ('reject-app','plain-source'):
        result,calls,tools=failed(('sign-release.sh',[]),FAKE_SPCTL=mode)
        assert tools[-1]==('hdiutil',['detach','build/release-mount']) and tools.count(('hdiutil',['detach','build/release-mount']))==1,tools
    result,calls,tools=failed(('none',[]),FAKE_PUBLISH_FAILS='1')
    assert [(c['args'],c['env']) for c in calls if c['tool']=='publish-release.sh']==[(['publish'],publish_env),(['recover'],publish_env)],calls
    assert git('status','--porcelain')=='' and git('rev-parse','HEAD')==head
print('PASS release-local guards stop before any build; sequence, notarization, Gatekeeper and recovery')
PY

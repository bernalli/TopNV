#!/usr/bin/env python3
"""Fail-closed release transaction. All hosted mutations go through gh api."""
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time

REPO='repos/bernalli/TopNV'
STABLE='https://github.com/bernalli/TopNV/releases/latest/download/appcast.xml'
PROOF='https://github.com/bernalli/TopNV/releases/download/update-proof/appcast.xml'

class ReleaseError(Exception): pass

def require(condition, reason):
    if not condition: raise ReleaseError(reason)

def version_valid(value):
    return re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+',value) and all(len(n)<=19 and int(n)<=9223372036854775807 for n in value.split('.'))

class Transport:
    def __init__(self, root): self.root=root
    def git(self,*args):
        result=subprocess.run(['git',*args],cwd=self.root,capture_output=True,text=True)
        require(result.returncode==0,'Git source validation failed')
        return result.stdout.strip()
    def api(self,method,path,body=None,file=None,binary=False):
        args=['gh','api','--include','--method',method,path,'-H','Accept: '+('application/octet-stream' if binary else 'application/vnd.github+json')]
        if file: args+=['-H','Content-Type: application/octet-stream','--input',str(file)]
        elif body is not None: args+=['--input','-']
        result=subprocess.run(args,input=json.dumps(body).encode() if body is not None else None,capture_output=True)
        split=re.split(br'\r?\n\r?\n',result.stdout,maxsplit=1)
        match=re.search(br'^HTTP/\S+ (\d{3})',split[0])
        require(match is not None and len(split)==2,'GitHub transport failed')
        status=int(match[1]); raw=split[1]
        require(result.returncode==0 or status>=400,'GitHub transport failed')
        if binary: return status,raw
        try: return status,json.loads(raw) if raw.strip() else {}
        except ValueError: raise ReleaseError('GitHub returned invalid JSON') from None
    def download(self,url,path):
        result=subprocess.run(['curl','--silent','--show-error','--location','--proto','=https','--proto-redir','=https','--connect-timeout','30','--max-time','600','--output',str(path),'--write-out','%{http_code}',url],capture_output=True,text=True)
        require(result.returncode==0,'download transport error')
        require(re.fullmatch(r'[0-9]{3}',result.stdout) is not None,'invalid download status')
        return int(result.stdout)
    def order(self,build,version,current):
        args=[str(self.root/'.build/release/release-check'),'order','--build',build,'--version',version]
        args+=['--current-feed',str(current)] if current else ['--no-current-feed']
        require(subprocess.run(args,cwd=self.root).returncode==0,'release ordering failed')
    def verify(self,dmg,feed,config):
        # Recheck the actual downloaded disk image, including its own bundled app.
        mount=self.root/'build/verify-mount'; mount.mkdir(exist_ok=True)
        attached=False
        try:
            require(subprocess.run(['hdiutil','attach','-nobrowse','-readonly','-mountpoint',str(mount),str(dmg)],stdout=subprocess.DEVNULL).returncode==0,'cannot mount downloaded DMG')
            attached=True
            env=dict(os.environ,TOPNV_EXPECT_UNIVERSAL='1',TOPNV_EXPECT_FEED_URL=config.feed)
            require(subprocess.run([str(self.root/'scripts/verify-bundle.sh'),str(mount/'TopNV.app')],env=env).returncode==0,'downloaded bundle invalid')
            args=[str(self.root/'.build/release/release-check'),'feed','--appcast',str(feed),'--dmg',str(dmg),'--app',str(mount/'TopNV.app'),'--tag',config.tag,'--prefix',config.prefix,'--version',config.version,'--build',config.build,'--feed',config.feed,'--public-key-file',str(self.root/'Assets/SparklePublicEDKey.txt')]
            require(subprocess.run(args).returncode==0,'downloaded feed invalid')
        finally:
            if attached: require(subprocess.run(['hdiutil','detach',str(mount)],stdout=subprocess.DEVNULL).returncode==0,'cannot detach downloaded DMG')

class Publisher:
    def __init__(self,root,env,transport):
        self.root=Path(root); self.env=env; self.io=transport; self.release_id=None; self.publishing=False
        event=env.get('GITHUB_EVENT_NAME','')
        self.channel=env.get('INPUT_CHANNEL','stable') or 'stable'
        self.version=env.get('GITHUB_REF','').removeprefix('refs/tags/v') if event=='push' else env.get('INPUT_VERSION','')
        require(version_valid(self.version),'invalid version')
        require(self.channel in ('stable','proof'),'unknown channel')
        self.proof=self.channel=='proof'
        self.tag='update-proof' if self.proof else 'v'+self.version
        self.feed=PROOF if self.proof else STABLE
        self.prefix='https://github.com/bernalli/TopNV/releases/download/'+self.tag+'/'
        self.sha=env.get('GITHUB_SHA',''); require(re.fullmatch('[0-9a-f]{40}',self.sha),'invalid source SHA')
        self.build=env.get('GITHUB_RUN_NUMBER',''); require(re.fullmatch('[1-9][0-9]{0,9}',self.build),'invalid build')
        self.notes=self.root/'release-notes'/('proof.md' if self.proof else self.version+'.md')
    def releases(self):
        all_releases=[]
        for page in range(1,1001):
            status,rows=self.io.api('GET',f'{REPO}/releases?per_page=100&page={page}')
            require(status==200 and isinstance(rows,list),'cannot list releases, including drafts')
            all_releases+=rows
            if len(rows)<100: return all_releases
        raise ReleaseError('release pagination limit exceeded')
    def existing(self):
        matches=[r for r in self.releases() if r.get('tag_name')==self.tag]
        require(len(matches)<=1,'ambiguous release tag')
        return matches[0] if matches else None
    def tag_commit(self):
        status,data=self.io.api('GET',f'{REPO}/git/ref/tags/{self.tag}')
        if status==404: return None
        require(status==200,'cannot read Git tag')
        obj=data.get('object',{})
        for _ in range(10):
            if obj.get('type')=='commit': return obj.get('sha')
            require(obj.get('type')=='tag' and re.fullmatch('[0-9a-f]{40}',obj.get('sha','')),'invalid Git tag object')
            status,data=self.io.api('GET',f"{REPO}/git/tags/{obj['sha']}")
            require(status==200,'cannot peel annotated tag'); obj=data.get('object',{})
        raise ReleaseError('annotated tag chain too deep')
    def source(self):
        require(self.io.git('rev-parse','HEAD')==self.sha,'checkout differs from requested SHA')
        event=self.env.get('GITHUB_EVENT_NAME'); ref=self.env.get('GITHUB_REF')
        commit=self.tag_commit()
        require(commit is None or commit==self.sha,'tag points to another commit')
        if self.proof:
            require(event=='workflow_dispatch' and ref=='refs/tags/update-proof' and commit==self.sha,'proof requires exact reviewed tag commit')
        else:
            require((event=='workflow_dispatch' and ref=='refs/heads/main') or (event=='push' and ref=='refs/tags/'+self.tag and commit==self.sha),'stable source ref is not authorized')
            self.io.git('merge-base','--is-ancestor',self.sha,'origin/main')
    def resolve(self):
        self.source()
        if not self.proof:
            require(self.existing() is None,'stable release already exists, including draft')
            require(not any(r.get('draft') and r.get('tag_name')!='update-proof' for r in self.releases()),'residual stable draft must be recovered first')
        try: require(bool(self.notes.read_text().strip()),'empty release notes')
        except OSError: raise ReleaseError('missing release notes') from None
        (self.root/'build').mkdir(exist_ok=True)
        output=self.env.get('GITHUB_OUTPUT')
        if output:
            with open(output,'a') as f:
                for k,v in [('version',self.version),('tag',self.tag),('feed',self.feed),('prefix',self.prefix),('notes',str(self.notes))]: f.write(k+'='+v+'\n')
    def order(self):
        (self.root/'build').mkdir(exist_ok=True)
        current=self.root/'build/current.xml'
        status=self.io.download(self.feed,current)
        if status==404:
            if self.proof: require(self.existing() is None,'proof feed missing on existing release')
            else:
                code,latest=self.io.api('GET',REPO+'/releases/latest')
                require(code==200 and latest.get('tag_name')=='v1.0.0' and not any(a.get('name')=='appcast.xml' for a in latest.get('assets',[])),'missing feed is not legacy bootstrap')
            current=None
        else: require(status==200,'feed download failed')
        self.io.order(self.build,self.version,current)
    def rollback(self):
        if self.release_id is None: return
        status,_=self.io.api('PATCH',f'{REPO}/releases/{self.release_id}',{'draft':True})
        require(status==200,'rollback failed')
    def publish(self):
        try:
            self.resolve(); self.order() # Recheck sources, references and old proof before any mutation.
            existing=self.existing()
            require(self.proof or existing is None,'stable release already exists')
            dmg=self.root/f'build/TopNV-{self.version}.dmg'; feed=self.root/'build/appcast.xml'
            require(dmg.is_file() and feed.is_file(),'verified assets missing')
            self.io.verify(dmg,feed,self)
            body={'tag_name':self.tag,'target_commitish':self.sha,'name':'TopNV update proof' if self.proof else 'TopNV '+self.version,'draft':True,'prerelease':self.proof,'make_latest':'false' if self.proof else 'true',
                  'body':self.notes.read_text()+'\n\nDownload the DMG and copy TopNV to Applications. Requires macOS 14+. The app uses an ad hoc signature. On first launch use System Settings > Privacy & Security > Open Anyway.\n'}
            if existing:
                self.release_id=existing['id']; self.record()
                status,_=self.io.api('PATCH',f'{REPO}/releases/{self.release_id}',body); require(status==200,'cannot draft proof')
                for asset in existing.get('assets',[]):
                    status,_=self.io.api('DELETE',f"{REPO}/releases/assets/{asset['id']}"); require(status==204,'cannot remove old proof asset')
            else:
                status,release=self.io.api('POST',REPO+'/releases',body)
                require(status==201 and isinstance(release.get('id'),int),'cannot create draft')
                self.release_id=release['id']; self.record()
            downloaded={}
            for path in [dmg,feed]:
                status,asset=self.io.api('POST',f'https://uploads.github.com/{REPO}/releases/{self.release_id}/assets?name={path.name}',file=path)
                require(status==201 and isinstance(asset.get('id'),int),'asset upload failed')
                status,content=self.io.api('GET',f"{REPO}/releases/assets/{asset['id']}",binary=True)
                require(status==200 and content==path.read_bytes(),'draft asset differs from local artifact')
                saved=self.root/'build'/('downloaded-'+path.name); saved.write_bytes(content); downloaded[path.name]=saved
            self.io.verify(downloaded[dmg.name],downloaded[feed.name],self)
            self.source() # Tag may have changed while uploading.
            self.publishing=True # Before PATCH: a lost response may still have published.
            status,_=self.io.api('PATCH',f'{REPO}/releases/{self.release_id}',{'draft':False,'prerelease':self.proof,'make_latest':'false' if self.proof else 'true'})
            require(status==200,'publish failed or response lost')
            for path in [feed,dmg]:
                fetched=self.root/'build'/('public-'+path.name)
                for attempt in range(3):
                    try:
                        status=self.io.download(self.prefix+path.name,fetched)
                        if status==200 and fetched.read_bytes()==path.read_bytes(): break
                    except (ReleaseError,OSError): pass
                    if attempt<2: time.sleep(1)
                else: raise ReleaseError('public readback differs or unavailable')
            if not self.proof: require(self.tag_commit()==self.sha,'stable tag changed after publication')
            self.publishing=False
        except BaseException as error:
            try: self.rollback()
            except BaseException:
                raise ReleaseError(f'public state indeterminate for release ID {self.release_id}; recovery failed') from None
            if isinstance(error,ReleaseError): raise
            raise ReleaseError('release interrupted or failed; draft recovery attempted') from None
    def recover(self):
        path=self.root/'build/release-transaction.json'
        if not path.exists(): return
        record=json.loads(path.read_text())
        require(record.get('run_id')==self.env.get('GITHUB_RUN_ID') and record.get('sha')==self.sha and record.get('tag')==self.tag, 'recovery record does not belong to this run')
        self.release_id=record['release_id']
        require(isinstance(self.release_id,int),'invalid recovery ID')
        try: self.rollback()
        except BaseException: raise ReleaseError(f'public state indeterminate for release ID {self.release_id}; recovery failed') from None
    def record(self):
        record={'release_id':self.release_id,'run_id':self.env.get('GITHUB_RUN_ID'),'sha':self.sha,'tag':self.tag}
        (self.root/'build/release-transaction.json').write_text(json.dumps(record)+'\n')
        print(f"Release ID {self.release_id}; run {record['run_id']}",flush=True)

def main():
    root=Path(__file__).resolve().parent.parent
    def interrupted(signum,frame): raise ReleaseError('release interrupted')
    for signum in (signal.SIGTERM,signal.SIGINT,signal.SIGHUP): signal.signal(signum,interrupted)
    try:
        require(len(sys.argv)==2 and sys.argv[1] in ('resolve','order','publish','recover'),'expected resolve, order, publish or recover')
        publisher=Publisher(root,os.environ,Transport(root)); getattr(publisher,sys.argv[1])()
    except (ReleaseError,OSError,ValueError,KeyError) as error:
        print('error: '+str(error),file=sys.stderr); return 1
    return 0

if __name__=='__main__': sys.exit(main())

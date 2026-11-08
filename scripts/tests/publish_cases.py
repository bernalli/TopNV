"""Test the same Publisher orchestration used by the workflow with a fake transport."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('publisher',ROOT/'scripts/publish-release.py')
module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)

class Fake:
    def __init__(self):
        self.releases=[]; self.tag=None; self.sha='a'*40; self.events=[]; self.fail=None; self.public=False; self.downloads={}; self.status=404
        self.latest={'tag_name':'v1.0.0','assets':[]}; self.order_failed=False; self.different=None; self.rollback_fails=False
    def git(self, *args):
        if args[0]=='rev-parse': return self.sha
        return ''
    def api(self, method, path, body=None, file=None, binary=False):
        self.events.append((method,path,body))
        if method=='GET' and '/git/ref/tags/' in path:
            return (404,{}) if self.tag is None else (200, {'object':self.tag})
        if method=='GET' and '/git/tags/' in path: return 200,{'object':{'type':'commit','sha':self.sha}}
        if method=='GET' and path.endswith('/releases/latest'): return 200,self.latest
        if method=='GET' and '/releases?per_page=' in path: return 200,self.releases
        if method=='POST' and path.endswith('/releases'):
            assert body['draft'] is True and body['target_commitish']==self.sha
            self.releases=[dict(body,id=5,assets=[])]
            if self.fail=='create': raise module.ReleaseError('injected create failure')
            return 201,self.releases[0]
        if method=='PATCH':
            if body.get('draft'):
                if self.rollback_fails: raise module.ReleaseError('rollback failed')
                self.public=False
            else:
                self.public=True
                if self.tag is None: self.tag={'type':'commit','sha':self.sha}
            if self.fail=='interrupt' and self.public: raise KeyboardInterrupt()
            if self.fail=='publish' and self.public: raise module.ReleaseError('injected publish response loss')
            return 200,dict(id=5,**body)
        if method=='POST' and '/assets?' in path:
            name=path.split('name=')[1]
            assert not self.public
            if self.fail==name: raise module.ReleaseError('upload failed')
            asset_id=len(self.downloads)+1; self.downloads[asset_id]=Path(file).read_bytes()
            return 201,{'id':asset_id}
        if method=='GET' and '/releases/assets/' in path:
            result=self.downloads[int(path.rsplit('/',1)[1])]
            return 200,result+b'bad' if self.different=='private' else result
        if method=='DELETE': return 204,{}
        raise AssertionError((method,path,body))
    def download(self,url,path):
        if self.fail=='transport': raise module.ReleaseError('transport error')
        if not self.public:
            if self.status==200: Path(path).write_bytes(b'current')
            return self.status
        name=url.rsplit('/',1)[1]
        content=b'feed' if name=='appcast.xml' else b'dmg'
        if self.different=='public': content+=b'bad'
        Path(path).write_bytes(content)
        if self.fail=='tag-after': self.tag={'type':'commit','sha':'b'*40}
        return 200
    def order(self,build,version,current):
        if self.order_failed: raise module.ReleaseError('bad current feed')
    def verify(self,*args):
        if self.fail=='verify': raise module.ReleaseError('invalid downloaded feed')

class Cases(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(dir=ROOT/'.work-evidence'); self.root=Path(self.temp.name)
        (self.root/'release-notes').mkdir(); (self.root/'release-notes/1.1.0.md').write_text('Notes'); (self.root/'release-notes/proof.md').write_text('Proof')
        self.env={'GITHUB_EVENT_NAME':'workflow_dispatch','GITHUB_REF':'refs/heads/main','GITHUB_SHA':'a'*40,'INPUT_VERSION':'1.1.0','INPUT_CHANNEL':'stable','GITHUB_RUN_NUMBER':'2','GITHUB_RUN_ID':'7'}
        self.transport=Fake()
    def tearDown(self): self.temp.cleanup()
    def publisher(self): return module.Publisher(self.root,self.env,self.transport)
    def prepared(self):
        p=self.publisher(); p.resolve(); p.order()
        (self.root/'build/TopNV-1.1.0.dmg').write_bytes(b'dmg'); (self.root/'build/appcast.xml').write_bytes(b'feed')
        return p
    def test_clean_checkout_and_stable_publish(self):
        p=self.prepared(); p.publish(); self.assertTrue(self.transport.public)
    def test_source_and_release_guards(self):
        for changes in [{'GITHUB_REF':'refs/heads/other'},{'INPUT_CHANNEL':'other'},{'INPUT_CHANNEL':'proof','GITHUB_EVENT_NAME':'push'},{'INPUT_VERSION':'1.1.0\n'}]:
            with self.subTest(changes=changes):
                old=dict(self.env); self.env.update(changes)
                with self.assertRaises(module.ReleaseError): self.publisher().resolve()
                self.env=old
        for draft in [False,True]:
            self.transport.releases=[{'tag_name':'v1.1.0','draft':draft,'id':9}]
            with self.assertRaises(module.ReleaseError): self.publisher().resolve()
        self.transport.releases=[]
        (self.root/'release-notes/1.1.0.md').unlink()
        with self.assertRaises(module.ReleaseError): self.publisher().resolve()
    def test_tags(self):
        for tag in [None,{'type':'commit','sha':'a'*40},{'type':'tag','sha':'c'*40}]:
            self.transport.tag=tag; self.publisher().resolve()
        self.transport.tag={'type':'commit','sha':'b'*40}
        with self.assertRaises(module.ReleaseError): self.publisher().resolve()
        self.transport.tag=None; p=self.prepared(); self.transport.tag={'type':'commit','sha':'b'*40}
        with self.assertRaises(module.ReleaseError): p.publish()
        self.assertFalse(self.transport.public)
    def test_http_bootstrap_matrix(self):
        for status in [403,500]:
            self.transport.status=status
            with self.assertRaises(module.ReleaseError): self.publisher().order()
        self.transport.status=404; self.transport.latest={'tag_name':'v1.1.0','assets':[]}
        with self.assertRaises(module.ReleaseError): self.publisher().order()
        self.transport.latest={'tag_name':'v1.0.0','assets':[{'name':'appcast.xml'}]}
        with self.assertRaises(module.ReleaseError): self.publisher().order()
        self.transport.status=200; self.transport.order_failed=True
        with self.assertRaises(module.ReleaseError): self.publisher().order()
        self.transport.order_failed=False; self.transport.fail='transport'
        with self.assertRaises(module.ReleaseError): self.publisher().order()
    def test_failures_never_leave_public_release(self):
        for failure in ['TopNV-1.1.0.dmg','appcast.xml','verify','publish','tag-after','interrupt']:
            with self.subTest(failure=failure):
                self.transport=Fake(); p=self.prepared(); self.transport.fail=failure
                with self.assertRaises(module.ReleaseError): p.publish()
                self.assertFalse(self.transport.public)
        for where in ['private','public']:
            self.transport=Fake(); p=self.prepared(); self.transport.different=where
            with self.assertRaises(module.ReleaseError): p.publish()
            self.assertFalse(self.transport.public)
    def test_recovery_only_owns_this_run(self):
        p=self.prepared(); p.publish(); p.recover(); self.assertFalse(self.transport.public)
        self.env['GITHUB_RUN_ID']='other'
        with self.assertRaises(module.ReleaseError): self.publisher().recover()
    def test_rollback_failure_remains_error(self):
        p=self.prepared(); self.transport.fail='publish'; self.transport.rollback_fails=True
        with self.assertRaisesRegex(module.ReleaseError,'indeterminate.*5'): p.publish()
    def test_proof_is_explicit_draft_and_not_latest(self):
        self.env.update(INPUT_CHANNEL='proof',GITHUB_REF='refs/tags/update-proof')
        self.transport.tag={'type':'commit','sha':'a'*40}
        p=self.prepared(); p.publish()
        body=[body for method,path,body in self.transport.events if method=='PATCH' and body.get('draft') is False][0]
        self.assertTrue(body['prerelease']); self.assertEqual(body['make_latest'],'false')
    def test_proof_404_rejects_existing_draft(self):
        self.env.update(INPUT_CHANNEL='proof',GITHUB_REF='refs/tags/update-proof')
        self.transport.releases=[{'tag_name':'update-proof','draft':True,'id':5}]
        with self.assertRaises(module.ReleaseError): self.publisher().order()

unittest.main()

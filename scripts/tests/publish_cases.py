"""Test the same Publisher orchestration used by the workflow with a fake transport."""
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('publisher',ROOT/'scripts/publish-release.py')
module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)

class Fake:
    def __init__(self):
        self.releases=[]; self.tag=None; self.sha='a'*40; self.events=[]; self.fail=None; self.public=False; self.downloads={}; self.status=404
        self.api_status=None; self.api_transport=False; self.deleted=[]; self.off_main=False; self.peeled=None
        self.latest={'tag_name':'v1.0.0','assets':[]}; self.order_failed=False; self.different=None; self.rollback_fails=False
        self.response_tag=None; self.public_delay=0; self.public_statuses=[]
    def git(self, *args):
        if args[0]=='merge-base' and self.off_main: raise module.ReleaseError('Git source validation failed')
        if args[0]=='rev-parse': return self.sha
        return ''
    def api(self, method, path, body=None, file=None, binary=False):
        self.events.append((method,path,body))
        if self.api_transport: raise module.ReleaseError('API transport failed')
        if self.api_status is not None: return self.api_status,{}
        if method=='GET' and '/git/ref/tags/' in path:
            return (404,{}) if self.tag is None else (200, {'object':self.tag})
        if method=='GET' and '/git/tags/' in path: return 200,{'object':{'type':'commit','sha':self.peeled or self.sha}}
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
            if self.fail=='draft' and body.get('draft'): raise module.ReleaseError('draft response lost')
            if self.fail=='publish' and self.public: raise module.ReleaseError('injected publish response loss')
            release=next(r for r in self.releases if path.endswith(f"/releases/{r['id']}"))
            # GitHub detaches the tag when an edit omits tag_name (live run 42518681929).
            release.update(body); release['tag_name']=body.get('tag_name','untagged-eb031defd646332f7d14')
            if self.response_tag and body.get('draft') is False: return 200,dict(release,tag_name=self.response_tag)
            return 200,dict(release)
        if method=='POST' and '/assets?' in path:
            name=path.split('name=')[1]
            assert not self.public
            if self.fail==name: raise module.ReleaseError('upload failed')
            if self.fail=='tag-moves' and name=='appcast.xml': self.tag={'type':'commit','sha':'b'*40}
            asset_id=len(self.downloads)+1; self.downloads[asset_id]=Path(file).read_bytes()
            return 201,{'id':asset_id}
        if method=='GET' and '/releases/assets/' in path:
            result=self.downloads[int(path.rsplit('/',1)[1])]
            return 200,result+b'bad' if self.different=='private' else result
        if method=='DELETE':
            self.deleted.append(path)
            if self.fail=='delete': raise module.ReleaseError('delete response lost')
            return 204,{}
        raise AssertionError((method,path,body))
    def download(self,url,path):
        if self.fail=='transport': raise module.ReleaseError('transport error')
        if not self.public:
            if self.status==200: Path(path).write_bytes(b'current')
            return self.status
        tag,name=url.rsplit('/',2)[1:]
        if not any(r.get('tag_name')==tag and not r.get('draft') for r in self.releases): return 404
        if self.public_delay>0:
            self.public_delay-=1; self.public_statuses.append(404); return 404
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
        self.temp=tempfile.TemporaryDirectory(dir=ROOT/'build/test-tmp'); self.root=Path(self.temp.name)
        (self.root/'release-notes').mkdir(); (self.root/'release-notes/1.1.0.md').write_text('Notes'); (self.root/'release-notes/proof.md').write_text('Proof')
        self.env={'GITHUB_EVENT_NAME':'workflow_dispatch','GITHUB_REF':'refs/heads/main','GITHUB_SHA':'a'*40,'INPUT_VERSION':'1.1.0','INPUT_CHANNEL':'stable','GITHUB_RUN_NUMBER':'2','GITHUB_RUN_ID':'7'}
        self.transport=Fake()
        sleep=mock.patch.object(module.time,'sleep'); self.sleep=sleep.start(); self.addCleanup(sleep.stop)
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
        for failure in ['create','TopNV-1.1.0.dmg','appcast.xml','verify','publish','tag-after','interrupt']:
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
    def test_api_errors_never_mean_absence(self):
        for status in [403,500]:
            self.transport.api_status=status
            with self.assertRaises(module.ReleaseError): self.publisher().resolve()
        self.transport.api_status=None; self.transport.api_transport=True
        with self.assertRaises(module.ReleaseError): self.publisher().resolve()
    def test_push_requires_exact_canonical_tag_and_checkout(self):
        self.env.update(GITHUB_EVENT_NAME='push',GITHUB_REF='refs/tags/v1.1.0')
        with self.assertRaises(module.ReleaseError): self.publisher().resolve()
        self.transport.tag={'type':'commit','sha':'a'*40}; self.publisher().resolve()
        self.transport.sha='b'*40
        with self.assertRaises(module.ReleaseError): self.publisher().resolve()
    def test_existing_proof_is_drafted_before_asset_replacement(self):
        self.env.update(INPUT_CHANNEL='proof',GITHUB_REF='refs/tags/update-proof')
        self.transport.tag={'type':'commit','sha':'a'*40}; self.transport.status=200
        self.transport.releases=[{'id':5,'tag_name':'update-proof','draft':False,'assets':[{'id':8},{'id':9}]}]
        p=self.prepared(); p.publish()
        self.assertEqual(len(self.transport.deleted),2)
        mutations=[(method,body) for method,path,body in self.transport.events if method!='GET']
        self.assertEqual(mutations[0][0],'PATCH'); self.assertTrue(mutations[0][1]['draft'])
        self.assertTrue(self.transport.public)
    def test_failure_after_proof_mutations_preserves_failure(self):
        self.env.update(INPUT_CHANNEL='proof',GITHUB_REF='refs/tags/update-proof')
        for failure in ['draft','delete']:
            self.transport=Fake(); self.transport.tag={'type':'commit','sha':'a'*40}; self.transport.status=200
            self.transport.releases=[{'id':5,'tag_name':'update-proof','draft':False,'assets':[{'id':8}]}]
            p=self.prepared(); self.transport.fail=failure
            with self.assertRaises(module.ReleaseError): p.publish()
            self.assertFalse(self.transport.public)
    def test_failed_stable_draft_blocks_rerun(self):
        p=self.prepared(); self.transport.fail='appcast.xml'
        with self.assertRaises(module.ReleaseError): p.publish()
        self.transport.fail=None
        with self.assertRaises(module.ReleaseError): self.publisher().resolve()
    def test_stable_requires_commit_on_main(self):
        for changes in [{},{'GITHUB_EVENT_NAME':'push','GITHUB_REF':'refs/tags/v1.1.0'}]:
            with self.subTest(changes=changes):
                self.env.update(changes); self.transport.tag={'type':'commit','sha':'a'*40}; self.transport.off_main=True
                with self.assertRaises(module.ReleaseError): self.publisher().resolve()
    def test_proof_requires_its_exact_tag(self):
        self.env.update(INPUT_CHANNEL='proof')
        self.transport.tag={'type':'commit','sha':'a'*40}
        with self.assertRaises(module.ReleaseError): self.publisher().resolve()
        self.env.update(GITHUB_REF='refs/tags/update-proof'); self.transport.tag=None
        with self.assertRaises(module.ReleaseError): self.publisher().resolve()
    def test_annotated_tag_peels_to_the_built_commit(self):
        self.transport.tag={'type':'tag','sha':'c'*40}; self.transport.peeled='b'*40
        with self.assertRaises(module.ReleaseError): self.publisher().resolve()
    def test_tag_moved_during_upload_blocks_publication(self):
        p=self.prepared(); self.transport.fail='tag-moves'
        with self.assertRaises(module.ReleaseError): p.publish()
        self.assertFalse(any(m=='PATCH' and b.get('draft') is False for m,_,b in self.transport.events))
    def test_any_residual_stable_draft_blocks(self):
        self.transport.releases=[{'tag_name':'v1.0.9','draft':True,'id':9}]
        with self.assertRaises(module.ReleaseError): self.publisher().resolve()
    def test_proof_404_rejects_existing_draft(self):
        self.env.update(INPUT_CHANNEL='proof',GITHUB_REF='refs/tags/update-proof')
        self.transport.releases=[{'tag_name':'update-proof','draft':True,'id':5}]
        with self.assertRaises(module.ReleaseError): self.publisher().order()
    def proof(self):
        self.env.update(INPUT_CHANNEL='proof',GITHUB_REF='refs/tags/update-proof')
        self.transport.tag={'type':'commit','sha':'a'*40}
    def test_publication_keeps_the_release_on_its_tag(self):
        self.proof(); p=self.prepared(); p.publish()
        self.assertTrue(self.transport.public); self.assertEqual(self.transport.releases[0]['tag_name'],'update-proof')
        for method,path,body in self.transport.events:
            if method=='PATCH': self.assertEqual(body['tag_name'],'update-proof')
    def test_rollback_keeps_the_draft_on_its_tag(self):
        self.proof(); p=self.prepared(); self.transport.fail='publish'
        with self.assertRaises(module.ReleaseError): p.publish()
        self.assertFalse(self.transport.public); self.assertEqual(self.transport.releases[0]['tag_name'],'update-proof')
    def test_publish_response_on_another_tag_is_rolled_back(self):
        self.proof(); p=self.prepared(); self.transport.response_tag='untagged-0'
        with self.assertRaisesRegex(module.ReleaseError,'tag'): p.publish()
        self.assertFalse(self.transport.public)
    def test_public_readback_waits_for_propagation(self):
        self.proof(); p=self.prepared(); self.transport.public_delay=5
        p.publish()
        self.assertTrue(self.transport.public); self.assertEqual(self.transport.public_statuses,[404]*5)
    def test_public_readback_gives_up_and_rolls_back(self):
        self.proof(); p=self.prepared(); self.transport.public_delay=100
        with self.assertRaisesRegex(module.ReleaseError,'public readback'): p.publish()
        self.assertFalse(self.transport.public)

class RealTransport(unittest.TestCase):
    def api(self,script,**options):
        with tempfile.TemporaryDirectory(dir=ROOT/'build/test-tmp') as tmp:
            gh=Path(tmp)/'gh'; gh.write_text('#!/bin/bash\n'+script+'\n'); gh.chmod(0o755)
            saved=os.environ['PATH']; os.environ['PATH']=tmp+':'+saved
            try: return module.Transport(Path(tmp)).api('GET','repos/x',**options)
            finally: os.environ['PATH']=saved
    def test_status_and_body_survive_the_real_parser(self):
        self.assertEqual(self.api("printf 'HTTP/2.0 200 OK\\nA: b\\r\\n\\r\\n{\"k\":1}'"),(200,{'k':1}))
        self.assertEqual(self.api("printf 'HTTP/2.0 404 Not Found\\nA: b\\r\\n\\r\\n{}'; exit 1"),(404,{}))
        self.assertEqual(self.api("printf 'HTTP/2.0 403 Forbidden\\nA: b\\r\\n\\r\\n{}'; exit 1")[0],403)
        self.assertEqual(self.api("printf 'HTTP/2.0 204 No Content\\nA: b\\r\\n\\r\\n'"),(204,{}))
        self.assertEqual(self.api("printf 'HTTP/2.0 200 OK\\nA: b\\r\\n\\r\\n\\xff\\x00'",binary=True),(200,b'\xff\x00'))
    def test_transport_failures_never_become_a_status(self):
        for script in ['exit 1',"printf 'garbage'; exit 1","printf 'HTTP/2.0 200 OK\\nA: b\\r\\n\\r\\n{}'; exit 1","printf 'HTTP/2.0 200 OK\\nA: b\\r\\n\\r\\nnot json'"]:
            with self.subTest(script=script):
                with self.assertRaises(module.ReleaseError): self.api(script)

unittest.main()

"""Exercise input guards before any destructive/build operation and verifier mutations."""
import base64
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parents[2]

def run_tests(kind):
    with tempfile.TemporaryDirectory(prefix='bundle-', dir=REPO / 'build/test-tmp') as tmp:
        root = Path(tmp)
        for name in ('AUTHORS', 'LICENSE'):
            shutil.copy2(REPO / name, root / name)
        shutil.copytree(REPO / 'Licenses', root / 'Licenses')
        shutil.copytree(REPO / 'Assets', root / 'Assets')
        public = root / 'Assets/SparklePublicEDKey.txt'
        public.write_text(base64.b64encode(bytes(32)).decode() + '\n')
        app = root / 'build/TopNV.app'
        app.mkdir(parents=True)
        sentinel = app / 'sentinel'
        sentinel.write_text('original')
        env = dict(os.environ, TOPNV_TEST_ROOT=str(root), TOPNV_EXECUTABLE=str(root / 'missing'))
        for name in ('TOPNV_VERSION', 'TOPNV_BUILD_NUMBER', 'TOPNV_FEED_URL'):
            env.pop(name, None)
        def bundle(**values):
            return subprocess.run(['bash', str(REPO / 'scripts/bundle.sh')], env=dict(env, **values), capture_output=True)
        def rejected(**values):
            result = bundle(**values)
            assert result.returncode != 0 and result.stderr, result
            assert sentinel.read_text() == 'original'
            assert b'error:' in result.stderr
            assert b'executable' not in result.stderr, result.stderr
        if kind == 'inputs':
            for value in ('', '1', '1.0', 'v1.0.0', '1.0.0-beta', '1.0.0\n', '9223372036854775808.0.0'):
                rejected(TOPNV_VERSION=value)
            for value in ('', '0', '-1', '1.5', 'x', '10000000000', '1\n'):
                rejected(TOPNV_BUILD_NUMBER=value)
            for value in ('', 'http://github.com/bernalli/TopNV/releases/latest/download/appcast.xml',
                          'https://github.com/bernalli/topNV/releases/latest/download/appcast.xml',
                          'https://evil.test/bernalli/TopNV/releases/latest/download/appcast.xml',
                          'https://github.com/bernalli/TopNV/releases/download/v1.1.0/appcast.xml',
                          'https://github.com/bernalli/TopNV/releases/latest/download/appcast.xml?x=1'):
                rejected(TOPNV_FEED_URL=value)
            original = public.read_bytes()
            for value in (b'', b'!', base64.b64encode(bytes(31)), base64.b64encode(bytes(33)), b' ' + original):
                public.write_bytes(value); rejected()
            public.unlink(); rejected(); public.write_bytes(original)
            for name in ('LICENSE', 'Licenses/Sparkle.txt'):
                path = root / name; saved = path.read_bytes()
                path.write_bytes(saved + b'!'); rejected()
                path.unlink(); rejected(); path.write_bytes(saved)
            result = bundle()
            assert b'executable' in result.stderr, result.stderr
            print('PASS bundle input matrix; rejected inputs preserve original app')
            return
        # Platform operations are replaced at the command boundary; plist and filesystem checks are real.
        bindir = root / 'bin'; bindir.mkdir()
        responses = {'plutil': 'exit 0', 'otool': 'echo "          path @executable_path/../Frameworks (offset 12)"',
                     'codesign': 'echo "Signature=adhoc" >&2', 'lipo': 'echo "arm64 x86_64"'}
        for name, script in responses.items():
            p = bindir / name; p.write_text('#!/bin/bash\n' + script + '\n'); p.chmod(0o755)
        env['PATH'] = str(bindir) + ':' + env['PATH']
        env['TOPNV_EXPECT_UNIVERSAL'] = '1'
        contents = app / 'Contents'
        (contents / 'MacOS').mkdir(parents=True)
        (contents / 'MacOS/TopNV').write_text('fixture')
        licenses = contents / 'Resources/Licenses'; licenses.mkdir(parents=True)
        shutil.copy(root / 'LICENSE', licenses / 'TopNV.txt')
        shutil.copy(root / 'Licenses/Sparkle.txt', licenses / 'Sparkle.txt')
        framework = contents / 'Frameworks/Sparkle.framework'; version = framework / 'Versions/B'; version.mkdir(parents=True)
        (framework / 'Versions/Current').symlink_to('B')
        for name in ('Sparkle', 'Autoupdate', 'Updater.app', 'XPCServices', 'Resources', 'Headers', 'Modules', 'PrivateHeaders'):
            if name in ('Sparkle', 'Autoupdate'): (version / name).write_text('fixture')
            else: (version / name).mkdir()
            (framework / name).symlink_to('Versions/Current/' + name)
        fplist = version / 'Resources/Info.plist'
        fplist.write_bytes(plistlib.dumps({'CFBundleShortVersionString': '2.10.1'}))
        plist = dict(CFBundleIdentifier='io.github.bernalli.topnv', CFBundleShortVersionString='1.1.0', CFBundleVersion='2',
                     LSMinimumSystemVersion='14.0', LSUIElement=True, SUFeedURL='https://github.com/bernalli/TopNV/releases/latest/download/appcast.xml',
                     SUPublicEDKey=original.decode().strip() if 'original' in locals() else public.read_text().strip(),
                     SUEnableAutomaticChecks=False, SUAllowsAutomaticUpdates=False, SUVerifyUpdateBeforeExtraction=True,
                     NSHumanReadableCopyright='Copyright (c) 2026 ' + (root / 'AUTHORS').read_text().splitlines()[0])
        info = contents / 'Info.plist'
        def verify(expected=None):
            result = subprocess.run(['bash', str(REPO / 'scripts/verify-bundle.sh'), str(app)], env=env, capture_output=True)
            if expected: assert result.returncode == 1 and expected.encode() in result.stdout + result.stderr, result
            else: assert result.returncode == 0, result
        info.write_bytes(plistlib.dumps(plist)); verify()
        for field, code in [('SUFeedURL','V1'), ('SUPublicEDKey','V2'), ('SUEnableAutomaticChecks','V3'),
                            ('SUAllowsAutomaticUpdates','V3'), ('SUVerifyUpdateBeforeExtraction','V3'),
                            ('CFBundleVersion','V4'), ('LSMinimumSystemVersion','V4'), ('NSHumanReadableCopyright','V13')]:
            changed = dict(plist); del changed[field]; info.write_bytes(plistlib.dumps(changed)); verify(code)
        for value in (0, 1, 'false', True):
            changed = dict(plist, SUEnableAutomaticChecks=value); info.write_bytes(plistlib.dumps(changed)); verify('V3')
        for changes, code in [({'SUFeedURL': 'https://github.com/bernalli/TopNV/releases/download/update-proof/appcast.xml'}, 'V1'),
                              ({'LSUIElement': False}, 'V1'), ({'SURequireSignedFeed': True}, 'V1'),
                              ({'SUEnableInstallerLauncherService': True}, 'V1'), ({'SUEnableDownloaderService': True}, 'V1'),
                              ({'SUEnableInstallerConnectionService': True}, 'V1'), ({'SUEnableInstallerStatusService': True}, 'V1'),
                              ({'SUPublicEDKey': base64.b64encode(b'\x01' * 32).decode()}, 'V2'),
                              ({'SUVerifyUpdateBeforeExtraction': False}, 'V3'), ({'CFBundleIdentifier': 'example.other'}, 'V4'),
                              ({'CFBundleShortVersionString': '1.1'}, 'V4'), ({'CFBundleVersion': '0'}, 'V4'),
                              ({'LSMinimumSystemVersion': '13.0'}, 'V4')]:
            info.write_bytes(plistlib.dumps(dict(plist, **changes))); verify(code)
        info.write_bytes(plistlib.dumps(dict(plist, NSHumanReadableCopyright='All rights reserved'))); verify('V13')
        info.write_bytes(plistlib.dumps(plist))
        for name in ('Current', 'Sparkle', 'Autoupdate', 'Updater.app', 'XPCServices', 'Resources', 'Headers', 'Modules', 'PrivateHeaders'):
            p = framework / ('Versions/Current' if name == 'Current' else name); dest = os.readlink(p)
            p.unlink(); p.symlink_to('missing'); verify('V6'); p.unlink(); p.symlink_to(dest)
        fplist.write_bytes(plistlib.dumps({'CFBundleShortVersionString': '0'})); verify('V5')
        fplist.write_bytes(plistlib.dumps({'CFBundleShortVersionString': '2.10.1'}))
        for name,code in [('TopNV.txt','V12'),('Sparkle.txt','V11')]:
            p=licenses/name; old=p.read_bytes(); p.write_bytes(b'changed'); verify(code); p.write_bytes(old)
        for name, script, code in [('otool','exit 0','V7'),('codesign','exit 1','V8'),('codesign','echo "flags=0x10000(runtime)" >&2','V9'),('lipo','echo arm64','V10'),('plutil','exit 1','V0')]:
            (bindir/name).write_text('#!/bin/bash\n'+script+'\n'); verify(code)
            (bindir/name).write_text('#!/bin/bash\n'+responses[name]+'\n')
        verify(); print('PASS verifier V0-V13 mutations')

run_tests(sys.argv[1])

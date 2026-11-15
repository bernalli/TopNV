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
LANGUAGES = ['en', 'it', 'es', 'fr', 'de', 'pt-BR', 'ja', 'zh-Hans']

def run_tests(kind):
    with tempfile.TemporaryDirectory(prefix='bundle-', dir=REPO / 'build/test-tmp') as tmp:
        root = Path(tmp)
        for name in ('AUTHORS', 'LICENSE'):
            shutil.copy2(REPO / name, root / name)
        shutil.copytree(REPO / 'Licenses', root / 'Licenses')
        shutil.copytree(REPO / 'Assets', root / 'Assets')
        shutil.copytree(REPO / 'Localization', root / 'Localization')
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
            for name in ('LICENSE', 'Licenses/Sparkle.txt', 'Assets/Fonts/PlusJakartaSans-OFL.txt',
                         'Assets/Fonts/PlusJakartaSans-SemiBold.ttf', 'Assets/GitHubMark.pdf'):
                path = root / name; saved = path.read_bytes()
                path.write_bytes(saved + b'!'); rejected()
                path.unlink(); rejected(); path.write_bytes(saved)
            for language in ('it', 'zh-Hans'):
                table = root / 'Localization' / (language + '.lproj') / 'Localizable.strings'
                saved = table.read_bytes()
                table.unlink(); rejected(); table.write_bytes(saved)
            (root / 'Localization/ko.lproj').mkdir(); rejected(); (root / 'Localization/ko.lproj').rmdir()
            result = bundle()
            assert b'executable' in result.stderr, result.stderr
            # A full run with platform tools replaced: every language folder lands in Resources.
            bindir = root / 'bin'; bindir.mkdir()
            for name, script in {'otool': 'echo "          path @executable_path/../Frameworks (offset 12)"',
                                 'codesign': 'exit 0'}.items():
                tool = bindir / name; tool.write_text('#!/bin/bash\n' + script + '\n'); tool.chmod(0o755)
            products = root / 'products'; (products / 'Sparkle.framework').mkdir(parents=True)
            executable = products / 'TopNV'; executable.write_text('#!/bin/bash\n'); executable.chmod(0o755)
            extra = root / 'Localization/it.lproj/AppleStyleUpdateDriver.strings'
            extra.write_text('"Later" = "Più tardi";\n')
            result = bundle(TOPNV_EXECUTABLE=str(executable), PATH=str(bindir) + ':' + env['PATH'])
            assert result.returncode == 0, result
            built = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
            assert built['CFBundleLocalizations'] == LANGUAGES, built.get('CFBundleLocalizations')
            for language in LANGUAGES:
                name = language + '.lproj/Localizable.strings'
                assert (app / 'Contents/Resources' / name).read_bytes() == (root / 'Localization' / name).read_bytes(), name
            assert (app / 'Contents/Resources/it.lproj/AppleStyleUpdateDriver.strings').read_bytes() == extra.read_bytes()
            # The About font with its license, and the vector GitHub mark, land in Resources.
            for source, bundled in [('Assets/Fonts/PlusJakartaSans-SemiBold.ttf', 'PlusJakartaSans-SemiBold.ttf'),
                                    ('Assets/Fonts/PlusJakartaSans-OFL.txt', 'Licenses/PlusJakartaSans-OFL.txt'),
                                    ('Assets/GitHubMark.pdf', 'GitHubMark.pdf')]:
                assert (app / 'Contents/Resources' / bundled).read_bytes() == (REPO / source).read_bytes(), bundled
            assert not list((app / 'Contents/Resources').glob('GitHubMark*.png'))
            # The update window's own tables from the repository land beside Localizable.strings.
            for language in LANGUAGES:
                name = language + '.lproj/AppleStyleUpdateDriver.strings'
                assert (REPO / 'Localization' / name).is_file(), name
                if language != 'it':
                    assert (app / 'Contents/Resources' / name).read_bytes() == (REPO / 'Localization' / name).read_bytes(), name
            # Signing: a recording codesign shows every call, in order, with each argument intact.
            log = root / 'codesign.log'; probe = root / 'build/sign-probe'
            (bindir / 'codesign').write_text('#!/bin/bash\n'
                                             '{ printf "%s\\t" "$@"; printf "\\n"; } >> "$FAKE_CODESIGN_LOG"\n'
                                             'if [[ "${@: -1}" == */sign-probe ]]; then\n'
                                             '  cmp -s "${@: -1}" /usr/bin/true || exit 3\n'
                                             '  [[ -z "${FAKE_PROBE_FAIL:-}" ]] || exit 1\n'
                                             'fi\n')
            def signed(**values):
                log.write_text('')
                result = bundle(**dict(dict(TOPNV_EXECUTABLE=str(executable), PATH=str(bindir) + ':' + env['PATH'],
                                            FAKE_CODESIGN_LOG=str(log)), **values))
                return result, [line.split('\t')[:-1] for line in log.read_text().splitlines()]
            verify_call = ['--verify', '--deep', '--strict', str(app)]
            result, calls = signed()
            assert result.returncode == 0, result
            assert calls == [['--force', '--sign', '-', '--timestamp=none', str(app)], verify_call], calls
            for identity in ('Developer ID Application', 'Developer ID Application: Example Developer (ABCDE12345)'):
                result, calls = signed(TOPNV_SIGN_IDENTITY=identity)
                assert result.returncode == 0, result
                framework = app / 'Contents/Frameworks/Sparkle.framework'; component = framework / 'Versions/B'
                runtime = ['--force', '--sign', identity, '--options', 'runtime', '--timestamp']
                assert calls == [['--force', '--sign', identity, '--timestamp=none', str(probe)],
                                 runtime + [str(component / 'XPCServices/Installer.xpc')],
                                 runtime + ['--preserve-metadata=entitlements', str(component / 'XPCServices/Downloader.xpc')],
                                 runtime + [str(component / 'Autoupdate')],
                                 runtime + [str(component / 'Updater.app')],
                                 runtime + [str(framework)],
                                 runtime + [str(app)],
                                 verify_call], calls
                assert not any(a.startswith(('--deep', '--entitlements')) for call in calls if '--sign' in call for a in call)
                assert not probe.exists()
            # A failed probe stops before the build and before the previous app is removed.
            shutil.rmtree(app); app.mkdir(); sentinel.write_text('original')
            identity = 'Developer ID Application: Example Developer (ABCDE12345)'
            result, calls = signed(TOPNV_SIGN_IDENTITY=identity, FAKE_PROBE_FAIL='1', TOPNV_EXECUTABLE=str(root / 'missing'))
            assert result.returncode == 1, result
            assert (f'error: signing identity "{identity}" not found; install the Developer ID Application '
                    'certificate or set TOPNV_SIGN_IDENTITY').encode() in result.stderr, result.stderr
            assert b'executable' not in result.stderr, result.stderr
            assert calls == [['--force', '--sign', identity, '--timestamp=none', str(probe)]], calls
            assert sentinel.read_text() == 'original' and sorted(p.name for p in app.iterdir()) == ['sentinel']
            assert not probe.exists()
            print('PASS bundle input matrix; rejected inputs preserve original app; languages, About font and mark bundled; signing order')
            return
        # Platform operations are replaced at the command boundary; plist and filesystem checks are real.
        bindir = root / 'bin'; bindir.mkdir()
        responses = {'plutil': 'exit 0', 'otool': 'echo "          path @executable_path/../Frameworks (offset 12)"',
                     'codesign': 'echo "Signature=adhoc" >&2', 'lipo': 'echo "arm64 x86_64"'}
        for name, script in responses.items():
            p = bindir / name; p.write_text('#!/bin/bash\n' + script + '\n'); p.chmod(0o755)
        env['PATH'] = str(bindir) + ':' + env['PATH']
        env['TOPNV_EXPECT_UNIVERSAL'] = '1'
        env['TOPNV_EXPECT_SIGNATURE'] = 'adhoc'
        contents = app / 'Contents'
        (contents / 'MacOS').mkdir(parents=True)
        (contents / 'MacOS/TopNV').write_text('fixture')
        licenses = contents / 'Resources/Licenses'; licenses.mkdir(parents=True)
        shutil.copy(root / 'LICENSE', licenses / 'TopNV.txt')
        shutil.copy(root / 'Licenses/Sparkle.txt', licenses / 'Sparkle.txt')
        shutil.copy(root / 'Assets/Fonts/PlusJakartaSans-OFL.txt', licenses / 'PlusJakartaSans-OFL.txt')
        shutil.copy(root / 'Assets/Fonts/PlusJakartaSans-SemiBold.ttf', contents / 'Resources/PlusJakartaSans-SemiBold.ttf')
        framework = contents / 'Frameworks/Sparkle.framework'; version = framework / 'Versions/B'; version.mkdir(parents=True)
        (framework / 'Versions/Current').symlink_to('B')
        for name in ('Sparkle', 'Autoupdate', 'Updater.app', 'XPCServices', 'Resources', 'Headers', 'Modules', 'PrivateHeaders'):
            if name in ('Sparkle', 'Autoupdate'): (version / name).write_text('fixture')
            else: (version / name).mkdir()
            (framework / name).symlink_to('Versions/Current/' + name)
        resources = contents / 'Resources'
        for language in LANGUAGES:
            folder = resources / (language + '.lproj'); folder.mkdir()
            shutil.copy(root / 'Localization' / (language + '.lproj/Localizable.strings'), folder / 'Localizable.strings')
        # Other tables (the update window's) are allowed beside Localizable.strings.
        (resources / 'it.lproj/AppleStyleUpdateDriver.strings').write_text('"Later" = "Più tardi";\n')
        fplist = version / 'Resources/Info.plist'
        fplist.write_bytes(plistlib.dumps({'CFBundleShortVersionString': '2.10.1'}))
        plist = dict(CFBundleIdentifier='io.github.bernalli.topnv', CFBundleShortVersionString='1.1.0', CFBundleVersion='2',
                     LSMinimumSystemVersion='14.0', LSUIElement=True, SUFeedURL='https://github.com/bernalli/TopNV/releases/latest/download/appcast.xml',
                     SUPublicEDKey=original.decode().strip() if 'original' in locals() else public.read_text().strip(),
                     SUEnableAutomaticChecks=False, SUAllowsAutomaticUpdates=False, SUVerifyUpdateBeforeExtraction=True,
                     NSHumanReadableCopyright='Copyright (c) 2026 ' + (root / 'AUTHORS').read_text().splitlines()[0],
                     CFBundleLocalizations=list(LANGUAGES))
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
        for value in (LANGUAGES[:-1], LANGUAGES + ['ko'], list(reversed(LANGUAGES)), 'en', [], None):
            changed = dict(plist)
            if value is None: del changed['CFBundleLocalizations']
            else: changed['CFBundleLocalizations'] = value
            info.write_bytes(plistlib.dumps(changed)); verify('V15')
        info.write_bytes(plistlib.dumps(plist))
        for language in ('en', 'pt-BR', 'zh-Hans'):
            folder = resources / (language + '.lproj'); table = folder / 'Localizable.strings'; saved = table.read_bytes()
            table.unlink(); verify('V15')
            table.mkdir(); verify('V15'); table.rmdir()
            shutil.rmtree(folder); verify('V15')
            folder.mkdir(); table.write_bytes(saved)
        info.write_bytes(plistlib.dumps(plist))
        for name in ('Current', 'Sparkle', 'Autoupdate', 'Updater.app', 'XPCServices', 'Resources', 'Headers', 'Modules', 'PrivateHeaders'):
            p = framework / ('Versions/Current' if name == 'Current' else name); dest = os.readlink(p)
            p.unlink(); p.symlink_to('missing'); verify('V6'); p.unlink(); p.symlink_to(dest)
        fplist.write_bytes(plistlib.dumps({'CFBundleShortVersionString': '0'})); verify('V5')
        fplist.write_bytes(plistlib.dumps({'CFBundleShortVersionString': '2.10.1'}))
        for name,code in [('TopNV.txt','V12'),('Sparkle.txt','V11'),('PlusJakartaSans-OFL.txt','V17')]:
            p=licenses/name; old=p.read_bytes(); p.write_bytes(b'changed'); verify(code); p.write_bytes(old)
            p.unlink(); verify(code); p.write_bytes(old)
        font = contents / 'Resources/PlusJakartaSans-SemiBold.ttf'; old = font.read_bytes()
        font.write_bytes(old + b'!'); verify('V16'); font.unlink(); verify('V16'); font.write_bytes(old); verify()
        for name, script, code in [('otool','exit 0','V7'),('codesign','exit 1','V8'),('codesign','echo "flags=0x10000(runtime)" >&2','V9'),('lipo','echo arm64','V10'),('plutil','exit 1','V0')]:
            (bindir/name).write_text('#!/bin/bash\n'+script+'\n'); verify(code)
            (bindir/name).write_text('#!/bin/bash\n'+responses[name]+'\n')
        # A long listing must not turn an early grep match into a false failure under pipefail.
        (bindir/'otool').write_text('#!/bin/bash\n'+responses['otool']+'\nexec /usr/bin/seq 1 200000\n'); verify()
        (bindir/'otool').write_text('#!/bin/bash\n'+responses['otool']+'\n')
        # The expected signature is explicit: no default, no other value.
        for mode in (None, '', 'foo', 'ADHOC', 'developer-id'):
            if mode is None: del env['TOPNV_EXPECT_SIGNATURE']
            else: env['TOPNV_EXPECT_SIGNATURE'] = mode
            verify('V9')
        env['TOPNV_EXPECT_SIGNATURE'] = 'adhoc'; verify()
        # Developer ID: codesign answers per signed path from files, like the real tool on each component.
        signatures = root / 'signatures'; signatures.mkdir()
        (bindir/'codesign').write_text('#!/bin/bash\n[[ "$1" == --verify ]] && exit 0\n'
                                       'cat "$FAKE_SIGNATURES/$(basename "${@: -1}")" >&2\n')
        env['FAKE_SIGNATURES'] = str(signatures)
        def details(team='ABCDE12345', flags='0x10000(runtime)', drop=(), extra=(), executable='/fixture', timestamp='14 Nov 2026 at 22:00:00'):
            lines = [f'Executable={executable}', 'Identifier=io.github.bernalli.topnv', 'Format=app bundle with Mach-O universal (x86_64 arm64)',
                     f'CodeDirectory v=20500 size=100 flags={flags} hashes=1+7 location=embedded',
                     'Authority=Developer ID Application: Example Developer (ABCDE12345)',
                     'Authority=Developer ID Certification Authority', 'Authority=Apple Root CA',
                     f'Timestamp={timestamp}', f'TeamIdentifier={team}', 'Runtime Version=14.0.0', *extra]
            return '\n'.join(l for l in lines if not l.startswith(drop) or not drop) + '\n'
        components = ('Installer.xpc', 'Downloader.xpc', 'Autoupdate', 'Updater.app', 'Sparkle.framework')
        def signed(**app_changes):
            (signatures / 'TopNV.app').write_text(details(**app_changes))
            for name in components: (signatures / name).write_text(details())
        env['TOPNV_EXPECT_SIGNATURE'] = 'developer-id'; signed(); verify()
        for changes in ({'extra': ('Signature=adhoc',)}, {'drop': ('Authority=Developer ID Application:',)},
                        {'drop': ('Authority=',)}, {'flags': '0x0(none)'}, {'flags': '0x2(adhoc)'},
                        {'drop': ('Timestamp=',)}, {'extra': ('Signed Time=14 Nov 2026 at 22:00:00',), 'drop': ('Timestamp=',)},
                        {'team': 'not set'}, {'drop': ('TeamIdentifier=',)}, {'drop': ('CodeDirectory',)}):
            signed(**changes); verify('V9')
        signed(); (signatures / 'TopNV.app').unlink(); verify('V9')
        for name in components:
            for changes in ({'flags': '0x0(none)'}, {'flags': '0x2(adhoc)'}, {'team': 'ZYXWV98765'}, {'team': 'not set'}):
                signed(); (signatures / name).write_text(details(**changes)); verify('V14')
            signed(); (signatures / name).unlink(); verify('V14')
        # Ambiguous metadata: runtime flags outside the CodeDirectory line, contradictory teams, an empty timestamp.
        def verdict():
            result = subprocess.run(['bash', str(REPO / 'scripts/verify-bundle.sh'), str(app)], env=env, capture_output=True)
            return result.returncode, (result.stdout + result.stderr).decode()
        ambiguous = [('TopNV.app', {'executable': '/Applications/flags=0x10000(runtime)/TopNV', 'flags': '0x0(none)'}, 'V9'),
                     ('TopNV.app', {'extra': ('TeamIdentifier=ZYXWV98765',)}, 'V9'),
                     ('TopNV.app', {'timestamp': ''}, 'V9')]
        ambiguous += [(name, {'extra': ('TeamIdentifier=ZYXWV98765',)}, 'V14') for name in components]
        accepted = []
        for target, changes, code in ambiguous:
            signed(); (signatures / target).write_text(details(**changes))
            status, output = verdict()
            if status != 1 or code not in output: accepted.append((target, changes, code))
        assert not accepted, accepted
        signed(); verify()
        # Ad hoc mode never accepts a Developer ID signature, and never looks at the components.
        signed(); env['TOPNV_EXPECT_SIGNATURE'] = 'adhoc'; verify('V9')
        (bindir/'codesign').write_text('#!/bin/bash\n'+responses['codesign']+'\n')
        verify(); print('PASS verifier V0-V17 mutations; signature modes')

run_tests(sys.argv[1])

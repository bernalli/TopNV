#!/usr/bin/env python3
"""Validate distributable inputs before building, or inspect bundled metadata."""
import base64
import hashlib
import os
from pathlib import Path
import plistlib
import re
import sys

SPARKLE_HASH = '389a4e4e9a32f059775b13a06e25a591445ba229d2838d26dd3e7c0c45127cfe'
MIT_HASH = 'd0d211e1fb7d9926f5e1693cab1e843b42152cdc39d38638a5cf83b3530feaaa'
STABLE = 'https://github.com/bernalli/TopNV/releases/latest/download/appcast.xml'
FEED = r'https://github\.com/bernalli/TopNV/releases/(latest/download|download/update-proof)/appcast\.xml'

def version(value):
    return isinstance(value, str) and re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', value) and all(int(v) <= 9223372036854775807 for v in value.split('.'))

def build(value):
    return isinstance(value, str) and re.fullmatch(r'[1-9][0-9]{0,9}', value)

def key(value):
    return isinstance(value, str) and len(base64.b64decode(value, validate=True)) == 32

def hash_matches(path, expected):
    return hashlib.sha256(path.read_bytes()).hexdigest() == expected

def main():
    mode, root = sys.argv[1], Path(sys.argv[2])
    if mode == 'inputs':
        checks = [
            ('version must have three Int64 components', lambda: version(os.environ.get('TOPNV_VERSION', '1.1.0'))),
            ('build must be a positive integer of at most ten digits', lambda: build(os.environ.get('TOPNV_BUILD_NUMBER', '1'))),
            ('feed must be the canonical stable or proof URL', lambda: re.fullmatch(FEED, os.environ.get('TOPNV_FEED_URL', STABLE))),
            ('public key missing or invalid', lambda: key((root/'Assets/SparklePublicEDKey.txt').read_text().rstrip())),
            ('Sparkle license missing or altered', lambda: hash_matches(root/'Licenses/Sparkle.txt', SPARKLE_HASH)),
            ('TopNV license missing or altered', lambda: hash_matches(root/'LICENSE', MIT_HASH)),
            ('AUTHORS is empty', lambda: bool((root/'AUTHORS').read_text().splitlines()[0].strip())),
        ]
    else:
        app = Path(sys.argv[3]); info = app/'Contents/Info.plist'
        try: p = plistlib.loads(info.read_bytes())
        except Exception: print('V0: unreadable plist', file=sys.stderr); return 1
        resources = app/'Contents/Resources/Licenses'
        checks = [
            ('V1: feed or application mode invalid', lambda: p.get('SUFeedURL') == os.environ.get('TOPNV_EXPECT_FEED_URL', STABLE) and p.get('LSUIElement') is True and not p.get('SURequireSignedFeed', False) and not any(p.get(k, False) for k in ('SUEnableInstallerLauncherService', 'SUEnableDownloaderService', 'SUEnableInstallerConnectionService', 'SUEnableInstallerStatusService'))),
            ('V2: public key mismatch', lambda: key(p.get('SUPublicEDKey')) and p['SUPublicEDKey'] == (root/'Assets/SparklePublicEDKey.txt').read_text().rstrip()),
            ('V3: updater flags must be booleans', lambda: all(type(p.get(k)) is bool and p[k] == v for k,v in [('SUEnableAutomaticChecks',False),('SUAllowsAutomaticUpdates',False),('SUVerifyUpdateBeforeExtraction',True)])),
            ('V4: invalid identity or version', lambda: version(p.get('CFBundleShortVersionString')) and build(p.get('CFBundleVersion')) and p.get('CFBundleIdentifier') == 'io.github.bernalli.topnv' and p.get('LSMinimumSystemVersion') == '14.0'),
            ('V11: Sparkle license mismatch', lambda: hash_matches(resources/'Sparkle.txt',SPARKLE_HASH)),
            ('V12: TopNV license mismatch', lambda: hash_matches(resources/'TopNV.txt',MIT_HASH)),
            ('V13: copyright mismatch', lambda: p.get('NSHumanReadableCopyright') == 'Copyright (c) 2026 ' + (root/'AUTHORS').read_text().splitlines()[0] and 'All rights reserved' not in p['NSHumanReadableCopyright']),
        ]
    failed = False
    for message, check in checks:
        try: valid = check()
        except (OSError, ValueError, TypeError, IndexError, KeyError): valid = False
        if not valid:
            print(('error: ' if mode == 'inputs' else '') + message, file=sys.stderr); failed = True
    return int(failed)

if __name__ == '__main__':
    sys.exit(main())

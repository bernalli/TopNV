#!/usr/bin/env bash
# Fails when an app source names a wallpaper API: TopNV never reads, re-applies or changes the
# wallpaper. The match ignores case, so every NSWorkspace desktop image symbol is covered.
set -euo pipefail
python3 -B - "$(dirname "$0")/../.." <<'PY'
from pathlib import Path
import re
import sys

PATTERN = re.compile(r'desktopimage', re.IGNORECASE)


def violations(sources):
    found = []
    for name, text in sorted(sources.items()):
        for number, line in enumerate(text.splitlines(), 1):
            if PATTERN.search(line):
                found.append(f'{name}:{number}: {line.strip()}')
    return found


# Negative cases in memory: each symbol is found in code and in comments.
for symbol in ('setDesktopImageURL', 'desktopImageURL', 'desktopImageOptions',
               'DesktopImageOptionKey'):
    for line in (f'try NSWorkspace.shared.{symbol}(url, for: screen, options: [:])',
                 f'let value = workspace.{symbol}(for: screen)',
                 f'// {symbol}'):
        assert violations({'Sample.swift': f'import AppKit\n{line}\n'}), line
assert violations({'Sample.swift': 'import AppKit\nlet url = screen.frame\n'}) == []

root = Path(sys.argv[1])
sources = {str(path.relative_to(root)): path.read_text(encoding='utf-8')
           for path in sorted((root / 'Sources').rglob('*.swift'))}
assert len(sources) > 10, 'the scan must read the real sources'
problems = violations(sources)
if problems:
    print('\n'.join(problems), file=sys.stderr)
    sys.exit(1)
print(f'PASS no wallpaper API in {len(sources)} sources')
PY

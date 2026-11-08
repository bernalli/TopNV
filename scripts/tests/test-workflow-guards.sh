#!/usr/bin/env bash
# Check workflow properties that the publisher simulation cannot observe.
set -euo pipefail
python3 - "$(cd "$(dirname "$0")/../.." && pwd)" <<'PY'
from pathlib import Path
import re, sys
root=Path(sys.argv[1])
release=(root/'.github/workflows/release.yml').read_text()
ci=(root/'.github/workflows/ci.yml').read_text()
steps=re.split(r'\n      - ',release)[1:]
def named(fragment):
    found=[i for i,s in enumerate(steps) if fragment in s]
    assert len(found)==1,fragment
    return found[0]
resolve=named('publish-release.sh resolve'); guard=named('run: scripts/require-signing-key.sh')
sign=named('run: scripts/sign-release.sh'); publish=named('publish-release.sh publish'); recover=named('publish-release.sh recover')
assert resolve<guard<sign<publish<recover
assert [i for i,s in enumerate(steps) if 'secrets.' in s]==[guard,sign]
assert release.count('secrets.')==2 and 'secrets.' not in ci
assert [i for i,s in enumerate(steps) if re.search(r'^\s+if:',s,re.M)]==[recover]
assert 'failure() || cancelled()' in steps[recover]
assert re.search(r'^permissions:\n  contents: write$',release,re.M) and re.search(r'^permissions:\n  contents: read$',ci,re.M)
assert 'cancel-in-progress: false' in release and 'pull_request_target' not in ci
for text in (release,ci):
    for action in re.findall(r'uses: (\S+)',text): assert re.fullmatch(r'[^@]+@[0-9a-f]{40}',action),action
    for block,line in re.findall(r'run: \|\n((?:          .*\n?)+)|run: (.*)',text):
        assert '${{' not in block+line,'expression in shell text'
print('PASS workflow guard order and secret scope')
PY

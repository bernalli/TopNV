#!/usr/bin/env bash
set -euo pipefail
python3 - "$(dirname "$0")/../.." <<'PY'
from pathlib import Path
import hashlib,sys
root=Path(sys.argv[1])
for name,expected in [('LICENSE','d0d211e1fb7d9926f5e1693cab1e843b42152cdc39d38638a5cf83b3530feaaa'),('Licenses/Sparkle.txt','389a4e4e9a32f059775b13a06e25a591445ba229d2838d26dd3e7c0c45127cfe'),('Assets/Fonts/PlusJakartaSans-OFL.txt','995c7199cab65954f545996326755daee7b63cc6b42b06c13da1f9502ab08a99')]:
    assert hashlib.sha256((root/name).read_bytes()).hexdigest()==expected,name
last=(root/'README.md').read_bytes().splitlines(keepends=True)[-1]
assert hashlib.sha256(last).hexdigest()=='4160324292cbdce664c93082f90040367bfd759e890c21edc8168568aa7a8668'
assert (root/'release-notes/1.1.0.md').read_text().strip()
print('PASS license and README copyright hashes')
PY

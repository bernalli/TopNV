#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT" <<'PY'
import importlib.util, os, pathlib, sys
root=pathlib.Path(sys.argv[1]); spec=importlib.util.spec_from_file_location('publisher',root/'scripts/publish-release.py'); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
p=m.Publisher(root,os.environ,m.Transport(root))
p.io.verify(root/f'build/TopNV-{p.version}.dmg',root/'build/appcast.xml',p)
PY

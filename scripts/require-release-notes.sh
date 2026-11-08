#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import os, pathlib, sys
try:
    assert pathlib.Path(os.environ['TOPNV_RELEASE_NOTES']).read_text().strip()
except Exception:
    sys.exit('error: release notes missing or empty')
PY

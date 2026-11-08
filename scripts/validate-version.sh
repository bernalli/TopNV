#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import os, re, sys
v=os.environ.get('TOPNV_VERSION','')
if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+',v) or any(len(n)>19 or int(n)>9223372036854775807 for n in v.split('.')):
    sys.exit('error: version must have three Int64 numeric components')
PY

#!/usr/bin/env bash
# Validate in memory only. Never echo values or enable tracing.
set +x
set -euo pipefail
python3 - <<'PY'
import base64, os, sys
try:
    value=os.environ.get('SPARKLE_ED_PRIVATE_KEY','')
    assert value and not any(c.isspace() for c in value)
    assert len(base64.b64decode(value,validate=True))==32
except Exception:
    sys.exit('error: signing key missing or invalid (expected base64 encoding of 32 bytes)')
PY

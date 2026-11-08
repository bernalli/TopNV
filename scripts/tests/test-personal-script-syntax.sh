#!/usr/bin/env bash
# Personal scripts are deliberately untracked; only inspect them when delivered locally.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for script in topnv-sparkle-key.sh topnv-proof.sh; do
  if [[ -f "$ROOT/$script" ]]; then
    bash -n "$ROOT/$script"
    if command -v shellcheck >/dev/null; then shellcheck "$ROOT/$script"; fi
    echo "PASS syntax only: $script (not executed)"
  fi
done

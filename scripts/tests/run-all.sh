#!/usr/bin/env bash
set -euo pipefail
for test in "$(dirname "$0")"/test-*.sh; do
  echo "Running $(basename "$test")"
  bash "$test"
done

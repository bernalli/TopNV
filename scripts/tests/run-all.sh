#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$(dirname "$0")/../../build/test-tmp"
for test in "$(dirname "$0")"/test-*.sh; do
  echo "Running $(basename "$test")"
  bash "$test"
done

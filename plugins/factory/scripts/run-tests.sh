#!/usr/bin/env bash
# Run every factory helper test. Each test builds throwaway Git fixtures in
# $TMPDIR and never touches the surrounding repository.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0

for test in "$SCRIPT_DIR"/*.test.sh; do
  printf '\n== %s ==\n' "$(basename "$test")"
  if ! bash "$test"; then
    fail=1
  fi
done

if [[ $fail -ne 0 ]]; then
  printf '\nFAIL: at least one factory helper test failed\n' >&2
  exit 1
fi

printf '\nPASS: all factory helper tests passed\n'

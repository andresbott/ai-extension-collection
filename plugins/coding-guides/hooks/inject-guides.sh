#!/usr/bin/env bash
# SessionStart hook: inject the user's standing coding guides into the session.
# Emits the documented `hookSpecificOutput` wrapper when jq or python3 is
# available; otherwise falls back to plain stdout (also a documented form).
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
file="${dir}/../context/coding-guides.md"

if command -v jq >/dev/null 2>&1; then
  jq -Rs '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: .}}' "$file"
elif command -v python3 >/dev/null 2>&1; then
  python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": open(sys.argv[1]).read()}}))' "$file"
else
  cat "$file"
fi

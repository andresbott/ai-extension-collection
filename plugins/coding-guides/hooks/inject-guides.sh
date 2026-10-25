#!/usr/bin/env bash
# SessionStart / SubagentStart hook: inject one file of the user's standing
# coding guides from context/. hooks.json registers one call per file, because
# Claude Code swaps any additionalContext over 10,000 characters for a file path
# and a short preview. The session gets every file; subagents get the ones about
# writing code, except the built-in agents that never write code.
#
#   Usage: inject-guides.sh <SessionStart|SubagentStart> <file in context/>
#
# Emits the documented `hookSpecificOutput` wrapper when jq or python3 is
# available. Without either, SessionStart falls back to plain stdout (also a
# documented form); SubagentStart has no plain-text form, so it fails with an
# install hint instead of silently injecting nothing.
set -euo pipefail

event="$1"
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
file="${dir}/../context/$2"

# Built-in agents that only search, plan, or configure: they get no guides.
skipped_agent() {
  case "$1" in
    Explore | Plan | claude-code-guide | statusline-setup) return 0 ;;
    *) return 1 ;;
  esac
}

if command -v jq >/dev/null 2>&1; then
  if [[ "$event" == SubagentStart ]] && skipped_agent "$(jq -r '.agent_type // empty' 2>/dev/null || true)"; then
    exit 0
  fi
  jq -Rs --arg event "$event" '{hookSpecificOutput: {hookEventName: $event, additionalContext: .}}' "$file"
elif command -v python3 >/dev/null 2>&1; then
  if [[ "$event" == SubagentStart ]] && skipped_agent "$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("agent_type") or "")' 2>/dev/null || true)"; then
    exit 0
  fi
  python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput": {"hookEventName": sys.argv[1], "additionalContext": open(sys.argv[2], encoding="utf-8").read()}}))' "$event" "$file"
elif [[ "$event" == SubagentStart ]]; then
  echo "coding-guides: install jq or python3 to inject the guides into subagents" >&2
  exit 1
else
  cat "$file"
fi

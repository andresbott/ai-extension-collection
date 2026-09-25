#!/usr/bin/env bash
# PreToolUse hook — coding-guides' single entry point for enforcing the standing
# conventions as HARD rules. (The SessionStart hook injects the same guides as
# soft guidance; this blocks violations outright.) Reads the tool-call JSON on
# stdin; `exit 2` blocks the call and returns the reason to the agent so it
# retries correctly.
#
# Add new rules as check_* functions and call them from run_checks().
# Requires jq; if jq is missing it fails open (allows the call) so a missing
# dependency never blocks the shell. The -m checks use GNU grep (-P/-z).
set -euo pipefail

deny() {
  # $1: reason (fed back to the agent). Followed by the fix, so every rule
  # nudges toward the same corrected form.
  printf 'BLOCKED by coding-guides: %s\n%s\n' \
    "$1" \
    'Use a single one-line message: git commit -m "<type>: one-line summary"' >&2
  exit 2
}

command -v jq >/dev/null 2>&1 || exit 0   # fail open when jq is unavailable

input="$(cat)"
tool_name="$(jq -r '.tool_name // empty' <<<"$input")"
cmd="$(jq -r '.tool_input.command // empty' <<<"$input")"

# Rule: git commit messages must be a single line.
check_single_line_commit() {
  [[ "$tool_name" == "Bash" ]] || return 0
  [[ "$cmd" =~ (^|[^[:alnum:]])git[[:space:]]+commit($|[[:space:]]) ]] || return 0

  # A -m / --message value that spans a newline (double- or single-quoted).
  # Also catches the heredoc-in-message form: -m "$(cat <<EOF ... )".
  if grep -Pzq '(?:-m|--message)[ =]*"[^"]*\n' <<<"$cmd" 2>/dev/null \
     || grep -Pzq "(?:-m|--message)[ =]*'[^']*\n" <<<"$cmd" 2>/dev/null; then
    deny 'commit -m message spans multiple lines'
  fi

  # Two or more -m / --message flags — git joins them into paragraphs.
  local m_count
  m_count="$({ grep -oE '(^|[[:space:]])--?m(essage)?([[:space:]=]|")' <<<"$cmd" || true; } | wc -l)"
  if (( m_count >= 2 )); then
    deny 'multiple -m flags create a multi-paragraph message'
  fi

  # Message read from a file/stdin — its contents can't be verified as one line.
  # Only relevant when no inline -m supplies the message.
  if (( m_count == 0 )) && [[ "$cmd" =~ (^|[[:space:]])(-F|--file)([[:space:]=-]|$) ]]; then
    deny 'commit reads its message from a file (-F/--file); use -m instead'
  fi
}

run_checks() {
  check_single_line_commit
  # Add further PreToolUse rules here.
}

run_checks
exit 0

#!/usr/bin/env bash
# PreToolUse hook — coding-guides' single entry point for enforcing the standing
# conventions as HARD rules. (The SessionStart hook injects the same guides as
# soft guidance; this blocks violations outright.) Reads the tool-call JSON on
# stdin; `exit 2` blocks the call and returns the reason to the agent so it
# retries correctly.
#
# Add new rules as check_* functions and call them from run_checks().
# Portable across GNU, BSD/macOS and BusyBox: matching uses bash's built-in
# [[ =~ ]] (POSIX ERE) and `grep -oE`, with no GNU-only flags. Needs jq to parse
# the payload; without it, git commit calls are blocked with an install hint
# (they can't be verified) and every other call is allowed.
set -euo pipefail

ONE_LINE_FIX='Use a single one-line message: git commit -m "<type>: one-line summary"'

deny() {
  # $1: reason (fed back to the agent). $2: how to fix it; defaults to the
  # one-line form, so every commit rule nudges toward the same corrected command.
  printf 'BLOCKED by coding-guides: %s\n%s\n' "$1" "${2:-$ONE_LINE_FIX}" >&2
  exit 2
}

# A `git commit` invocation; `git commit-graph` and the like don't match.
COMMIT_RE='(^|[^[:alnum:]])git[[:space:]]+commit($|[[:space:]])'

input="$(cat)"

# Without jq the payload can't be parsed, so the commit rules can't run. Fail
# closed only for what they guard: a Bash call whose raw JSON mentions
# `git commit` (JSON \n and \t escapes read as spaces, so a commit on its own
# line still counts; errs toward blocking). Everything else passes, so the agent
# can still run the command that installs jq.
require_jq() {
  command -v jq >/dev/null 2>&1 && return 0
  local tool_re='"tool_name"[[:space:]]*:[[:space:]]*"Bash"'
  local raw="${input//\\n/ }"
  raw="${raw//\\t/ }"
  if [[ "$raw" =~ $tool_re && "$raw" =~ $COMMIT_RE ]]; then
    deny 'jq is not installed, so the commit message cannot be checked for a single line' \
      'Install jq (e.g. apt install jq, dnf install jq, brew install jq), then retry the commit.'
  fi
  exit 0
}
require_jq

tool_name="$(jq -r '.tool_name // empty' <<<"$input")"
cmd="$(jq -r '.tool_input.command // empty' <<<"$input")"

# Rule: git commit messages must be a single line.
check_single_line_commit() {
  [[ "$tool_name" == "Bash" ]] || return 0
  [[ "$cmd" =~ $COMMIT_RE ]] || return 0

  # A -m / --message value that spans a newline (double- or single-quoted).
  # Also catches the heredoc-in-message form: -m "$(cat <<EOF ... )".
  # In bash's regex a newline is an ordinary character, so [^"] runs across
  # lines; no grep -z/-P needed.
  local nl=$'\n'
  local dq_re="(-m|--message)[ =]*\"[^\"]*${nl}"
  local sq_re="(-m|--message)[ =]*'[^']*${nl}"
  if [[ "$cmd" =~ $dq_re || "$cmd" =~ $sq_re ]]; then
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

#!/usr/bin/env bash
# Unit tests for coding-guides-pre-tool-use.sh (the coding-guides PreToolUse hook).
# Plain bash — no bats/framework dependency. Feeds crafted tool-call payloads to
# the hook and asserts the decision (exit 2 = blocked, 0 = allowed) and, for
# blocks, the reason handed back to the agent.
#
#   Run:  bash plugins/coding-guides/hooks/coding-guides-pre-tool-use.test.sh
#   Exit: 0 = all passed (or skipped), 1 = at least one failure.
set -uo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hook="${dir}/coding-guides-pre-tool-use.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed — the hook fails open without it, nothing to assert."
  exit 0
fi
have_grep_p=0
grep -Pq '' <<<"" 2>/dev/null && have_grep_p=1

pass=0 fail=0 skipped=0

# run <expected_exit> <reason_substr|-> <desc> <command>
run() {
  local expected="$1" want="$2" desc="$3" cmd="$4" out got
  out="$(jq -n --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}' | bash "$hook" 2>&1 1>/dev/null)"
  got=$?
  if [[ "$got" != "$expected" ]]; then
    printf 'FAIL  %s\n        got exit %s, want %s\n' "$desc" "$got" "$expected"
    fail=$((fail+1)); return
  fi
  if [[ "$want" != "-" && "$out" != *"$want"* ]]; then
    printf 'FAIL  %s\n        reason "%s" not found in: %s\n' "$desc" "$want" "$out"
    fail=$((fail+1)); return
  fi
  printf 'PASS  %s\n' "$desc"
  pass=$((pass+1))
}
skip()  { printf 'SKIP  %s (%s)\n' "$1" "$2"; skipped=$((skipped+1)); }
allow() { run 0 - "$1" "$2"; }        # <desc> <command>
block() { run 2 "$1" "$2" "$3"; }     # <reason_substr> <desc> <command>

# --- allowed: legitimate single-line usage -------------------------------
allow "single-line -m"                 'git commit -m "feat: add thing"'
allow "chained add + commit, one line" 'git add -A && git commit -m "fix: bug"'
allow "two statements, single-line -m" $'git add -A\ngit commit -m "fix: bug"'
allow "message text mentions -F"       'git commit -m "docs: explain the -F flag"'
allow "commit-graph is not a commit"   'git commit-graph write'
allow "non-git bash command"           'ls -la && echo done'
allow "commit --amend, no message"     'git commit --amend --no-edit'

# --- blocked: multi-line message forms -----------------------------------
block "multi-paragraph"  "multiple -m flags"         'git commit -m "feat: x" -m "the body"'
block "file (-F/--file)" "message from -F file"      'git commit -F /tmp/msg.txt'
block "file (-F/--file)" "message from -F- heredoc"  $'git commit -F- <<EOF\nfeat: x\nbody\nEOF'

if (( have_grep_p )); then
  block "spans multiple lines" "newline in double-quoted -m" $'git commit -m "feat: x\n\n- bullet"'
  block "spans multiple lines" "newline in single-quoted -m" $'git commit -m \'feat: x\n body\''
  block "spans multiple lines" "heredoc fed into -m"         $'git commit -m "$(cat <<EOF\nfeat: x\nbody\nEOF\n)"'
  block "spans multiple lines" "--message= with newline"     $'git commit --message="feat: x\n body"'
else
  skip "newline-in--m cases" "grep -P unavailable"
fi

echo
printf 'RESULT: %d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skipped"
(( fail == 0 ))

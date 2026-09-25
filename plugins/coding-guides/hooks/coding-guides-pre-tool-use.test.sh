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
bash_bin="$(command -v bash)"

# A PATH holding only the tools the hook uses, minus jq: simulates a machine
# without jq even when the test machine has it.
nojq_path="$(mktemp -d)"
trap 'rm -rf "$nojq_path"' EXIT
for tool in cat grep wc; do ln -s "$(command -v "$tool")" "${nojq_path}/${tool}"; done

pass=0 fail=0 skipped=0

# check <expected_exit> <reason_substr|-> <desc> <payload_json> [PATH]
check() {
  local expected="$1" want="$2" desc="$3" payload="$4" path="${5:-$PATH}" out got
  out="$(PATH="$path" "$bash_bin" "$hook" <<<"$payload" 2>&1 1>/dev/null)"
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
skip()    { printf 'SKIP  %s (%s)\n' "$1" "$2"; skipped=$((skipped+1)); }
payload() { jq -n --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}'; }
allow()   { check 0 - "$1" "$(payload "$2")"; }        # <desc> <command>
block()   { check 2 "$1" "$2" "$(payload "$3")"; }     # <reason_substr> <desc> <command>

if command -v jq >/dev/null 2>&1; then
  # --- allowed: legitimate single-line usage -----------------------------
  allow "single-line -m"                 'git commit -m "feat: add thing"'
  allow "chained add + commit, one line" 'git add -A && git commit -m "fix: bug"'
  allow "two statements, single-line -m" $'git add -A\ngit commit -m "fix: bug"'
  allow "message text mentions -F"       'git commit -m "docs: explain the -F flag"'
  allow "commit-graph is not a commit"   'git commit-graph write'
  allow "non-git bash command"           'ls -la && echo done'
  allow "commit --amend, no message"     'git commit --amend --no-edit'

  # --- blocked: multi-line message forms ---------------------------------
  block "multi-paragraph"      "multiple -m flags"           'git commit -m "feat: x" -m "the body"'
  block "file (-F/--file)"     "message from -F file"        'git commit -F /tmp/msg.txt'
  block "file (-F/--file)"     "message from -F- heredoc"    $'git commit -F- <<EOF\nfeat: x\nbody\nEOF'
  block "spans multiple lines" "newline in double-quoted -m" $'git commit -m "feat: x\n\n- bullet"'
  block "spans multiple lines" "newline in single-quoted -m" $'git commit -m \'feat: x\n body\''
  block "spans multiple lines" "heredoc fed into -m"         $'git commit -m "$(cat <<EOF\nfeat: x\nbody\nEOF\n)"'
  block "spans multiple lines" "--message= with newline"     $'git commit --message="feat: x\n body"'
else
  skip "jq-backed rules" "jq not installed"
fi

# --- jq missing: commit calls blocked with an install hint, the rest pass ---
# Raw JSON payloads, so these run whether or not the test machine has jq.
nojq_block() { check 2 "$1" "$2" "$3" "$nojq_path"; }   # <reason_substr> <desc> <payload_json>
nojq_allow() { check 0 - "$1" "$2" "$nojq_path"; }      # <desc> <payload_json>
nojq_block "jq is not installed" "no jq: single-line commit"     '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat: x\""}}'
nojq_block "Install jq"          "no jq: reason says how to fix" '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat: x\""}}'
nojq_block "jq is not installed" "no jq: commit on its own line" '{"tool_name":"Bash","tool_input":{"command":"git add -A\ngit commit -m \"fix: bug\""}}'
nojq_block "jq is not installed" "no jq: spaced JSON"            '{"tool_name": "Bash", "tool_input": {"command": "git commit -m x"}}'
nojq_allow "no jq: other command passes"   '{"tool_name":"Bash","tool_input":{"command":"sudo apt install jq"}}'
nojq_allow "no jq: commit-graph passes"    '{"tool_name":"Bash","tool_input":{"command":"git commit-graph write"}}'
nojq_allow "no jq: non-Bash tool passes"   '{"tool_name":"Write","tool_input":{"content":"git commit -m x"}}'

echo
printf 'RESULT: %d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skipped"
(( fail == 0 ))

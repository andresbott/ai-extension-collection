#!/usr/bin/env bash
# Unit tests for inject-guides.sh (the coding-guides SessionStart and
# SubagentStart hooks) and the hook wiring in hooks.json. Plain bash — no
# bats/framework dependency. Runs a copy of the script against a fixture
# context file and asserts the hook output Claude Code receives, then runs
# every command registered in hooks.json against the real guides.
#
#   Run:  bash plugins/coding-guides/hooks/inject-guides.test.sh
#   Exit: 0 = all passed (or skipped), 1 = at least one failure.
set -uo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_root="$(dirname "$dir")"
bash_bin="$(command -v bash)"
python_bin="$(command -v python3 || true)"
have_jq=0; command -v jq >/dev/null 2>&1 && have_jq=1

# Claude Code swaps an additionalContext string over 10,000 characters for a
# file path and a 2,000-character preview. Bytes stand in for characters: a
# file never has more characters than bytes.
cap=10000

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# A copy of the script beside a fixture context/ dir, so its own path
# resolution runs without depending on the real guides. The fixture holds
# what JSON has to escape.
mkdir -p "$work/plugin/hooks" "$work/plugin/context"
script="$work/plugin/hooks/inject-guides.sh"
cp "$dir/inject-guides.sh" "$script"
fixture="$work/plugin/context/fixture.md"
printf '# Fixture — "quotes", back\\slash, tab\there, $HOME, `ticks`, é\n\nSecond paragraph.\n' >"$fixture"

# PATHs holding only what the script needs, minus jq (python3 fallback) and
# minus both jq and python3 (plain-text fallback).
nojq_path="$work/nojq" noparser_path="$work/noparser"
mkdir -p "$nojq_path" "$noparser_path"
for tool in cat dirname; do
  ln -s "$(command -v "$tool")" "$nojq_path/$tool"
  ln -s "$(command -v "$tool")" "$noparser_path/$tool"
done
[[ -n "$python_bin" ]] && ln -s "$python_bin" "$nojq_path/python3"

pass=0 fail=0 skipped=0
ok()   { printf 'PASS  %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf 'FAIL  %s\n        %s\n' "$1" "$2"; fail=$((fail+1)); }
skip() { printf 'SKIP  %s (%s)\n' "$1" "$2"; skipped=$((skipped+1)); }

# The payloads Claude Code sends on stdin.
session_payload='{"session_id":"s1","transcript_path":"/tmp/s1.jsonl","cwd":"/tmp","hook_event_name":"SessionStart","source":"startup"}'
subagent_payload() {  # <agent_type>
  printf '{"session_id":"s1","transcript_path":"/tmp/s1.jsonl","cwd":"/tmp","hook_event_name":"SubagentStart","agent_id":"agent-1","agent_type":"%s"}' "$1"
}

# run <PATH> <event> <stdin>: run the script copy on the fixture; sets out, err, code.
run() {
  out="$(PATH="$1" "$bash_bin" "$script" "$2" fixture.md <<<"$3" 2>"$work/err")"
  code=$?
  err="$(<"$work/err")"
}

# injected <desc> <event>: the last run handed Claude Code the fixture for <event>.
injected() {
  local got_event got_context
  if (( code != 0 )); then bad "$1" "exit $code: $err"; return; fi
  got_event="$(jq -r '.hookSpecificOutput.hookEventName' <<<"$out" 2>/dev/null)"
  got_context="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out" 2>/dev/null)"
  if [[ "$got_event" != "$2" ]]; then bad "$1" "hookEventName \"$got_event\", want \"$2\" (output: $out)"; return; fi
  if [[ "$got_context" != "$(<"$fixture")" ]]; then bad "$1" "additionalContext is not the fixture: $got_context"; return; fi
  ok "$1"
}

# nothing <desc>: the last run injected nothing and succeeded.
nothing() {
  if (( code != 0 )); then bad "$1" "exit $code: $err"; return; fi
  if [[ -n "$out" ]]; then bad "$1" "want no output, got: $out"; return; fi
  ok "$1"
}

# --- the context cap: every injected file must fit ------------------------
for file in "$plugin_root"/context/*.md; do
  size="$(wc -c <"$file")"
  if (( size < cap )); then ok "${file##*/} fits the context cap ($size bytes)"
  else bad "${file##*/} fits the context cap" "$size bytes, cap $cap"; fi
done

if (( have_jq )); then
  # --- jq: JSON for both events, subagent skip list ------------------------
  run "$PATH" SessionStart "$session_payload"
  injected "SessionStart: injects the named file" SessionStart
  run "$PATH" SubagentStart "$(subagent_payload general-purpose)"
  injected "SubagentStart: injects into general-purpose" SubagentStart
  run "$PATH" SubagentStart "$(subagent_payload architects:Evans)"
  injected "SubagentStart: injects into a plugin agent" SubagentStart
  run "$PATH" SubagentStart "$(subagent_payload Explorer)"
  injected "SubagentStart: skip list matches whole names only" SubagentStart
  for agent in Explore Plan claude-code-guide statusline-setup gitauto:pr-writer; do
    run "$PATH" SubagentStart "$(subagent_payload "$agent")"
    nothing "SubagentStart: skips $agent"
  done

  # --- python3 fallback (no jq) ---------------------------------------------
  if [[ -n "$python_bin" ]]; then
    run "$nojq_path" SessionStart "$session_payload"
    injected "no jq: SessionStart via python3" SessionStart
    run "$nojq_path" SubagentStart "$(subagent_payload general-purpose)"
    injected "no jq: SubagentStart via python3" SubagentStart
    run "$nojq_path" SubagentStart "$(subagent_payload Explore)"
    nothing "no jq: python3 still skips Explore"
  else
    skip "python3 fallback" "python3 not installed"
  fi
else
  skip "JSON output and skip list" "jq not installed"
fi

# --- neither jq nor python3 -------------------------------------------------
# Plain stdout is context for SessionStart only; SubagentStart has no
# plain-text form, so it must fail visibly rather than inject nothing.
run "$noparser_path" SessionStart "$session_payload"
if (( code == 0 )) && [[ "$out" == "$(<"$fixture")" ]]; then
  ok "no jq or python3: SessionStart falls back to plain text"
else
  bad "no jq or python3: SessionStart falls back to plain text" "exit $code, output: $out $err"
fi
run "$noparser_path" SubagentStart "$(subagent_payload general-purpose)"
if (( code != 0 )) && [[ -z "$out" && "$err" == *"jq or python3"* ]]; then
  ok "no jq or python3: SubagentStart fails with an install hint"
else
  bad "no jq or python3: SubagentStart fails with an install hint" "exit $code, stdout: $out, stderr: $err"
fi

# --- hooks.json: every registered command works on the real guides --------
if (( have_jq )); then
  sessions=0 subagents=0
  for event in SessionStart SubagentStart; do
    if [[ "$event" == SessionStart ]]; then payload="$session_payload"; else payload="$(subagent_payload general-purpose)"; fi
    while IFS= read -r command; do
      out="$(CLAUDE_PLUGIN_ROOT="$plugin_root" "$bash_bin" -c "$command" <<<"$payload" 2>"$work/err")"
      code=$?
      context="$(jq -r --arg e "$event" 'select(.hookSpecificOutput.hookEventName == $e) | .hookSpecificOutput.additionalContext // empty' <<<"$out" 2>/dev/null)"
      if (( code == 0 )) && [[ -n "$context" ]]; then
        ok "hooks.json $event: ${command##* }"
      else
        bad "hooks.json $event: ${command##* }" "exit $code, output: $out $(<"$work/err")"
      fi
      if [[ "$event" == SessionStart ]]; then
        sessions=$((sessions+1)); printf '%s' "$context" >"$work/session-$sessions.md"
      else
        subagents=$((subagents+1))
      fi
    done < <(jq -r --arg e "$event" '.hooks[$e][]?.hooks[]?.command' "$dir/hooks.json")
  done
  if (( subagents > 0 )); then ok "hooks.json registers SubagentStart injection"
  else bad "hooks.json registers SubagentStart injection" "no SubagentStart hooks"; fi
  for file in "$plugin_root"/context/*.md; do
    found=0
    for saved in "$work"/session-*.md; do
      [[ -e "$saved" && "$(<"$saved")" == "$(<"$file")" ]] && found=1
    done
    if (( found )); then ok "SessionStart injects ${file##*/}"
    else bad "SessionStart injects ${file##*/}" "no SessionStart hook in hooks.json injects it"; fi
  done
else
  skip "hooks.json wiring" "jq not installed"
fi

echo
printf 'RESULT: %d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skipped"
(( fail == 0 ))

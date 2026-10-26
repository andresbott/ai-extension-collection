---
description: Open (or reuse) a PR for the current work and wait until CI is green — branch, verify, commit, push, open PR, watch CI. Does not merge; run /gitauto:ship afterwards to land it.
argument-hint: "[branch name]"
model: haiku
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/ship.sh:*), Agent, AskUserQuestion
---
!`${CLAUDE_PLUGIN_ROOT}/scripts/ship.sh prepare --for pr '$ARGUMENTS'`

If the output above starts with `NEED_ACCOUNT`, several GitHub accounts can push
to this repo. Call AskUserQuestion once: "Which GitHub account should gitauto use
for <repo>? It is saved for this clone.", with one option per login in
`accounts`. If the user picks one, run
`${CLAUDE_PLUGIN_ROOT}/scripts/ship.sh account '<login>'`. If that prints
`DONE state=saved`, run `${CLAUDE_PLUGIN_ROOT}/scripts/ship.sh prepare --for pr '$ARGUMENTS'`
and use its output in place of the output above from here on. With no pick,
reply with `error: no GitHub account chosen, so nothing was shipped`, then the
`NEED_ACCOUNT` line verbatim; on any other `account` output, reply with that
output verbatim. Then stop.

If the output starts with `success:` or `error:`, the run ends here: reply with
the output verbatim (its result line, then its `DONE` line). Call no tools.

Otherwise read the `SHIP` line and prepare the text:

- If `need=pr writer=expert`, call the Agent tool once with subagent_type
  `gitauto:pr-writer` and the prompt
  `Base: <base>. Draft command: ${CLAUDE_PLUGIN_ROOT}/scripts/ship.sh draft`.
  Do not write a title, subject, or body yourself; the run below loads the saved draft.
- Write each text the `--- write` block lists (if any), following its rule.
  Never use single quotes inside a text.

Then run it in the foreground (never `run_in_background`) with `timeout: 600000`,
passing each text you wrote: `branch` → `--branch '<n1>' '<n2>' '<n3>'`,
`title` → `--title`, `subject` → `--subject`, `message` → `--message`, and
`body` → `--body-stdin`. It prints one `ship: ...` progress line per stage:

```sh
${CLAUDE_PLUGIN_ROOT}/scripts/ship.sh open-pr [--branch ...] [--title '<title>'] [--subject '<subject>'] [--message '<message>'] [--body-stdin <<'EOF'
<body>
EOF]
```

If its last line starts with `WAITING`, CI is still running: run
`${CLAUDE_PLUGIN_ROOT}/scripts/ship.sh open-pr` again the same way (no flags,
title, subject, message, or body; it resumes). Do this at most 5 more times, saying
nothing in between.

Otherwise, do not re-run it. Reply with:

- its last two lines verbatim: the result line (`success:` or `error:`, or
  `warning:` for a final `WAITING`), then the outcome line (`READY`, `STOPPED`, or
  a final `WAITING`);
- if a `--- failure` block precedes those two lines, the block verbatim (it holds
  the failed verify output or the failed CI checks and their logs), followed by
  one sentence naming the most likely cause. Do not attempt a fix; the user decides.

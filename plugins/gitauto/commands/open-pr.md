---
description: Open (or reuse) a PR for the current work and wait until CI is green — branch, verify, commit, push, open PR, watch CI. Does not merge; run /gitauto:ship afterwards to land it.
argument-hint: "[branch name]"
model: haiku
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/ship.sh:*), Agent
---
!`${CLAUDE_PLUGIN_ROOT}/scripts/ship.sh prepare --for pr '$ARGUMENTS'`

If the output above starts with `DONE`, reply with that line verbatim. Call no tools.

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

- its last line verbatim (`READY`, `STOPPED`, or a final `WAITING`); after
  `READY`, add "run /gitauto:ship to merge";
- if a `--- failure` block precedes that line, the block verbatim (it holds the
  failed verify output or the failed CI checks and their logs), followed by one
  sentence naming the most likely cause. Do not attempt a fix; the user decides.

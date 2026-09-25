---
description: Open (or reuse) a PR for the current work and wait until CI is green — branch, verify, commit, push, open PR, watch CI. Does not merge; run /gitauto:ship afterwards to land it.
argument-hint: "[branch name]"
model: haiku
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/ship.sh:*), Agent
---
!`${CLAUDE_PLUGIN_ROOT}/scripts/ship.sh prepare --for pr '$ARGUMENTS'`

If the output above starts with `DONE`, reply with that line verbatim. Call no tools.

Otherwise read the `SHIP` line and prepare the text, based on `need`:

- `need=pr writer=expert`: call the Agent tool once with subagent_type
  `gitauto:pr-writer` and the prompt
  `Base: <base>. Draft command: ${CLAUDE_PLUGIN_ROOT}/scripts/ship.sh draft`.
  Do not write a title or body yourself; the run below loads the saved draft.
- `need=pr writer=cheap`: from the context above, write:
  - a **title**: one plain, imperative prose line a reviewer can read (e.g.
    `Add a discovery view for albums`);
  - a **subject**: one Conventional Commit line, `type(scope): summary` (types:
    feat fix docs style refactor perf test build ci chore revert; `!` for breaking).
    It is saved in the PR and becomes the squash subject when `/gitauto:ship` merges;
  - a **body** with `## Summary` (the why, 1–3 sentences), `## What` (2–5
    bullets of what matters), and optional `## Notes`. No tests section, no
    attribution.
- `need=message`: write a one-line Conventional Commit message.
- `need=none`: write nothing.

Never use single quotes inside the title, subject, or message.

If `protected=yes`, add `--branch '<n1>' '<n2>' '<n3>'` with 3 concise lowercase
names (`feat/`, `fix/`, `docs/`, or `chore/` plus a kebab slug); a branch name
given in `args` goes first.

Then run it in the foreground (never `run_in_background`) with `timeout: 600000`,
including only the parts that apply. It prints one `ship: ...` progress line per stage:

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

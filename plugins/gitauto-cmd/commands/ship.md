---
description: Ship the current work — branch, verify, commit, push, open PR, wait for CI, squash-merge, sync main, clean up (optional tag)
argument-hint: "[branch name] [tag=<semver>] [deleteRemote=true]"
model: haiku
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/ship.sh:*), Agent
---
!`${CLAUDE_PLUGIN_ROOT}/scripts/ship.sh prepare '$ARGUMENTS'`

If the output above starts with `DONE`, reply with that line verbatim. Call no tools.

Otherwise read the `SHIP` line and prepare the text, based on `need`:

- `need=pr writer=expert`: call the Agent tool once with subagent_type
  `gitauto-cmd:pr-writer` and the prompt
  `Base: <base>. Draft command: ${CLAUDE_PLUGIN_ROOT}/scripts/ship.sh draft`.
  Do not write a title or body yourself; the run below loads the saved draft.
- `need=pr writer=cheap`: from the context above, write a title (one
  Conventional Commit line, `type(scope): summary`) and a body with
  `## Summary` (the why, 1–3 sentences), `## What` (2–5 bullets of what
  matters), and optional `## Notes`. No tests section, no attribution.
- `need=message`: write a one-line Conventional Commit message.
- `need=none`: write nothing.

Never use single quotes inside the title or message.

Flags: if `protected=yes`, add `--branch '<n1>' '<n2>' '<n3>'` with 3 concise
lowercase names (`feat/`, `fix/`, `docs/`, or `chore/` plus a kebab slug); a
branch name given in `args` goes first. From `args`: `tag=<v>` becomes
`--tag <v>`. Add `--delete-remote` only if the args ask to delete the remote
branch. Never add a tag otherwise, and never ask about one.

Then run exactly once, with `run_in_background: true`, including only the parts that apply. It prints one
`ship: ...` progress line per stage, which the user can follow live:

```sh
${CLAUDE_PLUGIN_ROOT}/scripts/ship.sh run [flags] [--title '<title>'] [--message '<message>'] [--body-stdin <<'EOF'
<body>
EOF]
```

When it finishes, do not re-run it. Reply with:

- its last line verbatim (`SHIPPED`, `PARTIAL`, or `STOPPED ...`);
- if a `--- failure` block precedes that line, the block verbatim (it holds the
  failed verify output or the failed CI checks and their logs), followed by one
  sentence naming the most likely cause. Do not attempt a fix; the user decides.

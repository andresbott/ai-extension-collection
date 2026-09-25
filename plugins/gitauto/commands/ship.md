---
description: Ship the current work — branch, verify, commit, push, open PR, wait for CI, squash-merge, sync main, clean up, then offer a release tag (never tags by default)
argument-hint: "[branch name] [tag=<semver> | no tag] [deleteRemote=true]"
model: haiku
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/ship.sh:*), Agent, AskUserQuestion
---
!`${CLAUDE_PLUGIN_ROOT}/scripts/ship.sh prepare '$ARGUMENTS'`

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
    It becomes the squash-merge subject and drives the tag bump;
  - a **body** with `## Summary` (the why, 1–3 sentences), `## What` (2–5
    bullets of what matters), and optional `## Notes`. No tests section, no
    attribution.
- `need=message`: write a one-line Conventional Commit message.
- `need=subject` (or `need=message+subject`): the open PR has a prose title and
  no saved subject; turn its `pr_title` line into one Conventional Commit
  subject (plus the message, if also asked).
- `need=none`: write nothing.

Never use single quotes inside the title, subject, or message.

Flags: if `protected=yes`, add `--branch '<n1>' '<n2>' '<n3>'` with 3 concise
lowercase names (`feat/`, `fix/`, `docs/`, or `chore/` plus a kebab slug); a
branch name given in `args` goes first. From `args`: `tag=<v>` becomes
`--tag <v>`; declining a tag in any wording (`no tag`, `dont tag`) becomes
`--no-tag`. Add `--delete-remote` only if the args ask to delete the remote branch.

Then run it in the foreground (never `run_in_background`) with `timeout: 600000`,
including only the parts that apply. It prints one `ship: ...` progress line per stage:

```sh
${CLAUDE_PLUGIN_ROOT}/scripts/ship.sh run [flags] [--title '<title>'] [--subject '<subject>'] [--message '<message>'] [--body-stdin <<'EOF'
<body>
EOF]
```

If its last line starts with `WAITING`, CI is still running: run
`${CLAUDE_PLUGIN_ROOT}/scripts/ship.sh run [flags]` again the same way (the same
`--tag`/`--no-tag`/`--delete-remote` flags, no title, subject, message, or body; it resumes).
Do this at most 5 more times, saying nothing in between.

**Release tag.** If the last line contains `tag=ask`, call AskUserQuestion once:
"PR #N is merged. Create a release tag? (latest: <latest or none>)". The first
option is "No tag". Then add one option per version in `tag_options`, and mark
the `tag_recommended` one "(suggested)". Only if the user picks or types a
version, run in the foreground:
`${CLAUDE_PLUGIN_ROOT}/scripts/ship.sh tag '<version>'`. Any other answer, or no
answer, means no tag. Never tag without an explicit choice.

Otherwise, do not re-run anything. Reply with:

- the run's last line verbatim (`SHIPPED`, `PARTIAL`, `STOPPED`, or a final
  `WAITING`), plus the `TAGGED`/`STOPPED stage=tag` line if you ran `tag`, or
  "no tag created" if the user declined;
- if a `--- failure` block precedes that line, the block verbatim (it holds the
  failed verify output or the failed CI checks and their logs), followed by one
  sentence naming the most likely cause. Do not attempt a fix; the user decides.

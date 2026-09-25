---
description: Ship the current work — branch, verify, commit, push, open PR, wait for CI, squash-merge, sync main, clean up, then offer a release tag (never tags by default)
argument-hint: "[branch name] [tag=<semver> | no tag] [deleteRemote=true]"
model: haiku
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/ship.sh:*), Agent, AskUserQuestion
---
!`${CLAUDE_PLUGIN_ROOT}/scripts/ship.sh prepare '$ARGUMENTS'`

If the output above starts with `DONE`, reply with that line verbatim. Call no tools.

Otherwise read the `SHIP` line and prepare the text:

- If `need=pr writer=expert`, call the Agent tool once with subagent_type
  `gitauto:pr-writer` and the prompt
  `Base: <base>. Draft command: ${CLAUDE_PLUGIN_ROOT}/scripts/ship.sh draft`.
  Do not write a title, subject, or body yourself; the run below loads the saved draft.
- Write each text the `--- write` block lists (if any), following its rule.
  Never use single quotes inside a text.

Flags: pass each text you wrote: `branch` → `--branch '<n1>' '<n2>' '<n3>'`,
`title` → `--title`, `subject` → `--subject`, `message` → `--message`, and
`body` → `--body-stdin`. From `args`: `tag=<v>` becomes `--tag <v>`; declining a
tag in any wording (`no tag`, `dont tag`) becomes `--no-tag`. Add
`--delete-remote` only if the args ask to delete the remote branch.

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

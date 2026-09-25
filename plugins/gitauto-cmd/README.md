# gitauto-cmd

A token-cheap version of [`gitauto`](../gitauto). Where `gitauto` runs each
stage through a dynamic workflow with schema-validated subagents, `gitauto-cmd`
uses plain slash commands on `haiku` plus bash scripts. The scripts do the work;
the model only writes the prose a script can't: branch names, commit messages,
and pull request descriptions. An expensive model is used only when a PR
description is genuinely hard to write.

## Commands

| Command | Arguments | Behaviour |
|---|---|---|
| `/gitauto-cmd:branch-out` | `[branch name]` | On `main`/`master`/the default branch, creates and checks out a feature branch; otherwise leaves the current branch unchanged. |
| `/gitauto-cmd:ship` | `[branch name] [tag=<semver>] [deleteRemote=true]` | branch → verify → commit → push → open PR → wait for CI → squash-merge → sync main → cleanup → optional tag. |

## How branch-out stays cheap

```text
/gitauto-cmd:branch-out  →  !`branch-out.sh`  →  (only if needed) branch-out.sh --create
```

- **`!` preprocessing** runs `scripts/branch-out.sh` before the model sees the
  prompt, so there's no exploratory tool call.
- **Zero-tool paths.** Already on a feature branch, or given a valid explicit
  name: the script finishes during preprocessing and prints one `DONE` line.
- **One tool call otherwise.** The script prints `NEED_NAME` and at most 25
  lines of `git status --short`. The model proposes 3 names and calls `--create`
  once.
- **No retry rounds.** If every candidate is taken, the script tries `-2`…`-9`
  suffixes on the first valid one.

## How ship stays cheap

```text
/gitauto-cmd:ship  →  !`ship.sh prepare`  →  [pr-writer agent]  →  ship.sh run (background)
```

1. **`prepare`** (preprocessing, no mutation) checks the guards and `gh` auth,
   sizes the change against the default branch, and prints a `SHIP` line:
   `need=pr|message|none` says what text is missing, and `writer=cheap|expert`
   says who writes it. For the cheap writer it appends status, commits,
   diffstat, and a patch truncated to 200 lines. Nothing to ship prints `DONE`.
2. **Writing the text:**
   - `writer=cheap`: haiku writes the title, body, or message from that context.
   - `writer=expert`: haiku launches the `pr-writer` agent (**`model: opus`**).
     It reads the repository itself and saves the draft with `ship.sh draft`, so
     haiku never re-types the body.
   - An already-open PR only needs a commit message; a clean tree needs nothing.
3. **`run`** is called once with `run_in_background`. It chains the helpers and
   blocks inside the script on `gh pr checks --watch`, so the model doesn't poll
   in a loop. The harness wakes the model once, when the script exits.

## Progress and failures

`run_in_background` gives the session back right away: you can keep chatting
while ship runs, and the model is woken once when it exits.

- **Progress:** `run` prints a `ship: started; live output: tail -f <log>` line,
  then `ship: [n] <stage> ...` and `ship: [n] <stage> -> <state>` for each
  stage. Follow it in Claude Code's background-task view, or `tail -f` the log
  for full live output, including the CI watch.
- **Failures come back into the session.** When verification or CI fails,
  `run` prints a `--- failure` block just before the final line. For verify,
  it holds the last 60 lines of its output. For CI, it holds the failed check
  names and the last 60 lines of up to 2 failed runs'
  `gh run view --log-failed`, with timestamps stripped. The command quotes the
  block and names the likely cause without trying a fix, so you can ask the
  session to fix it and ship again (the existing PR is reused). The number of
  lines is set by `GITAUTO_CMD_FAIL_LINES`.

A change is **complex** when it touches more than 10 files, more than 400
lines, or more than 3 top-level directories. You can override these limits
with `GITAUTO_CMD_COMPLEX_FILES`, `GITAUTO_CMD_COMPLEX_LINES`, and
`GITAUTO_CMD_COMPLEX_DIRS`. `GITAUTO_CMD_PATCH_LINES` sets the size of the
cheap writer's patch.

The commit message defaults to the PR title, and the merge subject is the PR
title (`<title> (#N)`), so a new PR needs just a title and a body.

## Output

```text
DONE state=created|unchanged|nothing|failed ...        # nothing left for the model
ship: [n] <stage> ... / -> <state>                      # progress, one pair per stage
--- failure: verify|wait-ci ...                         # only on those failures
SHIPPED pr=#N url=... sync=synced cleanup=clean ... log=<file>
PARTIAL ...                                             # merged, but sync/cleanup/tag incomplete
STOPPED stage=<stage> state=<state> report=<why> log=<file>
```

The full helper output goes to the log file, not into the model's context.

## Safety

`scripts/gitauto-*.sh` are copied verbatim from `gitauto` (along with their
tests), so this plugin has no install-time dependency on it. Every guard
carries over:

- `main`, `master`, and the resolved default branch are protected; detached
  HEAD and an unresolvable `origin` default are refused. Every mutating helper
  re-checks the guard right before it acts.
- Verification (Make `verify`, then `test`/`lint`/`vet`/`check`, npm scripts,
  or Go checks) must pass or skip before anything is committed.
- The merge needs a valid Conventional Commit subject, a matching PR head, and
  checks that are green or explicitly absent.
- Sync fast-forwards only and refuses a dirty primary worktree. Cleanup keeps
  the local branch and deletes the remote branch only with `deleteRemote=true`.
  Tagging happens only with an explicit `tag=<semver>`.
- **Merged-PR guard:** new work on a branch whose PR is already merged is never
  skipped past. `prepare` refuses a dirty tree, and `run` stops unless `HEAD` is
  exactly the merged PR's head commit.

`ship` stages everything (`git add -A`), including unrelated changes in the
working tree. Check `git status` first.

## Tests

```sh
bash plugins/gitauto-cmd/scripts/run-tests.sh
```

This runs `branch-out.test.sh`, `ship.test.sh` (a local bare remote plus a fake
`gh`, end to end), and the copied helper tests.

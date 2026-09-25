# gitauto

Token-cheap Git delivery commands for **Claude Code and pi**, backed by bash
scripts. The scripts do the work; the model only writes the prose a script
can't: branch names, commit messages, and pull request descriptions. An
expensive model is used only when a PR description is genuinely hard to write.

## Commands

| Command | Arguments | Behaviour |
|---|---|---|
| `/gitauto:branch-out` | `[branch name]` | On `main`/`master`/the default branch, creates and checks out a feature branch; otherwise leaves the current branch unchanged. |
| `/gitauto:open-pr` | `[branch name]` | branch → verify → commit → push → open (or reuse) PR → wait for CI; stops at green (`READY`). Never merges. |
| `/gitauto:ship` | `[branch name] [tag=<semver> \| no tag] [deleteRemote=true]` | The same flow, then squash-merge → sync main → cleanup → offer a release tag (never tags by default). |

`open-pr` then `ship` is the review-first path: `open-pr` gets the PR green, and
a later `ship` finds it open with a clean tree (`need=none`). It skips verify,
reuses the PR, and merges with the subject saved in the PR, so no text has to
be written the second time.

## One core, two adapters

```text
scripts/*.sh             core, shared: all Git and GitHub behaviour, the output
                         lines, and the `--- write` rules for every text
agents/pr-writer.md      shared prompt for complex PRs
commands/*.md            Claude Code adapter (+ .claude-plugin/plugin.json)
pi/index.ts              pi adapter (loaded through the repo's package.json)
```

- **Behaviour lives in the core.** A flow change goes into the scripts, so both
  harnesses get it. An adapter only runs the scripts, has a model write the
  texts the `--- write` block lists, asks the user about a tag, and re-runs on
  `WAITING`. It never makes Git decisions.
- **The output lines are the interface** (see [Output](#output)). Changing one
  is a breaking change: update the script tests and both adapters.
- **Writing rules are printed, not copied.** `prepare` and `branch-out.sh` print
  a `--- write` block with one `<key>: <rule>` line per text they need
  (`branch`, `title`, `subject`, `body`, `message`). Each adapter hands it to its
  model unchanged, so the rules live only in `gitauto_write_rules`.

## Use it in pi

Install the repository as a pi package (its root `package.json` lists the pi
adapters):

```sh
pi install git:github.com/andresbott/ai-extension-collection
```

The same `/gitauto:branch-out`, `/gitauto:open-pr`, and `/gitauto:ship`
commands appear, with the same arguments. The pi adapter runs the flow in
TypeScript, so no model decides how to run it:

- **Texts** come from one nested model call without tools, given the script's
  output. For complex changes, a one-shot `pi --print` process runs the shared
  `pr-writer.md` prompt with read-only tools and saves the draft. If it saves
  none, the cheap writer takes over.
- **Two models, as in Claude Code** (haiku for the command, opus for
  `pr-writer`), with no setup:
  - **Simple texts** (branch names, commit messages, small PR texts, the failure
    diagnosis) use a cheap model: Haiku, or else a GPT mini or a Flash model.
    gitauto picks the newest one you can reach, preferring your session's
    provider (for example `github-copilot/claude-haiku-4.5`). It falls back to
    the session's model only when none is available. The widget shows which
    model wrote the texts.
  - **Complex PR titles and bodies** (the `pr-writer` expert) use your session's
    model, the stronger one you chose. If it saves no draft, for example after a
    failure or a refusal, the cheap writer takes over.

  `GITAUTO_CHEAP_MODEL` and `GITAUTO_EXPERT_MODEL` (`provider/id` or a bare id)
  are optional overrides for either role.
- **Your chat stays clean.** Progress lines show in a widget while the command
  runs; only the final report is added to the session, so you can ask the model
  about a failure afterwards.
- **The tag question** is a pi selector, with "No tag" first.
- **No 10-minute cap.** `GITAUTO_CMD_RUN_BUDGET` defaults to 3600 seconds, so
  `WAITING` rounds are rare; up to 5 are still resumed automatically.
- `GITAUTO_PI_BIN` overrides the `pi` binary the expert writer runs.

## How branch-out stays cheap

```text
/gitauto:branch-out  →  !`branch-out.sh`  →  (only if needed) branch-out.sh --create
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
/gitauto:ship  →  !`ship.sh prepare`  →  [pr-writer agent]  →  ship.sh run (foreground, resumable)
```

1. **`prepare`** (preprocessing, no mutation) checks the guards and `gh` auth,
   sizes the change against the default branch, and prints a `SHIP` line:
   `need=pr|message|none` says what text is missing, and `writer=cheap|expert`
   says who writes it. A `--- write` block lists each text to write, with its
   rule. For the cheap writer it appends status, commits,
   diffstat, and a patch truncated to 200 lines. Nothing to ship prints `DONE`.
2. **Writing the text:**
   - `writer=cheap`: haiku writes the prose title, the Conventional subject,
     the body, or the message from that context.
   - `writer=expert`: haiku launches the `pr-writer` agent (**`model: opus`**).
     It reads the repository itself and saves the draft with `ship.sh draft`, so
     haiku never re-types the body.
   - An already-open PR only needs a commit message; a clean tree needs nothing.
3. **`run`** is a normal foreground tool call. It chains the helpers and blocks
   inside the script on `gh pr checks --watch`, so the model doesn't poll in a
   loop and reads the output only once, when the call returns.

## Foreground runs and slow CI

The command never uses `run_in_background`, so the session waits until the run
finishes; you can still interrupt it. Claude Code caps a foreground Bash call at
10 minutes, so `run` stays within a budget of `GITAUTO_CMD_RUN_BUDGET` seconds
(default 540). The CI wait gets whatever time is left, and at least
`GITAUTO_CMD_CI_MIN` seconds (default 30).

If CI is still running when the budget runs out, `run` exits with
`WAITING stage=wait-ci pr=#N ...`. The command then runs `ship.sh run` again
with the same `--tag` and `--delete-remote` flags, up to 5 more times. A re-run
resumes where the last one stopped:

- A clean `HEAD` that is already on its upstream skips verify and commit,
  because it was verified before it was pushed.
- The push is a no-op, and the open PR is reused.
- The merge subject comes from `--subject`, the one saved in the PR body, or a
  Conventional PR title.

Each extra round is one short tool call.

## Release tag prompt

`ship` never creates a tag unless you explicitly choose one.

- With `tag=<semver>` in the arguments, it tags straight away through `make tag`,
without asking. The version is passed as both `version=<v>` and `VERSION=<v>`,
so the target can read either spelling.
- With `no tag` (in any wording), it doesn't ask; the result shows `tag=declined`.
- Otherwise, if the repo has a `make tag` target, `run` only *recommends*. It
  ends with `tag=ask tag_recommended=<v> tag_options=<recommended>,<others>
  latest=<v>`. The recommendation comes from the merge subject: `feat` is a
  minor bump, `!` is a major one (a minor one before 1.0), anything else is a
  patch.
- The command then asks once with `AskUserQuestion`. **"No tag" is the first
  option**, followed by each option, with the recommended one marked
  "(suggested)". Only an explicitly chosen or typed version runs
  `ship.sh tag <v>`, from the primary worktree. Any other answer, or none,
  means no tag.
- Repos without a `make tag` target are never asked (`tag=none`).

## Progress and failures

- **Progress:** `run` prints a `ship: started; live output: tail -f <log>` line,
  then `ship: [n] <stage> ...` and `ship: [n] <stage> -> <state>` for each
  stage. `tail -f` the log for full live output, including the CI watch.
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

## Titles and subjects

A PR title is **plain prose** (`Add a discovery view for albums`). The squash
subject is a separate **Conventional Commit** line
(`feat(webui): add discovery view`). The writer (haiku, or the Opus
`pr-writer`) produces both in one pass, so it costs about one extra output line.

- **Saved in the PR.** `run` adds `<!-- gitauto-subject: <subject> -->` to the
  PR body. A later `ship`, in any session, reads it back without a model.
- **Uses.** The subject is the commit message by default, the squash subject
  (`<subject> (#N)`), and the signal for the tag bump.
- **Where the merge subject comes from**, in order: `--subject`, then the
  subject saved in the PR body, then a PR title that is already Conventional.
- **Fallback for PRs without one** (opened by hand, or before this change) that
  have a prose title: `prepare` reports `need=subject` with a `pr_title:` line,
  and haiku reshapes that one line. If `run` still has no subject, it stops
  with `state=needs-subject` *before* waiting on CI.
- **Validation.** An invalid `--subject` fails before any mutation. `open-pr`
  never asks for a subject for an existing PR, since it doesn't merge.

## Output

```text
DONE state=created|unchanged|nothing|failed ...        # nothing left for the model
SHIP ... need=... writer=... / NEED_NAME ...            # prepare / branch-out: context follows
--- write                                               # then `<key>: <rule>` per text to write
ship: [n] <stage> ... / -> <state>                      # progress, one pair per stage
--- failure: verify|wait-ci ...                         # only on those failures
SHIPPED pr=#N url=... sync=synced cleanup=clean ... tag=ask|declined|none|tagged ... log=<file>
READY pr=#N url=... ci=green|none log=<file>            # open-pr: PR open, CI green, not merged
TAGGED version=<v> latest=<v> log=<file>                # after an explicitly chosen tag
PARTIAL ...                                             # merged, but sync/cleanup/tag incomplete
WAITING stage=wait-ci pr=#N url=... log=<file>          # CI still running; re-run to resume
STOPPED stage=<stage> state=<state> report=<why> log=<file>
```

The full helper output goes to the log file, not into the model's context.

## Safety

`scripts/gitauto-*.sh` are self-contained guarded helpers, each with its own
test. Every guard applies:

- `main`, `master`, and the resolved default branch are protected; detached
  HEAD and an unresolvable `origin` default are refused. Every mutating helper
  re-checks the guard right before it acts.
- Verification (Make `verify`, then `test`/`lint`/`vet`/`check`, npm scripts,
  Go checks, or Maven `verify` via `./mvnw` or `mvn`) must pass or skip before
  anything is committed.
- The merge needs a valid Conventional Commit subject, a matching PR head, and
  checks that are green or explicitly absent.
- Sync fast-forwards only and refuses a dirty primary worktree. Cleanup keeps
  the local branch and deletes the remote branch only with `deleteRemote=true`.
  Tagging happens only with an explicit `tag=<semver>` or an explicit answer to
  the tag question.
- **Merged-PR guard:** new work on a branch whose PR is already merged is never
  skipped past. `prepare` refuses a dirty tree, and `run` stops unless `HEAD` is
  exactly the merged PR's head commit.

`ship` stages everything (`git add -A`), including unrelated changes in the
working tree. Check `git status` first.

## Tests

```sh
bash plugins/gitauto/scripts/run-tests.sh
node --test plugins/gitauto/pi/*.test.ts
```

The first runs `branch-out.test.sh`, `ship.test.sh` (a local bare remote plus a
fake `gh`, end to end), and the helper tests. The second runs the pi adapter's
parser and flow tests, plus end-to-end runs of the pi commands against the real
scripts with a fake model and the same fake `gh` (`scripts/testdata/fake-gh`).
`npm test` from the repository root runs both.

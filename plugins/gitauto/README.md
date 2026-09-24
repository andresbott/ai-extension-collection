# gitauto

A guarded Git delivery suite. Every step of the flow — branch, verify, commit,
push, open a pull request, wait for CI, merge, synchronize the default branch,
clean up, tag — is a slash command backed by a deterministic bash helper that
owns the mutation and enforces its own safety checks. `/gitauto:ship` runs the
whole flow in order and reports a stage ledger.

## Commands

| Command | Arguments | Behaviour |
|---|---|---|
| `/gitauto:branch` | `[name]` | On `main`/`master`, creates and checks out a feature branch; an explicit name wins, otherwise a name is inferred from the uncommitted changes, with deterministic file-based and invented fallbacks. Existing feature branches are left unchanged. |
| `/gitauto:verify` | `[check \| target=<make-target>]` | Runs one explicit check or Make target when supplied; otherwise prefers a `verify` Make target, then declared `test`, `lint`, `vet`, and `check` targets, then package scripts or standard Go module checks. Stops on the first failure and returns `pass`, `fail`, or `skip`. |
| `/gitauto:commit` | `[message]` | On a feature branch, stages everything and creates exactly one commit with a one-line message (supplied verbatim, or composed from the diff). No body, no `Co-Authored-By`. Clean trees are unchanged; `main`, `master`, and detached HEAD are blocked before staging. |
| `/gitauto:push` | `[remote=<name>]` | Pushes the current feature branch and configures its upstream, re-checking the protected-branch guard immediately before pushing. Defaults to `origin`. |
| `/gitauto:open-pr` | `[title=<text>] [body=<markdown>] [base=<branch>]` | Reuses an existing open pull request or creates one for the current branch. Merged and closed pull requests stay distinct, and lookup failures never fall through to creation. A missing title or body is composed as a compact `## Summary` / `## What` / optional `## Notes` description. |
| `/gitauto:wait-ci` | `[pr=<number>]` | Watches the pull request checks and returns `green`, `failed`, `none`, `pending`, or `blocked`. Never merges; "no checks configured" stays distinct from a failure. |
| `/gitauto:merge` | `[pr=<number>] [subject=<conventional-subject>]` | Squash-merges one open pull request with a validated Conventional Commit subject, after confirming the head matches the current branch and checks are green or explicitly absent. Already-merged pull requests are idempotent. |
| `/gitauto:sync-main` | `[remote=<name>] [main=<branch>]` | Locates the primary worktree, refuses to overwrite a dirty one, switches it to the default branch, fetches, and fast-forwards only. |
| `/gitauto:cleanup` | `[branch=<feature>] [remote=<name>] [deleteRemote=true\|false]` | Prunes remote state and removes clean, inactive worktrees for a merged branch. The local branch is always kept, remote deletion requires an explicit `deleteRemote=true`, and active or dirty worktrees are deferred and reported as partial. |
| `/gitauto:tag` | `[version=<semver>] [subject=<conventional-subject>] [remote=<name>] [worktree=<path>]` | Without a version, recommends the next SemVer and publishes nothing. An explicit, strictly increasing version runs from the synchronized primary default-branch worktree and authorizes the repository's `make tag` target. |
| `/gitauto:ship` | `[branch=] [message=] [title=] [body=] [subject=] [base=] [remote=] [deleteRemote=] [tag=]` | Runs the full flow in order and keeps a stage ledger (see below). |

`/gitauto:ship` runs the stages in exactly this order:

```text
branch → verify → commit → push → open-pr → wait-ci → merge → sync-main → cleanup → optional tag
```

A failed required pre-merge stage stops the flow immediately and the partial
ledger is still reported. An already-merged pull request skips the redundant
wait-ci and merge stages and continues with synchronization and cleanup. A
cleanup or tag failure after a successful merge is reported as `partial` — never
as a merge failure. Remote deletion happens only with `deleteRemote=true`, and
tagging only when an explicit `tag=<version>` was supplied.

Every command ends its response with a fenced `text` block of `key=value` lines
mirroring the helper output, so the result is machine-readable and cannot be
softened in prose.

## Safety model

Each command is a thin launcher. The real work runs in three layers:

```text
/gitauto:<leaf>  →  workflows/<leaf>.js  →  scripts/gitauto-<leaf>.sh
   command            dynamic workflow        deterministic helper
```

The command exists only to resolve `${CLAUDE_PLUGIN_ROOT}` and hand the workflow
a `root` pointing at `scripts/`; a workflow cannot resolve that variable itself.
The workflow owns the prompt and a JSON output schema the runtime validates and
retries against. The helper owns every mutation.

The split below is deliberate and identical across all leaves:

- **The bash helpers in `scripts/` own every mutation.** Staging, committing,
  branching, pushing, pull request creation, merging, fetching, fast-forwarding,
  worktree removal, and tagging happen only inside a helper.
- **The helpers own discovery and guards.** They resolve the remote default
  branch without mutating refs (cached remote HEAD, remote symref, `gh`, then
  local `main`/`master` only when the remote is unconfigured), treat `main`,
  `master`, and the resolved default branch as protected, refuse to act on a
  detached HEAD, refuse when a configured `origin` has an unresolvable default
  branch, and re-check branch safety immediately before the mutating step.
- **The agent only chooses names, messages, and prose.** It may inspect the
  repository with read-only commands (`git status`, `git log`, `git diff`,
  `git branch`, `git worktree list`, `gh pr view`) to compose a branch name, a
  commit message, a pull request title and body, or a Conventional Commit
  subject — then it calls the helper once and reports what the helper printed.
- **Each helper runs at most once per command.** Commands are explicitly
  forbidden from re-running a helper to work around a `blocked` or `failed`
  result.

Workflow names are suffixed `-run` (`gitauto:verify-run`) so they do not collide
with the command names (`/gitauto:verify`). Without that suffix the slash command
resolves to the workflow instead of the command, which launches it with no `root`.

## Claude Code

Install the plugin from the marketplace and the commands appear as
`/gitauto:<leaf>`:

```text
/plugin install gitauto@ai-extension-collection
```

Claude Code auto-discovers both `commands/` and `workflows/`, and substitutes
`${CLAUDE_PLUGIN_ROOT}` in command markdown with the installed plugin directory,
so the helpers are invoked from the plugin's own `scripts/`.

## Pi

Pi is not wired up yet. Its `pi-claude-marketplace` bridge handles `agents/`,
`commands/`, `hooks/`, `mcp`, and `skills/` — there is no `workflows/` bridge, so
a plugin-shipped workflow is currently Claude Code only.

The workflow scripts themselves remain Pi-compatible: each falls back to
`$HOME/.pi/workflows/saved` when no `root` argument is supplied, which is where
the upstream `pi-code-config` Makefile installs the helpers. Wiring Pi to load
them from the plugin is still an open task.

## Requirements

- `bash` and `git` for every command.
- The GitHub CLI `gh`, authenticated, for `open-pr`, `wait-ci`, and `merge`
  (and, as a fallback, for default-branch resolution).
- A `tag` target in the repository's `Makefile`, `makefile`, or `GNUmakefile`
  for `tag`. Without it, tagging is blocked.
- `verify` uses whatever the repository declares: Make targets, package scripts,
  or Go module checks. It skips cleanly when it finds none.

## Tests

The helpers have their own test suite. Each test builds throwaway Git fixtures
in `$TMPDIR` and never touches the surrounding repository:

```sh
bash plugins/gitauto/scripts/run-tests.sh
```

It runs every `scripts/*.test.sh` file and fails if any of them fails.

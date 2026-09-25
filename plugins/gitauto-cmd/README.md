# gitauto-cmd

A token-cheap version of [`gitauto`](../gitauto). Where `gitauto` runs each
stage through a dynamic workflow with schema-validated subagents, `gitauto-cmd`
uses a plain slash command plus one bash script. The script does the work; the
model only writes the one thing a script can't: a branch name.

## Commands

| Command | Arguments | Behaviour |
|---|---|---|
| `/gitauto-cmd:branch-out` | `[branch name]` | On `main`/`master`/the default branch, creates and checks out a feature branch; otherwise leaves the current branch unchanged. |

## How it stays cheap

```text
/gitauto-cmd:branch-out  →  !`branch-out.sh`  →  (only if needed) branch-out.sh --create
```

- **`!` preprocessing** runs `scripts/branch-out.sh` before the model sees the
  prompt, so there's no exploratory tool call.
- **Zero-tool paths.** Already on a feature branch, or given a valid explicit
  name: the script finishes during preprocessing and prints one `DONE` line. The
  model echoes it without calling any tools.
- **One tool call otherwise.** With no name (or a plain-language hint), the
  script prints `NEED_NAME` plus at most 25 lines of `git status --short`. The
  model proposes 3 names and calls `--create` once.
- **No retry rounds.** If every candidate is taken, the script tries `-2`…`-9`
  suffixes on the first valid one instead of asking the model again.
- **`model: haiku`** and single-line output.

## Safety

The same guards as `gitauto`'s branch stage (`scripts/lib.sh` is copied from
`gitauto-lib.sh`, so this plugin has no install-time dependency on `gitauto`):

- `main`, `master`, and the resolved remote default branch count as protected.
- It refuses on a detached HEAD or when `origin`'s default branch can't be
  resolved.
- Candidates are validated with `git check-ref-format` and checked against
  local and `origin` branches.
- The protected-branch guard is re-checked right before `git switch -c`.

## Output

Every run ends with exactly one line:

```text
DONE state=created branch=<name> from=<base>
DONE state=unchanged branch=<name>
DONE state=failed report=<reason>
```

## Tests

```sh
bash plugins/gitauto-cmd/scripts/branch-out.test.sh
```

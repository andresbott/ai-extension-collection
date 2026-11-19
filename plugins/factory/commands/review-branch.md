---
description: Use when the user wants the changes on the current branch reviewed by several specialised reviewers before they open a pull request, including uncommitted and untracked work, in a normal or an exhaustive low-noise review. Prints the findings, then offers to fix the chosen ones through the factory's delivery engine, each fix starting from a failing test for the finding's scenario.
disable-model-invocation: true
---

# Review the current branch

Review everything the current branch changes against its base: its commits
plus the uncommitted and untracked work in the checkout. Print the findings,
then offer to fix them.

This command is an entry point to the factory's review engine. First read
`${CLAUDE_PLUGIN_ROOT}/references/review-engine.md` and follow it for the
whole review. This file says which change to review, how to print it, and
what happens after; it only adds to the engine, never relaxes it.

## What this entry point provides

- **Snapshot:** "Snapshot the branch" below.
- **Intent:** under "The author says:", what the user said about this work,
  quoted verbatim (the part of the command's arguments that describes the
  work, without a mode or base branch, and, when this conversation built the
  change, the user's requests in it), then the branch's commit messages
  (`git log --format=%B <base>..HEAD`). Empty when there is neither.
- **Print:** "Print the findings" below.
- **Clean up:** "Clean up" below.
- **After:** "Offer fixes" below.

## Snapshot the branch

Never change the user's checkout, index, or branch while doing this.

1. **Find the base.** If the user named a base branch or commit, use it.
   Otherwise find the default branch's name: `git symbolic-ref --short
   refs/remotes/origin/HEAD` without its `origin/` prefix, else `main` or
   `master`, whichever exists. Compare against the local branch of that name
   when it exists, else `origin/<name>`, and use `git merge-base HEAD
   <that>`. When the current branch (`git branch --show-current`) is the
   default branch itself, the base is `HEAD`, so only the uncommitted work is
   reviewed.
2. **Make the run folder:** `mktemp -d -t review-branch-XXXX`, with a
   `scratch/` folder inside.
3. **Capture the working tree** in a commit of its own, through a temporary
   index so the user's index is untouched. From the repository root:
   - `GIT_INDEX_FILE=<run>/index git read-tree HEAD`
   - `GIT_INDEX_FILE=<run>/index git add -A` (tracked changes, deletions, and
     untracked files that are not ignored)
   - `GIT_INDEX_FILE=<run>/index git write-tree` gives the tree
   - If the tree equals `HEAD^{tree}`, there is no uncommitted work and the
     head is `HEAD`. Otherwise the head is `git commit-tree <tree> -p HEAD -m
     'review-branch snapshot'`.
   Keep the tree id: "Offer fixes" compares against it.
4. **Hold the head in a ref of its own:** `git update-ref
   refs/review-branch/<run-folder-name> <head>`.
5. **Add the worktree:** `git worktree add --detach <run>/worktree <ref>`.
6. **Save the diff:** `git diff <base> <head> > <run>/changes.diff`, and the
   changed files from `git diff --name-only <base> <head>`.

## Print the findings

A finding may point at any line of the head version, inside the diff or not.
Print exactly this, and nothing else before it, blockers first, then
should-fix, then nits:

```
## Review of <branch>
<base short sha>..<head short sha> · <n> commits<, plus uncommitted work> · <normal|exhaustive>
<one sentence: the verdict>

### Findings (<count>)

1. `<path>:<line>` or `<path>:<start>-<end>` · <severity>
   <written by the engine's rules; at most four lines>
```

End with one line: how many findings were refuted or trimmed and, in
exhaustive mode, how many were dropped as one-off.

## Clean up

- `git worktree remove --force <run>/worktree`
- `git update-ref -d refs/review-branch/<run-folder-name>`
- `rm -rf <run>`
- `git worktree prune`

The snapshot commit is left unreferenced; git collects it in time.

## Offer fixes

With no findings, stop here. Otherwise:

1. **Check for edits during the review.** Build the working tree's tree
   again, as in step 3 of the snapshot, with the temporary index in a fresh
   `mktemp -d` folder that you delete afterwards. If it differs from the
   reviewed tree, the user changed code during the review: say so in the
   question, since some findings may point at lines that moved or are
   already fixed.
2. **Ask once** with these numbered lines, numbers included, and wait:
   1. Fix the blockers and should-fix findings (`<count>`).
   2. Fix every finding, nits included (`<count>`).
   3. Fix only the findings I name (answer with their numbers, such as
      `3: 1,4`).
   4. No fixes.

   When there is uncommitted work, the fixes cannot start on top of it, so
   add: "Your uncommitted work is committed first, as one commit, so the
   fixes build on it. That includes these untracked files: <the untracked,
   not ignored files from `git status --short`, or "none">. To commit it
   yourself instead, answer `4` and commit it first." This question is the
   user's consent to that commit; without uncommitted work, nothing is
   committed for the user.
3. **No fixes:** stop.
4. **Fixes:** run the chosen findings through the delivery engine, as below.
   The engine's step 1 still shows its restatement and groups, but waits for
   an answer only when a question there is the user's.

### Fixing through the delivery engine

Read `${CLAUDE_PLUGIN_ROOT}/references/delivery-engine.md` and follow it for
the rest of the run, with this as its entry point. It only adds to the
engine, never relaxes it.

- **Collect:** one task per chosen finding. The task's words are the finding
  in full, from the engine's result, not the shorter printed text: its path
  and line, severity, claim, failing scenario, and fix. Add the user's answer
  to the fix question, quoted verbatim, as an answer on every task. The
  findings are verified, so the delivery engine's "understand each task"
  subagent only locates the code and the overlaps; it does not re-review.
- **Record:** a notes file outside the repo, `tasks.md` in a temp folder
  created once for the fixes (`mktemp -d -t review-branch-fix-XXXX`; the
  engine's plans go in the same folder). One section per task: the finding
  quoted verbatim, its state, and every note appended under it. Never
  rewrite the quoted finding.
- **States:** a `State:` line per task in `tasks.md`, starting at `open`.
  Follow-up items are listed under the task, each marked open, built, not
  needed, or the user's.
- **Save:** nothing to commit; `tasks.md` stays outside the repo.
- **Follow-ups:** mark each item in `tasks.md` as the engine's "Follow-ups"
  decides. A task with items to build goes back to `open`.

**Commit the uncommitted work first.** In the delivery engine's step 1, right
after "Leave main", if the working tree has uncommitted or untracked work,
stage it with `git add -A` and commit it as one commit with a one-line message
that names the work (such as `wip: <branch> before review fixes`). Do it
before the baseline, so the fixes and their reverts never mix with the
user's work.

**Implementer rules, added to every implementer prompt:**

- Start from the finding's failing scenario. Write a test that fails for that
  input or state and shows the wrong result, and watch it fail before you
  change the code. If you cannot make it fail, change nothing and report
  "not reproduced" with what you tried; the task is deferred with that.
- A finding with no failing scenario (a missing test, a convention, a
  refactor) needs the check that proves it is done instead: the missing test
  itself, the rule's check, or tests that pin the current behaviour before
  and after a refactor.

**Additions to the report:**

- the path of `tasks.md`
- the findings that were not chosen, by number, as left open

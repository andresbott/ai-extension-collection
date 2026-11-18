---
name: review-pr
description: Use when the user wants a GitHub pull request reviewed by several specialised reviewers, given by number or URL or as the pull request of the current branch, in a normal or an exhaustive low-noise review, with the review comments printed for them to check instead of posted.
disable-model-invocation: true
---

# Review a pull request

You are the orchestrator. Subagents review the pull request (PR) in an
isolated git worktree; you pick them, merge and verify what they find, and
print the result as one GitHub review: a short summary body plus inline
comments anchored to lines of the PR's diff.

**Never post anything.** No `gh pr review`, `gh pr comment`, `gh api` writes,
approvals, commits, or pushes. Print the review; the user decides what to do
with it.

## 0. Choose the mode

- **Normal:** one team of reviewers, every finding verified.
- **Exhaustive:** three independent teams review in parallel, and a final
  pass keeps only what at least two teams found, or a blocker it confirms.
  About three times the time and cost, with less noise and nitpicking.

If the user's words name the mode ("normal" or "exhaustive"), use it.
Otherwise ask which one, with the two lines above, and wait for the answer
before anything else.

## 1. Check out the PR

1. **Find the PR.** Use the number or URL the user gave. With none, use the
   PR of the current branch (`gh pr view --json number`); if there is none,
   say so and stop.
2. **Read it:** `gh pr view <n> --json
   number,title,body,url,state,baseRefName,baseRefOid,headRefOid,files`.
   A merged or closed PR is still reviewed; say its state in the header.
3. **Make the run folder:** `mktemp -d -t review-pr-XXXX`, with a `scratch/`
   folder inside. Everything the run creates lives in it: the worktree, the
   diff, and every subagent's scratch work.
4. **Fetch the head into a ref of its own,** never through `FETCH_HEAD`
   (other sessions share it): `git fetch origin
   +refs/pull/<n>/head:refs/review-pr/<run-folder-name>`. Check that the ref
   resolves to `headRefOid`. If it does not, the PR moved: re-read it and
   fetch again, once.
5. **Add the worktree:** `git worktree add --detach <run>/worktree <ref>`.
   Never check out, switch, or change anything in the user's own checkout.
6. **Save the diff:** `gh pr diff <n> > <run>/pr.diff`. This is the diff
   GitHub shows, and the only lines an inline comment can be anchored to.

## 2. Pick the reviewers

Always these three:

- **Correctness:** bugs, edge cases, error handling, and security in the
  changed code.
- **Intent:** whether the change does what the PR title and body say, all of
  it, and nothing unrelated.
- **Tests and conventions:** runs the project's checks in the worktree when
  they run without network installs, and judges whether new behaviour is
  tested. Also checks the repository's own rules (AGENTS.md, CLAUDE.md,
  CONTRIBUTING).

Then one per area of the diff that carries real logic (a language, a
framework, an API spec, infrastructure code):

- If an installed specialist agent fits the area, use it.
- Otherwise launch a general subagent and open its prompt with the role
  ("You are a senior Ansible engineer reviewing ...").
- If the PR changes an agent's own definition, do not use that agent to
  review it; brief a general subagent as that expert instead.

At most six reviewers. Version bumps, lock files, and generated files need no
reviewer of their own.

## 3. Brief and run them

Run all reviewers in parallel. Give each its own scratch folder,
`<run>/scratch/<role>` (for example `scratch/correctness`), and create it
before it starts. Every brief contains:

- the PR title and body verbatim, under "The PR says:"
- the worktree path, `<run>/pr.diff`, and the head and base commits
- its focus, from step 2, with pointers to what to check
- these rules:
  - read only the worktree, the run folder, and public documentation; never
    search or read other paths on the machine, such as other repositories
  - never edit files in the worktree: copies, builds, and throwaway tools go
    in its scratch folder, and every command runs with `TMPDIR` set to that
    folder; checks that only write build output may run in the worktree
  - no git commands that change anything; no `gh` writes; do not post
- the report shape: per finding, the path, the line or line range in the
  head version, the severity (`blocker`, `should-fix`, or `nit`), what is
  wrong, the evidence (read, ran, or reproduced, and how), and the suggested
  fix; then one line on what it checked and found fine; under 400 words

Point them at what to check, and leave out your own verdict on the change.

**Exhaustive mode:** launch three teams, `a`, `b`, and `c`, all in parallel,
each with the full set of reviewers from step 2 and the same briefs. Every
reviewer is a fresh subagent that is not told about the other teams, and its
scratch folder is `<run>/scratch/<team>-<role>` (for example
`scratch/b-correctness`).

## 4. Merge and verify

**Normal mode:**

1. **Merge.** One finding per root cause. Where reviewers overlap, keep the
   clearest wording and the severity the evidence supports.
2. **Trim.** Keep every blocker and should-fix item, and at most five nits in
   total (inline and outside the diff), the most useful ones.
3. **Verify.** Launch one fresh subagent with every finding left, the
   worktree, and its own scratch folder (`<run>/scratch/verify`), under the
   reviewer rules from step 3: each finding's claim and location, without
   the reviewers' evidence. It confirms or refutes each one, by reading the
   code first and reproducing only when reading cannot settle it. Drop the
   refuted ones.

**Exhaustive mode:**

1. **Merge per team.** Merge each team's findings on their own, as in normal
   mode, into three lists. Do not trim or drop anything yet.
2. **Final pass.** Launch one fresh subagent with the three lists, labelled
   by team (each finding's claim, location, and severity, without the
   reviewers' evidence), the worktree, and its own scratch folder (`<run>/scratch/final`),
   under the reviewer rules from step 3. It:
   - matches findings across the lists by root cause, not by wording
   - keeps a finding only when at least two teams raised it, or when one team
     rated it a blocker and the final pass confirms it is one
   - drops everything else as one-off noise
   - verifies each kept finding against the code, as the verifier in normal
     mode does, and drops the refuted ones
   - reports, per kept finding, the claim, the location, the severity the
     evidence supports, how many teams raised it, and its evidence
3. **Trim.** As in normal mode, at most five nits in total.

**Both modes:**

1. **Anchor.** A finding becomes an inline comment only when its path is in
   the PR's files and its line or range lies inside one hunk of `pr.diff`:
   on the new side (`RIGHT`), or on the old side (`LEFT`) for a removed line.
   - About several places: anchor on the main one, name the others in the
     text.
   - About a missing test: anchor on the changed code that is untested.
   - Everything else (files or lines outside the diff, the PR title or
     description) goes in the summary body, under "Outside this diff".

## 5. Print the review

Print exactly this, and nothing else before it:

```
## Review of #<n>: <title>
<url> · <state> · head <short sha> · <normal|exhaustive>
Would post as: REQUEST_CHANGES | COMMENT

### Review body
<one sentence: the verdict>
- <up to four bullets: the points that matter most>

Outside this diff:
- <findings that could not be anchored; omit the block when empty>

### Inline comments (<count>)

1. `<path>:<line>` or `<path>:<start>-<end>` · <RIGHT|LEFT> · <severity>
   <the comment as posted: what is wrong, why it matters, the fix; at most
   six lines>
```

In exhaustive mode, end each comment's first line with the number of teams
that raised it (`· 2/3 teams`).

Use `REQUEST_CHANGES` when there is a blocker, otherwise `COMMENT`. End with
one line: "Not posted." plus how many findings were refuted or trimmed and,
in exhaustive mode, how many were dropped as one-off.

## 6. Clean up

Always, also when an earlier step failed:

- `git worktree remove --force <run>/worktree`
- `git update-ref -d refs/review-pr/<run-folder-name>`
- `rm -rf <run>`
- `git worktree prune`

Then check that `git worktree list` no longer shows the run's worktree.

## Common mistakes

| Mistake | Fix |
| --- | --- |
| Inline comment on a file or line outside the PR's diff | GitHub rejects it: move it under "Outside this diff" |
| One comment listing many lines ("L4, L77–94, L107") | Anchor on the main place, name the others in the text |
| Reading the head through `FETCH_HEAD` | Fetch into `refs/review-pr/<run>` and check it against `headRefOid` |
| Reviewers sharing one scratch folder overwrite each other's copies | One folder per subagent, `<run>/scratch/<role>` |
| Tools write temp files to `/tmp` or `~` | Run every command with `TMPDIR` set to the subagent's scratch folder |
| A subagent searches the machine for related repositories | Worktree, run folder, and public docs only |
| Long review body that repeats the inline comments | One verdict sentence and at most four bullets |
| Exhaustive teams told about each other, or sharing a reviewer | Fresh subagents per team, no mention of the other teams |
| Starting before the mode is settled | Ask normal or exhaustive first, unless the user named one |

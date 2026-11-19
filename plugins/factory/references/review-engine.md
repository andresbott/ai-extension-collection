# Review engine

The shared process behind the factory's review commands (`review-pr`,
`review-branch`). The command that sent you here is the **entry point**: it
says which change to review, what it claims to do, and how to print the
result. This file says how to review it. The entry point only adds steps or
fills in what is listed under "What the entry point provides"; it never
relaxes the rules here.

You are the orchestrator. Subagents review the change in an isolated git
worktree; you pick them, merge and verify what they find, and hand the
verified findings to the entry point's printer.

**Never post or change anything during the review** (steps 0 to 6). No
`gh pr review`, `gh pr comment`, `gh api` writes, approvals, commits on any
branch, or pushes, and nothing that checks out, switches, or changes the
user's own checkout. The only objects, refs, and worktrees the review may
create are the ones the entry point's snapshot names, and it removes the refs
and worktrees at the end. The entry point's "After" step (step 7) is outside
the review: it may change the checkout only as that step says, and only after
the user agreed to it.

## What the entry point provides

- **Snapshot:** a run folder `<run>` (from `mktemp -d`) with a `scratch/`
  folder inside, a detached worktree of the head at `<run>/worktree`, the
  diff from base to head at `<run>/changes.diff`, the base and head commits,
  and the list of changed files. Everything the run creates lives in `<run>`.
- **Intent:** what the change says it does, quoted verbatim, under a label
  (such as "The PR says:"). It may be empty.
- **Print:** how to print the findings, and what to do with findings that
  cannot be placed.
- **Clean up:** what to remove, always, also when an earlier step failed.
- **After:** anything that happens once the review is printed. Optional.

## 0. Choose the mode

1. **Normal:** one team of reviewers, every finding verified.
2. **Exhaustive:** three independent teams review in parallel, and a final
   pass keeps only what at least two teams found, or a blocker it confirms.
   About three times the time and cost, with less noise and nitpicking.

If the user's words name the mode ("normal" or "exhaustive"), use it.
Otherwise ask which one, with the two numbered lines above, numbers included,
so the user can answer `1` or `2`, and wait for the answer before anything
else, including the entry point's snapshot.

## 1. Snapshot

Follow the entry point's steps to build the snapshot. If there is nothing to
review (an empty diff), say so, clean up, and stop.

## 2. Pick the reviewers

Always these three:

- **Correctness:** bugs, edge cases, error handling, and security in the
  changed code.
- **Intent:** whether the change does what the intent says, all of it, and
  nothing unrelated. With an empty intent, only whether something unrelated
  slipped in.
- **Tests and conventions:** runs the project's checks in the worktree when
  they run without network installs, and judges whether new behaviour is
  tested. Also checks the repository's own rules (AGENTS.md, CLAUDE.md,
  CONTRIBUTING).

Then one per area of the diff that carries real logic (a language, a
framework, an API spec, infrastructure code):

- If an installed specialist agent fits the area, use it.
- Otherwise launch a general subagent and open its prompt with the role
  ("You are a senior Ansible engineer reviewing ...").
- If the change edits an agent's own definition, do not use that agent to
  review it; brief a general subagent as that expert instead.

At most six reviewers. Version bumps, lock files, and generated files need no
reviewer of their own.

## 3. Brief and run them

Run all reviewers in parallel. Give each its own scratch folder,
`<run>/scratch/<role>` (for example `scratch/correctness`), and create it
before it starts. Every brief contains:

- the intent verbatim, under the entry point's label
- the worktree path, `<run>/changes.diff`, and the head and base commits
- its focus, from step 2, with pointers to what to check
- these rules:
  - read only the worktree, the run folder, and public documentation; never
    search or read other paths on the machine, such as other repositories or
    the user's own checkout
  - never edit files in the worktree: copies, builds, and throwaway tools go
    in its scratch folder, and every command runs with `TMPDIR` set to that
    folder; checks that only write build output may run in the worktree
  - no git commands that change anything; no `gh` writes; do not post
- the report shape: per finding, the path, the line or line range in the
  head version, the severity (`blocker`, `should-fix`, or `nit`), what is
  wrong, the failing scenario when there is one (the input or state, and the
  wrong result), the evidence (read, ran, or reproduced, and how), and the
  suggested fix; then one line on what it checked and found fine; under 400
  words

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
   total, the most useful ones.
3. **Verify.** Launch one fresh subagent with every finding left, the
   worktree, and its own scratch folder (`<run>/scratch/verify`), under the
   reviewer rules from step 3: each finding's claim, location, and failing
   scenario, without the reviewers' evidence. It confirms or refutes each
   one, by reading the code first and reproducing only when reading cannot
   settle it. Drop the refuted ones.

**Exhaustive mode:**

1. **Merge per team.** Merge each team's findings on their own, as in normal
   mode, into three lists. Do not trim or drop anything yet.
2. **Final pass.** Launch one fresh subagent with the three lists, labelled
   by team (each finding's claim, location, failing scenario, and severity,
   without the reviewers' evidence), the worktree, and its own scratch folder
   (`<run>/scratch/final`), under the reviewer rules from step 3. It:
   - matches findings across the lists by root cause, not by wording
   - keeps a finding only when at least two teams raised it, or when one team
     rated it a blocker and the final pass confirms it is one
   - drops everything else as one-off noise
   - verifies each kept finding against the code, as the verifier in normal
     mode does, and drops the refuted ones
   - reports, per kept finding, the claim, the location, the failing
     scenario, the severity the evidence supports, how many teams raised it,
     and its evidence
3. **Trim.** As in normal mode, at most five nits in total.

The result is the list of verified findings, each with its path, line or
range, severity, claim, failing scenario (when there is one), fix, and, in
exhaustive mode, how many teams raised it. Keep it for the entry point's
"After" step: the printed text is shorter than the finding.

## 5. Print

Print as the entry point says. **Write every finding and bullet so the author
gets it in about ten seconds,** without opening another file:

1. **The problem first:** one sentence on what goes wrong and when, with the
   concrete case (the input, the state, the caller), not a category such as
   "possible race condition".
2. **The fix:** one sentence on what to change. Add a short code suggestion
   only when it is shorter than describing it.
3. **Evidence only when it is not obvious:** a one-line repro or the failing
   case, never the reviewer's whole trail.

Cut whatever the author can read from the lines the finding points at: do not
restate the code, quote the diff, or explain what the code does. No hedging
("maybe", "consider", "it might be worth"), no praise, no mention of
reviewers, teams, or verification. Plain words, short sentences, and keep it
shorter whenever cutting more loses nothing.

In exhaustive mode, end each finding's first line with the number of teams
that raised it (`· 2/3 teams`).

## 6. Clean up

Follow the entry point's clean-up, always, also when an earlier step failed.
Then check that `git worktree list` no longer shows the run's worktree.

## 7. After

Follow the entry point's "After" step, if it has one.

## Common mistakes

| Mistake | Fix |
| --- | --- |
| One finding listing many lines ("L4, L77–94, L107") | Point at the main place, name the others in the text |
| Reviewers sharing one scratch folder overwrite each other's copies | One folder per subagent, `<run>/scratch/<role>` |
| Tools write temp files to `/tmp` or `~` | Run every command with `TMPDIR` set to the subagent's scratch folder |
| A subagent searches the machine for related repositories, or reads the user's checkout | Worktree, run folder, and public docs only |
| Finding that restates the code or explains what it does | Problem and when it happens, then the fix; the author sees the code |
| Exhaustive teams told about each other, or sharing a reviewer | Fresh subagents per team, no mention of the other teams |
| Starting before the mode is settled | Ask normal or exhaustive first, unless the user named one |

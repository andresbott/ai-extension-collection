---
name: auto-improve
description: Use when you will be away and want the agent to improve the current branch's stability, code quality, and architecture unattended. One reviewer subagent finds the issues, a fresh subagent fixes each one (failing test first, all checks green before every commit), complex findings optionally get a plan and are landed by subagents, and a second, independent review checks the fixes. Asks up front whether breaking changes are allowed and whether to tackle complex findings. Tracks every finding in TODO.md.
disable-model-invocation: true
---

Improve this codebase's stability, code quality, and architecture on the
current branch, unattended. If the user named a path or area, limit the work to
it.

The user is about to leave. Ask your questions in the first step, then work
through to the end without asking again: decide, write the decision in
TODO.md, and continue.

You are the orchestrator. Subagents do the reading, fixing, and check runs, so
your own context stays clean for the whole run. Ask each subagent for a report
under 700 words; fix subagents need far less.

The user's own words are the reference for the whole run: the request that
started it, the scope, and the answers from step 0. Every subagent prompt quotes
them verbatim under "The user asked:", with your reading of them separately
under "My reading:", never as settled rulings.

## 0. Before the user leaves

1. Check the branch. If it is `main` or `master`, ask the user which branch to
   work on, and wait.
2. Restate the request: the scope and anything else the user asked for, each
   with a "Read as:" line. Name every word or phrase that could mean two
   things, with both meanings. If a fork would lead to different work and the
   context does not settle it, add it as a question to the ones below; this is
   the last chance to ask.
3. Ask the user two questions together and wait for the answers:
   - **Are breaking changes allowed?** Breaking means a change to a public
     API, CLI flags, config or file formats, wire formats, or a stored schema.
     Include the answer in every reviewer, planner, and fixer prompt.
   - **Should it also tackle complex findings?** Complex means a large effort,
     or a fix that spans several modules or needs a design choice. With "no",
     complex findings are deferred with a plan; with "yes", step 5 plans and
     lands them.
4. Choose how to write TODO.md:
   - If the `todo` command is installed (`todo --version` succeeds), make every
     TODO.md change through it: `todo add-category`, `todo add --title --desc
     --parent-title`, `todo progress`, `todo done`, `todo defer`, `todo edit
     --set-desc`, and `todo list --json` to read. It writes the file in the
     format the user's tools expect.
   - Otherwise edit `TODO.md` by hand in the same shape: a `#` heading per
     round, `- [ ]` for open, `- [/]` in progress, `- [x]` done, `- [>]`
     deferred, and the details as indented lines under the task.
   - Add to an existing TODO.md; never remove or rewrite items you did not
     create.
   - Start every task title with its finding id (`R1-04: ...`), so each title
     is unique and can be addressed by `--title`.

After this step, tell the user you are starting and that you will not ask
anything else.

## 1. Baseline

Launch a subagent to find the project's build, test, and lint commands (README,
AGENTS.md or CLAUDE.md, Makefile, package manifests, CI config) and run them.
It reports each command, whether it passed, the numbers (tests run and passed,
lint warnings), and which suites are slow (integration, end-to-end, race
detector), so you keep those for the final run.

These commands are **the checks** for the rest of the run. Record the commit
you start from as the base.

If a check already fails, record it in TODO.md as finding `R1-00` and fix it
first, the same way as the others. If it is still red after that, stop and
report: there is no gate to verify fixes against.

## 2. Review

Launch **one** read-only reviewer subagent. If a specialist reviewer agent fits
the stack, use it. Give it the scope, the breaking-change answer, and the
checks, and nothing about what you expect it to find: a reviewer confirms
whatever it is handed.

It reviews three things: stability (bugs, error handling, races, leaks, missing
validation), code quality (duplication, dead code, unclear or fragile code,
missing tests on risky paths), and architecture (boundaries, dependency
direction, ownership of data, coupling).

It returns at most 20 findings, most severe first, each with:

- a short claim, as the title
- file and line
- a concrete failing scenario: the input or state, and the wrong result
- a specific fix
- severity (critical, high, medium, low) and effort (small, medium, large)
- confirmed (it traced the path) or plausible
- whether the fix is breaking

## 3. Record

Before fixing anything, add a category `auto-improve round 1` to TODO.md and
one task per finding, in severity order. Put file and line, scenario, fix,
severity, effort, and confidence in the task's description. Commit TODO.md.

Defer a finding now, with the reason in its description, when its fix is
breaking and breaking changes are not allowed.

Mark each complex finding by adding `[complex]` to its title. Step 4 skips
them. If the user did not want complex findings tackled, defer them now and
write a short plan in each description so the user can pick it up.

## 4. Fix: a fresh subagent per finding

Work through the open findings that are not complex, one at a time, most
severe first. For each:

1. Mark the task in progress.
2. Launch a **new** subagent; never reuse one from an earlier finding. Its
   prompt contains the finding with all its fields, the breaking-change
   answer, the checks, and the fixer rules below. It works directly on the
   current branch. Because fixes run one after another, each starts from the
   last one's result, with no worktrees or merges.
3. When it reports, check that its commits are on the branch and run the full
   checks yourself (in a subagent, or so you only read the summary and exit
   codes).
4. Green: mark the task done, and put the commit hashes and the measured
   numbers in its description (for example, tests 412 → 415 passing).
5. Red: launch a fresh subagent to repair the breakage. If it cannot,
   `git revert` the finding's commits, confirm the checks are green again, and
   defer the task with the reason.
6. Not reproduced or blocked: defer the task with what the fixer reported.
7. Anything the fixer noticed outside its finding goes into TODO.md as a new
   open task for round 2. Do not fix it in this round.

Commit the TODO.md updates at the end of the round.

### Fixer rules (put these in every fixer prompt)

- Reproduce first. Write a test that fails for the scenario in the finding,
  and watch it fail. If you cannot make it fail, change nothing and report "not
  reproduced" with what you tried. A pure refactor with no behaviour change
  needs tests that pin the current behaviour instead, passing before and after.
- Make the smallest change that fixes the finding. No changes outside it.
- Run the build, tests, and lint before every commit; all must pass.
- Never loosen a quality gate to pass: no skipped or deleted tests, no lint
  ignores, no lowered thresholds or coverage, no weakened assertions. If the
  fix cannot pass without that, stop and report.
- Stop and report if the fix needs a breaking change that is not allowed.
- If what you find contradicts the finding, or the user's words as quoted,
  report the conflict instead of working around it.
- Commit per change with a one-line message. Never push.
- Leave shared things alone: do not edit TODO.md (the orchestrator owns it),
  and do not touch the user's data, caches, running services, ports, git
  config, other branches, or commits you did not make. No rebase, reset,
  stash, amend, or force.
- Report in under 300 words: fixed, not reproduced, or blocked; the commits;
  the test you added; the check results with numbers; anything you noticed
  outside the finding.

## 5. Complex findings (only if the user said yes)

After the simple fixes, work through the complex findings one at a time, most
severe first. For each:

1. Mark the task in progress.
2. **Plan.** Launch a planner subagent with the finding, the breaking-change
   answer, and the checks. It writes an implementation plan: small tasks in
   order, each with the files it touches, the test that proves it, and a state
   where the checks pass. It may use a plan-writing skill such as
   `superpowers:writing-plans` if one is installed, but the plan never goes in
   the repo, whatever that skill's default location: it is saved in a temp
   folder outside the repo, created once for the run (for example
   `mktemp -d -t auto-improve-XXXX`), as `<finding id>.md`. It is never
   committed. The planner also lists every open decision and risk it found.
   Put the plan's path in the task's description.
3. **Gate.** Do not start implementing, and defer the task with the plan path
   and the question, when the plan shows:
   - a decision that is clearly the user's: product behaviour, a trade-off
     with no clear winner, or a breaking change that is not allowed
   - a critical risk: data loss, a migration of stored data, security, or a
     change to how the system is deployed or run

   Any other question has a reasonable default: settle it yourself, or ask a
   specialist reviewer subagent, and pick the option with the best long-term
   maintainability. Write each such decision in the plan.
4. **Land.** Hand the plan's tasks, in order, to fresh fixer subagents, one
   task per subagent, under the fixer rules from step 4 plus the plan. After each
   task, run the full checks yourself, as in step 4. If a fixer hits a
   decision or risk from the gate list, stop the finding there.
5. Done: mark the task done with the commit hashes and measured numbers.
   Stopped, or red and unrepairable: `git revert` that finding's commits,
   confirm the checks are green, and defer the task with the plan path, a
   short summary of the plan (the temp folder may be cleared), how far it
   got, and why it stopped. The same goes for a task deferred at the gate.

Commit the TODO.md updates at the end of this step.

## 6. Second review

Round 1's fixes are new code, and new code has bugs; budget for this round.
Launch a **new** reviewer subagent, independent of the first. Give it the
scope, the breaking-change answer, the checks, and the range
`<base>..HEAD`. Ask it to review the changed code and the code around it, for
problems the fixes introduced and for anything the first review missed. Do not
give it round 1's findings or the fixers' reports.

Merge its findings with the open round-2 tasks from step 4, record them under
`auto-improve round 2`, and handle them the same way as in steps 3 to 5. Stop
after round 2; defer whatever is left.

## 7. Final verification

Run the full checks, including the slow suites, in a subagent.

Then launch a fresh subagent with only the user's words (as quoted in the
briefs) and the range `<base>..HEAD`. It checks, point by point, that the work
matches what the user asked: it stayed in scope, it honoured both answers, and
nothing they asked for is missing. Do not give it your reading, the findings,
or the fixers' reports. Revert or defer what does not match.

Then report to the user, short:

- **Check these**, first: the assumptions you made about what the user asked,
  and any mismatch the last check found
- what got better, in a few plain bullets, each saying where the change is in
  terms the user can verify without reading the code
- findings fixed, deferred, and not reproduced, per round
- complex findings landed, and those stopped with the plan path and the
  question the user needs to answer
- the commit range and the before and after numbers from the checks
- what was not run, and why
- deferred items that need the user's decision

## Rules for the whole run

- Stay on the current branch. Never push, merge, or open a pull request.
- One-line commit messages, one commit per change.
- Every finding is in TODO.md before it is fixed, and ends done or deferred
  with a reason.
- Never loosen a quality gate; a fix that cannot pass is reverted and deferred.

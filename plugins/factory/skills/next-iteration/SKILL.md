---
name: next-iteration
description: Use when you will be away and want the agent to implement the open items under the "Next iteration" heading in TODO.md. It marks them in progress, groups them by complexity (easy items batched into one subagent, harder ones each get their own), has independent subagents settle open questions up front, asks the user only the ones they cannot decide, and records the results, then implements the items with specialized subagents and commits on the current branch.
disable-model-invocation: true
---

Implement the open items under the "Next iteration" heading of `TODO.md` on
the current branch, unattended. If the user named a different file or heading,
use that instead.

The user is about to leave. Ask your questions in step 1, then work through to
the end without asking again. The user sees only the questions an
independent subagent could not decide (see "Qualifying a question"). After
step 1, such a question defers the part that depends on it; nothing stops the
whole run except a check that is red before you start.

You are the orchestrator. Subagents read code, implement, and run the checks,
so your own context stays clean for the whole run. Ask each subagent for a
report under 500 words.

The user's words are the reference for the whole run: each item's title and
description in TODO.md, anything they said when starting the run, and their
answers from step 1. Every subagent prompt quotes them verbatim under "The
user asked:", with your reading of them separately under "My reading:", never
as settled rulings.

## 0. Collect the items

1. Check the branch. If it is `main` or `master`, add "which branch should I
   work on?" to the questions in step 1, and do not commit until it is
   answered.
2. Choose how to read and write TODO.md:
   - If the `todo` command is installed (`todo --version` succeeds), make every
     change through it: `todo list --json` to read, `todo progress`, `todo
     done`, `todo defer`, `todo edit --set-desc`, and `todo add --title --desc
     --parent-title`. Address items by `--number` from a fresh `todo list
     --json`, since titles may repeat.
   - Otherwise edit `TODO.md` by hand in the same shape: `- [ ]` open, `- [/]`
     in progress, `- [x]` done, `- [>]` deferred, details as indented lines
     under the task.
   - Never remove or rewrite items you were not asked to work on.
3. Find the heading whose text is "Next iteration" (any case, any level). Take
   every open (`[ ]`) and in-progress (`[/]`) task under it, including tasks
   under its sub-headings and their subtasks. Skip done and deferred ones. If
   the heading is missing or has no open items, tell the user and stop.
4. Mark every collected item in progress, and commit TODO.md once you are on a
   branch other than `main` or `master`.

## 1. Before the user leaves

1. **Understand each item.** Launch one read-only subagent with all the items,
   quoted verbatim. For each item it finds the code involved and reports: the
   files and areas it touches, which other items it overlaps or depends on,
   the effort (easy, medium, complex), and every open question, meaning a
   point where two readings would lead to different results and neither the
   code nor the item settles it.
2. **Restate.** For each item, write the item quoted word for word, with a
   "Read as:" line. Name every word or phrase that could mean two things, with
   both meanings.
3. **Group by complexity.**
   - **Easy:** small, obvious, a few files, no design choice. Batch related
     easy items into one group per area, so one subagent handles several. Do
     not give each easy item its own subagent.
   - **Medium:** a real change in one area, with a clear approach. One group
     per item.
   - **Complex:** large, spans several modules, or needs a design choice. One
     group per item, planned before it is built (step 4).
   Order the groups so an item comes after the items it depends on.
4. **Qualify the questions.** Do not pass the open questions straight to the
   user. Send them to independent subagents first, following "Qualifying a
   question" below: one fresh subagent per item (or per area, when several
   items share questions), never the subagent that raised them. Each question
   comes back either decided or as the user's.
5. **Ask once.** Show the user, together:
   - the restatement and the groups
   - the decided questions, each with its answer and one line of reason, as
     information: the user may overrule any of them, but nothing is asked
   - the questions that are the user's, each with the options and why the
     subagent could not decide
   - whether breaking changes are allowed (a public API, CLI flags, config or
     file formats, wire formats, a stored schema), when any item could need
     one
   If no question is the user's and no breaking change is possible, still show
   the rest and say you are starting unless they object. Otherwise wait for
   the answers.
6. **Capture the results.** In the description of the item each belongs to,
   write the user's answers quoted verbatim under "Answer:", and the decided
   questions under "Decided:" with their reason (or the user's override under
   "Answer:"). One that applies to every item goes into each of them. Commit
   TODO.md.

Then tell the user you are starting and that you will not ask anything else.

### Qualifying a question

Every open question, before the run and during it, goes through an
independent subagent before it can reach the user:

- **Fresh and independent.** A new subagent for each batch, never the one that
  raised the question or one that implements the item. If an installed
  specialist agent fits the area, use it; otherwise brief a new subagent as
  one ("You are a senior ... reviewing a design choice").
- **Its brief.** The user's words for the item under "The user asked:", the
  question, every option seen so far, and the files involved. Not your
  preferred option: a qualifier handed an answer tends to confirm it.
- **What it does.** It reads the code, the docs, and the project's
  conventions, and picks the option with the best long-term maintainability.
- **What counts as the user's.** It may not decide, and returns the question
  as the user's, when it is about product behaviour or what the user wants, a
  trade-off with no clear winner, a breaking change, or a critical risk (data
  loss, a migration of stored data, security, a change to how the system is
  deployed or run). It also returns it when the code and the user's words do
  not give it enough to choose.
- **Its report,** per question: decided, with the answer and a one-line
  reason; or the user's, with the options and why it could not decide.

## 2. Baseline

Launch a subagent to find the project's build, test, and lint commands
(README, AGENTS.md or CLAUDE.md, Makefile, package manifests, CI config) and
run them. It reports each command, whether it passed, and the numbers (tests
run and passed, lint warnings). These commands are **the checks** for the rest
of the run. Record the commit you start from as the base.

If a check already fails, fix that first with its own subagent under the
implementer rules. If it is still red after that, stop and report: there is no
gate to verify the items against.

## 3. Implement easy and medium groups

Work through the groups in order, one at a time, so each starts from the last
one's result on the same branch, with no worktrees or merges. For each group:

1. **Pick the specialist.** If an installed agent fits the group's stack or
   area (a Go, Vue, API, or infrastructure specialist, for example), use it.
   Otherwise launch a new general-purpose subagent and open its prompt with
   the role it plays ("You are a senior Go engineer working on ..."). Never
   reuse a subagent from an earlier group.
2. **Brief it.** Its prompt contains, for every item in the group, the user's
   words under "The user asked:" (title, description, and captured answers),
   your reading under "My reading:", the files the step 1 subagent found, the
   breaking-change answer, the checks, and the implementer rules below.
3. **Verify.** When it reports, check that its commits are on the branch and
   run the full checks yourself (in a subagent, or so you only read the
   summary and exit codes).
4. **Green:** mark each finished item done, with the commit hashes in its
   description.
5. **Red:** launch a fresh subagent to repair the breakage. If it cannot,
   `git revert` the group's commits, confirm the checks are green again, and
   defer the items with the reason.
6. **Blocked or contradicted:** defer the item with what the implementer
   reported, and keep going with the next group.
7. Anything an implementer noticed outside its items goes into TODO.md as a
   new open task under "Next iteration". Do not build it in this run.

### Questions during the run

When a question comes up after step 1, do not ask the user. Qualify it as in
"Qualifying a question" and write the result in the item's description.
Decided: the implementer goes on with that answer. The user's: defer only the
part that depends on it, with the options and the qualifier's reason under
"Needs you:", build what does not depend on it, and continue with the other
groups. The user is asked about it in the final report, not during the run.

### Implementer rules (put these in every implementer prompt)

- Implement exactly the items in your brief, and nothing else.
- Write or update tests for the behaviour you add or change, and watch a new
  test fail before you make it pass.
- Run the build, tests, and lint before every commit; all must pass.
- Never loosen a quality gate to pass: no skipped or deleted tests, no lint
  ignores, no lowered thresholds or coverage, no weakened assertions. If the
  item cannot pass without that, stop and report.
- Choose the approach with the best long-term maintainability.
- If the code, the item, or the user's words as quoted contradict "My
  reading:", report the conflict instead of working around it. Stop and
  report if the item needs a breaking change that is not allowed.
- If you hit an open question your brief does not settle, do not pick an
  answer yourself: finish what does not depend on it, then report the
  question with the options you see. The orchestrator has it qualified and
  sends a fresh implementer with the result.
- Follow the repository's own rules (AGENTS.md, CLAUDE.md), such as version
  bumps.
- Commit per item with a one-line message. Never push.
- Leave shared things alone: do not edit TODO.md (the orchestrator owns it),
  and do not touch the user's data, caches, running services, ports, git
  config, other branches, or commits you did not make. No rebase, reset,
  stash, amend, or force.
- Report in under 300 words, per item: done, blocked, or conflict; the
  commits; the tests you added; the check results with numbers; anything you
  noticed outside your items.

## 4. Implement complex groups

After the easy and medium groups, work through the complex items one at a
time. For each:

1. **Plan.** Launch a planner subagent with the item (the user's words and
   your reading), the breaking-change answer, and the checks. It writes an
   implementation plan: small tasks in order, each with the files it touches,
   the test that proves it, and a state where the checks pass. It may use a
   plan-writing skill if one is installed, but the plan never goes in the repo:
   it is saved in a temp folder outside the repo, created once for the run
   (for example `mktemp -d -t next-iteration-XXXX`), as a file named after the
   item. It also lists every open decision and risk. Put the plan's path in
   the item's description.
2. **Gate.** Qualify the plan's open decisions as in "Qualifying a question",
   and write the decided ones in the plan. Do not build, and defer the item
   with the plan path and the question under "Needs you:", when a decision
   comes back as the user's, or the plan needs a breaking change that is not
   allowed.
3. **Land.** Hand the plan's tasks, in order, to fresh specialist subagents,
   one task (or a few small, related ones) per subagent, under the implementer
   rules plus the plan. Run the full checks after each, as in step 3.
4. **Done:** mark the item done with the commit hashes. Stopped, or red and
   unrepairable: `git revert` that item's commits, confirm the checks are
   green, and defer the item with the plan path, a short summary of the plan,
   how far it got, and why it stopped.

Commit the TODO.md updates at the end of each step.

## 5. Check against the user's words

Run the full checks in a subagent.

Then launch a fresh subagent with only the user's words (the items as quoted,
and the captured answers) and the range `<base>..HEAD`, plus output or
screenshots where they show the result. It checks each item, clause by
clause, and reports what does not match, what is missing, and anything built
that no item asked for. Do not give it your reading or the implementers'
reports. Fix the mismatches with a fresh implementer, or reopen the item and
list the mismatch in its description.

## 6. Report

Keep it short. Open with **Check these**: the assumptions you made, the
decisions you took during the run, and every "Needs you:" item. Then:

- for each item: done, deferred, or reopened, and what changed and where, in
  terms the user can verify without reading the code
- the commit range and the before and after numbers from the checks
- new items added to TODO.md
- what was not run, and why

## Rules for the whole run

- Stay on the current branch (or the one the user named). Never push, merge,
  or open a pull request.
- One-line commit messages, one commit per change.
- Every collected item ends done, deferred with a reason, or reopened with
  the mismatch.
- Never loosen a quality gate; a change that cannot pass is reverted and the
  item deferred.

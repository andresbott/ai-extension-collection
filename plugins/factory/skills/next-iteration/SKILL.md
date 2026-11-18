---
name: next-iteration
description: Use when you will be away and want the agent to implement every task in state "ready" in the project's todo list, plus "followup" tasks whose follow-ups an expert subagent can settle without the user. It works only through the todo binary, groups the tasks by complexity (easy ones batched into one subagent, harder ones each get their own), has independent subagents settle open questions up front, asks the user only the ones they cannot decide, then implements the tasks with specialized subagents, moves each one through working, review, and done or followup as its work progresses, and commits on the current branch.
disable-model-invocation: true
---

Implement every task in state `ready` in the project's todo list on the
current branch, unattended. If the user named a different list file, pass it
to every command with `-f <file>`.

The user is about to leave. Ask your questions in step 1, then work through to
the end without asking again. The user sees only the questions an
independent subagent could not decide (see "Qualifying a question"). After
step 1, such a question defers the part that depends on it; nothing stops the
whole run except a check that is red before you start.

You are the orchestrator. Subagents read code, implement, review, and run the
checks, so your own context stays clean for the whole run. Ask each subagent
for a report under 500 words.

The user's words are the reference for the whole run: each task's title,
description, and subtasks, anything they said when starting the run, and their
answers from step 1. Every subagent prompt quotes them verbatim under "The
user asked:", with your reading of them separately under "My reading:", never
as settled rulings.

## The todo binary

The binary is `/usr/local/bin/todo-08-rc1`. Below, `todo` stands for that
path: always call it by that full path. (This is a test build; once the
final version is installed, the path becomes `/usr/local/bin/todo`, and this
line is the only one to change.)

- **Only through the binary.** Every read and every change to the list goes
  through it. Never open, parse, or edit `.todo.json` (or `TODO.md`) yourself,
  and never let a subagent do it.
- **Reading:** `todo list --json`. Address tasks by `--id`, the 7-character id
  from that output; titles may repeat and numbers shift when tasks are added.
- **States:** `todo status --id <id> --to <state>`. A subtask can only be open
  or done: close it with `todo done --id <id>`.
- **Descriptions:** `todo edit --id <id> --set-desc <text>` replaces the whole
  description. Read the current one from `list --json` first and append to it,
  so the user's words are never lost. Start every block you append with a
  line `[next-iteration <YYYY-MM-DD>]`, so a later run can tell the run's notes
  from the user's text.
- **Plans:** `todo edit --id <id> --set-plan <path>`.
- **New subtasks:** `todo add --parent-id <id> --title <title> --desc <text>`.
- **Committing:** stage the list file (`.todo.json` unless the user named
  another) with `git add`, in commits of its own. Never stage
  `.todo.json.lock`.
- **Reverting:** when the run reverts a task's commits, revert only the code
  commits, never one that touches the list file. Record the outcome through
  the binary instead.

## Task states

Change a task's state only when its own work reaches that point, one step at a
time. Never move a task ahead of its work (a task waiting for its reviewer is
still `working`), and never touch tasks that were not collected in step 0.

- `ready` → `working`: its group starts (planning counts as starting).
- `working` → `review`: its implementation is committed, the checks are
  green, and its reviewer starts.
- `review` → `working`: the review found something and a fixer starts.
- `review` → `done`: the review passed and no follow-up items came up.
- `review` → `followup`: the review passed, and follow-up items came up. Add
  each as an open subtask of the task, then set the state.
- `followup` → `ready`: an expert cleared its follow-ups without the user
  (see "Clearing follow-ups").
- any → `deferred`: blocked, reverted, or waiting on the user ("Needs you:").

A follow-up item is anything an implementer or reviewer noticed while working
on the task that the task did not ask for and that was not built. Mark the
task's own subtasks done as they are built and reviewed; follow-up subtasks
stay open. A task that ends `deferred` keeps its follow-up items too: add them
as open subtasks before deferring it.

### Tasks that come back

A task that ended `followup` or `deferred` in an earlier run returns to
`ready` once the user has dealt with it: answered the "Needs you:" items,
kept, edited, or removed the follow-up subtasks, or added new ones. Pick it
up like any other `ready` task, with these differences:

- **The work is what is still open:** its open subtasks, and every "Needs
  you:" item the user has answered. Done subtasks and parts an earlier run
  built are context, not work; do not redo or re-review them.
- **The user's words** are all the text not inside a `[next-iteration ...]`
  block, plus the "Answer:" quotes inside those blocks. Where the user's text
  answers a "Needs you:" item, that answer settles it; it is not an open
  question any more. Earlier "Decided:" notes still stand unless the user's
  text overrules them.
- **If nothing is clearly open** (every subtask done and no new text from the
  user), ask in step 1 what is left to do.

### Clearing follow-ups

A task in `followup` may not need the user at all. Before it waits for them,
try to clear it with an expert:

- **The expert.** A fresh subagent, never one that built or reviewed the
  task. If an installed specialist agent fits the area, use it; otherwise
  brief a new subagent as one ("You are a senior ..."). Its brief: the user's
  words for the task under "The user asked:", its open follow-up subtasks, the
  "Needs you:" notes, and the files involved. Not your preferred answers.
- **What it does,** per open follow-up: it reads the code and the project's
  conventions and decides whether it can be settled without the user, using
  the same limits as "Qualifying a question". Each one comes back as **build**
  (in line with what the task asked, with any decision it took and a one-line
  reason), **not needed** (already handled, or not part of the task, with the
  reason), or **the user's** (the options and why it could not decide).
- **Cleared,** when none is the user's: append the decisions to the task's
  description, close each "not needed" subtask with `todo done` and its reason
  in the description, and set the task to `ready`. The open subtasks are now
  its work, as in "Tasks that come back".
- **Not cleared:** the task stays `followup`. Append the expert's results,
  with the user's questions under "Needs you:".

When it happens:

- **At the start.** In step 0, also collect every task in `followup`, and
  clear them in step 1 before anything else. A cleared task joins this run
  like any `ready` task. For one that is not cleared, put its questions in the
  step 1 question round; if the user's answers settle them all, set it to
  `ready` and it joins too.
- **During the run.** When a task ends `followup` (steps 3 and 4), clear it
  right away. If it is cleared, set it to `ready` and queue it as a new group
  at the end of its kind (easy and medium, or complex), and build it in this
  run. A task gets one such extra round per run: if it ends `followup` again,
  it stays there for the user.

## 0. Collect the tasks

1. Check the branch. If it is `main` or `master`, add "which branch should I
   work on?" to the questions in step 1, and do not commit until it is
   answered.
2. Check the binary: if `todo --version` fails, tell the user and stop. Check
   that the list file exists; if it does not, tell the user and stop without
   running any other `todo` command, since the binary would create one.
3. Run `todo list --json`. Take every task in state `ready` or `followup`,
   wherever it sits, with its subtasks. Ignore every other state. If there
   are none, tell the user and stop. For a task that carries `[next-iteration ...]` notes, work
   out what is still open as in "Tasks that come back", and hand only that
   to every subagent as the work, with the rest as context.
4. Do not change any state yet.

## 1. Before the user leaves

0. **Clear follow-ups.** For each collected task in `followup`, run "Clearing
   follow-ups". The rest of step 1 covers the `ready` tasks, including the
   cleared ones; a task that is not cleared only adds its questions to the
   question round (5).
1. **Understand each task.** Launch one read-only subagent with all the tasks,
   quoted verbatim. For each task it finds the code involved and reports: the
   files and areas it touches, which other tasks it overlaps or depends on,
   the effort (easy, medium, complex), and every open question, meaning a
   point where two readings would lead to different results and neither the
   code nor the task settles it.
2. **Restate.** For each task, write the task quoted word for word, with a
   "Read as:" line. Name every word or phrase that could mean two things, with
   both meanings.
3. **Group by complexity.**
   - **Easy:** small, obvious, a few files, no design choice. Batch related
     easy tasks into one group per area, so one subagent handles several. Do
     not give each easy task its own subagent.
   - **Medium:** a real change in one area, with a clear approach. One group
     per task.
   - **Complex:** large, spans several modules, or needs a design choice. One
     group per task, planned before it is built (step 4).
   Order the groups so a task comes after the tasks it depends on.
4. **Qualify the questions.** Do not pass the open questions straight to the
   user. Send them to independent subagents first, following "Qualifying a
   question" below: one fresh subagent per task (or per area, when several
   tasks share questions), never the subagent that raised them. Each question
   comes back either decided or as the user's.
5. **Ask once.** Show the user, together:
   - the restatement and the groups
   - the decided questions, each with its answer and one line of reason, as
     information: the user may overrule any of them, but nothing is asked
   - the questions that are the user's, each with the options and why the
     subagent could not decide
   - whether breaking changes are allowed (a public API, CLI flags, config or
     file formats, wire formats, a stored schema), when any task could need
     one
   If no question is the user's and no breaking change is possible, still show
   the rest and say you are starting unless they object. Otherwise wait for
   the answers.
6. **Capture the results.** Append to the description of the task each
   belongs to the user's answers quoted verbatim under "Answer:", and the
   decided questions under "Decided:" with their reason (or the user's
   override under "Answer:"). One that applies to every task goes into each of
   them. Commit the list file once you are on a branch other than `main` or
   `master`.

Then tell the user you are starting and that you will not ask anything else.

### Qualifying a question

Every open question, before the run and during it, goes through an
independent subagent before it can reach the user:

- **Fresh and independent.** A new subagent for each batch, never the one that
  raised the question or one that implements the task. If an installed
  specialist agent fits the area, use it; otherwise brief a new subagent as
  one ("You are a senior ... reviewing a design choice").
- **Its brief.** The user's words for the task under "The user asked:", the
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
gate to verify the tasks against. No task has changed state at this point.

## 3. Implement easy and medium groups

Work through the groups in order, one at a time, so each starts from the last
one's result on the same branch, with no worktrees or merges. For each group:

1. **Start.** Set each task in the group to `working` (the implementer works
   on all of them).
2. **Pick the specialist.** If an installed agent fits the group's stack or
   area (a Go, Vue, API, or infrastructure specialist, for example), use it.
   Otherwise launch a new general-purpose subagent and open its prompt with
   the role it plays ("You are a senior Go engineer working on ..."). Never
   reuse a subagent from an earlier group.
3. **Brief it.** Its prompt contains, for every task in the group, the user's
   words under "The user asked:" (title, description, subtasks, and captured
   answers), your reading under "My reading:", the files the step 1 subagent
   found, the breaking-change answer, the checks, and the implementer rules
   below.
4. **Verify.** When it reports, check that its commits are on the branch and
   run the full checks yourself (in a subagent, or so you only read the
   summary and exit codes).
5. **Red:** launch a fresh subagent to repair the breakage. If it cannot,
   `git revert` the group's commits, confirm the checks are green again, and
   defer the tasks with the reason.
6. **Blocked or contradicted:** defer the task with what the implementer
   reported, and keep going with the rest of the group.
7. **Review.** Green: review the finished tasks one at a time, as in
   "Reviewing a task" below. Set a task to `review` only when its own
   reviewer starts.
8. **Close.** Append the commit hashes to each task's description, mark its
   own subtasks done, and set it to `done` or `followup` (see "Task states").
   Commit the list file. A task that ends `followup` goes straight to
   "Clearing follow-ups".

### Reviewing a task

Launch a fresh reviewer subagent, never one that built the task, with only
the user's words (the task as quoted, its subtasks, and the captured answers)
and the task's commits, plus output or screenshots where they show the
result. Do not give it your reading or the implementer's report. It checks
the task clause by clause (for a task that came back, only what was open at
the start of this run) and reports what does not match, what is missing,
anything built that the task did not ask for, and bugs or rule violations in
the change.

If it finds something, set the task back to `working` and have a fresh
implementer fix it under the implementer rules, run the full checks, then set
it to `review` and review it again with another fresh reviewer. If the second
review still finds a mismatch, defer the task with the mismatch under "Needs
you:". Anything the reviewer noticed outside the task is a follow-up item.

### Questions during the run

When a question comes up after step 1, do not ask the user. Qualify it as in
"Qualifying a question" and append the result to the task's description.
Decided: the implementer goes on with that answer. The user's: defer only the
part that depends on it, with the options and the qualifier's reason under
"Needs you:", build what does not depend on it, and continue with the other
groups. The user is asked about it in the final report, not during the run.

### Implementer rules (put these in every implementer prompt)

- Implement exactly the tasks in your brief, and nothing else.
- Write or update tests for the behaviour you add or change, and watch a new
  test fail before you make it pass.
- Run the build, tests, and lint before every commit; all must pass.
- Never loosen a quality gate to pass: no skipped or deleted tests, no lint
  ignores, no lowered thresholds or coverage, no weakened assertions. If the
  task cannot pass without that, stop and report.
- Choose the approach with the best long-term maintainability.
- If the code, the task, or the user's words as quoted contradict "My
  reading:", report the conflict instead of working around it. Stop and
  report if the task needs a breaking change that is not allowed.
- If you hit an open question your brief does not settle, do not pick an
  answer yourself: finish what does not depend on it, then report the
  question with the options you see. The orchestrator has it qualified and
  sends a fresh implementer with the result.
- Follow the repository's own rules (AGENTS.md, CLAUDE.md), such as version
  bumps.
- Commit per task with a one-line message. Never push.
- Leave shared things alone: do not run the todo binary, and do not open,
  edit, or stage `.todo.json`, its lock file, or `TODO.md` (the orchestrator
  owns the list). Do not touch the user's data, caches, running services,
  ports, git config, other branches, or commits you did not make. No rebase,
  reset, stash, amend, or force.
- Report in under 300 words, per task: done, blocked, or conflict; the
  commits; the tests you added; the check results with numbers; anything you
  noticed outside your tasks.

## 4. Implement complex groups

After the easy and medium groups, work through the complex tasks one at a
time. For each:

1. **Start.** Set the task to `working`.
2. **Plan.** Launch a planner subagent with the task (the user's words and
   your reading), the breaking-change answer, and the checks. It writes an
   implementation plan: small tasks in order, each with the files it touches,
   the test that proves it, and a state where the checks pass. It may use a
   plan-writing skill if one is installed, but the plan never goes in the repo:
   it is saved in a temp folder outside the repo, created once for the run
   (for example `mktemp -d -t next-iteration-XXXX`), as a file named after the
   task. It also lists every open decision and risk. Record the plan's path
   with `todo edit --set-plan`.
3. **Gate.** Qualify the plan's open decisions as in "Qualifying a question",
   and write the decided ones in the plan. Do not build, and defer the task
   with the question under "Needs you:", when a decision comes back as the
   user's, or the plan needs a breaking change that is not allowed.
4. **Land.** Hand the plan's steps, in order, to fresh specialist subagents,
   one step (or a few small, related ones) per subagent, under the
   implementer rules plus the plan. Run the full checks after each, as in
   step 3.
5. **Review and close** as in step 3: `review`, then `done` or `followup`
   (and then "Clearing follow-ups").
   Stopped, or red and unrepairable: `git revert` the task's commits, confirm
   the checks are green, and defer the task with a short summary of the plan,
   how far it got, and why it stopped.

Commit the list file at the end of each task.

## 5. Final checks

Run the full checks in a subagent on the final state. If something is red
that was green after each task, have a fresh subagent find which task's
commits cause it and repair it under the implementer rules; if it cannot,
`git revert` that task's commits, confirm the checks are green, and defer the
task with the reason.

## 6. Report

Keep it short. Open with **Check these**: the assumptions you made, the
decisions you took during the run, and every "Needs you:" task. Then:

- for each task: its final state (done, followup, or deferred), and what
  changed and where, in terms the user can verify without reading the code
- the follow-up subtasks added, under which task, and which follow-ups an
  expert cleared or dropped as not needed, with the reason
- the commit range and the before and after numbers from the checks
- what was not run, and why

## Rules for the whole run

- Stay on the current branch (or the one the user named). Never push, merge,
  or open a pull request.
- One-line commit messages, one commit per change.
- Every collected task ends `done`, `followup`, or `deferred` with a reason.
- Never loosen a quality gate; a change that cannot pass is reverted and the
  task deferred.

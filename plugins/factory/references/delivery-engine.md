# Delivery engine

The shared process behind the factory's delivery commands (`next-iteration`,
`auto-deliver`, and the fixes after `review-branch`). The command that sent you here is the **entry point**: it says
where the tasks come from and how to record them. This file says how to build
them. The entry point only adds steps or fills in what is listed under "What
the entry point provides"; it never relaxes the rules here.

The user is about to leave. Ask your questions in step 1, then work through to
the end without asking again. The user sees only the questions an
independent subagent could not decide (see "Qualifying a question"). After
step 1, such a question defers the part that depends on it; nothing stops the
whole run except a check that is red before you start.

You are the orchestrator. Subagents read code, implement, review, and run the
checks, so your own context stays clean for the whole run. Ask each subagent
for a report under 500 words.

The user's words are the reference for the whole run: the tasks as the entry
point collected them, anything the user said when starting the run, and their
answers from step 1. Every subagent prompt quotes them verbatim under "The
user asked:", with your reading of them separately under "My reading:", never
as settled rulings.

## Working unattended

After step 1 nobody is watching. Any command that needs the user's approval
stops the whole run until they come back, so the run must never need one.
Read this section again at the start of every group, and put it in every
subagent prompt.

- **Never change a checkout.** No `git checkout`, `switch`, `worktree`,
  `stash`, `reset`, `rebase`, or `cherry-pick`, in any repository or folder:
  this one, another one on the machine, or a temporary copy you made. The
  run's only branch change is "Leave main" in step 1, while the user is still
  here to approve it.
- **Read other commits instead.** To see another commit, branch, or
  repository, use read-only commands: `git show <ref>:<path>`,
  `git log <ref>`, `git diff <a> <b>`, `git -C <repo> log`.
- **Keep commands plain.** Run them from the repository, one per call. Do not
  `cd` into folders outside it or chain commands through `$(...)`; that is
  what triggers approval prompts.
- **Park what needs the user.** If a step truly needs a command from the list
  above, or anything else that would ask for approval, do not run it. Record
  it under "Needs you:" with the command and why it is needed, defer only the
  part that depends on it, and continue with the rest.

## What the entry point provides

- **Collect:** the tasks, each with the user's words quoted verbatim.
- **Record:** how to add a note to a task (answers, decisions, commit hashes,
  "Needs you:" items) without losing the user's words.
- **States:** how to move a task through `working`, `review`, `done`,
  `followup`, and `deferred`, and how to add a follow-up item to it.
- **Save:** whether the record lives in a file to commit, and how.
- **Follow-ups:** how to close a follow-up item, and which state a task with
  cleared follow-ups returns to (its starting state).

## Task states

Change a task's state only when its own work reaches that point, one step at a
time. Never move a task ahead of its work (a task waiting for its reviewer is
still `working`), and never touch tasks the entry point did not collect.

- the entry point's starting state (such as `ready` or `open`) → `working`:
  its group starts (planning counts as starting).
- `working` → `review`: its implementation is committed, the checks are
  green, and its reviewer starts.
- `review` → `working`: the review found something and a fixer starts.
- `review` → `done`: the review passed and no follow-up items came up.
- `review` → `followup`: the review passed, and follow-up items came up. Add
  each as a follow-up item of the task, then set the state.
- `followup` → the starting state: an expert cleared follow-up items to
  build in this run (see "Follow-ups").
- `followup` → `done`: every follow-up item was closed as not needed.
- any → `deferred`: blocked, reverted, or waiting on the user ("Needs you:").

A follow-up item is anything an implementer or reviewer noticed while working
on the task that the task did not ask for and that was not built. A task that
ends `deferred` keeps its follow-up items too: add them before deferring it.
They are not cleared or built in this run, since the task's own work is not
finished; they wait with the task.

## 1. Before the user leaves

1. **Leave main.** Run the factory's new-branch script from the repository
   root: `../scripts/new-branch.sh '<hint>'`, the path relative to this
   file's directory, with a hint of a few words naming the tasks. On a
   feature branch it changes nothing. On `main`, `master`, or the default
   branch, it either creates a branch (`success:`) or prints `NEED_NAME` and
   a `--- write` block: write the branch names its rule asks for (no single
   quotes) and run it once more as `new-branch.sh --create '<n1>' '<n2>'
   '<n3>'`. Uncommitted work moves to the new branch with you. This is the
   run's only branch change, and the user is still here to approve it. If it ends
   with `error:`, add "which branch should I work on?" to the questions
   below, with the error, and do not commit until it is answered.
2. **Understand each task.** Launch one read-only subagent with all the tasks,
   quoted verbatim. For each task it finds the code involved and reports: the
   files and areas it touches, which other tasks it overlaps or depends on,
   the effort (easy, medium, complex), and every open question, meaning a
   point where two readings would lead to different results and neither the
   code nor the task settles it.
3. **Restate.** For each task, write the task quoted word for word, with a
   "Read as:" line. Name every word or phrase that could mean two things, with
   both meanings.
4. **Group by complexity.**
   - **Easy:** small, obvious, a few files, no design choice. Batch related
     easy tasks into one group per area, so one subagent handles several. Do
     not give each easy task its own subagent.
   - **Medium:** a real change in one area, with a clear approach. One group
     per task.
   - **Complex:** large, spans several modules, or needs a design choice. One
     group per task, planned before it is built (step 4).
   Order the groups so a task comes after the tasks it depends on.
5. **Qualify the questions.** Do not pass the open questions straight to the
   user. Send them to independent subagents first, following "Qualifying a
   question" below: one fresh subagent per task (or per area, when several
   tasks share questions), never the subagent that raised them. Each question
   comes back either decided or as the user's.
6. **Ask once.** Show the user, together:
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
7. **Capture the results.** Record on the task each belongs to the user's
   answers quoted verbatim under "Answer:", and the decided questions under
   "Decided:" with their reason (or the user's override under "Answer:"). One
   that applies to every task goes on each of them. Save the record once you
   are on a branch other than `main` or `master`.

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
   words under "The user asked:" (the task and its captured answers), your
   reading under "My reading:", the files the step 1 subagent found, the
   breaking-change answer, the checks, and the implementer rules below.
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
8. **Close.** Record the commit hashes on each task and set it to `done` or
   `followup`, then save the record. A task that ends `followup` goes
   straight to "Follow-ups".

### Reviewing a task

Launch a fresh reviewer subagent, never one that built the task, with only
the user's words (the task as quoted and the captured answers) and the task's
commits, plus output or screenshots where they show the result. Do not give
it your reading or the implementer's report. It checks the task clause by
clause and reports what does not match, what is missing, anything built that
the task did not ask for, and bugs or rule violations in the change.

If it finds something, set the task back to `working` and have a fresh
implementer fix it under the implementer rules, run the full checks, then set
it to `review` and review it again with another fresh reviewer. If the second
review still finds a mismatch, defer the task with the mismatch under "Needs
you:". Anything the reviewer noticed outside the task is a follow-up item.

### Questions during the run

When a question comes up after step 1, do not ask the user. Qualify it as in
"Qualifying a question" and record the result on the task. Decided: the
implementer goes on with that answer. The user's: defer only the part that
depends on it, with the options and the qualifier's reason under "Needs
you:", build what does not depend on it, and continue with the other groups.
The user is asked about it in the final report, not during the run.

### Follow-ups

Follow-up items are built in this run, not handed to the user, whenever their
scope can be settled without the user. When a task ends `followup`, clear it
right away:

- **The expert.** A fresh subagent, never one that built or reviewed the
  task. If an installed specialist agent fits the area, use it; otherwise
  brief a new subagent as one ("You are a senior ..."). Its brief: the user's
  words for the task under "The user asked:", its open follow-up items, any
  "Needs you:" notes, and the files involved. Not your preferred answers.
- **What it decides,** per item, after reading the code and the project's
  conventions:
  - **build:** it can state the scope: what to build, where, and the test or
    check that proves it is done. This covers defects and gaps the task's
    work exposed or left behind (a bug, an edge case, a missing test, docs
    the change made stale) and anything else that serves what the user asked
    for. It writes that scope, with any decision it took and a one-line
    reason.
  - **not needed:** already handled, or of no use to what the user asked
    for, with the reason.
  - **the user's:** it may not decide, under the same limits as "Qualifying a
    question" (product behaviour or what the user wants, a trade-off with no
    clear winner, a breaking change, a critical risk), or it cannot pin the
    scope down from the code and the user's words.
- **Build what can be built.** Items are independent: one item being the
  user's never holds back the others. Record the expert's decisions on the
  task, close each "not needed" item with its reason, and keep the user's
  items open under "Needs you:". If any item is **build**, return the task to
  its starting state and queue it as a new group, rated easy, medium, or
  complex by the expert, with the build items and their scope as its only
  work; the user's items are not part of it. An easy or medium group goes at
  the end of the remaining easy and medium groups; if step 3 has already
  ended, it runs as in step 3 right after the current complex task. A complex
  group goes at the end of the complex ones. It is then built, reviewed, and
  closed like any task; its reviewer checks the build items against the
  expert's scope and the user's words, not the parts already reviewed.
- **Nothing to build:** if every item is not needed, set the task to `done`.
  If the user's items are all that is left, it stays `followup` for the user.
- **Four rounds per task per run.** The first clearing after a task's own
  build is round 1. Items found while building follow-ups are cleared the
  same way, but a task gets at most four rounds in a run. After that, items
  still to build stay open marked "cap reached" with the expert's scope, not
  as the user's; the report lists them apart from the ones that need the
  user.

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
  owns the task record). Do not touch the user's data, caches, running
  services, ports, git config, other branches, or commits you did not make.
  No rebase, reset, stash, amend, or force.
- Nobody is watching: a command that needs approval stops the whole run.
  Never change a checkout (no `git checkout`, `switch`, `worktree`, `stash`,
  `reset`, `rebase`, or `cherry-pick`), in this repository, another one, or a
  temporary copy. To see another commit or repository, use `git show
  <ref>:<path>`, `git log <ref>`, or `git diff <a> <b>`. Run plain commands
  from the repository, one per call, without `cd` into other folders or
  `$(...)`. If you truly need one of these, do not run it: report it as
  blocked with the command and why.
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
   (for example `mktemp -d -t delivery-XXXX`), as a file named after the
   task. It also lists every open decision and risk. Record the plan's path on
   the task.
3. **Gate.** Qualify the plan's open decisions as in "Qualifying a question",
   and write the decided ones in the plan. Do not build, and defer the task
   with the question under "Needs you:", when a decision comes back as the
   user's, or the plan needs a breaking change that is not allowed.
4. **Land.** Hand the plan's steps, in order, to fresh specialist subagents,
   one step (or a few small, related ones) per subagent, under the
   implementer rules plus the plan. Run the full checks after each, as in
   step 3.
5. **Review and close** as in step 3: `review`, then `done` or `followup`
   (and then "Follow-ups").
   Stopped, or red and unrepairable: `git revert` the task's commits, confirm
   the checks are green, and defer the task with a short summary of the plan,
   how far it got, and why it stopped.

Save the record at the end of each task.

## 5. Final checks

Run the full checks in a subagent on the final state. If something is red
that was green after each task, have a fresh subagent find which task's
commits cause it and repair it under the implementer rules; if it cannot,
`git revert` that task's commits, confirm the checks are green, and defer the
task with the reason.

## 6. Report

Keep it short. Open with **Check these**: the assumptions you made, the
decisions you took during the run, and every "Needs you:" item. Then:

- for each task: its final state (done, followup, or deferred), and what
  changed and where, in terms the user can verify without reading the code
- the follow-up items, under which task: which were built, which were dropped
  as not needed (with the reason), which are left for the user and why, and
  which stopped at the round cap (with their scope)
- the commit range and the before and after numbers from the checks
- what was not run, and why

The entry point may add to this report.

## Rules for the whole run

- Stay on the current branch (or the one the user named). Never push, merge,
  or open a pull request.
- One-line commit messages, one commit per change.
- Every task ends `done`, `followup`, or `deferred` with a reason.
- Never loosen a quality gate; a change that cannot pass is reverted and the
  task deferred.
- When reverting, revert only code commits, never one that only saves the
  task record.

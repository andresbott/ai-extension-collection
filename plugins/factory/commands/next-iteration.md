---
description: Use when you will be away and want the agent to implement every task in state "ready" in the project's todo list, plus "followup" tasks whose follow-ups an expert subagent can settle without the user. It works only through the todo binary, groups the tasks by complexity (easy ones batched into one subagent, harder ones each get their own), has independent subagents settle open questions up front, asks the user only the ones they cannot decide, then implements the tasks with specialized subagents, moves each one through working, review, and done or followup as its work progresses, and commits on the current branch.
disable-model-invocation: true
---

Implement every task in state `ready` in the project's todo list on the
current branch, unattended. If the user named a different list file, pass it
to every command with `-f <file>`.

This command is an entry point to the factory's delivery engine. First read
`${CLAUDE_PLUGIN_ROOT}/references/delivery-engine.md` and follow it for the
whole run. This file says where the tasks come from and how to record
them; it only adds to the engine, never relaxes it.

## The todo binary

The binary is `todo`, as found on `PATH`, version 0.8 or later.

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

## What this entry point provides

- **Collect:** step 0 below. The user's words for a task are its title,
  description, and subtasks.
- **Record:** append to the task's description, as in "Descriptions" above.
  Record a plan's path with `--set-plan`.
- **States:** the engine's states map one to one onto `todo status`, from
  `ready`. Mark the task's own subtasks done as they are built and reviewed.
  A follow-up item is a new open subtask of the task; follow-up subtasks stay
  open.
- **Save:** commit the list file.
- **Follow-ups:** follow-up items are open subtasks. Close a "not needed"
  one with `todo done` and its reason in the description; a built one is
  closed like any subtask once reviewed. A task with items to build goes
  `followup` → `ready`, and its work in this run is only the subtasks the
  expert decided to build (plus any the user's answers settled); the
  subtasks left for the user stay open and are not built.

## Tasks that come back

A task that ended `followup` or `deferred` in an earlier run returns to
`ready` once the user has dealt with it: answered the "Needs you:" items,
kept, edited, or removed the follow-up subtasks, or added new ones. Pick it
up like any other `ready` task, with these differences:

- **The work is what is still open:** its open subtasks, and every "Needs
  you:" item the user has answered. Done subtasks and parts an earlier run
  built are context, not work; do not redo or re-review them, and its
  reviewer checks only what was open at the start of this run.
- **The user's words** are all the text not inside a `[next-iteration ...]`
  block, plus the "Answer:" quotes inside those blocks. Where the user's text
  answers a "Needs you:" item, that answer settles it; it is not an open
  question any more. Earlier "Decided:" notes still stand unless the user's
  text overrules them.
- **If nothing is clearly open** (every subtask done and no new text from the
  user), ask in step 1 what is left to do.

## Tasks qualified ahead of time

`/factory:qualify-sprint` prepares tasks before this run and records its
work in `[qualify-sprint <YYYY-MM-DD>]` blocks. Read them like your own
`[next-iteration ...]` blocks: the text inside is not the user's words,
except its "Answer:" quotes, and its "Decided:" notes stand unless the
user's text overrules them. In step 1 of the engine:

- **Use what it recorded.** Its `Scope:` and `Size:` are the starting point
  for the understanding subagent and for grouping; regroup only if the code
  has changed so that they no longer fit. Its `Depends on:` orders the
  groups. Its `Breaking changes:` answer is the breaking-change answer for
  that task: do not ask it again.
- **Ask only what is new.** Its decided and answered questions are not open
  questions. Qualify and ask only what the subagent finds that the block
  does not settle. When nothing is left for the user, say you are starting
  and start, without waiting.

## Follow-ups from earlier runs

Step 0 also collects every task in `followup`. At the start of the engine's
step 1, before anything else, clear each one as in the engine's "Follow-ups":
its open subtasks are the items. A task with items to build goes to `ready`
and joins this run, with those items as its work, as in "Tasks that come
back". Put the items that are the user's in the step 1 question round; each
one the user's answer settles joins the task's work, and if that gives a
task still in `followup` work to do, set it to `ready` and it joins too.
This start-of-run clearing does not count toward the task's four follow-up
rounds; those start after its build in this run.

## 0. Collect the tasks

1. Check the binary: run `todo --version`, which prints `todo version
   X.Y.Z` (possibly with a suffix such as `-rc1`). If it fails, or the
   version is below 0.8 (compare major, then minor; ignore any suffix), tell
   the user the version found and that the command needs todo 0.8 or later on
   `PATH`, and stop. Check that the list file exists; if it does not, tell the
   user and stop without running any other `todo` command, since the binary
   would create one.
2. Run `todo list --json`. Take every task in state `ready` or `followup`,
   wherever it sits, with its subtasks. Ignore every other state. If there
   are none, tell the user and stop. For a task that carries
   `[next-iteration ...]` notes, work out what is still open as in "Tasks
   that come back", and hand only that to every subagent as the work, with
   the rest as context.
3. Do not change any state yet.

Then continue with the engine's step 1.

## Additions to the report

- every collected task ends `done`, `followup`, or `deferred`

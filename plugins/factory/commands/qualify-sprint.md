---
description: Use before /factory:next-iteration, while you are still around, to get a sprint's tasks ready for an unattended run. It takes the sprint you name, else the only open one, else the one called "next", and goes over every task in it that is not yet ready. It refines each one against the code, sizes it, settles every open question (the obvious choices itself, the rest through independent expert subagents, and only what they cannot decide by asking you, in one round), asks whether breaking changes are allowed, records everything on the task through the todo binary, and sets the tasks that are fully settled to ready. It changes no code and makes no commits.
disable-model-invocation: true
---

Prepare a sprint so `/factory:next-iteration` can build it without asking
anything. For every task in the sprint that is not yet `ready`, work out what
it needs, refine the technical details, size it, settle every open question,
and set it to `ready` once nothing is left open.

The user is here for this run; it is the run that asks so the next one does
not have to. Still, the user's time is the cost to keep down: settle what you
can without them, and ask what is left in one round.

You are the orchestrator. Subagents read the code and settle the questions,
so your own context stays clean. Ask each subagent for a report under 500
words.

Read `${CLAUDE_PLUGIN_ROOT}/references/delivery-engine.md`, sections
"Task states", "1. Before the user leaves" (steps 2 to 7), and "Qualifying a
question". This run is that step 1, done ahead of time and in more depth: it
uses the same effort levels, the same rules for qualifying a question, and
the same "Answer:" and "Decided:" records, so `next-iteration` can take them
as they are. Do not run the rest of the engine: no branch change, no
baseline, no implementing.

## The todo binary

The binary is `todo`, as found on `PATH`, version 0.9 or later (it has
sprints). Follow the rules in `${CLAUDE_PLUGIN_ROOT}/commands/next-iteration.md`,
section "The todo binary", with these differences:

- **Note blocks** start with a line `[qualify-sprint <YYYY-MM-DD>]` instead
  of `[next-iteration ...]`. As there, read the current description first and
  append to it, so the user's words are never lost.
- **No commits.** This run changes only the list file and leaves it
  uncommitted; `next-iteration` commits it on its branch. Never run `git add`
  or `git commit`, and never change branches.
- If the user named a list file, pass it to every command with `-f <file>`.

## 0. Pick the sprint and the tasks

1. **Check the binary.** Run `todo --version`. If it fails, or the version is
   below 0.9 (compare major, then minor; ignore any suffix such as `-rc1`),
   tell the user the version found and that the command needs todo 0.9 or
   later on `PATH`, and stop. Check that the list file exists; if it does
   not, tell the user and stop without running any other `todo` command.
2. **Pick the sprint.** Run `todo sprint list --json` (the sprints not done).
   Take the first that applies:
   - the sprint the user named in the arguments, by reference, id, or name
     (ignoring case); if none matches, list the sprints and stop
   - the only sprint whose `status` is `open` (sprints in `ready`,
     `progress`, or `done` do not count)
   - the sprint named `next` (ignoring case)
   Otherwise list the sprints with their names and ask which one, once.
   If there are no sprints, tell the user and stop.
3. **Collect the tasks.** Run `todo list --flat --sprint <id>` and take
   every top-level task (with its subtasks) whose state is not `ready`,
   `working`, `review`, `done`, or `wontdo`: that is `new`, `open`,
   `followup`, and `deferred`. The flat output lists subtasks too: a
   subtask is a record whose `parentId` is another task's id; keep it with
   its task, not as a task of its own. Tasks already `ready` are context,
   not work:
   read them too, since the tasks you qualify may depend on them or overlap
   them. If there is nothing to qualify, say so and stop.
4. **The user's words** for a task are its title, its description, and its
   subtasks. For a task that carries `[next-iteration ...]` or
   `[qualify-sprint ...]` blocks, they are all the text outside those
   blocks, plus the "Answer:" quotes inside them. Earlier "Decided:" notes
   still stand unless the user's text overrules them, and a "Needs you:"
   item the user's text answers is settled. For a `followup` or `deferred`
   task, the work is what is still open: its open subtasks (the follow-up
   items) and its unanswered "Needs you:" items.

Do not change any state yet.

## 1. Refine each task

1. **Explore.** Launch read-only subagents, each with the user's words for
   its tasks quoted verbatim under "The user asked:", and the `ready` tasks
   of the sprint as context. Give each complex-looking task its own
   subagent; batch small related tasks of one area into one subagent. Each
   reports, per task:
   - the files and areas it touches, and how the change would be made there
   - the acceptance check: the test or observable result that proves it done
   - the size, as the engine's effort levels: easy, medium, or complex
     (step 1.4 of the engine)
   - the tasks in the sprint it overlaps or depends on, and any task outside
     the sprint it depends on that is not done
   - whether it could need a breaking change (a public API, CLI flags,
     config or file formats, wire formats, a stored schema)
   - every open question: a point where two readings, or two ways to build
     it, lead to different results and neither the code nor the task settles
     it, with every option it sees
   - for a `followup` task, which follow-up items an expert could clear, as
     in the engine's "Follow-ups"
2. **Restate.** For each task, write the task quoted word for word, with a
   "Read as:" line. Name every word or phrase that could mean two things,
   with both meanings; each such word is an open question too.

## 2. Settle the questions

Take every open question through these steps, in order. A question leaves
the ladder at the first step that settles it.

1. **The obvious choice.** Settle it yourself, without asking anyone, when
   one option is clearly right: the code or the project's conventions
   already decide it, the user's words point one way, or it is a small
   choice as the engine's "Qualifying a question" defines it. Record it
   under "Decided:" with a one-line reason.
2. **An expert subagent.** Send the rest to independent subagents, exactly as
   in the engine's "Qualifying a question": a fresh one per task (or per
   area, when tasks share questions), never the one that raised the
   question, an installed specialist when one fits (for example a Go, Vue,
   API, or architecture reviewer), with every option seen so far and not
   your preferred one. When the question is which way to build something,
   ask it for the current best practice for this stack and this project, and
   to say why the other options lose. Each question comes back decided, with
   a one-line reason, or as the user's, with why it could not decide.
3. **The user.** Only what the expert returned as the user's.

## 3. Ask once

Show the user, together:

- the sprint, and for each task: the restatement, its size, and the refined
  scope in two or three lines (what changes, where, and the acceptance
  check)
- the decided questions, each with its answer and one line of reason, as
  information: the user may overrule any of them, but nothing is asked
- the questions that are the user's, each with the options and why the
  expert could not decide
- for each task that could need a breaking change, whether one is allowed,
  with what would break; ask it once for the whole sprint when the same
  answer obviously fits every task, and per task otherwise

Ask through AskUserQuestion when there are four questions or fewer, each
with the options and the expert's lean first, if it had one; otherwise ask
them in the message, numbered. If nothing is the user's and no breaking
change is possible, show the rest and say you will record it unless they
object.

An answer can raise a new question, or change a task's scope. Take each new
question through the ladder again, and ask what is still the user's in one
more round. Stop asking about a task when the user says to leave it.

## 4. Record and set the states

For each collected task, append one `[qualify-sprint <YYYY-MM-DD>]` block to
its description, with these lines, so `next-iteration` reads everything it
needs from the task itself:

- `Size: easy|medium|complex`
- `Scope:` what to build, where, and the acceptance check
- `Depends on:` the tasks it must come after, by reference or id, if any
- `Breaking changes: allowed|not allowed`, on every task: the user's answer
  where one could be needed, otherwise `not allowed (none expected)`, so
  `next-iteration` never has to ask
- `Decided:` each question settled by the obvious choice or by an expert,
  with its one-line reason
- `Answer:` each of the user's answers, quoted verbatim (an override of a
  decided question too)
- `Needs you:` each question still open, with the options

For a `followup` task, apply the expert's decisions to its follow-up items:
append its reason to the item's description, then close it with `todo
done`; keep the others open with their scope.

Then set the states with `todo status`:

- **`ready`**: nothing is under "Needs you:", the scope, size, and
  breaking-change answer are recorded, and every task it depends on ends
  this run `ready` or is already `done` (`next-iteration` builds only
  `ready` tasks, and orders them by `Depends on:`).
- **unchanged**: anything is still open, including a dependency that does
  not end `ready` or `done`. Leave the state as it was (`new`, `open`,
  `followup`, or `deferred`) with the open items under "Needs you:"; for a
  dependency, name the task it waits for.

## 5. Report

Keep it short. Open with **Check these**: the assumptions you made and the
decisions taken without asking. Then:

- the sprint, and each task with its size and its final state
- the tasks that are not `ready`, each with what is still open
- that the list file is changed and not committed, and that
  `/factory:next-iteration` will pick up the `ready` tasks

## Rules for the whole run

- Change no code, make no commits, and never change branches.
- Every read and change to the list goes through the todo binary.
- Never touch tasks outside the sprint, or the sprint's tasks that were
  already `ready`, `working`, `review`, `done`, or `wontdo`.
- Never drop the user's words: append, never replace.

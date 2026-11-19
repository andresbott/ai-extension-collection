---
description: Use when handing the rest of the current feature to the agent and you only want to be asked about really critical issues. It splits what is left of the feature in this conversation into tasks, has independent subagents settle open questions up front, asks the user only the ones they cannot decide, then implements the tasks with specialized subagents, reviews each one against the user's words, and commits on the current branch.
disable-model-invocation: true
---

Finish the feature the user is working on in this conversation, on the
current branch, unattended. Only stop to ask the user about really critical
issues.

This command is an entry point to the factory's delivery engine. First read
`${CLAUDE_PLUGIN_ROOT}/references/delivery-engine.md` and follow it for the
whole run. This file says where the tasks come from and how to record
them; it only adds to the engine, never relaxes it.

## What this entry point provides

- **Collect:** step 0 below.
- **Record:** a notes file outside the repo, `tasks.md` in a temp folder
  created once for the run (`mktemp -d -t auto-deliver-XXXX`; the engine's
  plans go in the same folder). One section per task: the user's words quoted
  verbatim, its state, and every note appended under it. Never rewrite the
  quoted words.
- **States:** a `State:` line per task in `tasks.md`, starting at `open`.
  Follow-up items are listed under the task, each marked open, built, not
  needed, or the user's.
- **Save:** nothing to commit; `tasks.md` stays outside the repo.
- **Follow-ups:** mark each item in `tasks.md` as the engine's "Follow-ups"
  decides. A task with items to build goes back to `open`.

## 0. Collect the tasks

1. **Find what is left.** From this conversation, list everything the user
   asked for in this feature that is not built yet, each item quoted word for
   word from the user's messages. Read the branch's commits and the working
   tree to tell built from not built; uncommitted work in progress counts as
   not built until its task is committed.
2. **Split into tasks.** One task per item the user asked for, keeping the
   user's quote with it. Do not add work the user did not ask for.
3. **If it is unclear what is left,** add that to the questions in the
   engine's step 1, with what you found built and not built.
4. Write `tasks.md`, then continue with the engine's step 1.

## Check against the user's words

After the engine's final checks (step 5) and before its report (step 6),
launch a fresh subagent with only the user's
original words from this conversation and the result (the diff from the base
commit, plus output or screenshots where they show it). It checks each item,
clause by clause, and reports what does not match. Do not give it your reading
or the implementers' reports. Fix the mismatches under the engine's
implementer rules, or list them as open in the report.

## Additions to the report

- the result of the check against the user's words, and any open mismatch
- the path of `tasks.md`

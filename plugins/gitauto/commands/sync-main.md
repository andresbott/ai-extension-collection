---
description: Synchronize the primary worktree default branch by fast-forward only
argument-hint: "[remote=<name>] [main=<branch>]"
---

Call the `Workflow` tool exactly once with `name` set to `gitauto:sync-main-run`
and `args` set to this exact JSON object:

```json
{"root": "${CLAUDE_PLUGIN_ROOT}/scripts"}
```

Add `"remote"` for a `remote=<name>` value and `"main"` for a `main=<branch>`
value in `$ARGUMENTS`. Never drop `root` — the workflow cannot find its helper
without it.

Wait for the workflow to finish, then report its result verbatim.

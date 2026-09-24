---
description: Run the complete guarded delivery flow from branch creation through optional release tagging
argument-hint: "[branch=<name>] [message=<text>] [title=<text>] [base=<branch>] [remote=<name>] [deleteRemote=true|false] [tag=<semver>]"
---

Call the `Workflow` tool exactly once with `name` set to `gitauto:ship-run`
and `args` set to this exact JSON object:

```json
{"root": "${CLAUDE_PLUGIN_ROOT}/scripts"}
```

Add any of `"branch"`, `"message"`, `"title"`, `"body"`, `"subject"`, `"base"`,
`"remote"`, `"deleteRemote"`, and `"tag"` for values present in `$ARGUMENTS`.
Never drop `root` — the workflow passes it to every nested stage, and none of
them can find their helper without it.

This runs the full flow — branch, verify, commit, push, open-pr, wait-ci, merge,
sync-main, cleanup, and optional tag — as nested workflows with their own stage
ledger and stop/skip/partial rules.

Wait for the workflow to finish, then report its stage ledger and summary verbatim.

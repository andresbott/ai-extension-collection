---
description: Clean up a merged feature branch while retaining its local branch
argument-hint: "[branch=<feature>] [remote=<name>] [deleteRemote=true|false]"
---

Call the `Workflow` tool exactly once with `name` set to `gitauto:cleanup-run`
and `args` set to this exact JSON object:

```json
{"root": "${CLAUDE_PLUGIN_ROOT}/scripts"}
```

Add `"branch"`, `"remote"`, and `"deleteRemote"` for values present in
`$ARGUMENTS`. Remote deletion requires an explicit `deleteRemote=true`. Never
drop `root` — the workflow cannot find its helper without it.

Wait for the workflow to finish, then report its result verbatim.

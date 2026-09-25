---
description: Move off main/master onto a safely named feature branch (no-op on a feature branch)
argument-hint: "[branch name]"
---

Call the `Workflow` tool exactly once with `name` set to `gitauto:flow-run`
and `args` set to this exact JSON object:

```json
{"root": "${CLAUDE_PLUGIN_ROOT}/scripts", "until": "branch"}
```

If `$ARGUMENTS` names a branch, add `"branch"` set to it; otherwise the flow
proposes candidate names and checks out the first free one. Never drop `root` or `until`.

Wait for the workflow to finish, then report its result verbatim.

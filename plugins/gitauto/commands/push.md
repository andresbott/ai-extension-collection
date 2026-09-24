---
description: Push the current feature branch and configure its upstream
argument-hint: "[remote=<name>]"
---

Call the `Workflow` tool exactly once with `name` set to `gitauto:push-run`
and `args` set to this exact JSON object:

```json
{"root": "${CLAUDE_PLUGIN_ROOT}/scripts"}
```

If `$ARGUMENTS` contains `remote=<name>`, add `"remote"` set to that value.
Never drop `root` — the workflow cannot find its helper without it.

Wait for the workflow to finish, then report its result verbatim.

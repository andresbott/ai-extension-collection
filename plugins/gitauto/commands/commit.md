---
description: Create exactly one guarded feature-branch commit containing all changes
argument-hint: "[message]"
---

Call the `Workflow` tool exactly once with `name` set to `gitauto:commit-run`
and `args` set to this exact JSON object:

```json
{"root": "${CLAUDE_PLUGIN_ROOT}/scripts"}
```

If `$ARGUMENTS` is non-empty, add `"_"` set to it before calling. Never drop
`root` — the workflow cannot find its helper without it.

Wait for the workflow to finish, then report its result verbatim.

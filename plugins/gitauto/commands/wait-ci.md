---
description: Wait for pull request checks and classify their terminal state
argument-hint: "[pr=<number>]"
---

Call the `Workflow` tool exactly once with `name` set to `gitauto:wait-ci-run`
and `args` set to this exact JSON object:

```json
{"root": "${CLAUDE_PLUGIN_ROOT}/scripts"}
```

If `$ARGUMENTS` contains a bare PR number or `pr=<number>`, add `"pr"` set to
that value. Never drop `root` — the workflow cannot find its helper without it.

Wait for the workflow to finish, then report its result verbatim.

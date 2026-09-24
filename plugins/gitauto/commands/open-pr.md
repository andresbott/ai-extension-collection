---
description: Create or reuse a pull request for the current feature branch
argument-hint: "[title=<text>] [body=<markdown>] [base=<branch>]"
---

Call the `Workflow` tool exactly once with `name` set to `gitauto:open-pr-run`
and `args` set to this exact JSON object:

```json
{"root": "${CLAUDE_PLUGIN_ROOT}/scripts"}
```

Add `"title"`, `"body"`, and `"base"` only for values present in `$ARGUMENTS`;
the workflow composes a missing title or body itself. Never drop `root` — the
workflow cannot find its helper without it.

Wait for the workflow to finish, then report its result verbatim.

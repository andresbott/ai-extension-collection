---
description: Squash-merge an open pull request with a Conventional Commit subject
argument-hint: "[pr=<number>] [subject=<conventional-subject>]"
---

Call the `Workflow` tool exactly once with `name` set to `gitauto:merge-run`
and `args` set to this exact JSON object:

```json
{"root": "${CLAUDE_PLUGIN_ROOT}/scripts"}
```

Add `"pr"` for a `pr=<number>` value and `"subject"` for a `subject=` value or
a bare value in `$ARGUMENTS`; the workflow derives a missing subject itself.
Never drop `root` — the workflow cannot find its helper without it.

Wait for the workflow to finish, then report its result verbatim.

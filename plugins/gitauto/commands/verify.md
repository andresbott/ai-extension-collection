---
description: Run requested or locally declared repository verification checks
argument-hint: "[check | target=<make-target>]"
---

Call the `Workflow` tool exactly once with `name` set to `gitauto:verify-run`
and `args` set to this exact JSON object:

```json
{"root": "${CLAUDE_PLUGIN_ROOT}/scripts"}
```

If `$ARGUMENTS` is non-empty, add one more key before calling: `check` for a
`check=` value, `target` for a `target=` value, or `_` for a bare value. Never
drop `root` — the workflow cannot find its helper without it.

Wait for the workflow to finish, then report its result verbatim.

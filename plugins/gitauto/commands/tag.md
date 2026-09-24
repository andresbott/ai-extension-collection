---
description: Recommend or explicitly publish a validated SemVer release tag
argument-hint: "[version=<semver>] [subject=<conventional-subject>]"
---

Call the `Workflow` tool exactly once with `name` set to `gitauto:tag-run`
and `args` set to this exact JSON object:

```json
{"root": "${CLAUDE_PLUGIN_ROOT}/scripts"}
```

Add `"version"` for a `version=` value or a bare value, plus `"subject"`,
`"remote"`, and `"worktree"` when present in `$ARGUMENTS`. Without a version the
workflow only recommends and publishes nothing. Never drop `root` — the workflow
cannot find its helper without it.

Wait for the workflow to finish, then report its result verbatim.

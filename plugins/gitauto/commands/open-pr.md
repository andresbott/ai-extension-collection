---
description: Run the ship flow up to an open pull request (branch, verify, commit, push, open-pr)
argument-hint: "[branch=<name>] [message=<text>] [title=<text>] [body=<markdown>] [base=<branch>] [remote=<name>]"
---

Call the `Workflow` tool exactly once with `name` set to `gitauto:flow-run`
and `args` set to this exact JSON object:

```json
{"root": "${CLAUDE_PLUGIN_ROOT}/scripts", "until": "open-pr"}
```

`$ARGUMENTS` may be `key=value` pairs or plain language. Add any of `"branch"`,
`"message"`, `"title"`, `"body"`, `"base"`, and `"remote"` that it specifies;
the flow composes anything missing itself. Never drop `root` or `until`.

This runs branch → verify → commit → push → open-pr and stops there: it never
waits for CI, merges, or tags.

Wait for the workflow to finish, then report its stage ledger and the pull
request URL verbatim.

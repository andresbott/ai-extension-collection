---
description: Run the complete guarded delivery flow from branch creation through optional release tagging
argument-hint: "[branch=<name>] [message=<text>] [title=<text>] [base=<branch>] [remote=<name>] [deleteRemote=true|false] [tag=<semver>|no tag]"
---

Call the `Workflow` tool exactly once with `name` set to `gitauto:flow-run`
and `args` set to this exact JSON object:

```json
{"root": "${CLAUDE_PLUGIN_ROOT}/scripts", "until": "ship"}
```

`$ARGUMENTS` may be `key=value` pairs or plain language. Add any of `"branch"`,
`"message"`, `"title"`, `"body"`, `"subject"`, `"base"`, `"remote"`, and
`"deleteRemote"` that it specifies. Never drop `root` or `until`.

Tag handling:

- An explicit version (`tag=1.2.3`, "tag v1.2.3") → add `"tag"` set to that
  version string.
- The user declines a tag in any wording ("dont create tag", "no tag",
  "without tagging", `tag=false`) → add `"tag": false`. Then do **not** ask,
  offer, or suggest creating a tag at any point — before, during, or after the
  flow.
- Otherwise → omit `"tag"`; no tag is created.

This runs branch → verify → commit → push → open-pr → wait-ci → merge →
sync-main → cleanup → optional tag, with its own stage ledger and
stop/skip/partial rules.

Wait for the workflow to finish, then report its stage ledger and summary
verbatim.

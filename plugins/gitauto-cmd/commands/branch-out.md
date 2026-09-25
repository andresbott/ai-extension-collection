---
description: Move off main/master onto a feature branch (no-op on a feature branch)
argument-hint: "[branch name]"
model: haiku
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/branch-out.sh:*)
---
!`${CLAUDE_PLUGIN_ROOT}/scripts/branch-out.sh '$ARGUMENTS'`

If the output above starts with `DONE`, reply with that line verbatim. Call no tools.

Otherwise invent 3 distinct, concise, lowercase branch names (`feat/`, `fix/`,
`docs/`, or `chore/` plus a kebab-case slug) from the `hint` and the listed
changes; with neither, use `work/<adjective>-<noun>`. Run exactly once:

`${CLAUDE_PLUGIN_ROOT}/scripts/branch-out.sh --create '<n1>' '<n2>' '<n3>'`

Reply with its output line verbatim. Nothing else.

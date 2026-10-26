---
description: Move off main/master onto a feature branch (no-op on a feature branch)
argument-hint: "[branch name]"
model: haiku
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/branch-out.sh:*)
---
!`${CLAUDE_PLUGIN_ROOT}/scripts/branch-out.sh '$ARGUMENTS'`

If the output above starts with `success:` or `error:`, reply with the output
verbatim (its result line, then its `DONE` line). Call no tools.

Otherwise write the branch names its `--- write` block asks for, following its
rule and never using single quotes. Run exactly once:

`${CLAUDE_PLUGIN_ROOT}/scripts/branch-out.sh --create '<n1>' '<n2>' '<n3>'`

Reply with its two output lines verbatim (the result line, then the `DONE`
line). Nothing else.

---
description: Move off main/master onto a feature branch (no-op on a feature branch)
argument-hint: "[branch name]"
model: haiku
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/branch-out.sh:*)
---
!`${CLAUDE_PLUGIN_ROOT}/scripts/branch-out.sh '$ARGUMENTS'`

If the output above starts with `DONE`, reply with that line verbatim. Call no tools.

Otherwise write the branch names its `--- write` block asks for, following its
rule and never using single quotes. Run exactly once:

`${CLAUDE_PLUGIN_ROOT}/scripts/branch-out.sh --create '<n1>' '<n2>' '<n3>'`

Reply with its output line verbatim. Nothing else.

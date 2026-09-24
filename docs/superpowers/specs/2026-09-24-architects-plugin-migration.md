# Architects Plugin Migration Specification

## Goal

Add the `architects` Claude Code plugin to this marketplace by reconciling its
implementations in:

- `/home/bott/.datos/edit/programacion-privado/odo-ai-marketplace`
- `/home/bott/.datos/edit/programacion/andresbott/pi-code-config`

## Requirements

- Treat both origin repositories as read-only.
- Add Pike, Natalia, Tony, Evans, and Margaret under
  `plugins/architects/agents/`.
- Preserve the shared agent instructions, which are identical in both origins.
- Use Claude Code plugin frontmatter in this repository: preserve the private
  marketplace's Claude-compatible `model` and `tools` declarations rather than
  Pi-specific metadata.
- Preserve the source plugin version `0.3.0` for the newly published plugin.
- Register `architects` in `.claude-plugin/marketplace.json`.
- Add `architects` to the available-plugin list in `README.md`.
- Keep the existing marketplace version bump associated with the current
  uncommitted change set; do not modify unrelated plugins.
- Do not commit unless explicitly requested.

## Acceptance criteria

- The plugin manifest is valid JSON and declares `architects` version `0.3.0`.
- The marketplace manifest is valid JSON and contains one `architects` entry.
- All five agent files exist and retain valid YAML frontmatter.
- Agent instruction bodies match both origin implementations.
- No files in either origin repository change.
- Repository whitespace checks pass.

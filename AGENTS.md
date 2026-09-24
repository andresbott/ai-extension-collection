# AGENTS.md

Guidance for AI agents working in this repository.

## Always bump versions with changes

Every commit must increase the marketplace `version` in
`.claude-plugin/marketplace.json`, regardless of the kind of change.

When a commit changes a plugin, it must also increase that plugin's `version` in
`plugins/<name>/.claude-plugin/plugin.json`.

- Use semantic versioning (`MAJOR.MINOR.PATCH`).
- A patch bump is appropriate for small, backward-compatible changes.
- Bump every changed plugin when one commit touches multiple plugins.
- Include version bumps in the same commit as the changes they describe.

The marketplace and installed plugins may be cached by commit, while their
version fields are the human-visible update signal. Keeping these versions
current prevents stale extensions from appearing up to date.

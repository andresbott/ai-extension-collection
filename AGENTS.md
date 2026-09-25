# AGENTS.md

Guidance for AI agents working in this repository.

## Always bump versions with changes

Every commit must increase the marketplace `version` in
`.claude-plugin/marketplace.json`, regardless of the kind of change.

When a commit changes a Claude plugin, it must also increase that plugin's
`version` in `plugins/<name>/.claude-plugin/plugin.json`.

When a commit changes a pi adapter (`plugins/<name>/pi/`), a pi-only plugin
(`plugins/pi-<name>/`, no `.claude-plugin/`), a shared lib (`libs/`), or the
root `package.json` (the pi package), it must also increase the root
`package.json` `version`.

- Use semantic versioning (`MAJOR.MINOR.PATCH`).
- A patch bump is appropriate for small, backward-compatible changes.
- Bump every changed plugin when one commit touches multiple plugins.
- Include version bumps in the same commit as the changes they describe.

The marketplace and installed plugins may be cached by commit, while their
version fields are the human-visible update signal. Keeping these versions
current prevents stale extensions from appearing up to date.

## Keep pi agent twins in sync

An agent in `plugins/<name>/agents/` may have a pi twin in
`plugins/<name>/pi/agents/` with the same file name. When you change one, make
the same change in the other; only the frontmatter and tool names differ (see
DEVELOPMENT.md, "Add pi agents"). `npm run test:pi` checks the pairing.

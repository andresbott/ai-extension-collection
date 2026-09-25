# Plugins

Each extension belongs in `plugins/<name>/`. A Claude Code plugin must include a
`.claude-plugin/plugin.json` manifest; register publishable ones in the root
[marketplace manifest](../.claude-plugin/marketplace.json). pi-only plugins
(`pi-*`) have only a `pi/` directory and no manifest; see
[DEVELOPMENT.md](../DEVELOPMENT.md).

Claude Code auto-discovers conventional plugin directories such as `agents/`,
`commands/`, `hooks/`, and `skills/`. A plugin may ship supporting files in other
directories (for example `scripts/`) and reference them from a command through
`${CLAUDE_PLUGIN_ROOT}`.

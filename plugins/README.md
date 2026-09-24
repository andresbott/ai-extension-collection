# Plugins

Each extension belongs in `plugins/<name>/` and must include a
`.claude-plugin/plugin.json` manifest. Register publishable plugins in the root
[marketplace manifest](../.claude-plugin/marketplace.json).

Claude Code auto-discovers conventional plugin directories such as `agents/`,
`commands/`, `hooks/`, and `skills/`.

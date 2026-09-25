# ai-extension-collection

A [Claude Code plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces)
for reusable extensions.

## Available plugins

| Plugin | Type | Provides | Description |
| --- | --- | --- | --- |
| `architects` | Agents | `pike-go`, `natalia-frontend`, `tony-openapi`, `evans-layering`, `margaret-setup` | Specialist agents for Go, Vue and TypeScript, OpenAPI, dependency layering, and project setup validation. |
| `coding-guides` | Hooks | `SessionStart` context injection, `PreToolUse` guard | Injects standing coding conventions and enforces selected tool-use rules. |
| `doc-authoring` | Skill | `agents-documentation` | Helps create and maintain internal, agent-facing project documentation. |
| `gitauto` | Slash commands, Agent | `/branch-out`, `/open-pr`, `/ship`; `pr-writer` agent | Token-cheap, script-backed Git commands on haiku: `open-pr` stops at green CI, `ship` has an opt-in tag prompt; an Opus PR writer is used only for complex changes. |
| `go-idioms` | Skills | `effective-go`, `golang-patterns` | Effective Go and idiomatic Go guidance for writing, reviewing, and refactoring Go code. |
| `session-sounds` | Hooks | `Stop`, `Notification` sounds | Plays a bundled sound (via `paplay`) when Claude finishes responding and on notifications. |

## Add the marketplace

In Claude Code, run:

```text
/plugin marketplace add andresbott/ai-extension-collection
```

The marketplace identifier is `ai-extension-collection`.

## Install a plugin

After a plugin is published, install it with:

```text
/plugin install <plugin-name>@ai-extension-collection
```

## Development

See [DEVELOPMENT.md](DEVELOPMENT.md) for instructions on adding plugins, testing
changes locally, and updating versions.

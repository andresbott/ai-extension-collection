# ai-extension-collection

A [Claude Code plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces)
for reusable extensions.

## Available plugins

- **`architects`** — provides specialist agents for Go, Vue and TypeScript,
  OpenAPI, dependency layering, and project setup validation.
- **`coding-guides`** — injects standing coding conventions and enforces selected
  tool-use rules.
- **`doc-authoring`** — helps create and maintain internal, agent-facing project
  documentation.
- **`gitauto`** — token-cheap, script-backed Git commands on haiku:
  `branch-out`, `open-pr` (stop at green CI), and `ship` (with an opt-in tag
  prompt); an Opus PR writer is used only for complex changes.
- **`go-idioms`** — provides Effective Go and idiomatic Go guidance for writing,
  reviewing, and refactoring Go code.

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

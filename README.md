# ai-extension-collection

A [Claude Code plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces)
and [pi package](https://pi.dev/packages) of reusable extensions.

## Available plugins

| Plugin | Type | Claude Code | pi | Description |
| --- | --- | :---: | :---: | --- |
| `architects` | Agents | ✅ | ✅ | Specialist agents for Go, Vue and TypeScript, OpenAPI, dependency layering, and project setup validation. In pi they need [`pi-subagents`](https://github.com/nicobailon/pi-subagents). |
| `coding-guides` | Hooks, pi extension | ✅ | ✅ | Injects standing coding conventions and enforces selected tool-use rules. |
| `doc-authoring` | Skill | ✅ | ✅ | Helps create and maintain internal, agent-facing project documentation. |
| `gitauto` | Slash commands, Agent, pi extension | ✅ | ✅ | Token-cheap, script-backed Git commands for Claude Code (on haiku) and pi: `open-pr` stops at green CI, `ship` has an opt-in tag prompt; an expensive PR writer is used only for complex changes. |
| `go-idioms` | Skills | ✅ | ✅ | Effective Go and idiomatic Go guidance for writing, reviewing, and refactoring Go code. |
| `session-sounds` | Hooks | ✅ | ❌ | Plays a bundled sound (via `paplay`) when Claude finishes responding and on notifications. |
| `pi-clear` | pi extension | ❌ | ✅ | `/clear` hides earlier conversation from the model while keeping the session. |
| `pi-clear-on-exit` | pi extension | ❌ | ✅ | Clears the terminal and its scrollback when interactive pi exits. |
| `pi-context` | pi extension | ❌ | ✅ | `/context` shows used, free, and total context-window tokens. |
| `pi-startup-splash` | pi extension | ❌ | ✅ | A startup splash with the model, cwd, context, skills, prompts, and extensions. |
| `pi-statusline` | pi extension | ❌ | ✅ | A compact footer with model, cwd, git branch, context usage, and session cost. |

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

## Use it in pi

Plugins with a pi adapter (`coding-guides`, `gitauto`), pi agents (`architects`),
skills (`doc-authoring`, `go-idioms`), and the pi-only `pi-*` plugins are also
a [pi package](https://pi.dev/packages), listed in the root `package.json`:

```sh
pi install git:github.com/andresbott/ai-extension-collection
```

The `architects` agents load through the
[`pi-subagents`](https://github.com/nicobailon/pi-subagents) extension. They set
no model, so they run on `subagents.defaultModel` or the parent session's model.
Pin one per agent with `subagents.agentOverrides.<Name>.model` in pi's
`settings.json`.

## Development

See [DEVELOPMENT.md](DEVELOPMENT.md) for instructions on adding plugins, testing
changes locally, and updating versions.

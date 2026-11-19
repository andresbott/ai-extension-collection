# ai-extension-collection

A [Claude Code plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces)
and [pi package](https://pi.dev/packages) of reusable extensions.

## Available plugins

| Plugin | Type | Claude Code | pi | Description |
| --- | --- | :---: | :---: | --- |
| `architects` | Agents | ✅ | ✅ | Specialist agents for Go, Vue and TypeScript, OpenAPI, dependency layering, Ansible automation, and project setup validation. In pi they need [`pi-subagents`](https://github.com/nicobailon/pi-subagents). |
| `coding-guides` | Hooks, Skills, pi extension | ✅ | ✅ | Injects standing coding conventions into the session and its subagents, and enforces selected tool-use rules. `/tldr` sums up the last answer, the work so far, or a topic in a few plain-language bullet points, without code names or jargon. `/explain` gives a short numbered picture of how a path, package, or feature works: the flows that matter, each a few steps checked against the code, with similar calls grouped and setup left out. |
| `doc-authoring` | Skill | ✅ | ✅ | Helps create and maintain internal, agent-facing project documentation. |
| `factory` | Slash commands, Skill, Agent, pi extension | ✅ | ✅ | Delivery commands, from writing code to merging it. `/auto-deliver` hands the rest of the feature in the conversation to the agent, which stops only for critical issues; it runs the same delivery engine as `/next-iteration`. `/auto-improve` improves the current branch unattended: one subagent reviews, a fresh subagent fixes each finding test-first, complex findings can be planned and landed by subagents, and a second review checks the fixes, all tracked in `TODO.md`. `/next-iteration` takes every task in state `ready` in the todo list (only through the `todo` binary), plus `followup` tasks an expert subagent can clear without the user, groups them by complexity, has independent subagents settle open questions up front, asks the user only the ones they cannot decide, then builds them with specialized subagents, moves each task through working, review, and done or followup, and commits on the current branch. `/review-pr` checks a GitHub pull request out into a separate worktree, has reviewer subagents picked for the areas it touches review it, verifies their findings, and prints a short summary plus inline comments on the diff, without posting them; its exhaustive mode runs three independent reviewer teams and keeps only what two of them found, or a confirmed blocker. `/review-branch` runs the same review engine on the current branch, uncommitted work included, and offers to fix the findings through the delivery engine, test-first from each finding's failing scenario. Token-cheap, script-backed Git commands for Claude Code (on haiku) and pi: `new-branch` leaves main, `open-pr` stops at green CI, `ship` merges and has an opt-in tag prompt; an expensive PR writer is used only for complex changes. `/generate-readme` writes a short, quick-glance README.md (header with image, what you can do with it, install or add-to-project steps, license footer) and a separate DEVELOPMENT.md. In pi, the commands that launch subagents (`auto-deliver`, `auto-improve`, `next-iteration`, `review-branch`, `review-pr`) need [`pi-subagents`](https://github.com/nicobailon/pi-subagents). |
| `go-idioms` | Skills | ✅ | ✅ | Effective Go and idiomatic Go guidance for writing, reviewing, and refactoring Go code. |
| `session-sounds` | Hooks | ✅ | ❌ | Plays a bundled sound (via `paplay`) when Claude finishes responding and on notifications. |
| `pi-clear` | pi extension | ❌ | ✅ | `/clear` hides earlier conversation from the model while keeping the session. |
| `pi-clear-on-exit` | pi extension | ❌ | ✅ | Clears the terminal and its scrollback when interactive pi exits. |
| `pi-context` | pi extension | ❌ | ✅ | `/context` shows a Claude-Code-style breakdown of context usage: grid, categories, and per-item lists. |
| `pi-rename` | pi extension | ❌ | ✅ | `/rename "title"` names the session verbatim; bare `/rename` has Sonnet (or the session model) generate a name. |
| `pi-render-mode` | pi extension (WIP) | ❌ | 🚧 | Work in progress, not in the pi package yet: `ctrl+r` switches rendering between normal, verbose, and minimal. |
| `pi-startup-splash` | pi extension | ❌ | ✅ | A startup splash with the model, cwd, context, skills, prompts, and extensions. |
| `pi-statusline` | pi extension | ❌ | ✅ | A compact footer with model, cwd, git branch, context usage, and session cost. |
| `pi-summarize` | pi extension | ❌ | ✅ | `/summarize` has Sonnet (or the session model) summarize the conversation into a chat card that is kept in the session but not sent to the model. |

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

Plugins with a pi adapter (`coding-guides`, `factory`), pi agents (`architects`),
skills (`coding-guides`, `doc-authoring`, `factory`, `go-idioms`), and the pi-only `pi-*` plugins are also
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

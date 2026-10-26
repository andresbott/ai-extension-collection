# pi-context

A Pi extension that adds **`/context`**: a breakdown of context-window usage
modeled on Claude Code's `/context`. It shows a grid of the window, one glyph per
slice colored by category, with a legend beside it and per-item lists below.
Vanilla Pi shows the total in the footer but has no breakdown.

## What it does

`/context` adds a **Context Usage** card to the chat:

```text
⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛃ ⛃ ⛃ ⛃ ⛃ ⛃ ⛃ ⛃ ⛃ ⛃   Claude Opus 4.7 · 231k/1M tokens (23.1%)
⛃ ⛃ ⛃ ⛃ ⛃ ⛃ ⛃ ⛃ ⛃ ⛃ ⛃ ⛃ ⛃ ⛃ ⛃ ⛃ ⛃ ⛃ ⛃ ⛃
⛃ ⛃ ⛃ ⛃ ⛃ ⛃ ⛃ ⛃ ⛃ ⛃ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶   Estimated usage by category
⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶   ⛁ System prompt: 1.6k tokens (0.2%)
⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶   ⛁ System tools: 679 tokens (0.1%)
⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶   ⛁ Extension tools: 9.3k tokens (0.9%)
⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶   ⛁ MCP tools: 1.2k tokens (0.1%)
⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶   ⛁ Extension prompts: 14.7k tokens (1.5%)
⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶   ⛁ Memory files: 407 tokens (<0.1%)
⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛝ ⛝ ⛝   ⛁ Skills: 2.8k tokens (0.3%)
                                          ⛃ Messages: 200k tokens (20.0%)
                                          ⛶ Free space: 753k (75.3%)
                                          ⛝ Autocompact buffer: 16.4k tokens (1.6%)

MCP tools
└ mcp: 879 tokens
└ mcp__context7: 168 tokens

Extension prompts
└ agent_browser: 9.1k tokens
└ coding-guides: 4.9k tokens

Memory files
└ AGENTS.md: 386 tokens

Skills
└ agents-documentation: 221 tokens
…
```

| Category | What it counts |
| --- | --- |
| System prompt | pi's own prompt sections: preamble, tool list, rules, docs, cwd, appended prompt |
| System tools | Declarations of pi's built-in tools (`read`, `bash`, `edit`, …) |
| Extension tools | Declarations of tools registered by extensions |
| MCP tools | Declarations of MCP tools (`mcp`, `mcp__*`, or registered by an MCP extension) |
| Extension prompts | Prompt sections added by extensions (e.g. `coding-guides`) |
| Memory files | Context files (`AGENTS.md` / `CLAUDE.md`) |
| Skills | The skill list in the system prompt |
| Messages | The conversation: the total minus everything above |

The grid is 10 columns wide for windows up to 200k tokens and 20 wide beyond,
like Claude Code. The autocompact buffer is pi's `compaction.reserveTokens`
(default 16,384, per-model overrides respected): auto-compaction starts when
usage reaches it. It is not shown when compaction is disabled.

The card is a custom session entry: it stays in the session file, so it is still
there after `/resume`, but it is never sent to the model and costs no context.
Outside the TUI (RPC, print) the same panel is sent as a plain-text
notification.

## How it works

- **What the model sees:** pi records the system prompt as named sections and
  tool changes as `toolsAdded` / `toolsRemoved` on system messages in the
  transcript. `/context` replays them from
  `ctx.sessionManager.buildSessionProjection()`. It therefore counts the exact
  prompt and tools of the last request, including sections that extensions add
  per run. Before the first request it falls back to `ctx.getSystemPrompt()`,
  split back into sections, and the active tools from `pi.getAllTools()`.
- **Tool origin:** `pi.getAllTools()` source paths and namespaces tell built-in,
  extension, and MCP tools apart.
- **Per-item lists:** memory files and skills are parsed from their prompt
  sections. Lists are sorted largest first; memory files stay in prompt order.
- **Totals:** the total is pi's `ctx.getContextUsage()`, which is based on the
  last response's real usage. Categories are estimated at chars / 4, the same
  heuristic pi uses, and **Messages** gets the remainder. When pi has no usage
  number (right after a compaction), messages are estimated too and the header
  says "estimated".

The logic is in [`pi/breakdown.ts`](./pi/breakdown.ts) (categories),
[`pi/report.ts`](./pi/report.ts) (grid, legend, lists), and
[`pi/command.ts`](./pi/command.ts) (reading pi), all unit-tested.
[`pi/render.ts`](./pi/render.ts) draws the card and needs the pi-tui runtime, so
[`pi/index.ts`](./pi/index.ts) injects it instead of the tests loading it.

The grid and legend are ported from
[oh-my-pi](https://github.com/can1357/oh-my-pi)'s built-in `/context` (MIT); see
[THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md).

## Install

It ships with the ai-extension-collection pi package:

```sh
pi install git:github.com/andresbott/ai-extension-collection
```

To load only this extension while iterating, from the repo root:

```sh
pi -e ./plugins/pi-context/pi/index.ts
```

Then type `/context` in an interactive Pi session.

## Test

From the repo root:

```sh
npm run test:pi
```

## Notes & limitations

- **Estimates by category.** pi does not expose a tokenizer, so the split uses
  chars / 4. JSON tool schemas usually tokenize denser than prose, so tool
  counts are rough. The total is pi's own number.
- **Last request, not the next one.** The breakdown reflects what the model saw
  on its last request. Tools or sections changed since then show up after the
  next message.
- **Pi only.** omp already has `/context` built in (and drops colliding
  extension commands), so this does nothing there.

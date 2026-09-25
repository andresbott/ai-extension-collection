# pi-render-mode

> **Work in progress — not shipped.** This extension is kept here for
> development only. It is deliberately **not** listed in the root
> `package.json` `pi.extensions`, so `pi install` of this package does not load
> it. Load it by hand to try it (see [Try it](#try-it)).

Rotate how the [Pi coding agent](https://pi.dev) renders a turn between three
modes with a single keypress. Pi-only (uses Pi's tool-render, markdown-transform,
shortcut, and working-loader extension APIs).

| Mode | Thinking | Tool call | Tool output |
|------|----------|-----------|-------------|
| `normal` *(default)* | hidden | shown, compact | truncated (expand with `ctrl+o`) |
| `verbose` | shown | shown | full |
| `minimal` | hidden | **hidden** | **hidden** |

**minimal** is the quiet mode: no per-tool rows at all — just Pi's working
spinner (with a `working…` message) for the whole turn, then the assistant's
output.

## Rotate

Press **`ctrl+r`** to cycle `normal → verbose → minimal → normal`. The active
mode shows in the footer (`render: <mode>`) and a notification confirms each
change. The chosen mode is **persisted globally** (`$PI_CODING_AGENT_DIR/render-mode.json`,
falling back to `~/.pi/agent/`) and restored on the next session.

This assumes Pi's built-in session-rename binding for `app.session.rename` is
disabled in `~/.pi/agent/keybindings.json`. To rebind the render-mode shortcut,
change `ROTATE_KEY` at the top of [`pi/index.ts`](./pi/index.ts).

## How it works

- **Thinking** — a markdown transformer blanks `assistant-thinking` blocks
  unless the mode is `verbose`. This is display-only: the real thinking stays in
  the session and in the model's context.
- **Tools** — the seven built-in tools (`read`, `bash`, `edit`, `write`,
  `find`, `grep`, `ls`) are re-registered with the same names, delegating
  execution to the originals and swapping in mode-aware renderers. They use
  `renderShell: "self"`, so minimal mode can render an empty (zero-height)
  component and the tool row disappears entirely — no empty boxed rows.
  Known third-party tool rows (FFF, web access, MCP, Pi Lens, subagents, and
  workflows) are suppressed through Pi's exported `ToolExecutionComponent`.
- **Spinner** — in minimal mode the working-loader message is set to `working…`;
  Pi's spinner is what remains on screen while the turn runs.

All mode decisions live in [`pi/modes.ts`](./pi/modes.ts) as pure functions
(unit tested); [`pi/index.ts`](./pi/index.ts) and [`pi/tools.ts`](./pi/tools.ts)
are thin wiring over the Pi SDK and pi-tui.

## Caveats

- Pi has no public global tool-render middleware. Minimal mode therefore uses
  a compatibility patch for explicitly known third-party tool names. Unknown
  or newly renamed tools keep their own rendering until added to the allowlist.
- The compatibility patch reads `ToolExecutionComponent.toolName`, an internal
  runtime field on a publicly exported component. A future Pi release could
  require this patch to be adjusted.
- A mode change affects **new** rendering. Already-printed rows re-render only
  when Pi repaints them (terminal width change, or the `ctrl+o` expand toggle).
- Hiding thinking is best-effort display suppression via the transformer; it is
  independent of Pi's own `ctrl+t` collapse toggle and the `hideThinkingBlock`
  setting.

## Try it

It is not part of the ai-extension-collection pi package yet. To load it for one
session, from the repo root:

```sh
pi -e ./plugins/pi-render-mode/pi/index.ts
```

Use `/reload` after editing.

## Tests

From the repo root:

```sh
npm run test:pi
```

The pure logic (mode cycling, thinking transform, result plans, persistence) is
unit tested. `index.ts` / `tools.ts` import pi-tui and the SDK as values (which
do not resolve outside an installed Pi), so they are verified live in Pi rather
than in unit tests.

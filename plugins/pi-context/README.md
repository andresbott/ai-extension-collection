# pi-context

A Pi extension that adds **`/context`** — a read-only readout of context-window
usage — mirroring omp's built-in `/context`. Vanilla Pi shows usage in the
footer but has no `/context` command to print it on demand.

## What it does

`/context` prints a one-line summary of the active model's context usage:

```
Context: 50,000 / 200,000 tokens (25%), 150,000 free (kimi-k3)
```

Unlike `/clear`, it changes nothing — it only reports.

## How it works

Pi hands the numbers straight to extensions, so this is a thin wrapper:

- `registerCommand("context")` — reads `ctx.getContextUsage()` (`{ tokens,
  contextWindow, percent }`) and `ctx.model?.name`, then shows the summary via
  `ctx.ui.notify`.

The formatting lives in [`pi/context.ts`](./pi/context.ts) as a pure, dependency-free
function; [`pi/index.ts`](./pi/index.ts) is only the wiring. Both are unit-tested.

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

- **Aggregate, not per-category.** Pi's public API exposes total usage, not a
  system/tools/messages split, so this reports used / window / % / free rather
  than omp's fuller per-section breakdown.
- **`tokens` can be `null`** right after a compaction and before the next model
  response; it then prints "not yet estimated" with the window size.
- **Pi only.** omp already has `/context` built in (and drops colliding
  extension commands), so this is a no-op there.

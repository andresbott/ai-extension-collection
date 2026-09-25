# pi-clear

A Pi extension that adds **`/clear`** — "clear the conversation context in place,
keeping the session" — mirroring omp's built-in `/clear`. Vanilla Pi has no
`/clear` (its 23 built-ins use `/new` to start a *new* session); this brings the
in-place clear to Pi.

## What it does

`/clear` hides the prior conversation from the model on the next and all
subsequent model calls, while leaving the session and its on-disk transcript
untouched. It's the "free up the context window but keep working in this
session" command.

## How it works

Pi's public extension API has no in-place context-reset primitive (only
session-level `newSession` / `fork` / `switchSession`). So `/clear` is built from
the two sanctioned hooks:

- `registerCommand("clear")` — arms a clear and notifies the user.
- `on("context")` — fires before every model call; it trims the model-bound
  message list, dropping everything before the point of the clear.

The trimming logic lives in [`pi/clear.ts`](./pi/clear.ts) as a pure, dependency-free
function; [`pi/index.ts`](./pi/index.ts) is only the wiring. Both are unit-tested.

## Install

It ships with the ai-extension-collection pi package:

```sh
pi install git:github.com/andresbott/ai-extension-collection
```

To load only this extension while iterating, from the repo root:

```sh
pi -e ./plugins/pi-clear/pi/index.ts
```

Then type `/clear` in an interactive Pi session.

## Test

No dependencies — Node's built-in runner over the TypeScript sources, from the
repo root:

```sh
npm run test:pi
```

## Behavior notes & limitations

- **Baseline = everything before your next message.** The clear is captured on
  the first model call after `/clear`, keeping the message you type next. This
  assumes the normal flow (`/clear`, then type a prompt).
- **Process-scoped.** The clear state is in-memory: it holds for the running Pi
  process, but a full restart + resume of the same session forgets it (the
  hidden messages come back). Re-run `/clear` if needed. Persisting it across
  restarts would require anchoring to a session entry — deliberately out of
  scope for v0.1.
- **`/compact` interplay.** A compaction after a `/clear` rewrites the message
  history and can shift the boundary; this isn't specially handled.
- **Pi only.** In omp, `/clear` is already built in and omp drops extension
  commands that collide with built-ins, so this extension is a no-op there.

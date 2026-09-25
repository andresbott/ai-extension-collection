# pi-rename

A Pi extension that adds **`/rename`**, modeled on Claude Code's `/rename`.
Pi's built-in `/name` only sets a name you type; `/rename` can also have the
model write one for you.

## What it does

| You type | Result |
| --- | --- |
| `/rename "Fix auth bug"` | Names the session `Fix auth bug`, verbatim. No model call. |
| `/rename Fix auth bug` | Same, quotes are optional. |
| `/rename` | Sends the conversation to a mid-tier model (Sonnet, see below), which returns a 3–6 word title, then names the session with it. |

The name appears in `/resume` like any name set with `/name`. The extension
names a session only when you run `/rename`; it never renames anything on its
own.

A typed title is used as-is. The only changes are trimming surrounding
whitespace and removing one pair of quotes (`"…"`, `'…'`, `` `…` ``, `“…”`) that
wraps the whole argument. Inner quotes, punctuation, and casing are kept.

## How it works

- `registerCommand("rename")`. With an argument, it calls `pi.setSessionName()`
  with that title. Without one, it builds a plain transcript from
  `ctx.sessionManager.getBranch()`, keeping only user and assistant text. If the
  transcript is over about 6,000 characters, it keeps the start and the end.
- The generated name comes from one side call (`sideCall()` in
  [`libs/pi-side-call`](../../libs/pi-side-call/)), made with
  `cacheRetention: "none"` and a fresh session ID. The main conversation and its
  context are not touched.
- The reply is tidied (first line only, with `Title:` labels, quotes, and any
  trailing period removed, and a length cap) before `pi.setSessionName()`.

The pure logic lives in [`pi/rename.ts`](./pi/rename.ts) and the shared
[`libs/pi-side-call`](../../libs/pi-side-call/); [`pi/index.ts`](./pi/index.ts)
is only the wiring. All are unit-tested.

## Install

It ships with the ai-extension-collection pi package:

```sh
pi install git:github.com/andresbott/ai-extension-collection
```

To load only this extension while iterating, from the repo root:

```sh
pi -e ./plugins/pi-rename/pi/index.ts
```

## Test

From the repo root:

```sh
npm run test:pi
```

## Notes & limitations

- **Uses Sonnet when it can.** The naming call goes to the newest available
  Sonnet, preferring the session's provider (for example
  `github-copilot/claude-sonnet-4.6`), with thinking left at the provider
  default. With no Sonnet available it uses the session's current model. The
  notification says which model is used. It costs one small request.
- **Failures change nothing.** With no model, missing auth, an empty session, a
  failed request, or an empty reply, the old name stays and you see a warning or
  an error.
- **Text only.** Tool calls and tool results are left out of the transcript
  given to the model.

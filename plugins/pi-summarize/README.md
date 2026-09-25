# pi-summarize

A Pi extension that adds **`/summarize`**: a mid-tier model summarizes the
conversation, and the summary appears in the chat as a card. The card is kept in
the session file, so it is still there after `/resume`, but it is never sent to
the model and costs no context.

## What it does

| You type | Result |
| --- | --- |
| `/summarize` | Sends the conversation to Sonnet (see below), then shows the Markdown summary (Goal, Key decisions, Progress, Open questions, Next steps) as a **Session summary** card in the chat. |

The extension summarizes only when you run `/summarize`; it never runs on its
own. Each run adds a new card; earlier cards stay where they were.

## How it works

- `registerCommand("summarize")` builds a plain transcript from
  `ctx.sessionManager.getBranch()`, keeping only user and assistant text. If the
  transcript is over about 100,000 characters (about 25k tokens), it keeps the
  start and the end.
- The summary comes from one side call (`sideCall()` in
  [`libs/pi-side-call`](../../libs/pi-side-call/)), made with
  `cacheRetention: "none"` and a fresh session ID. The main conversation and its
  context are not touched.
- The trimmed reply is stored with `pi.appendEntry("session-summary", …)`
  together with the model that wrote it. `pi.registerEntryRenderer()` draws it
  as a card with rendered Markdown. Custom entries are not part of the model's
  context, so the summary does not change what the model sees.

The logic lives in [`pi/command.ts`](./pi/command.ts),
[`pi/summarize.ts`](./pi/summarize.ts), and the shared `libs/pi-side-call`, all
unit-tested. [`pi/render.ts`](./pi/render.ts) draws the card and needs the
pi-tui runtime, so it is injected into `command.ts` by
[`pi/index.ts`](./pi/index.ts) instead of being loaded by the tests.

## Install

It ships with the ai-extension-collection pi package:

```sh
pi install git:github.com/andresbott/ai-extension-collection
```

To load only this extension while iterating, from the repo root:

```sh
pi -e ./plugins/pi-summarize/pi/index.ts
```

## Test

From the repo root:

```sh
npm run test:pi
```

## Notes & limitations

- **Uses Sonnet when it can.** The summary call goes to the newest available
  Sonnet, preferring the session's provider (for example
  `github-copilot/claude-sonnet-4.6`). With no Sonnet available it uses the
  session's current model. The notification says which model is used. It costs
  one request sized by the conversation.
- **Failures change nothing.** With no model, missing auth, an empty session, a
  failed request, or an empty reply, no card is added and you see a warning or
  an error.
- **Text only.** Tool calls and tool results are left out of the transcript, so
  the summary relies on what was said, not on every file that was touched.
- **Card in the TUI only.** Entry renderers run in the interactive TUI. In RPC
  mode the summary is also shown as a notification; in print and JSON modes it
  is only stored in the session.

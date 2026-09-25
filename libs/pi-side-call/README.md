# pi-side-call

Shared helpers for pi extensions that make a one-off model call beside the main
conversation. It has no domain knowledge and no runtime dependencies; each type
it reads is a structural slice that pi's own types satisfy.

| Module | Export | Purpose |
| --- | --- | --- |
| [`models.ts`](./models.ts) | `pickModel(available, families, sessionProvider?)` | Picks a model by family, for example `[/sonnet/i]`. The session's provider wins, then the earliest family, then the newest version. The caller supplies the families. |
| [`transcript.ts`](./transcript.ts) | `buildTranscript(entries, maxChars)` | Flattens a session branch's user and assistant text. Over budget, it keeps the start and the end. |
| [`side-call.ts`](./side-call.ts) | `sideCall(registry, model, prompt, signal?)` | Sends one user message and returns the reply text. It writes no prompt cache and uses a fresh session ID. It throws on a failed request, an error, or an abort. |

Used by `pi-rename`, `pi-summarize`, and gitauto's pi adapter
(`pickCheapModel`). Tests run with `npm run test:pi`.

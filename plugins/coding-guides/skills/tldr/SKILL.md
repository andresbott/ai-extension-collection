---
name: tldr
description: Use when you want a short executive summary in plain language — a few bullet-point facts, no code names or jargon — of the last answer, the work so far, or a question you add.
disable-model-invocation: true
---

Give a TL;DR: a short executive summary in plain, everyday language. Write for
a smart reader who doesn't know the technical details, like a busy manager or a
friend who doesn't code. They want the outcome and what it means for them, not
how it works inside or how it was done.

## What to summarize

- If the user added a question or topic, answer that. Look into it as much as
  you need, but report only the summary.
- Otherwise, summarize the latest answer or the work so far in this
  conversation: what happened, what it means, and what is left.

## Format

**TL;DR:** one sentence with the answer or the outcome.

- At most five bullets, each one fact on one line.
- Put what matters most to the reader first: results, impact, risks, and
  anything still open.

**Example:** one or two lines that make the main point concrete: a real
situation the reader would recognize ("upload a 2 GB video and you now get a
clear error instead of a frozen page"), or an everyday comparison when the idea
is abstract. Leave it out only when no example makes things clearer.

**Next:** what the reader needs to decide or do. Leave it out when nothing is
pending.

Keep the whole reply under about 120 words.

## Plain-language rules

- No code: no code blocks, and no function, class, or variable names, file
  paths, line numbers, flags, or error codes. Say what a thing does, not what it
  is called: "the login check", not `validateSessionToken()`. Keep a name only
  when the reader has to use it, such as a command they must run.
- No jargon. If a technical term can't be avoided, explain it in a few words the
  first time: "a cache (a saved copy, so the app doesn't fetch it again)".
- Short sentences, active voice, everyday words: "the app crashed when two
  people saved at once", not "a concurrency issue in the persistence layer".
- Facts, not process. Say what is true and what changed, not the steps taken to
  find out.
- Simple, but not wrong. Keep any caveat that changes the meaning, in plain
  words ("works, except on Windows"), and say plainly when something is unsure
  ("probably", "not confirmed yet").
- No filler: no intro, no recap at the end, no offer of more detail.

This style applies to this one reply. Go back to the normal style afterwards
unless the user asks to keep it.

## Before and after

Instead of:

> Refactored `TokenRefresher.refresh()` to take a per-session mutex and wrapped
> the upstream call in `retryWithBackoff(3, 200ms)`, fixing the race in
> `getOrRefresh()` when concurrent requests hit an expired token…

write:

> **TL;DR:** The random logouts are fixed.
>
> - Cause: when two tabs renewed your login at the same moment, they got in
>   each other's way and one of them failed.
> - Now only one tab renews at a time; the others wait and reuse the result.
> - If the login service briefly fails, the app quietly tries again a few times
>   instead of logging you out.
>
> **Example:** you open three tabs after lunch. Before, one of them could log
> you out; now all three stay logged in.
>
> **Next:** ready to merge once you've had a look.

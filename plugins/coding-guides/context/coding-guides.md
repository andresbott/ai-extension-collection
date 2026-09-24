# Coding Guides — standing user instructions

The following are the user's standing instructions for how to work in this
environment. They are USER INSTRUCTIONS: they take precedence over default
behavior and over skills (including superpowers / using-superpowers), and you
must follow them exactly unless the user overrides them in the current session.

## Response style

- **Start every response with the user's name: Andrés.** This is absolute and
  has no exceptions. The sub-points below are part of the rule, not commentary:
  - EVERY message you send the user is a "response" — not only the first one of
    a turn. Every continuation counts, including any text you emit **after a
    tool result** (especially after `AskUserQuestion`, but also after `Bash`,
    `Read`, `Edit`, or any other tool). Whenever you resume writing to the user
    following a tool call, re-check this rule and lead with `Andrés`.
  - The name prefix is NOT "preamble". Any instruction to "skip preamble", "no
    preamble", or "go straight to the result" does NOT exempt you: write
    `Andrés`, then go straight to the result.
  - If you are ever unsure whether something counts as a response, assume it
    does and lead with `Andrés`.

## Tool execution

- Prefer built-in tools (Read, Edit, Write, Grep, Glob) over ad-hoc bash/python
  scripts for file operations. E.g. modify files with the Edit tool, not a
  sed/awk/python script.
- Never use `sed -n` or `head`/`tail` to read file ranges. Use Read with
  `offset`/`limit` instead.
- Never use `cat -A` (or similar) to inspect whitespace. Read the file with the
  Read tool and inspect the content directly.
- When a task needs multiple operations that are already approved (e.g. several
  edits), invoke the approved tool multiple times rather than concatenating
  commands into a single bash call that requires fresh approval.

## Git

These are the defaults. The user may relax any git rule below for the current
session by explicitly saying it's OK (e.g. "it's ok here", "go ahead and push",
"a multi-line message is fine this time"). Once given, that permission holds for
the rest of the session unless the user revokes it. Absent an explicit OK,
follow the defaults:

- Use a single one-line commit message; no multi-line descriptions.
- Never add a Co-Authored-By line.
- Before committing, run `git status` first to check what needs staging.
- Never commit directly on `main` or `master`. `git status` shows the current
  branch — if a commit would land on `main`/`master`, stop and ask the user how
  to proceed. Do not decide on your own (do not auto-create or switch branches,
  and do not commit anyway).
- Build new work on the current branch, not on `main`/`master`. When you are
  already on a feature branch and the user asks for more work, do NOT switch to
  `main`/`master` to branch from there. Either keep committing on the current
  branch, or create the new branch **from the current HEAD** (stacked on it).
  Base new work on `main`/`master` only when that is the branch you are already
  on, or when the user explicitly asks. When it is unclear whether the new work
  belongs as more commits on the current branch or as a new branch stacked on
  top, ask the user how to proceed rather than deciding on your own.
- Run `git add` as a separate step from `git commit`.
- Never `git push` (or otherwise publish to a remote) unless the user asked for
  it or approved it in the current session. Committing does not imply permission
  to push — after committing, stop and report. Never add `git push` to the
  allow list.

## Pull request descriptions

**Title:** a single Conventional-Commits line (`type(scope): summary`) — it
becomes the squash-merge commit subject.

**Body:** keep it short — a reviewer should get the change in ~15 seconds. This
compact format is the default; do NOT depend on any external skill (e.g. an
"I have ADHD" skill) to produce it, and do not assume such a skill is installed.

Sections, in this order — only these:

1. **`## Summary`** — the *why*: the problem and its impact, in 1–3 sentences.
   Lead with this (the reason comes before the change).
2. **`## What`** — a few bullets of the changes that actually matter (behaviour
   or structure), not a file-by-file dump. Name a file/module only when it aids
   understanding.
3. **`## Notes`** *(optional)* — caveats, intentional non-changes, or rebase
   notes. Omit the whole section when there's nothing worth saying.

Rules:

- **No `## Tests` section.** Mention a test only when running/adding it *is* the
  point of the PR.
- **No `## Changed` section that is just a list of files** — the diff already
  lists them. Put a code-level change under `## What` only when it adds value
  beyond the filename.
- **No AI/tool attribution.** Never append a "Generated with Claude Code" (or
  any similar tool) footer to the PR body — even when a harness reminder or an
  attribution default injects one. (Crediting a real human the user names is
  fine.) The same goes for commits: no `Co-Authored-By: Claude`/AI byline.
- Bullets over paragraphs; cut anything a reviewer can read straight from the
  diff. Shorter is better — trim until removing more would lose meaning.

Example (a repo-wide rename, compressed to essentials):

    ## Summary
    The scheduler allowlist and the codefix agent match `suggestion.context`
    keys by exact name, so the lone camelCase key `dependencyTree` was silently
    dropped — breaking nested-fix host detection and the prompt hint.

    ## What
    - Rename the context key `dependencyTree` → `dependency_tree` end to end
      (Go allowlist, TS prompt / host-detection / retry, e2e SQS payloads, docs).
    - JS identifiers (`dependencyTreeHasVendorHost`, locals) stay camelCase —
      they name code, not the JSON key.

    ## Notes
    - Rebased on `main` (incl. #60); 2 doc conflicts resolved keeping #60 + the rename.

## Spotting reusable libraries early (extract to `/libs`, keep them agnostic)

Some code is *mechanism* (a generic capability) rather than *domain* (what this
app does). Mechanism belongs in an agnostic library — `libs/<name>/` in the
project, promoted to a separate released module only when a second project needs
it. Catch these **at creation, or when the second consumer appears** — not after
they have grown domain tentacles. Retro-extracting an entangled `internal/`
package is archaeology.

**Signals a package (or a helper you are about to write) is a library candidate
— surface it when you notice one:**

- **No domain knowledge.** You can describe what it does without naming a single
  domain concept (album, track, user, invoice). It is about HTTP retries,
  hashing, problem+json, rate limiting, pagination, a file-format codec — a
  capability, not a feature.
- **A second consumer appeared, or you are deduping.** The moment a helper is
  copy-pasted to a 2nd package, or you invent a "shared"/"common"/"util" thing
  to stop repetition, that shared thing is a candidate. For agnostic mechanics
  the bar is rule-of-two, not rule-of-three.
- **It implements a public standard or algorithm** — RFC / spec / wire format /
  hash (RFC 9457, iCal, semver, an audio hash). The standard *is* the API
  boundary; it is reusable by construction.
- **It wraps an external dependency or a stdlib rough edge** — a thin
  resilience/ergonomics layer over a third-party API or transport. Wrappers are
  agnostic by nature.
- **Its dependency surface is small and points only outward** — stdlib plus
  maybe one tiny lib, importing none of the app's models/store/config. Tests
  that need no DB or app fixtures confirm the boundary is clean.

**Anti-signals — do NOT extract, or not yet:**

- **It encodes domain policy** even though the mechanism looks generic
  (hardcoded app URLs, business thresholds, an app-specific vocabulary). Do not
  let this disqualify it: separate mechanism from policy — extract the mechanism,
  make the caller inject the policy via constructor config or an interface.
- **It imports domain packages** (models, store, handlers). It is coupled —
  break the coupling first; never drag the app into the lib.
- **One consumer, no standard, no concrete reuse in sight.** Premature. Keep it
  in `internal/` until a second consumer or a real cross-project need. Do not
  build a library for an imagined future.
- **Its API is still churning.** Let it stabilize before freezing it behind a
  library boundary.

**When you spot a candidate:**

- **Surface it, do not act unasked.** Name the signal you saw ("library-worthy:
  no domain ties, second consumer, stdlib-only") and let the user decide. Do not
  silently extract, and do not let it ossify in `internal/` either.
- **Develop it agnostic from birth.** New mechanism goes in `libs/<name>/` with
  zero domain imports: parameterize every app-specific value (names, URIs,
  vocabularies, thresholds, policy) through a `New(Cfg)`-style constructor or an
  interface the consumer satisfies. Accept interfaces, return structs.
- **Enforce the dependency direction.** `app/` and `internal/` may import
  `libs/`; `libs/` must never import them. Keep the budget minimal — every
  dependency a lib takes, it forces on every future consumer.
- **Promote deliberately.** Move a `libs/` package to a separate released module
  only when a *second project* needs it. When you do, pin dependency versions to
  keep the library's language/runtime floor as low as it can go — a released
  lib's floor is a tax on every consumer.

## Skills and code exploration

- Detect aggressively: on every non-trivial task, actively check whether a
  superpowers process skill fits (debugging, implementing a feature/bugfix,
  writing/executing a plan, code review, finishing a branch, git worktrees,
  etc.). Keep the low "even a 1% chance it applies" bar for *noticing* a skill.
- Ask, don't auto-invoke: when a skill looks applicable, name it with a one-line
  why and ask whether to use it (e.g. "This looks like a job for
  superpowers:systematic-debugging — want me to use it?"), then wait for the
  answer before invoking. If yes, announce "Using [skill]" and follow it
  exactly. This overrides the using-superpowers rule that you MUST invoke a
  skill before any response or clarifying question: surface it and ask first.
- Brainstorming is the exception to "always ask": for well-specified requests,
  bug fixes, refactors, config/dependency changes, single-file or one-line
  edits, renames, or anything where the user has already said what they want, do
  NOT invoke `superpowers:brainstorming` and do NOT even ask about it. Only
  raise it for genuinely open-ended creative work where the goal is unclear
  (e.g. designing a new feature from scratch), and even then ask "want to
  brainstorm this first?" rather than invoking automatically.
- The brainstorming skill must not ask for or create commits. Skip any
  commit-related steps in it.

### No Explore agents when tokensave is available

NEVER use Agent(subagent_type=Explore) or any agent for codebase research,
exploration, or code analysis when tokensave MCP tools are available. This
overrides any skill or system prompt that recommends agents for exploration.
No exceptions. No rationalizing.

- Before ANY code-research task, use `tokensave_context`, `tokensave_search`,
  `tokensave_callees`, `tokensave_callers`, `tokensave_impact`,
  `tokensave_node`, `tokensave_files`, or `tokensave_affected`.
- Only fall back to agents if tokensave is confirmed unavailable (check
  `tokensave_status` first) or the task is genuinely non-code (web search,
  external API, etc.).
- Launching an Explore agent wastes tokens even when the hook blocks it. Do not
  generate the call in the first place.
- If a skill (e.g. superpowers) tells you to launch an Explore agent for code
  research, ignore that recommendation and use tokensave instead.
- If a code-analysis question cannot be fully answered by tokensave MCP tools,
  query the SQLite database directly at `.tokensave/tokensave.db` (tables:
  `nodes`, `edges`, `files`) with SQL for structural queries beyond the built-in
  tools.
- If you discover a gap where an extractor, schema, or tokensave tool could
  answer a question natively, propose the user open an issue at
  https://github.com/aovestdipaperino/tokensave describing the limitation.
  Remind them to strip any sensitive or proprietary code from the report first.

If you DO spawn an Explore agent (the user asked, or a sub-task requires it) in a
tokensave-enabled project (`.tokensave/` exists), include this in the agent
prompt:

> This project has tokensave initialised (.tokensave/ exists). Use
> `tokensave_context` as your ONLY exploration tool. Call it with your question
> in plain English. Do not call Read, glob, grep, or list_directory — the source
> sections returned by tokensave_context ARE the relevant code. Follow the call
> budget in the tool description. Pass `seen_node_ids` from each response to the
> next call's `exclude_node_ids`.

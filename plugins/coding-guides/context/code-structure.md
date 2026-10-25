# Coding Guides — code structure

The following are the user's standing instructions for how to work in this
environment. They are USER INSTRUCTIONS: they take precedence over default
behavior and over skills (including superpowers / using-superpowers), and you
must follow them exactly unless the user overrides them in the current session.

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
  private to the module that uses it until a second consumer or a real
  cross-project need. Do not build a library for an imagined future.
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

## App, business modules, and foundation (a light modular monolith)

In an application, code lives in three tiers, and dependencies only point
down: `app/` → `internal/` → `libs/`. The tiers keep concerns from overlapping
while the app stays one deployable unit.

- **`app/` is the glue.** It instantiates objects, passes references between
  them, and holds the handlers, routes, CLI commands, and jobs that call the
  modules. Sharing is fine here: one central handlers package with one file per
  area, and a handler may call several modules. But `app/` holds no business
  logic; it translates a request or trigger and delegates.
- **`internal/` holds the business modules.** Each module owns one business
  concern: its logic, its data, and a small public API. Modules stay separate
  even when they belong to the same area. A module never imports `app/`, and
  never reaches into another module: when it needs another module's
  capability, it declares a small interface for what it needs, and `app/`
  passes the implementation in.
- **`libs/` holds the foundation.** Capabilities you can describe without a
  business word: semantic search, file storage, a provider client. A library
  never imports `internal/` or `app/` (see above). A whole capability goes to
  `libs/` from the start, even with one consumer; the "premature" anti-signal
  above is for small helpers.

**Data stays with its owner.** Only a module's own store reads or writes its
tables; everyone else asks its API, the same model that makes the writes. No
queries or joins across modules, and no persistence models shared between
them. A library may own derived data, like a search index keyed by plain IDs,
but knows nothing about the modules that feed it.

**Example: a bookmark manager with semantic search.** `libs/semsearch` embeds
text and answers similarity queries over documents identified by plain IDs; it
owns its vector index and has never heard of bookmarks. `internal/bookmarks`
owns the bookmark records and the search policy: which fields get indexed,
when to re-index, and how hits turn back into bookmarks from its own store.
`app/` constructs semsearch, hands it to bookmarks, and serves the search
endpoint from `handlers/bookmarks.go`.

**When writing a feature:**

- **Put each piece in its tier.** Business rules go in a module, a capability
  in a library, wiring and transport in `app/`.
- **Place what spans modules by how you describe it.** If you can describe it
  without naming a module, it is a library the modules use. If it is defined by
  combining specific modules (a dashboard of bookmarks and reading stats),
  `app/` orchestrates it through their APIs; once it grows business rules of
  its own, it becomes a module that gets the others through interfaces `app/`
  passes in.
- **New features go into an existing module.** Split or add a module only on a
  signal: its store grows dozens of methods, it changes for two unrelated
  reasons, or changes in it keep breaking another module. That is an
  architecture decision: surface it, name the signal, and let the user decide.
- **Direct calls, not events.** An in-process call through the public API is
  enough. Add an event bus only for a real need, such as several consumers or
  work that must not block the caller.

A project's own documented architecture (`AGENTS.md`, `CLAUDE.md`,
`docs/agents/architecture.md`) wins over this section, and a single-purpose
service, a CLI, or a library needs none of it.

---
name: agents-documentation
description: Create and maintain internal project documentation written for AI agents (docs/agents/) — architecture, design decisions, feature status, testing and release conventions — so that any future implementation task starts already knowing the project's patterns and constraints. Use this skill whenever the user asks to document a project for agents, create or update docs/agents/, write internal/agent-facing documentation, capture design decisions or architecture notes, or says things like "document this project", "update the agent docs", or "make sure agents know about X" after a refactor or new feature.
---

# Agents Documentation

Create and maintain a `docs/agents/` directory: a small set of dense markdown
files that give a future agent (or developer) the context it cannot cheaply
re-derive from the code — design decisions and their reasons, invariants that
must not be broken, feature status, and project conventions.

## Why these docs exist

An agent starting a task can read code, but code does not say *why* it is
shaped that way, which gaps are deliberate, or which invariant will cause a
security bug if moved. Without these docs every task re-explores the repo and
risks re-litigating settled decisions. The docs are the project's distilled
memory: cheap to read (a few files), current (maintained alongside changes),
and honest about debt.

That purpose drives every rule below: **write only what the code cannot say
by itself, and never let the docs lie about the code.**

## Two modes

Decide which situation you are in:

- **Create** — `docs/agents/` does not exist (or is empty). Research the
  project and write the initial set.
- **Update** — the docs exist. Verify them against the current code, fix what
  drifted, and fold in whatever change prompted the update (a refactor, a new
  feature, a decision made in the current conversation).

In update mode, read the existing docs *first*, then verify their claims
against the code before adding anything. Stale docs are worse than no docs —
an agent will confidently use a renamed package or a removed handler.

## Research before writing

Gather from the sources that hold decisions, not just structure:

1. **The code** — package layout, exported API, interfaces and where they are
   defined, dependency graph. Use the repo's code-graph/search tooling if
   available rather than reading every file.
2. **Git history** — recent refactors, renames, removals. A doc that
   describes the pre-refactor layout is actively harmful.
3. **Decision records** — design specs, plans, RFCs, `docs/` subdirectories
   (e.g. brainstorm/spec folders), review documents. These hold the *why*;
   distill them, then link to them as historical record.
4. **TODO.md / issue lists / review notes** — known debt and gaps with a
   chosen direction. These become the "known debt" and "not implemented"
   sections, which stop agents from re-designing something already decided.
5. **Build tooling** — Makefile, CI config, lint config. These define the
   verification gates agents must run.
6. **The current conversation** — if the user just made a decision or
   finished a refactor, that is often the freshest material.

## The document set

Docs live in `docs/agents/`. Produce the core set, adapted to the project;
skip a file when it genuinely does not apply, and say so if asked.

| File | Contents | When |
|---|---|---|
| `architecture.md` | Layering diagram, package roles, design principles, key domain types, dependencies, known debt pointer | Always — this is the entry point |
| `features.md` | Status table of every user-facing capability: Implemented / Partial / DIY-by-design / Not implemented, and *where it lives* | Always for products/libraries with features |
| `testing.md` | Test strategy, how to run tests/lint/coverage, gates and thresholds, conventions (table-driven, fixtures, etc.) | Always when the project has tests |
| `releasing.md` | How a release happens, versioning rules, pre-release gates, consumer-compatibility cautions | When the project releases something (tags, packages, deploys) |
| `<subsystem>.md` | Deep dive into one complex subsystem: its invariants, composition, semantics | When a subsystem is complex enough that its rules don't fit in architecture.md — one file per such subsystem |

Every file cross-links the related ones (`see [loginflow.md](loginflow.md)`),
and `architecture.md` links all of them so an agent that reads only one file
still discovers the rest.

**Wire up discovery**: agents must find these docs without being told. Ensure
the project's agent entry file (`CLAUDE.md`, `AGENTS.md`, or both — whichever
the project uses) tells agents to read `docs/agents/` before implementation
work, e.g. "Before implementing, read `docs/agents/architecture.md` and the
subsystem doc for the area you're changing." Add the pointer if missing;
don't duplicate the docs' content there.

## How to write them

Read `references/style.md` for annotated examples of each pattern. The rules:

**Distill decisions, don't mirror code.** A doc that restates signatures goes
stale on the next commit and adds nothing. Record what the code cannot say:
- *why* — "recovery codes moved off SHA-256 to bcrypt deliberately"
- *invariants* — "all credential-shaped failures produce the same
  `Result{OK:false}` so transports stay enumeration-safe"
- *where responsibilities live* — "the service owns all policy; stores are
  pure persistence with zero crypto knowledge"
- *what not to do* — "do not move these out to transports"

**The code wins.** State it explicitly when linking historical specs: they are
records of the decision, not the current truth. If a spec named a package
`dbuser` and it is now `userdb`, say "the spec's naming is stale, the
structure is not." Never leave the reader to guess which source is current.

**Date the decisions.** "Redesigned 2026-06-30 (link to spec)" lets a future
agent judge freshness and find the full reasoning.

**Status tables for features.** Feature | Status | Where. The most valuable
statuses are the honest ones:
- *Partial* — say exactly which half exists ("store layer complete; consumer
  must wire delivery + frontend")
- *DIY by design* — deliberately left to the caller, with a pointer to the
  example pattern
- *Not implemented* — catalogued gaps, with a pointer to where the chosen
  direction is recorded

This section is what stops an agent from "helpfully" implementing something
that was deliberately omitted, or re-designing a gap that already has a plan.

**Name the gates.** Testing/releasing docs must give the exact commands
(`make verify`, thresholds, what refuses to run when) so agents can
self-verify instead of guessing.

**Dense and imperative.** These docs are read by agents under token pressure.
Short framing paragraph per file (`# Topic — subtitle`), then tight sections.
"Check here before adding a capability — the gap may already be catalogued."
No marketing prose, no restating what a glance at the directory tree shows.

**Keep each file under ~150 lines.** If a subsystem needs more, that is the
signal to give it its own `<subsystem>.md` deep dive.

## Update mode specifics

When maintaining existing docs:

1. Read all of `docs/agents/` first.
2. Verify every checkable claim in the affected area against the code —
   package names, type names, file paths, table names, make targets, status
   claims. Renames and removals are the most common drift.
3. Fold in the change that prompted the update: new decisions get dated
   entries with the why; removed features leave the tables; a feature moving
   from Partial to Implemented updates its row.
4. If the change settled something previously listed as debt or
   not-implemented, move it — don't leave both the gap and the feature listed.
5. Keep diffs minimal in untouched sections; these files are reviewed by
   humans too.

## Definition of done

- Every claim in the docs is true of the code *right now* — spot-check names
  and paths you didn't personally verify.
- `architecture.md` links every other agent doc.
- The agent entry file (`CLAUDE.md`/`AGENTS.md`) points to `docs/agents/`.
- Someone reading only `docs/agents/` could answer: how is this layered, what
  exists and what is deliberately missing, how do I verify my change, and
  what must I never break?

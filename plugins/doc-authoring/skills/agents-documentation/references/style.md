# Style reference — annotated examples

Patterns extracted from a real `docs/agents/` set (a Go auth library). Copy
the *shape*, not the content.

## File opener: one framing paragraph, then structure

```markdown
# Architecture — layering, interfaces, design decisions

`userauth` (module `github.com/go-bumbu/userauth`) is a Go **library** for user
authentication: pluggable user stores, multiple auth strategies, multi-factor
login, and session management. It is consumed by applications like Persona.
```

Why it works: one sentence says what the project *is* and who consumes it.
The `# Title — subtitle` form lets an agent scanning filenames + first lines
route itself.

## Layering diagram: ASCII, roles under the boxes

```markdown
## Layering

    loginflow/handlers   register/handlers (JSON)      auth/* (per-request auth)
            |                    |                            |
        loginflow (engine)   register (engine)     chain / cookieauth / basicauth
                          ...
    userauth.go  <- domain types + capability interfaces

- **`userauth.go` is the domain core**: `User`, all capability interfaces,
  sentinel errors. No HTTP.
- **`loginflow` is the only login engine.** The old fixed login handlers were
  removed in the `refactor-handler` branch; anything login-shaped goes through
  `loginflow.Flow` — see [loginflow.md](loginflow.md).
```

Why it works: the diagram gives shape; the bullets give the *rule* each box
enforces ("the only login engine", "No HTTP") — the constraints an agent must
not violate. Note the explicit "the old X was removed" — that pre-empts an
agent finding stale references elsewhere.

## Recording a decision: date it, link the spec, state who wins

```markdown
## Verification codes: service = policy, store = persistence

Redesigned 2026-06-30 (`../superpowers/specs/2026-06-30-verification-code-hybrid-design.md`):

- **`VerificationCodeService` owns all policy**: generation, SHA-256 hashing,
  expiry, defaults. Both hashing sites live in this one type, so the
  issue/verify hash agreement cannot drift.
- **`CodeStore` implementations are pure persistence with zero crypto
  knowledge**: `StoreCode(userID, hash, expiresAt)` + atomic `ConsumeCode`.
- `userdb`'s own `VerifyEmailCode` predates this design and does **not**
  satisfy `CodeVerifier` (phase 2 — a `CodeStore` adapter — has not landed).
```

Why it works: the heading *is* the decision ("service = policy, store =
persistence"). The date + spec link give provenance. The "cannot drift"
clause states the *why*. The last bullet is the honesty that matters most:
which part of the design has NOT landed yet.

When historical docs conflict with code, say so explicitly:

```markdown
Note: the spec named the package `dbuser`; it has since been renamed to
**`userdb`** — the spec's naming is stale, the structure is not.
```

## Invariants: imperative, with the failure mode

```markdown
It owns the security invariants callers tend to get wrong — do not move
these out to transports:

- the user must exist and be enabled **at every step**, not just the first;
- **all credential-shaped failures produce the same `Result{OK:false}`**
  (unknown user, disabled user, wrong code) so transports stay
  enumeration-safe without trying. A non-nil error means internal failure
  (5xx), never "try again".
```

Why it works: each invariant names the rule AND the consequence of breaking
it (enumeration leaks, security bugs). "Callers tend to get wrong" tells the
agent why the boundary is where it is.

## Feature status table: honest statuses with pointers

```markdown
| Feature | Status | Where |
|---|---|---|
| JSON API login | Implemented | `loginflow/handlers.JSON` — presets `NewPasswordTOTP` |
| Form-based login | DIY by design | caller-owned transport over `Flow.Submit`; pattern in `demo/examples/login/password.go` |
| Email 2FA | Partial | store layer complete; consumer must wire delivery + frontend |

## Not implemented (catalogued in TODO.md)

Rate limiting / lockout hooks, CSRF helpers, session listing/revocation, ...
```

Why it works: "DIY by design" + example pointer stops an agent from building
a form handler into the library. "Partial" names exactly which half exists.
The not-implemented list points at where each gap's chosen direction lives.

## Gates: exact commands, exact thresholds, non-negotiables

```markdown
| Target | What it runs |
|---|---|
| `make test` | `go test ./... -cover` — the fast suite |
| `make verify` | test + license-check + lint + benchmark + coverage — the full gate before calling work done |

- The coverage gate is on the **total** figure, threshold **80%**. If it
  falls below, write the missing tests — never lower the threshold.
- `nolint` directives must name the linter and carry an explanation. Fix the
  code instead of silencing the tool — a valid `//nolint` is rare.
```

Why it works: an agent can self-verify without asking. The two prose bullets
encode policy ("never lower the threshold") that a Makefile cannot express.

## Releasing: mechanics plus the trap

```markdown
    make tag version="v1.2.3"

`make tag` refuses unless you are on `main` with a clean working tree, then
runs the full `make verify` gate before creating and pushing the tag.

- **The `replace ../http` directive in go.mod** affects local development
  only — consumers resolve the published version. Make sure the required
  version is actually published before tagging.
```

Why it works: the command, what guards it, and the one project-specific trap
(a local `replace` directive) that would break consumers — exactly the thing
an agent cannot infer from a green build.

## Anti-patterns

- **API mirrors**: listing every exported function with its doc comment.
  Goes stale instantly; the code and `go doc` already do this.
- **Aspirational docs**: describing planned architecture as if it exists.
  Use the status table and dated decision entries instead.
- **Generic advice**: "write tests for new features" — noise. Only
  project-specific rules earn a line.
- **Duplicating CLAUDE.md/AGENTS.md**: those files point here; content lives
  here once.
- **Walls of MUSTs**: state the reason ("so transports stay enumeration-safe
  without trying") — agents follow rules better when the why travels with
  them.

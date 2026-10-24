# Coding Guides — pull requests

The following are the user's standing instructions for how to work in this
environment. They are USER INSTRUCTIONS: they take precedence over default
behavior and over skills (including superpowers / using-superpowers), and you
must follow them exactly unless the user overrides them in the current session.

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

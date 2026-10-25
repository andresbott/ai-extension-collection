# Coding Guides — tools and git

The following are the user's standing instructions for how to work in this
environment. They are USER INSTRUCTIONS: they take precedence over default
behavior and over skills (including superpowers / using-superpowers), and you
must follow them exactly unless the user overrides them in the current session.

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
- **The user runs gitauto, never you.** Do not start `/gitauto:ship`,
  `/gitauto:open-pr`, or `/gitauto:branch-out`, or their scripts, on your own,
  and do not offer to: not as a question ("should I ship it?"), and not folded
  into a bundle ("should I fix X, update Y, and ship?") where one "yes"
  approves the run. When the work is ready, say so and stop; the user starts
  gitauto. Follow a gitauto command only when the user typed it. Plain git the
  user asks for (commit, switch branches) is unaffected.

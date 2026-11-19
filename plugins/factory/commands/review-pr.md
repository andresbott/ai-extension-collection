---
description: Use when the user wants a GitHub pull request reviewed by several specialised reviewers, given by number or URL or as the pull request of the current branch, in a normal or an exhaustive low-noise review, with the review comments printed for them to check instead of posted.
disable-model-invocation: true
---

# Review a pull request

Review a GitHub pull request (PR) and print the result as one GitHub review: a
short summary body plus inline comments anchored to lines of the PR's diff.

This command is an entry point to the factory's review engine. First read
`${CLAUDE_PLUGIN_ROOT}/references/review-engine.md` and follow it for the
whole run. This file says which change to review and how to print it; it only
adds to the engine, never relaxes it.

**Never post anything.** Print the review; the user decides what to do with
it.

## What this entry point provides

- **Snapshot:** "Check out the PR" below.
- **Intent:** the PR title and body verbatim, under "The PR says:".
- **Print:** "Print the review" below.
- **Clean up:** "Clean up" below.
- **After:** nothing.

## Check out the PR

1. **Find the PR.** Use the number or URL the user gave. With none, use the
   PR of the current branch (`gh pr view --json number`); if there is none,
   say so and stop.
2. **Read it:** `gh pr view <n> --json
   number,title,body,url,state,baseRefName,baseRefOid,headRefOid,files`.
   A merged or closed PR is still reviewed; say its state in the header.
3. **Make the run folder:** `mktemp -d -t review-pr-XXXX`, with a `scratch/`
   folder inside.
4. **Fetch the head into a ref of its own,** never through `FETCH_HEAD`
   (other sessions share it): `git fetch origin
   +refs/pull/<n>/head:refs/review-pr/<run-folder-name>`. Check that the ref
   resolves to `headRefOid`. If it does not, the PR moved: re-read it and
   fetch again, once.
5. **Add the worktree:** `git worktree add --detach <run>/worktree <ref>`.
6. **Save the diff:** `gh pr diff <n> > <run>/changes.diff`. This is the diff
   GitHub shows, and the only lines an inline comment can be anchored to.

## Print the review

**Anchor first.** A finding becomes an inline comment only when its path is
in the PR's files and its line or range lies inside one hunk of
`changes.diff`: on the new side (`RIGHT`), or on the old side (`LEFT`) for a
removed line.

- About several places: anchor on the main one, name the others in the text.
- About a missing test: anchor on the changed code that is untested.
- Everything else (files or lines outside the diff, the PR title or
  description) goes in the summary body, under "Outside this diff".

Then print exactly this, and nothing else before it:

```
## Review of #<n>: <title>
<url> · <state> · head <short sha> · <normal|exhaustive>
Would post as: REQUEST_CHANGES | COMMENT

### Review body
<one sentence: the verdict>
- <up to four bullets: the points that matter most>

Outside this diff:
- <findings that could not be anchored; omit the block when empty>

### Inline comments (<count>)

1. `<path>:<line>` or `<path>:<start>-<end>` · <RIGHT|LEFT> · <severity>
   <the comment as posted, written by the engine's rules; at most four lines>
```

Use `REQUEST_CHANGES` when there is a blocker, otherwise `COMMENT`. End with
one line: "Not posted." plus how many findings were refuted or trimmed and,
in exhaustive mode, how many were dropped as one-off.

## Clean up

- `git worktree remove --force <run>/worktree`
- `git update-ref -d refs/review-pr/<run-folder-name>`
- `rm -rf <run>`
- `git worktree prune`

## Common mistakes

| Mistake | Fix |
| --- | --- |
| Inline comment on a file or line outside the PR's diff | GitHub rejects it: move it under "Outside this diff" |
| Reading the head through `FETCH_HEAD` | Fetch into `refs/review-pr/<run>` and check it against `headRefOid` |
| Long review body that repeats the inline comments | One verdict sentence and at most four bullets |

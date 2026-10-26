#!/usr/bin/env bash
# Tests for ship.sh with a local bare remote and a fake gh. Fixtures live in $TMPDIR.
set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ship.sh"
TESTDATA="$(dirname "$SCRIPT")/testdata"
roots=()
trap 'rm -rf "${roots[@]}"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }
unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN GIT_SSH_COMMAND GIT_SSH FAKE_SSH_LOGIN
# A global url.<x>.insteadOf would rewrite the fixture remotes.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

fixture() {
  root="$(mktemp -d)"; roots+=("$root")
  repo="$root/repo"; remote="$root/remote.git"; bin="$root/bin"; export FAKE_GH="$root/gh"
  mkdir -p "$bin" "$FAKE_GH"
  git init -q --bare -b main "$remote"
  git init -q -b main "$repo"
  git -C "$repo" config user.name "Gitauto Test"; git -C "$repo" config user.email gitauto@example.invalid
  printf 'base\n' > "$repo/README.md"; git -C "$repo" add README.md; git -C "$repo" commit -qm init
  git -C "$repo" remote add origin "$remote"; git -C "$repo" push -qu origin main 2>/dev/null
  git -C "$repo" remote set-head origin main
  cp "$TESTDATA/fake-gh" "$bin/gh"
  chmod +x "$bin/gh"
  export PATH="$bin:$PATH"
}
ship() { (cd "$repo" && "$SCRIPT" "$@") || true; }
on() { git -C "$repo" branch --show-current; }
# The result line for people, right above the final status line.
result() { tail -n 2 <<<"$1" | head -n 1; }

fixture
out="$(ship prepare '')"
[[ "$out" == $'success: nothing to ship on main\nDONE state=nothing branch=main report=nothing to ship' ]] || fail "nothing: $out"
pass "clean main has nothing to ship"

printf 'change\n' >> "$repo/README.md"
out="$(ship prepare 'tag=v1.0.0')"
grep -q '^SHIP branch=main protected=yes base=main pr=none dirty=1 .* need=pr writer=cheap$' <<<"$out" || fail "cheap: $out"
grep -q '^args: tag=v1.0.0$' <<<"$out" || fail "args: $out"
grep -q '^+change$' <<<"$out" || fail "patch missing: $out"
[[ "$(sed -n '/^--- write$/,/^--- status$/p' <<<"$out" | cut -d: -f1 | tr '\n' ' ')" == '--- write branch title subject body --- status ' ]] ||
  fail "cheap write block: $out"
[[ "$(on)" == main ]] || fail "prepare must not mutate"
pass "small change is rated cheap and shows a truncated patch"

out="$(cd "$repo" && GITAUTO_CMD_COMPLEX_LINES=0 "$SCRIPT" prepare '')"
grep -q 'need=pr writer=expert$' <<<"$out" || fail "expert: $out"
! grep -q -- '--- patch' <<<"$out" || fail "expert context should be minimal: $out"
[[ "$(sed -n '/^--- write$/,$p' <<<"$out" | cut -d: -f1 | tr '\n' ' ')" == '--- write branch ' ]] ||
  fail "expert on main only needs branch names: $out"
pass "large change is handed to the expert writer with no patch"

out="$(ship run --title 'feat: x')"
grep -q '^STOPPED stage=branch ' <<<"$out" || fail "branch required: $out"
[[ "$(on)" == main ]] || fail "should stay on main"
pass "run on main without branch candidates stops before any mutation"

out="$(ship run --branch 'bad..name' --title 'feat: x')"
grep -q '^STOPPED stage=branch state=failed report=no valid branch name candidate log=' <<<"$out" || fail "bad branch: $out"
[[ "$(result "$out")" == 'error: failed to create a feature branch: no valid branch name candidate' ]] || fail "bad branch result: $out"
[[ "$(on)" == main ]] || fail "should stay on main"
pass "a branch-out failure inside run stops with its reason"

out="$(ship draft --title 'feat: add change' --body-stdin <<<'## Summary
Because.')"
[[ "$out" == "DRAFTED title=feat: add change" ]] || fail "draft: $out"
out="$(ship run --branch feat/change)"
grep -q '^SHIPPED pr=#7 url=https://github.com/o/r/pull/7 sync=synced cleanup=clean ' <<<"$out" || fail "ship: $out"
[[ "$(result "$out")" == 'success: ship finished: PR #7 merged, main synced, branch cleaned up' ]] || fail "ship result: $out"
[[ "$(on)" == main ]] || fail "should be back on main, got $(on)"
[[ "$(git -C "$repo" log -1 --format=%s feat/change)" == "feat: add change" ]] || fail "commit message not taken from draft title"
grep -q 'Because.' "$FAKE_GH/body" || fail "draft body not used"
grep -q -- '--subject feat: add change (#7)' "$FAKE_GH/merge" || fail "merge subject: $(cat "$FAKE_GH/merge")"
git --git-dir="$remote" show-ref --verify --quiet refs/heads/feat/change || fail "branch not pushed"
pass "drafted PR ships end to end: branch, commit, push, PR, merge, sync, cleanup"

fixture
git -C "$repo" switch -qc feat/open
printf 'one\n' >> "$repo/README.md"
out="$(ship run --title 'fix: first' --body-stdin <<<'## Summary
First.')"
grep -q '^SHIPPED ' <<<"$out" || fail "first ship: $out"
git -C "$repo" switch -q feat/open
rm "$FAKE_GH/state"
printf 'two\n' >> "$repo/README.md"
out="$(ship prepare '')"
grep -q 'pr=open#7_fix:_first .* need=message writer=cheap$' <<<"$out" || fail "open pr: $out"
[[ "$(sed -n '/^--- write$/,/^--- status$/p' <<<"$out" | cut -d: -f1 | tr '\n' ' ')" == '--- write message --- status ' ]] ||
  fail "open pr write block: $out"
pass "an open PR only needs a commit message"

printf 'MERGED' > "$FAKE_GH/state"
out="$(ship prepare '')"
grep -q '^DONE state=failed report=pull request merged#7 is already merged' <<<"$out" || fail "merged dirty: $out"
git -C "$repo" commit -qam 'fix: after merge'
out="$(ship run)"
grep -q '^STOPPED stage=open-pr state=blocked report=pull request #7 is already merged without the current HEAD' <<<"$out" || fail "merged ahead: $out"
[[ "$(on)" == feat/open ]] || fail "must not sync away from unmerged work"
pass "new work on a merged PR's branch is never skipped"

fixture
git -C "$repo" switch -qc feat/broken
printf 'verify:\n\t@echo boom-from-verify; exit 1\n' > "$repo/Makefile"
out="$(ship run --title 'feat: broken' --body-stdin <<<'body')"
grep -q '^STOPPED stage=verify state=fail ' <<<"$out" || fail "verify: $out"
grep -q '^--- failure: verify' <<<"$out" || fail "verify failure block missing: $out"
grep -q '^boom-from-verify$' <<<"$out" || fail "verify output not returned: $out"
grep -q '^ship: \[1\] verify -> fail$' <<<"$out" || fail "progress missing: $out"
[[ "$(tail -n 1 <<<"$out")" == STOPPED* ]] || fail "final line must be last: $out"
[[ "$(result "$out")" == 'error: failed to verify the changes: make verify failed' ]] || fail "verify result: $out"
[[ -n "$(git -C "$repo" status --porcelain)" ]] || fail "nothing should be committed"
[[ ! -f "$FAKE_GH/head" ]] || fail "no PR should be opened"
pass "failed verification stops before commit and returns its output"

fixture
git -C "$repo" switch -qc feat/red
printf 'red\n' >> "$repo/README.md"
touch "$FAKE_GH/cifail"
out="$(ship run --title 'feat: red' --body-stdin <<<'body')"
grep -q '^STOPPED stage=wait-ci state=failed .* url=https://github.com/o/r/pull/7 ' <<<"$out" || fail "ci: $out"
grep -q '^failed check: build$' <<<"$out" || fail "check name missing: $out"
grep -q '^--- FAIL: TestThing$' <<<"$out" || fail "failed log missing or not stripped: $out"
[[ "$(result "$out")" == 'error: failed to get CI green: one or more CI checks failed' ]] || fail "ci result: $out"
[[ ! -f "$FAKE_GH/merge" ]] || fail "must not merge on red CI"
[[ "$(on)" == feat/red ]] || fail "must stay on the branch to fix it"
pass "red CI stops before merge and returns failed checks and logs"

fixture
git -C "$repo" switch -qc feat/offline
printf 'offline\n' >> "$repo/README.md"
touch "$FAKE_GH/cidown"
out="$(GITAUTO_CHECKS_RETRIES=0 ship run --title 'feat: offline' --body-stdin <<<'body')"
grep -q '^STOPPED stage=wait-ci state=error report=could not read CI status (.*connection reset by peer); re-run to resume ' <<<"$out" ||
  fail "gh error: $out"
! grep -q -- '^--- failure' <<<"$out" || fail "a gh error is not a CI failure: $out"
[[ ! -f "$FAKE_GH/merge" ]] || fail "must not merge when CI cannot be read"
pass "a gh error during the CI wait stops as an error, not as red CI"

fixture
git -C "$repo" switch -qc feat/slow
printf 'verify:\n\t@echo run >> $(MARK)\n' > "$repo/Makefile"
export MARK="$root/verify-runs"
touch "$FAKE_GH/cislow"
out="$(cd "$repo" && GITAUTO_CMD_RUN_BUDGET=1 GITAUTO_CMD_CI_MIN=1 "$SCRIPT" run --title 'feat: slow' --body-stdin <<<'body' || true)"
grep -q '^WAITING stage=wait-ci pr=#7 ' <<<"$out" || fail "waiting: $out"
[[ "$(result "$out")" == 'warning: CI is still running on PR #7; run /gitauto:ship again to resume' ]] || fail "waiting result: $out"
[[ ! -f "$FAKE_GH/merge" ]] || fail "must not merge while CI runs"
rm "$FAKE_GH/cislow"
out="$(ship run)"
grep -q '^ship: \[1\] verify -> skip$' <<<"$out" || fail "resume should skip verify: $out"
grep -q '^SHIPPED pr=#7 ' <<<"$out" || fail "resume: $out"
grep -q -- '--subject feat: slow (#7)' "$FAKE_GH/merge" || fail "resume merge subject: $(cat "$FAKE_GH/merge")"
[[ "$(wc -l < "$MARK")" -eq 1 ]] || fail "verify ran $(wc -l < "$MARK") times"
pass "slow CI hands back WAITING and a bare re-run resumes without re-verifying"

fixture
git -C "$repo" switch -qc feat/late
printf 'late\n' >> "$repo/README.md"
touch "$FAKE_GH/cilate"
out="$(ship run --title 'feat: late check' --body-stdin <<<'body')"
grep -q '^SHIPPED pr=#7 ' <<<"$out" || fail "late check: $out"
[[ "$(grep -c '^ship: \[[0-9]*\] wait-ci -> green$' <<<"$out")" -eq 2 ]] || fail "late check should wait for CI twice: $out"
grep -q '^ship: \[[0-9]*\] merge -> pending$' <<<"$out" || fail "merge should first see the late check pending: $out"
pass "a check that registers after the CI wait is waited for before merging"

tag_fixture() {
  fixture
  printf 'tag:\n\t@echo $(VERSION) > %s/tagged\n' "$root" > "$repo/Makefile"
  git -C "$repo" add Makefile; git -C "$repo" commit -qm 'add tag target'
  git -C "$repo" push -q origin main 2>/dev/null
  git -C "$repo" tag v1.0.0
  git -C "$repo" switch -qc feat/tagme
  printf 'tag me\n' >> "$repo/README.md"
}

tag_fixture
out="$(ship run --title 'feat: taggable' --body-stdin <<<'body')"
grep -q '^SHIPPED .* tag=ask tag_recommended=v1.1.0 tag_options=v1.1.0,v1.0.1,v2.0.0 latest=v1.0.0 ' <<<"$out" || fail "tag ask: $out"
[[ ! -f "$root/tagged" ]] || fail "ship must never tag by default"
pass "ship recommends a tag but never creates one by default"

out="$(ship tag v1.1.0)"
grep -q '^TAGGED version=v1.1.0 latest=v1.0.0 ' <<<"$out" || fail "tag: $out"
[[ "$(result "$out")" == 'success: tagged v1.1.0' ]] || fail "tag result: $out"
[[ "$(cat "$root/tagged")" == v1.1.0 ]] || fail "make tag did not run with the chosen version"
pass "an explicitly chosen version is tagged via make tag"

tag_fixture
out="$(ship run --no-tag --title 'feat: untagged' --body-stdin <<<'body')"
grep -q '^SHIPPED .* tag=declined ' <<<"$out" || fail "no-tag: $out"
pass "--no-tag skips the tag question"

tag_fixture
out="$(ship run --tag v0.9.0 --title 'feat: low tag' --body-stdin <<<'body')"
grep -q '^PARTIAL .* tag=failed tag_report=version must be greater than the latest tag ' <<<"$out" || fail "partial: $out"
[[ "$(result "$out")" == 'warning: PR #7 merged, main synced, but tag v0.9.0 failed: version must be greater than the latest tag' ]] ||
  fail "partial result: $out"
pass "a tag that fails after the merge is a PARTIAL with a warning"

fixture
git -C "$repo" switch -qc feat/notarget
printf 'x\n' >> "$repo/README.md"
out="$(ship run --title 'fix: no target' --body-stdin <<<'body')"
grep -q '^SHIPPED .* tag=none ' <<<"$out" || fail "no target: $out"
pass "repos without a make tag target are never asked"

fixture
git -C "$repo" switch -qc feat/review
printf 'review me\n' >> "$repo/README.md"
out="$(ship open-pr --title 'feat: review me' --body-stdin <<<'body')"
grep -q '^READY pr=#7 url=https://github.com/o/r/pull/7 ci=green ' <<<"$out" || fail "open-pr: $out"
[[ "$(result "$out")" == 'success: PR #7 is ready: CI is green; run /gitauto:ship to merge' ]] || fail "open-pr result: $out"
[[ ! -f "$FAKE_GH/merge" ]] || fail "open-pr must not merge"
[[ "$(on)" == feat/review ]] || fail "open-pr must stay on the branch"
out="$(ship prepare '')"
grep -q 'pr=open#7_feat:_review_me .* need=none ' <<<"$out" || fail "after open-pr: $out"
! grep -q -- '^--- write$' <<<"$out" || fail "nothing to write should print no write block: $out"
out="$(ship run)"
grep -q '^SHIPPED pr=#7 ' <<<"$out" || fail "ship after open-pr: $out"
grep -q -- '--subject feat: review me (#7)' "$FAKE_GH/merge" || fail "subject from PR title: $(cat "$FAKE_GH/merge")"
pass "open-pr stops at green CI; ship later merges the reused PR"

fixture
git -C "$repo" switch -qc feat/prose
printf 'prose\n' >> "$repo/README.md"
out="$(ship run --title 'Add a prose title' --subject 'feat(readme): add prose' --body-stdin <<<'## Summary
Why.')"
grep -q '^SHIPPED pr=#7 ' <<<"$out" || fail "prose ship: $out"
[[ "$(cat "$FAKE_GH/title")" == 'Add a prose title' ]] || fail "PR title should stay prose"
grep -qx '<!-- gitauto-subject: feat(readme): add prose -->' "$FAKE_GH/body" || fail "subject not saved in body: $(cat "$FAKE_GH/body")"
grep -q -- '--subject feat(readme): add prose (#7)' "$FAKE_GH/merge" || fail "merge subject: $(cat "$FAKE_GH/merge")"
[[ "$(git -C "$repo" log -1 --format=%s feat/prose)" == 'feat(readme): add prose' ]] || fail "commit message should be the subject"
pass "a prose title ships with a separate Conventional subject"

fixture
git -C "$repo" switch -qc feat/prose-later
printf 'later\n' >> "$repo/README.md"
out="$(ship open-pr --title 'Review this first' --subject 'fix: review first' --body-stdin <<<'body')"
grep -q '^READY ' <<<"$out" || fail "prose open-pr: $out"
out="$(ship prepare '')"
grep -q 'need=none ' <<<"$out" || fail "saved subject should need no model: $out"
out="$(ship run)"
grep -q -- '--subject fix: review first (#7)' "$FAKE_GH/merge" || fail "saved subject not used: $(cat "$FAKE_GH/merge")"
pass "a later ship merges with the subject saved in the PR body"

fixture
git -C "$repo" switch -qc feat/by-hand
printf 'hand\n' >> "$repo/README.md"
git -C "$repo" commit -qam 'wip'
git -C "$repo" push -qu origin feat/by-hand 2>/dev/null
printf 'feat/by-hand' > "$FAKE_GH/head"; printf 'Opened by hand' > "$FAKE_GH/title"; printf 'no marker' > "$FAKE_GH/body"
git -C "$repo" rev-parse HEAD > "$FAKE_GH/oid"
out="$(ship prepare '')"
grep -q 'need=subject ' <<<"$out" || fail "hand PR should need a subject: $out"
grep -q '^pr_title: Opened by hand$' <<<"$out" || fail "pr_title missing: $out"
grep -q '^subject: .*Reshape the pr_title line into it\.$' <<<"$out" || fail "subject rule missing: $out"
out="$(ship run)"
grep -q '^STOPPED stage=merge state=needs-subject ' <<<"$out" || fail "missing subject: $out"
! grep -q 'wait-ci' <<<"$out" || fail "should stop before waiting on CI: $out"
[[ ! -f "$FAKE_GH/merge" ]] || fail "must not merge without a subject"
out="$(ship run --subject 'feat: opened by hand')"
grep -q -- '--subject feat: opened by hand (#7)' "$FAKE_GH/merge" || fail "fallback subject: $(cat "$FAKE_GH/merge")"
pass "a hand-opened prose PR asks for a subject once, then merges"

fixture
git -C "$repo" switch -qc feat/bad
printf 'bad\n' >> "$repo/README.md"
out="$(ship run --title 'Fine title' --subject 'not conventional' --body-stdin <<<'body')"
grep -q '^DONE state=failed report=--subject must be' <<<"$out" || fail "bad subject: $out"
[[ "$(result "$out")" == 'error: --subject must be a one-line Conventional Commit subject' ]] || fail "bad subject result: $out"
[[ -n "$(git -C "$repo" status --porcelain)" ]] || fail "nothing should be committed"
pass "an invalid subject fails before any mutation"

# Several gh accounts on github.com. The fetch URL is GitHub's, so the account
# check runs; pushes still go to the local bare remote.
github_fixture() {
  fixture
  cp "$TESTDATA/fake-ssh" "$bin/ssh"; chmod +x "$bin/ssh"
  git -C "$repo" remote set-url origin git@github.com:o/r.git
  git -C "$repo" remote set-url --push origin "$remote"
  printf 'a b' > "$FAKE_GH/logins"; printf 'a b' > "$FAKE_GH/push"
}
github_fixture
git -C "$repo" switch -qc feat/account
printf 'account\n' >> "$repo/README.md"
out="$(ship prepare '')"
[[ "$out" == 'NEED_ACCOUNT host=github.com repo=o/r accounts=a,b report=several gh accounts can push to o/r; choose one' ]] ||
  fail "ask: $out"
! grep -q '^pr view' "$FAKE_GH/log" || fail "the account question must come before the PR lookup"
out="$(ship account c)"
[[ "$out" == $'error: c is not logged in to gh on github.com (logged in: a,b)\nDONE state=failed report=c is not logged in to gh on github.com (logged in: a,b)' ]] ||
  fail "unknown pick: $out"
out="$(ship account b)"
[[ "$out" == $'success: saved b as the gh account for o/r\nDONE state=saved account=b host=github.com repo=o/r report=b chosen for o/r' ]] ||
  fail "pick: $out"
out="$(ship prepare '')"
grep -q '^SHIP branch=feat/account .* need=pr writer=cheap$' <<<"$out" || fail "prepare after the pick: $out"
grep -q $'^tok-b\tpr view feat/account ' "$FAKE_GH/tokens" || fail "PR lookup without b's token: $(cat "$FAKE_GH/tokens")"
out="$(ship open-pr --title 'feat: account' --body-stdin <<<'body')"
grep -q '^READY pr=#7 ' <<<"$out" || fail "open-pr as b: $out"
grep -q $'^tok-b\tpr create ' "$FAKE_GH/tokens" || fail "PR created without b's token: $(cat "$FAKE_GH/tokens")"
pass "with several gh accounts, prepare asks first and every gh call uses the picked one"

rm "$repo/.git/gitauto.json"
out="$(ship run)"
grep -q '^STOPPED stage=account state=ask report=several gh accounts can push to o/r (a,b); run ship.sh prepare to choose one ' <<<"$out" ||
  fail "run without a pick: $out"
out="$(FAKE_SSH_LOGIN=a ship prepare '')"
grep -q '^SHIP ' <<<"$out" || fail "the SSH key should decide: $out"
[[ "$(jq -r .account "$repo/.git/gitauto.json")" == a ]] || fail "the SSH pick was not saved"
pass "run never asks; the SSH key's account is picked without a question"

fixture
git -C "$repo" switch -qc feat/hidden
printf 'hidden\n' >> "$repo/README.md"
touch "$FAKE_GH/prerror"
out="$(ship prepare '')"
[[ "$out" == "error: pull request lookup failed: GraphQL: Could not resolve to a Repository with the name 'o/r'. (repository)"$'\n'"DONE state=failed report=pull request lookup failed: GraphQL: Could not resolve to a Repository with the name 'o/r'. (repository)" ]] ||
  fail "lookup error: $out"
pass "a PR lookup error stops prepare with gh's message instead of reading as no PR"

fixture
git -C "$repo" switch -qc feat/refused
printf 'refused\n' >> "$repo/README.md"
touch "$FAKE_GH/prcreate-error"
out="$(ship run --title 'feat: refused' --body-stdin <<<'body')"
emu='GraphQL: Unauthorized: As an Enterprise Managed User, you cannot access this content (createPullRequest)'
grep -qF "STOPPED stage=open-pr state=failed report=pull request creation failed: $emu log=" <<<"$out" || fail "refused: $out"
[[ "$(result "$out")" == "error: failed to open the pull request: pull request creation failed: $emu" ]] || fail "refused result: $out"
pass "a refused PR creation stops with gh's error"

# A helper that dies under set -e prints no report; its last logged error stands in.
fixture
git -C "$repo" switch -qc feat/rejected
printf 'rejected\n' >> "$repo/README.md"
printf '#!/bin/sh\necho "rejected by policy" >&2\nexit 1\n' > "$remote/hooks/pre-receive"; chmod +x "$remote/hooks/pre-receive"
out="$(ship run --title 'feat: rejected' --body-stdin <<<'body')"
grep -qF "STOPPED stage=push state=error report=failed to push some refs to '$remote' log=" <<<"$out" || fail "rejected push: $out"
[[ "$(result "$out")" == "error: failed to push the branch: failed to push some refs to '$remote'" ]] || fail "rejected result: $out"
pass "a helper that dies without a report stops with the last error it logged"

fixture
cp "$TESTDATA/fake-ssh" "$bin/ssh"; chmod +x "$bin/ssh"
git -C "$repo" remote set-url origin git@work-alias:o/r.git
printf 'github.com' > "$FAKE_GH/auth-only"
out="$(ship prepare '')"
[[ "$(tail -n 1 <<<"$out")" == "DONE state=nothing branch=main report=nothing to ship" ]] || fail "broken login elsewhere blocked prepare: $out"
printf 'git.corp.example' > "$FAKE_GH/auth-only"
out="$(ship prepare '')"
[[ "$out" == $'error: GitHub CLI is unavailable or unauthenticated\nDONE state=failed report=GitHub CLI is unavailable or unauthenticated' ]] ||
  fail "origin host without a login passed: $out"
pass "prepare checks gh auth for the origin host only"

# prepare cuts the patch at GITAUTO_CMD_PATCH_LINES on purpose, and pipefail
# must not turn the resulting SIGPIPE into a failed prepare: the command's ! line
# aborts on any non-zero exit. The patch block's status is that of its last
# writer, the untracked-file loop, so the failure needs a new file printed after
# `head` is gone. A tracked diff far past the pipe buffer (>64 KB) guarantees
# `head` has exited before the loop runs, so the SIGPIPE is certain, not
# timing-dependent. The exit code is checked directly, since ship() swallows it.
fixture
awk 'BEGIN { for (i = 0; i < 4000; i++) printf "line %04d %s\n", i, "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" }' > "$repo/README.md"
printf 'new\n' > "$repo/new.txt"
rc=0
out="$(cd "$repo" && GITAUTO_CMD_PATCH_LINES=1 GITAUTO_CMD_COMPLEX_LINES=100000 "$SCRIPT" prepare '')" || rc=$?
[[ "$rc" -eq 0 ]] || fail "truncated patch made prepare exit $rc"
grep -q '^SHIP branch=main .* need=pr writer=cheap$' <<<"$out" || fail "truncated prepare context: $out"
[[ "$(sed -n '/^--- patch (truncated)$/,$p' <<<"$out")" == $'--- patch (truncated)\ndiff --git a/README.md b/README.md' ]] ||
  fail "patch should stop after 1 line: $out"
pass "a patch past GITAUTO_CMD_PATCH_LINES is truncated without failing prepare"

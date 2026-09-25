#!/usr/bin/env bash
# Tests for ship.sh with a local bare remote and a fake gh. Fixtures live in $TMPDIR.
set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ship.sh"
TESTDATA="$(dirname "$SCRIPT")/testdata"
roots=()
trap 'rm -rf "${roots[@]}"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

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

fixture
out="$(ship prepare '')"
[[ "$out" == "DONE state=nothing branch=main report=nothing to ship" ]] || fail "nothing: $out"
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

out="$(ship draft --title 'feat: add change' --body-stdin <<<'## Summary
Because.')"
[[ "$out" == "DRAFTED title=feat: add change" ]] || fail "draft: $out"
out="$(ship run --branch feat/change)"
grep -q '^SHIPPED pr=#7 url=https://github.com/o/r/pull/7 sync=synced cleanup=clean ' <<<"$out" || fail "ship: $out"
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
[[ ! -f "$FAKE_GH/merge" ]] || fail "must not merge on red CI"
[[ "$(on)" == feat/red ]] || fail "must stay on the branch to fix it"
pass "red CI stops before merge and returns failed checks and logs"

fixture
git -C "$repo" switch -qc feat/slow
printf 'verify:\n\t@echo run >> $(MARK)\n' > "$repo/Makefile"
export MARK="$root/verify-runs"
touch "$FAKE_GH/cislow"
out="$(cd "$repo" && GITAUTO_CMD_RUN_BUDGET=1 GITAUTO_CMD_CI_MIN=1 "$SCRIPT" run --title 'feat: slow' --body-stdin <<<'body' || true)"
grep -q '^WAITING stage=wait-ci pr=#7 ' <<<"$out" || fail "waiting: $out"
[[ ! -f "$FAKE_GH/merge" ]] || fail "must not merge while CI runs"
rm "$FAKE_GH/cislow"
out="$(ship run)"
grep -q '^ship: \[1\] verify -> skip$' <<<"$out" || fail "resume should skip verify: $out"
grep -q '^SHIPPED pr=#7 ' <<<"$out" || fail "resume: $out"
grep -q -- '--subject feat: slow (#7)' "$FAKE_GH/merge" || fail "resume merge subject: $(cat "$FAKE_GH/merge")"
[[ "$(wc -l < "$MARK")" -eq 1 ]] || fail "verify ran $(wc -l < "$MARK") times"
pass "slow CI hands back WAITING and a bare re-run resumes without re-verifying"

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
[[ "$(cat "$root/tagged")" == v1.1.0 ]] || fail "make tag did not run with the chosen version"
pass "an explicitly chosen version is tagged via make tag"

tag_fixture
out="$(ship run --no-tag --title 'feat: untagged' --body-stdin <<<'body')"
grep -q '^SHIPPED .* tag=declined ' <<<"$out" || fail "no-tag: $out"
pass "--no-tag skips the tag question"

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
[[ -n "$(git -C "$repo" status --porcelain)" ]] || fail "nothing should be committed"
pass "an invalid subject fails before any mutation"

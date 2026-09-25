#!/usr/bin/env bash
# Tests for ship.sh with a local bare remote and a fake gh. Fixtures live in $TMPDIR.
set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ship.sh"
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
  cat > "$bin/gh" <<'GH'
#!/usr/bin/env bash
s="$FAKE_GH"; printf '%s\n' "$*" >> "$s/log"
json=''; prev=''; for a in "$@"; do [[ "$prev" == --json ]] && json="$a"; prev="$a"; done
case "${1:-} ${2:-}" in
  'auth status') exit 0 ;;
  'repo view') exit 1 ;;
  'pr create')
    while [[ $# -gt 0 ]]; do case "$1" in --head) printf '%s' "$2" > "$s/head" ;; --title) printf '%s' "$2" > "$s/title" ;; --body) printf '%s' "$2" > "$s/body" ;; esac; shift; done
    git rev-parse HEAD > "$s/oid"
    printf 'https://github.com/o/r/pull/7\n' ;;
  'pr view')
    [[ -f "$s/head" ]] || { printf 'no pull requests found for branch\n' >&2; exit 1; }
    state="$(cat "$s/state" 2>/dev/null || echo OPEN)"
    case "$json" in
      number,state,url) printf '7\t%s\thttps://github.com/o/r/pull/7\n' "$state" ;;
      number,state,headRefName) printf '7\t%s\t%s\n' "$state" "$(cat "$s/head")" ;;
      number,state,title) printf '%s#7 %s\n' "${state,,}" "$(cat "$s/title")" ;;
      number) printf '7\n' ;;
      title) cat "$s/title"; printf '\n' ;;
      headRefOid) cat "$s/oid" ;;
    esac ;;
  'pr checks')
    if [[ -f "$s/cifail" ]]; then
      if [[ -n "$json" ]]; then printf 'build\thttps://github.com/o/r/actions/runs/99/job/1\n'; exit 0; fi
      printf 'build\tfail\n'; exit 1
    fi
    printf 'all checks passed\n' ;;
  'run view') printf 'build\tTest\t2026-01-02T03:04:05.1234567Z --- FAIL: TestThing\nbuild\tTest\t2026-01-02T03:04:05.2Z expected 1, got 2\n' ;;
  'pr merge') printf '%s\n' "$*" > "$s/merge"; printf 'MERGED' > "$s/state" ;;
  *) printf 'fake gh: unsupported %s\n' "$*" >&2; exit 9 ;;
esac
GH
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
[[ "$(on)" == main ]] || fail "prepare must not mutate"
pass "small change is rated cheap and shows a truncated patch"

out="$(cd "$repo" && GITAUTO_CMD_COMPLEX_LINES=0 "$SCRIPT" prepare '')"
grep -q 'need=pr writer=expert$' <<<"$out" || fail "expert: $out"
! grep -q -- '--- patch' <<<"$out" || fail "expert context should be minimal: $out"
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

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAIT_SCRIPT="$SCRIPT_DIR/gitauto-wait-ci.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
root="$(mktemp -d)"; trap 'rm -rf "$root"' EXIT
repo="$root/repo"; bin="$root/bin"; log="$root/gh.log"
mkdir -p "$repo" "$bin"
git -C "$repo" init -q -b feat/ci
git -C "$repo" config user.name "Gitauto Test"
git -C "$repo" config user.email "gitauto@example.invalid"
printf 'base\n' > "$repo/README.md"; git -C "$repo" add README.md; git -C "$repo" commit -qm init
cat > "$bin/gh" <<'GH'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "$GH_LOG"
case "${1:-} ${2:-}" in
  'pr view')
    [[ "${GH_SCENARIO:-}" != unresolved ]] || exit 1
    printf '42\n'
    ;;
  'pr checks')
    reset='Post "https://api.github.com/graphql": read tcp: connection reset by peer'
    if [[ "$*" == *--json* ]]; then
      case "${GH_SCENARIO:-}" in
        failed) printf 'pass\nfail\n' ;;
        drop) printf 'pass\npending\n' ;;
        dropdone) printf 'pass\nskipping\n' ;;
        down) printf '%s\n' "$reset" >&2; exit 1 ;;
      esac
      exit 0
    fi
    case "${GH_SCENARIO:-green}" in
      green) printf 'checks passed\n'; exit 0 ;;
      failed) printf 'unit test failed\n' >&2; exit 1 ;;
      # The connection drops during the first watch, while a check is still running.
      drop)
        (( $(grep -c -- '--watch' "$GH_LOG") >= 2 )) || { printf '%s\n' "$reset" >&2; exit 1; }
        printf 'checks passed\n' ;;
      dropdone|down) printf '%s\n' "$reset" >&2; exit 1 ;;
      none) printf 'no checks reported on the branch\n' >&2; exit 1 ;;
      pending) printf 'checks still pending\n' >&2; exit 8 ;;
      # Checks register only on the third ask, like a pull_request workflow on a new PR.
      late)
        (( $(grep -c '^pr checks' "$GH_LOG") >= 3 )) || { printf 'no checks reported on the branch\n' >&2; exit 1; }
        printf 'checks passed\n' ;;
    esac
    ;;
  *) printf 'unexpected gh command: %s\n' "$*" >&2; exit 9 ;;
esac
GH
chmod +x "$bin/gh"

: > "$log"
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_SCENARIO=green GITAUTO_CHECKS_INTERVAL=1 "$WAIT_SCRIPT" 'pr=42') 2>&1)" || fail "green checks failed: $output"
[[ "$output" == *'state=green'* && "$output" == *'number=42'* ]] || fail "green state missing: $output"
grep -q '^pr checks 42 --watch --interval 1$' "$log" || fail "checks command mismatch"
! grep -q 'pr merge' "$log" || fail "wait-ci attempted a merge"
printf 'PASS: green checks are reported without merging\n'

: > "$log"
set +e
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_SCENARIO=failed "$WAIT_SCRIPT" '42') 2>&1)"
status=$?
set -e
[[ $status -ne 0 && "$output" == *'state=failed'* ]] || fail "failed checks were not preserved: status=$status output=$output"
! grep -q 'pr merge' "$log" || fail "failed CI attempted a merge"
[[ "$(grep -c -- '--watch' "$log")" -eq 1 ]] || fail "failed checks were watched again"
grep -q '^pr checks 42 --json bucket' "$log" || fail "failed checks were not confirmed"
printf 'PASS: failed checks return failure without merging\n'

: > "$log"
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_SCENARIO=drop GITAUTO_CHECKS_RETRY_INTERVAL=0 "$WAIT_SCRIPT" '42') 2>&1)" || fail "dropped watch failed: $output"
[[ "$output" == *'state=green'* ]] || fail "a dropped watch with checks still running was not resumed: $output"
[[ "$(grep -c -- '--watch' "$log")" -eq 2 ]] || fail "dropped watch: expected 2 watches, got $(grep -c -- '--watch' "$log")"
printf 'PASS: a watch that loses GitHub while checks run is resumed\n'

: > "$log"
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_SCENARIO=dropdone "$WAIT_SCRIPT" '42') 2>&1)" || fail "dropped finished watch failed: $output"
[[ "$output" == *'state=green'* ]] || fail "finished checks behind a dropped watch were not green: $output"
[[ "$(grep -c -- '--watch' "$log")" -eq 1 ]] || fail "finished checks were watched again"
printf 'PASS: a watch that loses GitHub after checks pass is green\n'

: > "$log"
set +e
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_SCENARIO=down GITAUTO_CHECKS_RETRIES=2 GITAUTO_CHECKS_RETRY_INTERVAL=0 "$WAIT_SCRIPT" '42') 2>&1)"
status=$?
set -e
[[ $status -ne 0 && "$output" == *'state=error'* && "$output" != *'state=failed'* ]] || fail "unreachable GitHub was not an error: status=$status output=$output"
[[ "$output" == *'report=could not read CI status (Post '*'connection reset by peer); re-run to resume'* ]] || fail "gh error not reported: $output"
[[ "$(grep -c -- '--watch' "$log")" -eq 3 ]] || fail "unreachable GitHub: expected 3 watches, got $(grep -c -- '--watch' "$log")"
printf 'PASS: gh errors are retried, then reported as an error rather than failed CI\n'

: > "$log"
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_SCENARIO=none GITAUTO_CHECKS_GRACE=2 GITAUTO_CHECKS_GRACE_INTERVAL=1 "$WAIT_SCRIPT" '42') 2>&1)" || fail "no-checks case should return safely: $output"
[[ "$output" == *'state=none'* ]] || fail "no-checks state missing: $output"
[[ "$(grep -c '^pr checks' "$log")" -ge 2 ]] || fail "no checks were not asked for again within the grace period"
printf 'PASS: absent checks are distinguished from failure after a grace period\n'

: > "$log"
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_SCENARIO=late GITAUTO_CHECKS_GRACE_INTERVAL=0 "$WAIT_SCRIPT" '42') 2>&1)" || fail "late checks failed: $output"
[[ "$output" == *'state=green'* ]] || fail "checks that registered late were missed: $output"
[[ "$(grep -c '^pr checks' "$log")" -eq 3 ]] || fail "late checks: expected 3 asks, got $(grep -c '^pr checks' "$log")"
printf 'PASS: checks that register after the PR opens are waited for\n'

: > "$log"
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_SCENARIO=pending "$WAIT_SCRIPT" '42') 2>&1)" || fail "pending checks should return a blocking state: $output"
[[ "$output" == *'state=pending'* ]] || fail "pending checks were not preserved: $output"
printf 'PASS: pending checks are not classified as absent\n'

: > "$log"
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_SCENARIO=unresolved "$WAIT_SCRIPT") 2>&1)" || fail "unresolved PR should return safely: $output"
[[ "$output" == *'state=blocked'* ]] || fail "unresolved PR was not blocked: $output"
! grep -q '^pr checks' "$log" || fail "checks ran without a PR"
printf 'PASS: unresolved PR is blocked\n'

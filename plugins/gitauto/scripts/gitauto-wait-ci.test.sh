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
    case "${GH_SCENARIO:-green}" in
      green) printf 'checks passed\n'; exit 0 ;;
      failed) printf 'unit test failed\n' >&2; exit 1 ;;
      none) printf 'no checks reported on the branch\n' >&2; exit 1 ;;
      pending) printf 'checks still pending\n' >&2; exit 8 ;;
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
printf 'PASS: failed checks return failure without merging\n'

: > "$log"
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_SCENARIO=none "$WAIT_SCRIPT" '42') 2>&1)" || fail "no-checks case should return safely: $output"
[[ "$output" == *'state=none'* ]] || fail "no-checks state missing: $output"
printf 'PASS: absent checks are distinguished from failure\n'

: > "$log"
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_SCENARIO=pending "$WAIT_SCRIPT" '42') 2>&1)" || fail "pending checks should return a blocking state: $output"
[[ "$output" == *'state=pending'* ]] || fail "pending checks were not preserved: $output"
printf 'PASS: pending checks are not classified as absent\n'

: > "$log"
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_SCENARIO=unresolved "$WAIT_SCRIPT") 2>&1)" || fail "unresolved PR should return safely: $output"
[[ "$output" == *'state=blocked'* ]] || fail "unresolved PR was not blocked: $output"
! grep -q '^pr checks' "$log" || fail "checks ran without a PR"
printf 'PASS: unresolved PR is blocked\n'

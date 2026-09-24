#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MERGE_SCRIPT="$SCRIPT_DIR/gitauto-merge.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
roots=(); cleanup() { if ((${#roots[@]})); then rm -rf "${roots[@]}"; fi; }; trap cleanup EXIT

new_fixture() {
  local branch="$1" root
  root="$(mktemp -d)"; roots+=("$root")
  repo="$root/repo"; bin="$root/bin"; log="$root/gh.log"
  mkdir -p "$bin"
  git init -q -b "$branch" "$repo"
  git -C "$repo" config user.name "Gitauto Test"; git -C "$repo" config user.email gitauto@example.invalid
  printf 'base\n' > "$repo/README.md"; git -C "$repo" add README.md; git -C "$repo" commit -qm init
  cat > "$bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$GH_LOG"
case "${1:-} ${2:-}" in
  'pr view')
    case "${GH_SCENARIO:-open}" in
      open) printf '42	OPEN	feat/merge\n' ;;
      merged) printf '42	MERGED	feat/merge\n' ;;
      closed) printf '42	CLOSED	feat/merge\n' ;;
      missing) exit 1 ;;
    esac
    ;;
  'pr checks')
    case "${GH_CHECKS:-green}" in
      green) printf 'green\n'; exit 0 ;;
      failed) printf 'failed\n' >&2; exit 1 ;;
      pending) printf 'pending\n' >&2; exit 8 ;;
      none) printf 'no checks reported on the branch\n' >&2; exit 1 ;;
    esac
    ;;
  'pr merge')
    [[ "$*" == "pr merge 42 --squash --subject feat: add feature (#42) --body " ]] || {
      printf 'merge args mismatch: %s\n' "$*" >&2; exit 9;
    }
    ;;
  *) printf 'unexpected gh command: %s\n' "$*" >&2; exit 9 ;;
esac
GH
  chmod +x "$bin/gh"
}

new_fixture main
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" "$MERGE_SCRIPT" 'pr=42' 'subject=feat: add feature') 2>&1)" || fail "main guard should return safely: $output"
[[ "$output" == *'state=blocked'* ]] || fail "main was not blocked: $output"
[[ ! -s "$log" ]] || fail "main guard called gh"
printf 'PASS: protected branch cannot merge\n'

new_fixture feat/merge
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_SCENARIO=open "$MERGE_SCRIPT" 'pr=42' 'subject=feat: add feature') 2>&1)" || fail "open PR merge failed: $output"
[[ "$output" == *'state=merged'* && "$output" == *'subject=feat: add feature (#42)'* ]] || fail "merge result missing: $output"
[[ "$(grep -c '^pr merge ' "$log")" -eq 1 ]] || fail "expected exactly one merge"
printf 'PASS: open PR is squash-merged with exact subject\n'

new_fixture feat/merge
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_SCENARIO=merged "$MERGE_SCRIPT" 'pr=42' 'subject=feat: add feature') 2>&1)" || fail "already-merged should return safely: $output"
[[ "$output" == *'state=already-merged'* ]] || fail "already merged state missing: $output"
! grep -q '^pr merge ' "$log" || fail "already merged PR was merged again"
printf 'PASS: already merged PR is idempotent\n'

for scenario in closed missing; do
  new_fixture feat/merge
  output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_SCENARIO="$scenario" "$MERGE_SCRIPT" 'pr=42' 'subject=feat: add feature') 2>&1)" || fail "$scenario PR should return safely: $output"
  [[ "$output" == *'state=blocked'* ]] || fail "$scenario PR was not blocked: $output"
  ! grep -q '^pr merge ' "$log" || fail "$scenario PR attempted merge"
done
printf 'PASS: closed and missing PRs are blocked\n'

new_fixture feat/merge
set +e
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_SCENARIO=open "$MERGE_SCRIPT" 'pr=42' $'subject=feat: bad\nbody') 2>&1)"
status=$?
set -e
[[ $status -ne 0 && "$output" == *'state=failed'* ]] || fail "multiline subject was not rejected: status=$status output=$output"
! grep -q '^pr merge ' "$log" || fail "invalid subject attempted merge"
printf 'PASS: invalid subject is rejected before merge\n'

for checks in failed pending; do
  new_fixture feat/merge
  output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_SCENARIO=open GH_CHECKS="$checks" "$MERGE_SCRIPT" 'pr=42' 'subject=feat: add feature') 2>&1)" || fail "$checks checks should block safely: $output"
  [[ "$output" == *'state=blocked'* ]] || fail "$checks checks did not block merge: $output"
  ! grep -q '^pr merge ' "$log" || fail "$checks checks reached merge"
done
printf 'PASS: failed and pending checks block standalone merge\n'

new_fixture feat/merge
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_SCENARIO=open GH_CHECKS=none "$MERGE_SCRIPT" 'pr=42' 'subject=feat: add feature') 2>&1)" || fail "no-checks merge failed: $output"
[[ "$output" == *'state=merged'* ]] || fail "explicit no-checks response did not allow merge: $output"
printf 'PASS: explicit no-checks response remains mergeable\n'

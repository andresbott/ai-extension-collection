#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MERGE_SCRIPT="$SCRIPT_DIR/factory-merge.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
roots=(); cleanup() { if ((${#roots[@]})); then rm -rf "${roots[@]}"; fi; }; trap cleanup EXIT

new_fixture() {
  local branch="$1" root
  root="$(mktemp -d)"; roots+=("$root")
  repo="$root/repo"; bin="$root/bin"; log="$root/gh.log"
  mkdir -p "$bin"
  git init -q -b "$branch" "$repo"
  git -C "$repo" config user.name "Factory Test"; git -C "$repo" config user.email factory@example.invalid
  printf 'base\n' > "$repo/README.md"; git -C "$repo" add README.md; git -C "$repo" commit -qm init
  cat > "$bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$GH_LOG"
[[ -z "${GH_HINT:-}" ]] || printf '%s\n' 'hint: if you need to wait for this pull request to be reviewed, merged, or closed before continuing, use this instead of' 'polling:' '  gh event listen' >&2
case "${1:-} ${2:-}" in
  'pr view')
    if [[ "$*" == *mergeable* ]]; then printf '%s\tmain\n' "${GH_MERGEABLE:-MERGEABLE}"; exit 0; fi
    if [[ "$*" == *baseRefName* ]]; then printf 'main\n'; exit 0; fi
    case "${GH_SCENARIO:-open}" in
      open) printf '42	OPEN	feat/merge\n' ;;
      merged) printf '42	MERGED	feat/merge\n' ;;
      closed) printf '42	CLOSED	feat/merge\n' ;;
      missing) printf 'GraphQL: Could not resolve to a PullRequest with the number of 42. (repository.pullRequest)\n' >&2; exit 1 ;;
      flaky)
        [[ "$(grep -c '^pr view ' "$GH_LOG")" -gt 1 ]] || { printf 'HTTP 502: Bad Gateway (https://api.github.com/graphql)\n' >&2; exit 1; }
        printf '42	OPEN	feat/merge\n' ;;
      down) printf 'HTTP 502: Bad Gateway (https://api.github.com/graphql)\n' >&2; exit 1 ;;
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
    # GH_MERGE_ERROR: gh refuses the merge with this message.
    [[ -z "${GH_MERGE_ERROR:-}" ]] || { printf '%s\n' "$GH_MERGE_ERROR" >&2; exit 1; }
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
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_SCENARIO=flaky FACTORY_GH_RETRY_DELAY=0 "$MERGE_SCRIPT" 'pr=42' 'subject=feat: add feature') 2>&1)" || fail "flaky lookup should recover: $output"
[[ "$output" == *'state=merged'* ]] || fail "one failed PR lookup stopped the merge: $output"
printf 'PASS: a transient PR lookup failure is retried\n'

new_fixture feat/merge
set +e
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_SCENARIO=down FACTORY_GH_RETRY_DELAY=0 "$MERGE_SCRIPT" 'pr=42' 'subject=feat: add feature') 2>&1)"
status=$?
set -e
[[ $status -ne 0 && "$output" == *'state=failed'* ]] || fail "persistent lookup failure was not a failure: status=$status output=$output"
[[ "$output" == *'report=pull request lookup failed: HTTP 502: Bad Gateway'* ]] || fail "lookup failure hid the gh error: $output"
[[ "$output" != *'pull request is missing'* ]] || fail "lookup failure was reported as a missing PR: $output"
[[ "$(grep -c '^pr view ' "$log")" -eq 3 ]] || fail "expected 3 lookup attempts, got $(grep -c '^pr view ' "$log")"
! grep -q '^pr merge ' "$log" || fail "failed lookup attempted merge"
printf 'PASS: a persistent PR lookup failure reports the gh error\n'

new_fixture feat/merge
set +e
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_SCENARIO=open "$MERGE_SCRIPT" 'pr=42' $'subject=feat: bad\nbody') 2>&1)"
status=$?
set -e
[[ $status -ne 0 && "$output" == *'state=failed'* ]] || fail "multiline subject was not rejected: status=$status output=$output"
! grep -q '^pr merge ' "$log" || fail "invalid subject attempted merge"
printf 'PASS: invalid subject is rejected before merge\n'

for checks in failed:blocked pending:pending; do
  new_fixture feat/merge
  output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_SCENARIO=open GH_CHECKS="${checks%%:*}" "$MERGE_SCRIPT" 'pr=42' 'subject=feat: add feature') 2>&1)" || fail "${checks%%:*} checks should stop safely: $output"
  [[ "$output" == *"state=${checks#*:}"* ]] || fail "${checks%%:*} checks did not report state=${checks#*:}: $output"
  ! grep -q '^pr merge ' "$log" || fail "${checks%%:*} checks reached merge"
done
printf 'PASS: failed checks block and pending checks report pending, neither merges\n'

new_fixture feat/merge
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_SCENARIO=open GH_CHECKS=none "$MERGE_SCRIPT" 'pr=42' 'subject=feat: add feature') 2>&1)" || fail "no-checks merge failed: $output"
[[ "$output" == *'state=merged'* ]] || fail "explicit no-checks response did not allow merge: $output"
printf 'PASS: explicit no-checks response remains mergeable\n'

for scenario in open:merged missing:blocked; do
  new_fixture feat/merge
  output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_HINT=1 GH_SCENARIO="${scenario%%:*}" "$MERGE_SCRIPT" 'pr=42' 'subject=feat: add feature') 2>&1)" || fail "${scenario%%:*} PR with a gh hint should return safely: $output"
  [[ "$output" == *"state=${scenario#*:}"* ]] || fail "a gh hint on stderr changed the ${scenario%%:*} outcome: $output"
done
new_fixture feat/merge
set +e
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_HINT=1 GH_SCENARIO=down FACTORY_GH_RETRY_DELAY=0 "$MERGE_SCRIPT" 'pr=42' 'subject=feat: add feature') 2>&1)"
set -e
[[ "$output" == *'report=pull request lookup failed: HTTP 502: Bad Gateway'* ]] || fail "a gh hint hid the lookup error: $output"
printf 'PASS: a gh hint on stderr is not read as the PR lookup\n'

new_fixture feat/merge
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_MERGEABLE=CONFLICTING "$MERGE_SCRIPT" 'pr=42' 'subject=feat: add feature') 2>&1)" || fail "a conflicting PR should return safely: $output"
[[ "$output" == *'state=conflict'* && "$output" == *'report=pull request #42 has merge conflicts with main; '* ]] || fail "conflict not reported: $output"
! grep -q '^pr merge ' "$log" || fail "a conflicting PR attempted merge"
printf 'PASS: a conflicting PR is reported before merging\n'

new_fixture feat/merge
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_MERGE_ERROR='X Pull request o/r#42 is not mergeable: the merge commit cannot be cleanly created.' "$MERGE_SCRIPT" 'pr=42' 'subject=feat: add feature') 2>&1)" || fail "a merge refused for a conflict should return safely: $output"
[[ "$output" == *'state=conflict'* && "$output" == *'conflicts with main'* ]] || fail "a refused merge was not reported as a conflict: $output"
printf 'PASS: a merge gh refuses for a conflict is reported as a conflict\n'

new_fixture feat/merge
set +e
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_MERGE_ERROR='GraphQL: Base branch was modified. (mergePullRequest)' "$MERGE_SCRIPT" 'pr=42' 'subject=feat: add feature') 2>&1)"
status=$?
set -e
[[ $status -ne 0 && "$output" == *'state=failed'* && "$output" == *'report=merge failed: GraphQL: Base branch was modified. (mergePullRequest)'* ]] ||
  fail "a refused merge hid the gh error: status=$status output=$output"
printf 'PASS: a merge gh refuses reports the gh error\n'

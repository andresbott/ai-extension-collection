#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPEN_PR_SCRIPT="$SCRIPT_DIR/gitauto-open-pr.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
roots=()
cleanup() { if ((${#roots[@]})); then rm -rf "${roots[@]}"; fi; }
trap cleanup EXIT

new_fixture() {
  local branch="$1" root
  root="$(mktemp -d)"; roots+=("$root")
  repo="$root/repo"; bin="$root/bin"; log="$root/gh.log"
  mkdir -p "$bin"
  git init -q -b "$branch" "$repo"
  git -C "$repo" config user.name "Gitauto Test"
  git -C "$repo" config user.email "gitauto@example.invalid"
  printf 'base\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -qm "initial commit"
  cat > "$bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s %s\n' "${1:-}" "${2:-}" >> "$GH_LOG"
case "${1:-} ${2:-}" in
  'auth status') exit 0 ;;
  'repo view') printf '%s\n' "${GH_BASE:-main}" ;;
  'pr view')
    case "${GH_SCENARIO:-none}" in
      open) printf '42\tOPEN\thttps://example.invalid/pr/42\n' ;;
      merged) printf '42\tMERGED\thttps://example.invalid/pr/42\n' ;;
      closed) printf '42\tCLOSED\thttps://example.invalid/pr/42\n' ;;
      none) printf 'no pull requests found for branch\n' >&2; exit 1 ;;
      error) printf 'network unavailable\n' >&2; exit 1 ;;
    esac
    ;;
  'pr create')
    shift 2
    base=''; head=''; title=''; body=''
    while (($#)); do
      case "$1" in
        --base) base="$2"; shift 2 ;;
        --head) head="$2"; shift 2 ;;
        --title) title="$2"; shift 2 ;;
        --body) body="$2"; shift 2 ;;
        *) printf 'unexpected argument: %s\n' "$1" >&2; exit 9 ;;
      esac
    done
    [[ "$base" == "$EXPECT_BASE" && "$head" == "$EXPECT_HEAD" && "$title" == "$EXPECT_TITLE" && "$body" == "$EXPECT_BODY" ]] || {
      printf 'create mismatch: base=%q head=%q title=%q body=%q\n' "$base" "$head" "$title" "$body" >&2
      exit 9
    }
    printf 'https://example.invalid/pr/77\n'
    ;;
  *) printf 'unexpected gh command: %s\n' "$*" >&2; exit 9 ;;
esac
GH
  chmod +x "$bin/gh"
}

new_fixture main
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" "$OPEN_PR_SCRIPT" 'title=x' 'body=y') 2>&1)" || fail "main guard should return safely: $output"
[[ "$output" == *'state=blocked'* ]] || fail "main was not blocked: $output"
[[ ! -s "$log" ]] || fail "main guard called gh"
printf 'PASS: protected branch is blocked before GitHub calls\n'

new_fixture feat/reuse
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_SCENARIO=open "$OPEN_PR_SCRIPT") 2>&1)" || fail "open PR reuse failed: $output"
[[ "$output" == *'state=reused'* && "$output" == *'number=42'* ]] || fail "open PR was not reused: $output"
! grep -q '^pr create$' "$log" || fail "reuse created another PR"
printf 'PASS: existing open PR is reused\n'

new_fixture feat/merged
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_SCENARIO=merged "$OPEN_PR_SCRIPT") 2>&1)" || fail "merged state should return safely: $output"
[[ "$output" == *'state=already-merged'* ]] || fail "merged PR was not distinct: $output"
! grep -q '^pr create$' "$log" || fail "merged state created a PR"

new_fixture feat/closed
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_SCENARIO=closed "$OPEN_PR_SCRIPT") 2>&1)" || fail "closed state should return safely: $output"
[[ "$output" == *'state=closed'* ]] || fail "closed PR was not distinct: $output"
! grep -q '^pr create$' "$log" || fail "closed state created a PR"
printf 'PASS: merged and closed PRs route distinctly\n'

new_fixture feat/error
set +e
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_SCENARIO=error EXPECT_BASE=main EXPECT_HEAD=feat/error EXPECT_TITLE=x EXPECT_BODY=y "$OPEN_PR_SCRIPT" 'title=x' 'body=y') 2>&1)"
status=$?
set -e
[[ $status -ne 0 && "$output" == *'state=failed'* ]] || fail "lookup error was not preserved: status=$status output=$output"
! grep -q '^pr create$' "$log" || fail "lookup error attempted PR creation"
printf 'PASS: PR lookup failure does not become confirmed absence\n'

new_fixture feat/create
body=$'## Summary\nWhy this matters.\n\n## What\n- Add the thing.'
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" GH_SCENARIO=none EXPECT_BASE=develop EXPECT_HEAD=feat/create EXPECT_TITLE='Add the thing' EXPECT_BODY="$body" "$OPEN_PR_SCRIPT" 'title=Add the thing' "body=$body" 'base=develop') 2>&1)" || fail "PR creation failed: $output"
[[ "$output" == *'state=created'* && "$output" == *'number=77'* ]] || fail "created PR outcome missing: $output"
grep -q '^pr create$' "$log" || fail "gh pr create was not called"
printf 'PASS: missing PR is created with exact arguments\n'

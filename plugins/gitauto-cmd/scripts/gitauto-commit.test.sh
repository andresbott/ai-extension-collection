#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMIT_SCRIPT="$SCRIPT_DIR/gitauto-commit.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

new_repo() {
  local branch="$1"
  local repo
  repo="$(mktemp -d)"
  git -C "$repo" init -q -b "$branch"
  git -C "$repo" config user.name "Gitauto Test"
  git -C "$repo" config user.email "gitauto@example.invalid"
  printf 'base\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -qm "initial commit"
  printf '%s\n' "$repo"
}

repos=()
cleanup() {
  if ((${#repos[@]})); then
    rm -rf "${repos[@]}"
  fi
}
trap cleanup EXIT

repo="$(new_repo main)"
repos+=("$repo")
printf 'changed\n' >> "$repo/README.md"
printf 'untracked\n' > "$repo/new.txt"
before_head="$(git -C "$repo" rev-parse HEAD)"
before_status="$(git -C "$repo" status --porcelain=v1)"
output="$( (cd "$repo" && "$COMMIT_SCRIPT" 'feat: forbidden') 2>&1)" || fail "main guard should return safely: $output"
[[ "$output" == *"state=blocked"* ]] || fail "main was not reported blocked: $output"
[[ "$(git -C "$repo" rev-parse HEAD)" == "$before_head" ]] || fail "main guard created a commit"
[[ "$(git -C "$repo" status --porcelain=v1)" == "$before_status" ]] || fail "main guard staged or changed files"

printf 'PASS: main is blocked without staging or committing\n'

repo="$(new_repo master)"
repos+=("$repo")
printf 'changed\n' >> "$repo/README.md"
before_head="$(git -C "$repo" rev-parse HEAD)"
before_status="$(git -C "$repo" status --porcelain=v1)"
output="$( (cd "$repo" && "$COMMIT_SCRIPT" 'feat: forbidden') 2>&1)" || fail "master guard should return safely: $output"
[[ "$output" == *"state=blocked"* ]] || fail "master was not reported blocked: $output"
[[ "$(git -C "$repo" rev-parse HEAD)" == "$before_head" ]] || fail "master guard created a commit"
[[ "$(git -C "$repo" status --porcelain=v1)" == "$before_status" ]] || fail "master guard staged or changed files"

printf 'PASS: master is blocked without staging or committing\n'

repo="$(new_repo feat/detached)"
repos+=("$repo")
git -C "$repo" checkout -q --detach
printf 'changed\n' >> "$repo/README.md"
before_head="$(git -C "$repo" rev-parse HEAD)"
before_status="$(git -C "$repo" status --porcelain=v1)"
output="$( (cd "$repo" && "$COMMIT_SCRIPT" 'feat: detached') 2>&1)" || fail "detached HEAD guard should return safely: $output"
[[ "$output" == *"state=blocked"* ]] || fail "detached HEAD was not reported blocked: $output"
[[ "$output" == *"branch=detached"* ]] || fail "detached HEAD was not identified: $output"
[[ "$(git -C "$repo" rev-parse HEAD)" == "$before_head" ]] || fail "detached guard created a commit"
[[ "$(git -C "$repo" status --porcelain=v1)" == "$before_status" ]] || fail "detached guard staged or changed files"

printf 'PASS: detached HEAD is blocked without staging or committing\n'

repo="$(new_repo feat/clean)"
repos+=("$repo")
before_head="$(git -C "$repo" rev-parse HEAD)"
output="$( (cd "$repo" && "$COMMIT_SCRIPT" 'chore: unused') 2>&1)" || fail "clean feature branch should return unchanged: $output"
[[ "$output" == *"state=unchanged"* ]] || fail "clean tree was not reported unchanged: $output"
[[ "$(git -C "$repo" rev-parse HEAD)" == "$before_head" ]] || fail "clean tree created a commit"

printf 'PASS: clean feature branch is unchanged\n'

repo="$(new_repo feat/commit)"
repos+=("$repo")
printf 'staged\n' >> "$repo/README.md"
git -C "$repo" add README.md
printf 'unstaged\n' >> "$repo/README.md"
printf 'untracked\n' > "$repo/new.txt"
before_count="$(git -C "$repo" rev-list --count HEAD)"
output="$( (cd "$repo" && "$COMMIT_SCRIPT" 'feat: save all changes') 2>&1)" || fail "feature commit should pass: $output"
after_count="$(git -C "$repo" rev-list --count HEAD)"
[[ $((after_count - before_count)) -eq 1 ]] || fail "expected exactly one new commit"
[[ -z "$(git -C "$repo" status --porcelain=v1)" ]] || fail "commit did not include all changes"
[[ "$(git -C "$repo" log -1 --format=%s)" == "feat: save all changes" ]] || fail "commit subject differs from positional message"
[[ "$(git -C "$repo" log -1 --format=%B)" == "feat: save all changes" ]] || fail "commit contains a body"
! git -C "$repo" log -1 --format=%B | grep -qi '^Co-Authored-By:' || fail "commit contains Co-Authored-By"
[[ "$output" == *"state=committed"* ]] || fail "commit outcome was not reported: $output"

printf 'PASS: positional message creates one commit containing all changes\n'

repo="$(new_repo feat/named-message)"
repos+=("$repo")
printf 'changed\n' >> "$repo/README.md"
output="$( (cd "$repo" && "$COMMIT_SCRIPT" 'message=fix: named message') 2>&1)" || fail "named message commit should pass: $output"
[[ "$(git -C "$repo" log -1 --format=%s)" == "fix: named message" ]] || fail "message= prefix was included in commit subject"
[[ "$(git -C "$repo" log -1 --format=%B)" == "fix: named message" ]] || fail "named commit contains a body"

printf 'PASS: message=<text> creates a one-line commit\n'

repo="$(new_repo feat/hooks)"
repos+=("$repo")
cat > "$repo/.git/hooks/pre-commit" <<'HOOK'
#!/usr/bin/env bash
printf 'ran\n' > .git/pre-commit-ran
HOOK
chmod +x "$repo/.git/hooks/pre-commit"
printf 'changed\n' >> "$repo/README.md"
output="$( (cd "$repo" && "$COMMIT_SCRIPT" 'fix: honor repository hooks') 2>&1)" || fail "hook-aware commit should pass: $output"
[[ -f "$repo/.git/pre-commit-ran" ]] || fail "repository pre-commit hook did not run"
[[ "$(git -C "$repo" log -1 --format=%B)" == "fix: honor repository hooks" ]] || fail "commit message was not the requested one-line message"

printf 'PASS: repository commit hooks are honored\n'

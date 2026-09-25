#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRANCH_SCRIPT="$SCRIPT_DIR/gitauto-branch.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

repo="$(mktemp -d)"
trap 'rm -rf "$repo"' EXIT

git -C "$repo" init -q -b main
git -C "$repo" config user.name "Gitauto Test"
git -C "$repo" config user.email "gitauto@example.invalid"
printf 'base\n' > "$repo/README.md"
git -C "$repo" add README.md
git -C "$repo" commit -qm "initial commit"

(
  cd "$repo"
  "$BRANCH_SCRIPT" "feat/explicit-name" >/dev/null
)

actual="$(git -C "$repo" branch --show-current)"
[[ "$actual" == "feat/explicit-name" ]] || fail "expected feat/explicit-name, got $actual"

printf 'PASS: explicit name is checked out from main\n'

new_repo() {
  local dir
  dir="$(mktemp -d)"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.name "Gitauto Test"
  git -C "$dir" config user.email "gitauto@example.invalid"
  printf 'base\n' > "$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit -qm "initial commit"
  printf '%s' "$dir"
}

taken_repo="$(new_repo)"
trap 'rm -rf "$repo" "$taken_repo"' EXIT
git -C "$taken_repo" branch feat/taken
git -C "$taken_repo" update-ref refs/remotes/origin/feat/remote-taken HEAD

output="$(cd "$taken_repo" && "$BRANCH_SCRIPT" feat/taken feat/remote-taken 'bad..name' feat/free)"
actual="$(git -C "$taken_repo" branch --show-current)"
[[ "$actual" == "feat/free" ]] || fail "expected feat/free, got $actual"
grep -q '^skipped_existing=feat/taken,feat/remote-taken$' <<<"$output" || fail "missing skipped_existing in: $output"

printf 'PASS: existing and invalid candidates are skipped in order\n'

exists_repo="$(new_repo)"
trap 'rm -rf "$repo" "$taken_repo" "$exists_repo"' EXIT
git -C "$exists_repo" branch feat/one
git -C "$exists_repo" branch feat/two

status=0
output="$(cd "$exists_repo" && "$BRANCH_SCRIPT" feat/one feat/two)" || status=$?
[[ $status -eq 3 ]] || fail "expected exit 3 when all candidates exist, got $status"
grep -q '^state=exists$' <<<"$output" || fail "expected state=exists in: $output"
actual="$(git -C "$exists_repo" branch --show-current)"
[[ "$actual" == "main" ]] || fail "expected to stay on main, got $actual"

printf 'PASS: state=exists is reported when every candidate is taken\n'

empty_repo="$(new_repo)"
trap 'rm -rf "$repo" "$taken_repo" "$exists_repo" "$empty_repo"' EXIT

status=0
output="$(cd "$empty_repo" && "$BRANCH_SCRIPT")" || status=$?
[[ $status -eq 2 ]] || fail "expected exit 2 without candidates, got $status"
grep -q '^state=failed$' <<<"$output" || fail "expected state=failed in: $output"

printf 'PASS: no hardcoded fallback name is invented without candidates\n'

feature_repo="$(mktemp -d)"
trap 'rm -rf "$repo" "$taken_repo" "$exists_repo" "$empty_repo" "$feature_repo"' EXIT

git -C "$feature_repo" init -q -b main
git -C "$feature_repo" config user.name "Gitauto Test"
git -C "$feature_repo" config user.email "gitauto@example.invalid"
printf 'base\n' > "$feature_repo/README.md"
git -C "$feature_repo" add README.md
git -C "$feature_repo" commit -qm "initial commit"
git -C "$feature_repo" switch -qc feat/already-there

(
  cd "$feature_repo"
  "$BRANCH_SCRIPT" "feat/ignored" >/dev/null
)

actual="$(git -C "$feature_repo" branch --show-current)"
[[ "$actual" == "feat/already-there" ]] || fail "expected feat/already-there, got $actual"

printf 'PASS: an existing feature branch is left unchanged\n'

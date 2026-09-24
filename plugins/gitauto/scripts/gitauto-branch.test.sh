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

repo_with_changes="$(mktemp -d)"
trap 'rm -rf "$repo" "$repo_with_changes"' EXIT

git -C "$repo_with_changes" init -q -b main
git -C "$repo_with_changes" config user.name "Gitauto Test"
git -C "$repo_with_changes" config user.email "gitauto@example.invalid"
printf 'base\n' > "$repo_with_changes/README.md"
git -C "$repo_with_changes" add README.md
git -C "$repo_with_changes" commit -qm "initial commit"
printf 'pending change\n' >> "$repo_with_changes/README.md"

(
  cd "$repo_with_changes"
  "$BRANCH_SCRIPT" >/dev/null
)

actual="$(git -C "$repo_with_changes" branch --show-current)"
[[ "$actual" == "work/readme" ]] || fail "expected work/readme, got $actual"

printf 'PASS: branch name is inferred from uncommitted changes\n'

clean_repo="$(mktemp -d)"
trap 'rm -rf "$repo" "$repo_with_changes" "$clean_repo"' EXIT

git -C "$clean_repo" init -q -b main
git -C "$clean_repo" config user.name "Gitauto Test"
git -C "$clean_repo" config user.email "gitauto@example.invalid"
printf 'base\n' > "$clean_repo/README.md"
git -C "$clean_repo" add README.md
git -C "$clean_repo" commit -qm "initial commit"

(
  cd "$clean_repo"
  "$BRANCH_SCRIPT" >/dev/null
)

actual="$(git -C "$clean_repo" branch --show-current)"
[[ "$actual" == "work/change" ]] || fail "expected work/change, got $actual"

printf 'PASS: a branch name is invented when no change suggests one\n'

feature_repo="$(mktemp -d)"
trap 'rm -rf "$repo" "$repo_with_changes" "$clean_repo" "$feature_repo"' EXIT

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

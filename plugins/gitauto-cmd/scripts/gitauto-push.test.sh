#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUSH_SCRIPT="$SCRIPT_DIR/gitauto-push.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
roots=()
cleanup() {
  if ((${#roots[@]})); then
    rm -rf "${roots[@]}"
  fi
}
trap cleanup EXIT

new_fixture() {
  local branch="$1" root
  root="$(mktemp -d)"; roots+=("$root")
  repo="$root/repo"; remote="$root/remote.git"
  git init -q --bare "$remote"
  git --git-dir="$remote" symbolic-ref HEAD refs/heads/main
  git init -q -b "$branch" "$repo"
  git -C "$repo" config user.name "Gitauto Test"
  git -C "$repo" config user.email "gitauto@example.invalid"
  printf 'base\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -qm "initial commit"
  git -C "$repo" remote add origin "$remote"
  git -C "$repo" push -q origin HEAD:refs/heads/main
}

for protected in main master; do
  new_fixture "$protected"
  before="$(git --git-dir="$remote" show-ref || true)"
  output="$( (cd "$repo" && "$PUSH_SCRIPT") 2>&1)" || fail "$protected guard should return safely: $output"
  [[ "$output" == *"state=blocked"* ]] || fail "$protected was not blocked: $output"
  [[ "$(git --git-dir="$remote" show-ref || true)" == "$before" ]] || fail "$protected updated the remote"
done
printf 'PASS: main and master cannot be pushed\n'

new_fixture feat/detached
git -C "$repo" checkout -q --detach
before="$(git --git-dir="$remote" show-ref)"
output="$( (cd "$repo" && "$PUSH_SCRIPT") 2>&1)" || fail "detached guard should return safely: $output"
[[ "$output" == *"state=blocked"* ]] || fail "detached HEAD was not blocked: $output"
[[ "$(git --git-dir="$remote" show-ref)" == "$before" ]] || fail "detached HEAD updated the remote"
printf 'PASS: detached HEAD cannot be pushed\n'

new_fixture feat/push
output="$( (cd "$repo" && "$PUSH_SCRIPT") 2>&1)" || fail "feature push failed: $output"
[[ "$output" == *"state=pushed"* ]] || fail "push outcome missing: $output"
[[ "$(git --git-dir="$remote" rev-parse refs/heads/feat/push)" == "$(git -C "$repo" rev-parse HEAD)" ]] || fail "remote branch mismatch"
[[ "$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}')" == "origin/feat/push" ]] || fail "upstream was not configured"
printf 'PASS: feature branch is pushed with upstream\n'

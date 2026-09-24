#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEANUP_SCRIPT="$SCRIPT_DIR/gitauto-cleanup.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
roots=(); cleanup() { if ((${#roots[@]})); then rm -rf "${roots[@]}"; fi; }; trap cleanup EXIT

new_fixture() {
  root="$(mktemp -d)"; roots+=("$root")
  primary="$root/primary"; feature="$root/feature"; remote="$root/remote.git"
  git init -q --bare "$remote"; git --git-dir="$remote" symbolic-ref HEAD refs/heads/main
  git init -q -b main "$primary"
  git -C "$primary" config user.name "Gitauto Test"; git -C "$primary" config user.email gitauto@example.invalid
  printf 'base\n' > "$primary/README.md"; git -C "$primary" add README.md; git -C "$primary" commit -qm init
  git -C "$primary" remote add origin "$remote"; git -C "$primary" push -qu origin main
  git -C "$primary" branch feat/work; git -C "$primary" worktree add -q "$feature" feat/work
  git -C "$feature" push -qu origin feat/work
}

new_fixture
output="$( (cd "$primary" && "$CLEANUP_SCRIPT" 'branch=main' 'deleteRemote=true') 2>&1)" || fail "protected cleanup should return safely: $output"
[[ "$output" == *'state=blocked'* ]] || fail "main cleanup was not blocked: $output"
[[ -n "$(git --git-dir="$remote" show-ref refs/heads/main)" ]] || fail "main remote branch was deleted"
printf 'PASS: protected branches cannot be cleaned up\n'

new_fixture
output="$( (cd "$primary" && "$CLEANUP_SCRIPT" 'branch=feat/work') 2>&1)" || fail "clean worktree cleanup failed: $output"
[[ "$output" == *'state=clean'* && "$output" == *'remote_branch=kept'* ]] || fail "clean outcome missing: $output"
[[ ! -d "$feature" ]] || fail "clean feature worktree was not removed"
git -C "$primary" show-ref --verify --quiet refs/heads/feat/work || fail "local feature branch was deleted"
git --git-dir="$remote" show-ref --verify --quiet refs/heads/feat/work || fail "remote branch was deleted without approval"
printf 'PASS: clean worktree is removed while local and remote branches are kept\n'

new_fixture
output="$( (cd "$feature" && "$CLEANUP_SCRIPT" 'branch=feat/work' 'deleteRemote=true') 2>&1)" || fail "active cleanup should return safely: $output"
[[ "$output" == *'state=partial'* && "$output" == *'worktree=deferred-active'* ]] || fail "active worktree was not deferred: $output"
[[ -d "$feature" ]] || fail "active worktree was removed"
! git --git-dir="$remote" show-ref --verify --quiet refs/heads/feat/work || fail "approved remote branch was not deleted"
git -C "$feature" show-ref --verify --quiet refs/heads/feat/work || fail "local branch was deleted"
printf 'PASS: approved remote deletion occurs while active worktree removal is deferred\n'

new_fixture
git -C "$primary" push -q origin --delete feat/work
output="$( (cd "$primary" && "$CLEANUP_SCRIPT" 'branch=feat/work' 'deleteRemote=true') 2>&1)" || fail "absent remote should be idempotent: $output"
[[ "$output" == *'state=clean'* && "$output" == *'remote_branch=absent'* ]] || fail "absent remote outcome missing: $output"
printf 'PASS: absent remote branch is idempotent\n'

new_fixture
printf 'dirty\n' > "$feature/dirty.txt"
output="$( (cd "$primary" && "$CLEANUP_SCRIPT" 'branch=feat/work') 2>&1)" || fail "dirty cleanup should return safely: $output"
[[ "$output" == *'state=partial'* && "$output" == *'worktree=deferred-dirty'* ]] || fail "dirty worktree was not deferred: $output"
[[ -f "$feature/dirty.txt" ]] || fail "dirty worktree content was removed"
printf 'PASS: dirty feature worktree is preserved\n'

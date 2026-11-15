#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SCRIPT="$SCRIPT_DIR/gitauto-sync-main.sh"
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
}

advance_remote() {
  local updater="$1"
  git clone -q "$remote" "$updater"
  git -C "$updater" config user.name "Remote Test"; git -C "$updater" config user.email remote@example.invalid
  printf 'remote\n' >> "$updater/README.md"; git -C "$updater" commit -qam "remote update"; git -C "$updater" push -q origin main
}

new_fixture
advance_remote "$root/updater"
remote_head="$(git --git-dir="$remote" rev-parse refs/heads/main)"
git -C "$primary" switch -qc scratch
output="$( (cd "$feature" && "$SYNC_SCRIPT") 2>&1)" || fail "clean primary sync failed: $output"
[[ "$output" == *'state=synced'* && "$output" == *'branch=main'* ]] || fail "synced outcome missing: $output"
[[ "$(git -C "$primary" branch --show-current)" == main ]] || fail "primary was not switched to main"
[[ "$(git -C "$primary" rev-parse HEAD)" == "$remote_head" ]] || fail "main was not fast-forwarded"
printf 'PASS: clean primary worktree switches and fast-forwards main\n'

new_fixture
printf 'dirty\n' > "$primary/local.txt"
before="$(git -C "$primary" rev-parse HEAD)"
output="$( (cd "$feature" && "$SYNC_SCRIPT") 2>&1)" || fail "dirty primary should return safely: $output"
[[ "$output" == *'state=blocked'* ]] || fail "dirty primary was not blocked: $output"
[[ "$(git -C "$primary" rev-parse HEAD)" == "$before" && -f "$primary/local.txt" ]] || fail "dirty primary was changed"
printf 'PASS: dirty primary worktree is preserved\n'

new_fixture
git -C "$primary" config user.name "Local Test"; git -C "$primary" config user.email local@example.invalid
printf 'local\n' > "$primary/local.txt"; git -C "$primary" add local.txt; git -C "$primary" commit -qm "local divergence"
local_head="$(git -C "$primary" rev-parse HEAD)"
advance_remote "$root/updater"
set +e
output="$( (cd "$feature" && "$SYNC_SCRIPT") 2>&1)"
status=$?
set -e
[[ $status -ne 0 && "$output" == *'state=failed'* ]] || fail "divergent main did not fail safely: status=$status output=$output"
[[ "$(git -C "$primary" rev-parse HEAD)" == "$local_head" ]] || fail "divergent main was rewritten"
printf 'PASS: divergent main is not rewritten\n'

# Many worktrees make `git worktree list` write in several chunks; a reader that
# stops at the first match must not kill the helper with SIGPIPE under pipefail.
new_fixture
for i in $(seq 150); do git -C "$primary" worktree add -q --no-checkout -b "extra/$i" "$root/extra-$i"; done
for i in 1 2 3 4 5; do
  output="$( (cd "$feature" && "$SYNC_SCRIPT") 2>&1)" || fail "sync with many worktrees failed on run $i: $output"
  [[ "$output" == *'state=synced'* ]] || fail "sync with many worktrees did not sync on run $i: $output"
done
printf 'PASS: many worktrees do not break primary worktree lookup\n'

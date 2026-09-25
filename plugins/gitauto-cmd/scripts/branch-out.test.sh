#!/usr/bin/env bash
# Tests for branch-out.sh. Fixtures live in $TMPDIR; the surrounding repo is untouched.
set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/branch-out.sh"
dirs=()
trap 'rm -rf "${dirs[@]}"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

new_repo() {
  local dir
  dir="$(mktemp -d)"
  dirs+=("$dir")
  git -C "$dir" init -q -b main
  git -C "$dir" config user.name "Gitauto Test"
  git -C "$dir" config user.email "gitauto@example.invalid"
  printf 'base\n' > "$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit -qm "initial commit"
  repo="$dir"
}
run() { (cd "$repo" && "$SCRIPT" "$@") || true; }
on() { git -C "$repo" branch --show-current; }

new_repo
out="$(run feat/explicit)"
[[ "$out" == "DONE state=created branch=feat/explicit from=main" ]] || fail "explicit: $out"
[[ "$(on)" == feat/explicit ]] || fail "explicit not checked out"
pass "explicit name is created without the model"

out="$(run feat/other)"
[[ "$out" == "DONE state=unchanged branch=feat/explicit" ]] || fail "unchanged: $out"
pass "feature branch is left unchanged"

new_repo
out="$(run '')"
[[ "$out" == "NEED_NAME on=main" ]] || fail "need name: $out"
printf 'x\n' > "$repo/new.txt"
out="$(run 'add a login page')"
grep -q '^NEED_NAME on=main hint=' <<<"$out" || fail "hint: $out"
grep -q 'new.txt' <<<"$out" || fail "status missing: $out"
[[ "$(on)" == main ]] || fail "preflight must not switch"
pass "missing or plain-language names ask the model with minimal context"

git -C "$repo" branch feat/taken
git -C "$repo" update-ref refs/remotes/origin/feat/remote HEAD
out="$(run --create 'bad..name' feat/taken feat/remote feat/free)"
[[ "$out" == "DONE state=created branch=feat/free from=main" ]] || fail "skip: $out"
pass "invalid and taken candidates are skipped in order"

new_repo
git -C "$repo" branch feat/a
git -C "$repo" branch feat/a-2
out="$(run --create feat/a)"
[[ "$out" == "DONE state=created branch=feat/a-3 from=main" ]] || fail "suffix: $out"
pass "all-taken candidates fall back to a numeric suffix"

new_repo
out="$(run --create 'bad..name')"
[[ "$out" == "DONE state=failed report=no valid branch name candidate" ]] || fail "invalid: $out"
git -C "$repo" switch -q --detach
out="$(run feat/x)"
[[ "$out" == "DONE state=failed report=detached HEAD" ]] || fail "detached: $out"
pass "invalid candidates and detached HEAD fail without changes"

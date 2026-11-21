#!/usr/bin/env bash
# Tests for new-branch.sh. Fixtures live in $TMPDIR; the surrounding repo is untouched.
set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/new-branch.sh"
dirs=()
trap 'rm -rf "${dirs[@]}"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

new_repo() {
  local dir
  dir="$(mktemp -d)"
  dirs+=("$dir")
  git -C "$dir" init -q -b main
  git -C "$dir" config user.name "Factory Test"
  git -C "$dir" config user.email "factory@example.invalid"
  printf 'base\n' > "$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit -qm "initial commit"
  repo="$dir"
}
run() { (cd "$repo" && "$SCRIPT" "$@") || true; }
on() { git -C "$repo" branch --show-current; }

new_repo
out="$(run feat/explicit)"
[[ "$out" == $'success: created feat/explicit from main and switched to it\nDONE state=created branch=feat/explicit from=main' ]] ||
  fail "explicit: $out"
[[ "$(on)" == feat/explicit ]] || fail "explicit not checked out"
pass "explicit name is created without the model"

out="$(run feat/other)"
[[ "$out" == $'success: already on the feature branch feat/explicit\nDONE state=unchanged branch=feat/explicit' ]] ||
  fail "unchanged: $out"
pass "feature branch is left unchanged"

new_repo
out="$(run '')"
[[ "$(tail -n 1 <<<"$out")" =~ ^DONE\ state=created\ branch=work/[a-z]+-[a-z]+\ from=main$ ]] || fail "random: $out"
pass "no args on a clean tree creates a random work/ branch without the model"

new_repo
git -C "$repo" switch -qc work/seed
git -C "$repo" switch -q main
names=()
for i in 1 2 3 4 5 6; do
  out="$(run '')"
  names+=("$(sed -n 's/^DONE state=created branch=\([^ ]*\) .*/\1/p' <<<"$out")")
  git -C "$repo" switch -q main
done
[[ "$(printf '%s\n' "${names[@]}" | sort -u | wc -l)" -eq 6 ]] || fail "repeated names: ${names[*]}"
pass "repeated runs pick distinct names that skip existing branches"

new_repo
printf 'todo\n' > "$repo/TODO.md"
printf '{}\n' > "$repo/.todo.json"
mkdir -p "$repo/docs"
printf 'todo\n' > "$repo/docs/todo.md"
git -C "$repo" add TODO.md
out="$(run '')"
[[ "$(tail -n 1 <<<"$out")" =~ ^DONE\ state=created\ branch=work/[a-z]+-[a-z]+\ from=main$ ]] || fail "todo only: $out"
pass "changes only to todo files still get a random work/ branch"

new_repo
printf 'todo\n' > "$repo/TODO.md"
printf 'x\n' > "$repo/new.txt"
out="$(run '')"
[[ "$(head -n 1 <<<"$out")" == "NEED_NAME on=main" ]] || fail "todo plus change: $out"
grep -q 'new.txt' <<<"$out" || fail "real change missing: $out"
grep -q 'TODO.md' <<<"$out" && fail "todo file shown to the model: $out"
[[ "$(on)" == main ]] || fail "preflight must not switch"
pass "todo files are left out of the status the model names from"

new_repo
printf 'x\n' > "$repo/new.txt"
out="$(run '')"
[[ "$(head -n 1 <<<"$out")" == "NEED_NAME on=main" ]] || fail "need name: $out"
grep -q -- '^--- write$' <<<"$out" || fail "write block missing: $out"
grep -q '^branch: 3 distinct.*use only work/[a-z]*-[a-z]*\.$' <<<"$out" || fail "branch rule missing: $out"
out="$(run 'add a login page')"
grep -q '^NEED_NAME on=main hint=' <<<"$out" || fail "hint: $out"
grep -q 'new.txt' <<<"$out" || fail "status missing: $out"
[[ "$(on)" == main ]] || fail "preflight must not switch"
pass "missing or plain-language names ask the model with minimal context"

git -C "$repo" branch feat/taken
git -C "$repo" update-ref refs/remotes/origin/feat/remote HEAD
out="$(run --create 'bad..name' feat/taken feat/remote feat/free)"
[[ "$(tail -n 1 <<<"$out")" == "DONE state=created branch=feat/free from=main" ]] || fail "skip: $out"
pass "invalid and taken candidates are skipped in order"

new_repo
printf 'x\n' > "$repo/new.txt"
out="$(run --random)"
[[ "$(tail -n 1 <<<"$out")" =~ ^DONE\ state=created\ branch=work/[a-z]+-[a-z]+\ from=main$ ]] || fail "--random: $out"
[[ "$(on)" == work/* ]] || fail "--random not checked out"
pass "--random creates a random work/ branch even with changes"

new_repo
git -C "$repo" branch feat/a
git -C "$repo" branch feat/a-2
out="$(run --create feat/a)"
[[ "$(tail -n 1 <<<"$out")" == "DONE state=created branch=feat/a-3 from=main" ]] || fail "suffix: $out"
pass "all-taken candidates fall back to a numeric suffix"

new_repo
out="$(run --create 'bad..name')"
[[ "$out" == $'error: failed to create a feature branch: no valid branch name candidate\nDONE state=failed report=no valid branch name candidate' ]] ||
  fail "invalid: $out"
git -C "$repo" switch -q --detach
out="$(run feat/x)"
[[ "$out" == $'error: failed to create a feature branch: detached HEAD\nDONE state=failed report=detached HEAD' ]] || fail "detached: $out"
pass "invalid candidates and detached HEAD fail without changes"

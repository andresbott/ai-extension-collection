#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAG_SCRIPT="$SCRIPT_DIR/gitauto-tag.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
roots=(); cleanup() { if ((${#roots[@]})); then rm -rf "${roots[@]}"; fi; }; trap cleanup EXIT

new_fixture() {
  root="$(mktemp -d)"; roots+=("$root")
  repo="$root/repo"; remote="$root/remote.git"
  git init -q --bare "$remote"; git --git-dir="$remote" symbolic-ref HEAD refs/heads/main
  git init -q -b main "$repo"
  git -C "$repo" config user.name "Gitauto Test"; git -C "$repo" config user.email gitauto@example.invalid
  printf 'base\n' > "$repo/README.md"; git -C "$repo" add README.md; git -C "$repo" commit -qm init
  git -C "$repo" remote add origin "$remote"; git -C "$repo" push -qu origin main
  git -C "$repo" tag v1.2.3
}

add_tag_target() {
  cat > "$repo/Makefile" <<'MAKE'
tag:
	@printf '%s\n' "$(VERSION)" > tag.out
MAKE
}

new_fixture
output="$( (cd "$repo" && "$TAG_SCRIPT") 2>&1)" || fail "missing target should return safely: $output"
[[ "$output" == *'state=blocked'* ]] || fail "missing tag target was not blocked: $output"
printf 'PASS: repository without make tag is blocked\n'

new_fixture; add_tag_target
git -C "$repo" switch -qc feat/release
output="$( (cd "$repo" && "$TAG_SCRIPT" 'version=v1.3.0') 2>&1)" || fail "feature branch should return safely: $output"
[[ "$output" == *'state=blocked'* && ! -e "$repo/tag.out" ]] || fail "feature branch was not blocked: $output"
printf 'PASS: feature branch cannot publish a tag\n'

new_fixture; add_tag_target
updater="$root/updater"; git clone -q "$remote" "$updater"
git -C "$updater" config user.name "Remote Test"; git -C "$updater" config user.email remote@example.invalid
printf 'remote\n' >> "$updater/README.md"; git -C "$updater" commit -qam remote; git -C "$updater" push -q origin main
output="$( (cd "$repo" && "$TAG_SCRIPT" 'version=v1.3.0') 2>&1)" || fail "stale main should return safely: $output"
[[ "$output" == *'state=blocked'* && ! -e "$repo/tag.out" ]] || fail "stale main was not blocked: $output"
printf 'PASS: stale local main cannot publish a tag\n'

for version in nope v1.2.3 v1.2.2; do
  new_fixture; add_tag_target
  set +e
  output="$( (cd "$repo" && "$TAG_SCRIPT" "version=$version") 2>&1)"
  status=$?
  set -e
  [[ $status -ne 0 && "$output" == *'state=failed'* && ! -e "$repo/tag.out" ]] || fail "invalid version $version was not rejected: status=$status output=$output"
done
printf 'PASS: malformed and non-increasing versions are rejected\n'

new_fixture; add_tag_target
output="$( (cd "$repo" && "$TAG_SCRIPT" 'subject=feat: add release flow') 2>&1)" || fail "recommendation failed: $output"
[[ "$output" == *'state=recommended'* && "$output" == *'version=v1.3.0'* && ! -e "$repo/tag.out" ]] || fail "minor recommendation mismatch: $output"
printf 'PASS: missing version recommends without publishing\n'

new_fixture; add_tag_target
output="$( (cd "$repo" && "$TAG_SCRIPT" 'version=v1.3.0') 2>&1)" || fail "explicit tag failed: $output"
[[ "$output" == *'state=tagged'* && "$(cat "$repo/tag.out")" == v1.3.0 ]] || fail "explicit version was not passed to make tag: $output"
printf 'PASS: explicit increasing SemVer invokes make tag exactly\n'

new_fixture; add_tag_target
git -C "$repo" branch feat/release
git -C "$repo" worktree add -q "$root/feature" feat/release
output="$( (cd "$root/feature" && "$TAG_SCRIPT" "worktree=$repo" 'version=v1.3.0') 2>&1)" || fail "primary-worktree tag failed: $output"
[[ "$output" == *'state=tagged'* && "$(cat "$repo/tag.out")" == v1.3.0 ]] || fail "tag did not run in supplied primary worktree: $output"
[[ ! -e "$root/feature/tag.out" ]] || fail "tag target ran in feature worktree"
printf 'PASS: explicit tag runs in supplied synchronized primary worktree\n'

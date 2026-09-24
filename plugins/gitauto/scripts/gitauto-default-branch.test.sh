#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
roots=(); cleanup() { if ((${#roots[@]})); then rm -rf "${roots[@]}"; fi; }; trap cleanup EXIT

new_trunk_fixture() {
  root="$(mktemp -d)"; roots+=("$root")
  repo="$root/repo"; remote="$root/remote.git"; bin="$root/bin"; log="$root/gh.log"
  mkdir -p "$bin"
  git init -q --bare "$remote"; git --git-dir="$remote" symbolic-ref HEAD refs/heads/trunk
  git init -q -b trunk "$repo"
  git -C "$repo" config user.name "Gitauto Test"; git -C "$repo" config user.email gitauto@example.invalid
  printf 'base\n' > "$repo/README.md"; git -C "$repo" add README.md; git -C "$repo" commit -qm init
  git -C "$repo" remote add origin "$remote"; git -C "$repo" push -qu origin trunk
  git -C "$repo" update-ref -d refs/remotes/origin/HEAD || true
  cat > "$bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$GH_LOG"
case "${1:-} ${2:-}" in
  'auth status') exit 0 ;;
  'repo view') printf 'trunk\n' ;;
  'pr view') printf '42\tOPEN\ttrunk\n' ;;
  'pr checks') printf 'green\n' ;;
  'pr merge') exit 0 ;;
  'pr create') printf 'https://example.invalid/pr/42\n' ;;
  *) printf 'unexpected gh command: %s\n' "$*" >&2; exit 9 ;;
esac
GH
  chmod +x "$bin/gh"
}

new_trunk_fixture
printf 'change\n' >> "$repo/README.md"
output="$( (cd "$repo" && "$SCRIPT_DIR/gitauto-branch.sh") 2>&1)" || fail "branch helper failed: $output"
[[ "$(git -C "$repo" branch --show-current)" != trunk ]] || fail "branch helper left work on custom default trunk: $output"
printf 'PASS: branch helper leaves a custom default branch\n'

new_trunk_fixture
printf 'change\n' >> "$repo/README.md"
before="$(git -C "$repo" rev-parse HEAD)"
output="$( (cd "$repo" && "$SCRIPT_DIR/gitauto-commit.sh" 'feat: forbidden') 2>&1)" || fail "commit guard should return safely: $output"
[[ "$output" == *'state=blocked'* && "$(git -C "$repo" rev-parse HEAD)" == "$before" ]] || fail "commit occurred on custom default: $output"
printf 'PASS: commit blocks a custom default branch\n'

new_trunk_fixture
output="$( (cd "$repo" && "$SCRIPT_DIR/gitauto-push.sh") 2>&1)" || fail "push guard should return safely: $output"
[[ "$output" == *'state=blocked'* ]] || fail "push did not block uncached custom default: $output"
printf 'PASS: push blocks custom default without cached remote HEAD\n'

new_trunk_fixture
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" "$SCRIPT_DIR/gitauto-open-pr.sh" 'title=x' 'body=y') 2>&1)" || fail "open-pr guard should return safely: $output"
[[ "$output" == *'state=blocked'* && ! -s "$log" ]] || fail "open-pr called GitHub from custom default: $output"
printf 'PASS: open-pr blocks a custom default branch\n'

new_trunk_fixture
output="$( (cd "$repo" && PATH="$bin:$PATH" GH_LOG="$log" "$SCRIPT_DIR/gitauto-merge.sh" 'pr=42' 'subject=feat: forbidden') 2>&1)" || fail "merge guard should return safely: $output"
[[ "$output" == *'state=blocked'* && ! -s "$log" ]] || fail "merge called GitHub from custom default: $output"
printf 'PASS: merge blocks a custom default branch\n'

new_trunk_fixture
output="$( (cd "$repo" && "$SCRIPT_DIR/gitauto-cleanup.sh" 'branch=trunk' 'deleteRemote=true') 2>&1)" || fail "cleanup guard should return safely: $output"
[[ "$output" == *'state=blocked'* ]] || fail "cleanup did not block custom default: $output"
git --git-dir="$remote" show-ref --verify --quiet refs/heads/trunk || fail "cleanup deleted custom default remote branch"
printf 'PASS: cleanup cannot delete a custom default branch\n'

new_trunk_fixture
cat > "$repo/Makefile" <<'MAKE'
tag:
	@printf '%s\n' "$(VERSION)" > tag.out
MAKE
git -C "$repo" tag v1.0.0
output="$( (cd "$repo" && "$SCRIPT_DIR/gitauto-tag.sh") 2>&1)" || fail "tag recommendation on custom default failed: $output"
[[ "$output" == *'state=recommended'* ]] || fail "tag helper rejected the actual custom default: $output"
printf 'PASS: tag accepts only the resolved custom default branch\n'

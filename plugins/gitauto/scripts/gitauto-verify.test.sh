#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFY_SCRIPT="$SCRIPT_DIR/gitauto-verify.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

new_repo() {
  local repo
  repo="$(mktemp -d)"
  git -C "$repo" init -q -b feat/verify
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

repo="$(new_repo)"
repos+=("$repo")
output="$( (cd "$repo" && "$VERIFY_SCRIPT" "printf 'explicit-ok\\n'") 2>&1)" || fail "explicit check should pass: $output"
[[ "$output" == *"command=printf 'explicit-ok\\n'"* ]] || fail "explicit command was not reported: $output"
[[ "$output" == *"explicit-ok"* ]] || fail "explicit command did not run: $output"
[[ "$output" == *"state=pass"* ]] || fail "explicit check did not return pass: $output"

printf 'PASS: explicit requested check runs and is reported\n'

repo="$(new_repo)"
repos+=("$repo")
cat > "$repo/Makefile" <<'MAKE'
custom-check:
	@printf 'custom-target\n' > target.log
MAKE
output="$( (cd "$repo" && "$VERIFY_SCRIPT" "target=custom-check") 2>&1)" || fail "explicit target should pass: $output"
[[ "$(cat "$repo/target.log")" == "custom-target" ]] || fail "explicit Make target did not run"
[[ "$output" == *"command=make custom-check"* ]] || fail "explicit target was not reported: $output"
[[ "$output" == *"state=pass"* ]] || fail "explicit target did not return pass: $output"

printf 'PASS: explicit requested Make target runs and is reported\n'

repo="$(new_repo)"
repos+=("$repo")
cat > "$repo/Makefile" <<'MAKE'
verify:
	@printf 'verify\n' >> commands.log
test:
	@printf 'test\n' >> commands.log
MAKE
output="$( (cd "$repo" && "$VERIFY_SCRIPT") 2>&1)" || fail "verify target should pass: $output"
[[ "$(cat "$repo/commands.log")" == "verify" ]] || fail "verify was not preferred: $(cat "$repo/commands.log")"
[[ "$output" == *"command=make verify"* ]] || fail "verify target was not reported: $output"
[[ "$output" == *"state=pass"* ]] || fail "verify target did not return pass: $output"

printf 'PASS: root Makefile verify target is preferred\n'

repo="$(new_repo)"
repos+=("$repo")
cat > "$repo/Makefile" <<'MAKE'
test:
	@printf 'test\n' >> commands.log
lint:
	@printf 'lint\n' >> commands.log
	@false
vet:
	@printf 'vet\n' >> commands.log
MAKE
set +e
output="$( (cd "$repo" && "$VERIFY_SCRIPT") 2>&1)"
status=$?
set -e
[[ $status -ne 0 ]] || fail "failing lint target should fail verification"
[[ "$(cat "$repo/commands.log")" == $'test\nlint' ]] || fail "checks did not stop after lint: $(cat "$repo/commands.log")"
[[ "$output" == *"command=make test"* ]] || fail "test target was not reported: $output"
[[ "$output" == *"command=make lint"* ]] || fail "lint target was not reported: $output"
[[ "$output" == *"state=fail"* ]] || fail "failure state was not reported: $output"

printf 'PASS: declared local Make targets run sequentially and stop on failure\n'

repo="$(new_repo)"
repos+=("$repo")
cat > "$repo/package.json" <<'JSON'
{
  "scripts": {
    "test": "printf 'package-test\\n'",
    "lint": "printf 'package-lint\\n'"
  }
}
JSON
output="$( (cd "$repo" && "$VERIFY_SCRIPT") 2>&1)" || fail "declared package checks should pass: $output"
[[ "$output" == *"command=npm test"* ]] || fail "npm test was not reported: $output"
[[ "$output" == *"command=npm run lint"* ]] || fail "npm lint was not reported: $output"
[[ "$output" == *"package-test"* && "$output" == *"package-lint"* ]] || fail "package checks did not run: $output"
[[ "$output" == *"state=pass"* ]] || fail "package checks did not return pass: $output"

printf 'PASS: declared package scripts run as ecosystem checks\n'

repo="$(new_repo)"
repos+=("$repo")
cat > "$repo/go.mod" <<'EOF'
module example.invalid/gitauto

go 1.23
EOF
cat > "$repo/main.go" <<'EOF'
package main

func main() {}
EOF
output="$( (cd "$repo" && "$VERIFY_SCRIPT") 2>&1)" || fail "Go checks should pass: $output"
[[ "$output" == *"command=go test ./..."* ]] || fail "Go tests were not reported: $output"
[[ "$output" == *"command=go vet ./..."* ]] || fail "Go vet was not reported: $output"
[[ "$output" == *"state=pass"* ]] || fail "Go checks did not return pass: $output"

printf 'PASS: Go module runs standard test and vet checks\n'

repo="$(new_repo)"
repos+=("$repo")
before_branch="$(git -C "$repo" branch --show-current)"
before_head="$(git -C "$repo" rev-parse HEAD)"
before_status="$(git -C "$repo" status --porcelain=v1)"
output="$( (cd "$repo" && "$VERIFY_SCRIPT") 2>&1)" || fail "repository with no checks should skip: $output"
[[ "$output" == *"state=skip"* ]] || fail "skip state was not reported: $output"
[[ "$output" == *"report=no verification checks discovered"* ]] || fail "skip reason was not reported: $output"
[[ "$(git -C "$repo" branch --show-current)" == "$before_branch" ]] || fail "verify changed branches"
[[ "$(git -C "$repo" rev-parse HEAD)" == "$before_head" ]] || fail "verify created a commit"
[[ "$(git -C "$repo" status --porcelain=v1)" == "$before_status" ]] || fail "verify changed the worktree or index"

printf 'PASS: missing checks skip without changing repository state\n'

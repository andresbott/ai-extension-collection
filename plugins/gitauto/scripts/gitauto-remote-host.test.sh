#!/usr/bin/env bash
# Tests for gitauto_remote_host and gitauto_gh_authenticated: gh auth is checked
# against the origin's host only, not every host gh is logged in to.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/gitauto-lib.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
root="$(mktemp -d)"; trap 'rm -rf "$root"' EXIT
bin="$root/bin"; mkdir -p "$bin"
cp "$SCRIPT_DIR/testdata/fake-ssh" "$bin/ssh"
# Only a github.com login works; checking any wider set of hosts fails, like a
# stale token on an unrelated GitHub Enterprise host.
cat > "$bin/gh" <<'GH'
#!/usr/bin/env bash
[[ "$*" == 'auth status --hostname github.com' ]]
GH
chmod +x "$bin/ssh" "$bin/gh"
export PATH="$bin:$PATH"
git init -q -b main "$root/repo"; cd "$root/repo"

host_of() {
  git remote remove origin 2>/dev/null || true
  git remote add origin "$1"
  gitauto_remote_host origin || printf '<none>'
}
check() {
  local got
  got="$(host_of "$1")"
  [[ "$got" == "$2" ]] || fail "$1: want $2, got $got"
}
check git@github.com:o/r.git github.com
check https://github.com/o/r.git github.com
check https://user:token@git.corp.example:8443/o/r.git git.corp.example
check ssh://git@github.com:22/o/r.git github.com
check git@work-alias:o/r.git github.com
check ssh://git@work-alias/o/r.git github.com
check "$root/remote.git" '<none>'
check ./dir/with:colon '<none>'
git remote remove origin
[[ "$(gitauto_remote_host origin || printf '<none>')" == '<none>' ]] || fail "a missing remote must have no host"
printf 'PASS: remote URLs map to the host gh uses, SSH aliases included\n'

host_of git@work-alias:o/r.git >/dev/null
gitauto_gh_authenticated origin || fail "a github.com origin must pass while another host's login is broken"
host_of https://git.corp.example/o/r.git >/dev/null
! gitauto_gh_authenticated origin || fail "an origin host without a login must fail"
printf 'PASS: gh auth is checked for the origin host only\n'

host_of "$root/remote.git" >/dev/null
! gitauto_gh_authenticated origin || fail "an unknown host must fall back to checking every host"
printf 'PASS: an origin with no host falls back to checking every host\n'

#!/usr/bin/env bash
# Tests for gitauto-account.sh: which gh account a clone uses, and when to ask.
# Fixtures live in $TMPDIR; gh and ssh are fakes (testdata/), so no network.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/gitauto-account.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }
roots=()
cleanup() { if ((${#roots[@]})); then rm -rf "${roots[@]}"; fi; }
trap cleanup EXIT
unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN GIT_SSH_COMMAND GIT_SSH FAKE_SSH_LOGIN
# A global url.<x>.insteadOf would rewrite the fixture remotes.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# A repo whose origin is <url>, gh logged in as <logins>, <pushers> able to push.
fixture() {
  local url="$1" logins="$2" pushers="$3" root
  root="$(mktemp -d)"; roots+=("$root")
  repo="$root/repo"; bin="$root/bin"; export FAKE_GH="$root/gh" FAKE_SSH_LOG="$root/ssh.log"
  mkdir -p "$bin" "$FAKE_GH"
  git init -q -b main "$repo"
  git -C "$repo" remote add origin "$url"
  cp "$SCRIPT_DIR/testdata/fake-gh" "$bin/gh"; cp "$SCRIPT_DIR/testdata/fake-ssh" "$bin/ssh"
  chmod +x "$bin/gh" "$bin/ssh"
  printf '%s' "$logins" > "$FAKE_GH/logins"
  printf '%s' "$pushers" > "$FAKE_GH/push"
  file="$repo/.git/gitauto.json"
}
account() { (cd "$repo" && PATH="$bin:$PATH" "$SCRIPT" "$@") || true; }
field() { sed -n "s/^$1=//p" <<< "$out"; }
expect() { # state account source
  [[ "$(field state)" == "$1" && "$(field account)" == "$2" && "$(field source)" == "$3" ]] ||
    fail "want state=$1 account=$2 source=$3, got: $out"
}

fixture "$(mktemp -d)/remote.git" 'a b' 'a'
out="$(account)"
[[ "$(field state)" == skip ]] || fail "local remote: $out"
[[ ! -s "$FAKE_GH/log" ]] || fail "a local remote must not call gh: $(cat "$FAKE_GH/log")"
pass "an origin without a GitHub host is skipped: gh picks as before"

fixture git@github.com:o/r.git 'a b' 'b'
out="$(cd "$repo" && PATH="$bin:$PATH" GH_TOKEN=x "$SCRIPT")"
expect resolved '' env
[[ ! -f "$file" ]] || fail "an env token must not be saved"
out="$(cd "$repo" && PATH="$bin:$PATH" GH_ENTERPRISE_TOKEN=x "$SCRIPT")"
expect resolved b access
pass "GH_TOKEN wins for github.com and is never saved; an enterprise token does not count there"

fixture git@github.com:o/r.git 'solo' ''
out="$(account)"
expect resolved solo only-login
[[ ! -f "$file" ]] || fail "the only login needs no saving"
! grep -q '^api ' "$FAKE_GH/log" || fail "the only login needs no probe"
pass "a single gh login is used without probing or saving"

fixture git@github.com:o/r.git 'a b c' 'a b'
out="$(FAKE_SSH_LOGIN=b account)"
expect resolved b ssh
[[ "$(jq -r .account "$file")" == b && "$(jq -r .source "$file")" == ssh ]] || fail "ssh choice not saved: $(cat "$file")"
[[ "$(jq -r .host "$file")/$(jq -r .repo "$file")/$(jq -r .version "$file")" == github.com/o/r/1 ]] || fail "file keys: $(cat "$file")"
jq -r '."$comment"' "$file" | grep -q 'gitauto.*plugins/gitauto#github-account' || fail "comment missing: $(cat "$file")"
grep -q -- '-T -o BatchMode=yes .* git@github.com$' "$FAKE_SSH_LOG" || fail "ssh check must not prompt: $(cat "$FAKE_SSH_LOG")"
pass "the login the SSH key belongs to is used and saved with a comment pointing at gitauto"

: > "$FAKE_SSH_LOG"
out="$(account)"
expect resolved b saved
[[ ! -s "$FAKE_SSH_LOG" ]] || fail "a saved account needs no SSH check"
pass "a saved account is reused without the SSH check"

printf 'a' > "$FAKE_GH/push"
out="$(account)"
expect resolved a access
[[ "$(jq -r .account "$file")" == a ]] || fail "lost access not re-derived: $(cat "$file")"
pass "a saved account that lost push access is worked out again"

printf '{ broken' > "$file"
out="$(account)"
expect resolved a access
jq -e '.account == "a"' "$file" >/dev/null || fail "broken file not rewritten: $(cat "$file")"
jq '.repo = "other/repo" | .account = "c"' "$file" > "$file.new" && mv "$file.new" "$file"
out="$(account)"
expect resolved a access
pass "an unreadable file, or one saved for another repo, is ignored and rewritten"

fixture git@github.com:o/r.git 'a b c' 'a c'
printf 'b' > "$FAKE_GH/read"
out="$(FAKE_SSH_LOGIN=b account)"
expect ask '' ''
[[ "$(field accounts)" == a,c ]] || fail "only accounts that can push are offered: $out"
[[ ! -f "$file" ]] || fail "nothing is saved before the user picks"
out="$(FAKE_SSH_LOGIN=o/r account)"
expect ask '' ''
pass "several accounts that can push are offered; a read-only SSH login or a deploy key decides nothing"

out="$(account choose=zz)"
[[ "$(field state)" == failed && "$(field report)" == 'zz is not logged in to gh on github.com (logged in: a,b,c)' ]] || fail "unknown login: $out"
out="$(account choose=b)"
[[ "$(field state)" == failed && "$(field report)" == 'b cannot push to o/r' ]] || fail "read-only choice: $out"
[[ ! -f "$file" ]] || fail "a refused choice must not be saved"
out="$(account choose=c)"
expect resolved c asked
[[ "$(jq -r .source "$file")" == asked ]] || fail "choice not saved: $(cat "$file")"
out="$(account)"
expect resolved c saved
pass "a choice is checked, saved, and then reused without asking"

fixture git@github.com:o/r.git 'a b' ''
out="$(account)"
[[ "$(field state)" == failed ]] || fail "nobody can push: $out"
[[ "$(field report)" == 'none of the gh accounts on github.com (a,b) can push to o/r; log in with one that can: gh auth login --hostname github.com' ]] ||
  fail "nobody report: $out"
touch "$FAKE_GH/apidown"
out="$(account)"
[[ "$(field state)" == failed && "$(field report)" == 'could not check every gh account: a: error connecting to api.github.com; b: error connecting to api.github.com' ]] ||
  fail "gh error: $out"
pass "no account that can push, or a gh error, fails with the reason"

fixture git@github.com:o/r.git '' ''
out="$(account)"
[[ "$(field state)" == failed && "$(field report)" == 'gh is not logged in to github.com; run gh auth login --hostname github.com' ]] || fail "no login: $out"
fixture git@github.com:o/r.git 'a b' 'a'
touch "$FAKE_GH/nojson"
out="$(account)"
[[ "$(field state)" == skip ]] || fail "old gh: $out"
pass "no login fails; a gh too old to list its accounts is skipped"

fixture ssh://git@work-alias:2222/o/r.git 'a b' 'a b'
out="$(FAKE_SSH_LOGIN=a account)"
expect resolved a ssh
grep -q -- '-p 2222 git@work-alias$' "$FAKE_SSH_LOG" || fail "ssh:// port and alias: $(cat "$FAKE_SSH_LOG")"
pass "an ssh:// remote is checked through its alias and port"

fixture git@github.com:o/r.git 'a b' 'a b'
cat > "$bin/custom-ssh" <<SH
#!/usr/bin/env bash
printf 'custom %s\n' "\$*" >> "$FAKE_SSH_LOG"
shift 2
FAKE_SSH_LOGIN=b exec "$bin/ssh" "\$@"
SH
chmod +x "$bin/custom-ssh"
git -C "$repo" config core.sshCommand "$bin/custom-ssh -i key"
out="$(account)"
expect resolved b ssh
grep -q '^custom -i key -T ' "$FAKE_SSH_LOG" || fail "core.sshCommand not used: $(cat "$FAKE_SSH_LOG")"
pass "the SSH check uses git's core.sshCommand"

fixture https://github.com/o/r.git 'a b' 'b'
out="$(FAKE_SSH_LOGIN=a account)"
expect resolved b access
[[ ! -s "$FAKE_SSH_LOG" ]] || fail "an HTTPS remote has no SSH key to check"
pass "an HTTPS remote skips the SSH check"

fixture git@git.corp.example:team/r.git 'a b' 'a'
out="$(account)"
expect resolved a access
[[ "$(field host)/$(field repo)" == git.corp.example/team/r ]] || fail "enterprise host: $out"
grep -q "^tok-a"$'\t'"api --hostname git.corp.example repos/team/r " "$FAKE_GH/tokens" || fail "enterprise probe: $(cat "$FAKE_GH/tokens")"
pass "a GitHub Enterprise host is probed with GH_ENTERPRISE_TOKEN"

fixture git@github.com:o/r.git 'a b' 'a'
git -C "$repo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init
git -C "$repo" worktree add -q "$repo-wt" 2>/dev/null
out="$( (cd "$repo-wt" && PATH="$bin:$PATH" "$SCRIPT") )"
expect resolved a access
[[ -f "$file" && ! -e "$repo-wt/.git/gitauto.json" ]] || fail "worktrees must share the main .git file"
pass "a linked worktree saves to the clone's shared .git directory"

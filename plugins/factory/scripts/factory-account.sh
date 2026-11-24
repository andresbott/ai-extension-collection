#!/usr/bin/env bash
# Pick the GitHub CLI account factory uses for this clone, so a repo only one of
# several logged-in gh accounts can push to works without `gh auth switch`.
#
#   factory-account.sh [remote=origin] [choose=<login>]
#
# Prints state= account= host= repo= source= accounts= report= lines:
#   resolved  use `account` (factory_export_account); source says how it was found:
#             env (a token variable is already set; account is empty), only-login,
#             saved, ssh, access, or asked (choose=)
#   ask       several logins can push to the repo; `accounts` lists them for the
#             user to pick, then re-run with choose=<login>
#   skip      no GitHub host, or a gh too old to list its logins: gh picks as before
#   failed    nothing usable; report says why (exit 2)
#
# Without choose=, the first single answer wins: a token variable, the saved
# choice, the only login, the login the remote's SSH key belongs to, then the
# one login with push access. "Can push", not "can see": every login can see a
# public repo, and ship needs write access to merge. A found account is saved to
# <git-common-dir>/factory.json (read and written with jq), so a later run, a
# resume, or another worktree reuses it; a fresh clone works it out again.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/factory-lib.sh"

COMMENT='Written by factory (https://github.com/andresbott/ai-extension-collection/tree/main/plugins/factory#github-account): the GitHub CLI account it uses for this clone. Edit "account" to change it, or delete this file to have factory work it out again.'

remote=origin; choose=''
for arg in "$@"; do
  case "$arg" in
    remote=*) remote="${arg#remote=}" ;;
    choose=*) choose="${arg#choose=}" ;;
    *) printf 'state=failed\nreport=unknown argument %s\n' "$arg"; exit 2 ;;
  esac
done

host=''; repo=''
result() { # state account source accounts report
  printf 'state=%s\naccount=%s\nhost=%s\nrepo=%s\nsource=%s\naccounts=%s\nreport=%s\n' \
    "$1" "$2" "$host" "$repo" "$3" "$4" "$5"
}
failed() { result failed '' '' "${2:-}" "$1"; exit 2; }

command -v gh >/dev/null 2>&1 || failed 'GitHub CLI (gh) is not installed'
if ! host="$(factory_remote_host "$remote")"; then
  host=''
  result skip '' '' '' "$remote has no GitHub host; gh picks the account"
  exit 0
fi
repo="$(factory_remote_repo "$remote")" || failed "the repository of $remote could not be read from its URL"
var="$(factory_token_var "$host")"

if [[ -z "$choose" ]]; then
  case "$var" in
    GH_TOKEN) env_var="${GH_TOKEN:+GH_TOKEN}"; env_var="${env_var:-${GITHUB_TOKEN:+GITHUB_TOKEN}}" ;;
    *) env_var="${GH_ENTERPRISE_TOKEN:+GH_ENTERPRISE_TOKEN}"; env_var="${env_var:-${GITHUB_ENTERPRISE_TOKEN:+GITHUB_ENTERPRISE_TOKEN}}" ;;
  esac
  if [[ -n "$env_var" ]]; then
    result resolved '' env '' "$env_var is set; gh uses it"
    exit 0
  fi
fi

command -v jq >/dev/null 2>&1 || failed 'jq is not installed; factory needs it for .git/factory.json'
file="$(factory_account_file)" || failed 'the git directory could not be found'

# 0: <login> can push to the repo; 1: it cannot (read-only, or a 404: GitHub
# hides repos a login has no access to); 2: the check itself was refused or
# failed (an IP allow list, unauthorized SSO, an expired token, a rate limit, a
# network error), with GitHub's message in $probe_error.
probe_error=''
can_push() {
  local token
  token="$(gh auth token --hostname "$host" --user "$1" 2>/dev/null)" || { probe_error="$1: gh has no token"; return 2; }
  factory_gh_capture env "$var=$token" gh api --hostname "$host" "repos/$repo" --jq '.permissions.push'
  if [[ $gh_status -eq 0 ]]; then
    [[ "$gh_out" == true ]]
    return
  fi
  grep -q 'HTTP 404' <<< "$gh_err" && return 1
  probe_error="$1: $(factory_gh_error "$gh_err")"
  return 2
}

save() { # account source
  local tmp
  tmp="$(mktemp "$file.XXXXXX")" &&
    jq -n --arg c "$COMMENT" --arg h "$host" --arg r "$repo" --arg a "$1" --arg s "$2" \
      --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{"$comment": $c, version: 1, host: $h, repo: $r, account: $a, source: $s, saved_at: $t}' > "$tmp" &&
    mv "$tmp" "$file" || { rm -f "${tmp:-}"; return 1; }
}
found() { # account source report
  local report="$3"
  save "$1" "$2" || report+="; $file could not be written"
  result resolved "$1" "$2" '' "$report"
  exit 0
}

# The saved choice, while that login still has a token and can push to this
# repo. Checked before listing the logins: `gh auth status` validates every
# token over the network, so this keeps a ship's usual case to one API call.
saved=''
[[ -n "$choose" || ! -f "$file" ]] ||
  saved="$(jq -r --arg h "$host" --arg r "$repo" \
    'select(type == "object" and .host == $h and .repo == $r) | .account | strings' "$file" 2>/dev/null || true)"
if [[ -n "$saved" ]] && gh auth token --hostname "$host" --user "$saved" >/dev/null 2>&1; then
  rc=0; can_push "$saved" || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    result resolved "$saved" saved '' "saved in $file"
    exit 0
  fi
  [[ "$rc" -eq 1 ]] || failed "could not check $probe_error"
fi

# Logged-in accounts with a working token. A gh without `auth status --json`
# cannot tell them apart, so it keeps picking the active one, as before.
if ! logins="$(gh auth status --hostname "$host" --json hosts \
    --jq ".hosts[\"$host\"][]? | select(.state == \"success\") | .login" 2>/dev/null)"; then
  result skip '' '' '' "gh cannot list its accounts (upgrade gh to pick one per repo); gh picks the account"
  exit 0
fi
listed="$(printf '%s\n' "$logins" | awk 'NF' | paste -sd, -)"
[[ -n "$listed" ]] || failed "gh is not logged in to $host; run gh auth login --hostname $host"
is_login() { [[ -n "$1" ]] && printf '%s\n' "$logins" | grep -qxF -- "$1"; }

if [[ -n "$choose" ]]; then
  is_login "$choose" || failed "$choose is not logged in to gh on $host (logged in: $listed)" "$listed"
  rc=0; can_push "$choose" || rc=$?
  case "$rc" in
    0) found "$choose" asked "$choose chosen for $repo" ;;
    1) failed "$choose cannot push to $repo" "$listed" ;;
    *) failed "could not check $probe_error" "$listed" ;;
  esac
fi

if [[ "$listed" != *,* ]]; then
  result resolved "$listed" only-login '' "the only gh login on $host"
  exit 0
fi

# The login the remote's SSH key belongs to: GitHub greets it by name. Uses the
# same ssh command as git, never prompts, and ignores deploy keys (owner/repo).
ssh_login() {
  local url target port='' cmd
  url="$(git remote get-url "$remote" 2>/dev/null)" || return 1
  case "$url" in
    ssh://*|git+ssh://*|ssh+git://*)
      target="${url#*://}"; target="${target%%/*}"
      if [[ "$target" =~ :([0-9]+)$ ]]; then port="${BASH_REMATCH[1]}"; target="${target%:*}"; fi ;;
    *://*) return 1 ;;
    *:*) [[ "${url%%:*}" != */* ]] || return 1; target="${url%%:*}" ;;
    *) return 1 ;;
  esac
  cmd="${GIT_SSH_COMMAND:-$(git config --get core.sshCommand 2>/dev/null || true)}"
  if [[ -z "$cmd" ]]; then cmd="$(printf '%q' "${GIT_SSH:-ssh}")"; fi
  local tmo
  tmo="$(command -v timeout || command -v gtimeout || true)"
  ${tmo:+"$tmo" 20} sh -c "$cmd \"\$@\"" factory-ssh -T -o BatchMode=yes -o ConnectTimeout=10 \
      ${port:+-p "$port"} "$target" </dev/null 2>&1 |
    sed -n 's/^Hi \([^! /]*\)! You.ve successfully authenticated.*/\1/p' | head -n 1
}
by_ssh="$(ssh_login || true)"
if is_login "$by_ssh"; then
  rc=0; can_push "$by_ssh" || rc=$?
  [[ "$rc" -ne 0 ]] || found "$by_ssh" ssh "$remote's SSH key belongs to $by_ssh"
fi

# Every login that can push; exactly one is the answer.
pushers=''; errors=''
while IFS= read -r login; do
  [[ -n "$login" ]] || continue
  rc=0; can_push "$login" || rc=$?
  case "$rc" in
    0) pushers+="${pushers:+,}$login" ;;
    1) ;;
    *) errors+="${errors:+; }$probe_error" ;;
  esac
done <<< "$logins"

# A failed check stops the run only when it leaves no account that can push:
# an account GitHub would not check could not push now anyway.
case "$pushers" in
  '')
    [[ -z "$errors" ]] || failed "no gh account on $host ($listed) is known to push to $repo; could not check $errors" "$listed"
    failed "none of the gh accounts on $host ($listed) can push to $repo; log in with one that can: gh auth login --hostname $host" "$listed" ;;
  *,*) result ask '' '' "$pushers" "several gh accounts can push to $repo; choose one${errors:+ (not checked: $errors)}"; exit 0 ;;
  *) found "$pushers" access "$pushers is the only gh account that can push to $repo${errors:+ (not checked: $errors)}" ;;
esac

#!/usr/bin/env bash

# Resolve a repository's default branch without mutating refs.
# Order: cached remote HEAD, remote HEAD symref, GitHub CLI, then local main/master
# only when the named remote is not configured.
gitauto_resolve_default_branch() {
  local remote="${1:-origin}" ref branch
  ref="$(git symbolic-ref --quiet "refs/remotes/$remote/HEAD" 2>/dev/null || true)"
  branch="${ref#refs/remotes/$remote/}"
  if [[ -n "$branch" ]]; then
    printf '%s\n' "$branch"
    return 0
  fi

  branch="$(git ls-remote --symref "$remote" HEAD 2>/dev/null | awk '$1 == "ref:" { sub("refs/heads/", "", $2); print $2; exit }')"
  if [[ -n "$branch" ]]; then
    printf '%s\n' "$branch"
    return 0
  fi

  if command -v gh >/dev/null 2>&1; then
    branch="$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || true)"
    if [[ -n "$branch" ]]; then
      printf '%s\n' "$branch"
      return 0
    fi
  fi

  if ! git remote get-url "$remote" >/dev/null 2>&1; then
    if git show-ref --verify --quiet refs/heads/main; then printf 'main\n'; return 0; fi
    if git show-ref --verify --quiet refs/heads/master; then printf 'master\n'; return 0; fi
  fi
  return 1
}

gitauto_remote_default_unresolved() {
  local remote="${1:-origin}"
  git remote get-url "$remote" >/dev/null 2>&1 && ! gitauto_resolve_default_branch "$remote" >/dev/null
}

gitauto_is_protected_branch() {
  local branch="$1" remote="${2:-origin}" default_branch
  [[ "$branch" == main || "$branch" == master ]] && return 0
  default_branch="$(gitauto_resolve_default_branch "$remote" 2>/dev/null || true)"
  [[ -n "$default_branch" && "$branch" == "$default_branch" ]]
}

# The host a remote points at, as gh sees it: an SSH config alias (Host work with
# HostName github.com) resolves to its real host through `ssh -G`, like gh does.
# Fails for a local-path remote or a missing one.
gitauto_remote_host() {
  local url host ssh=no real
  url="$(git remote get-url "${1:-origin}" 2>/dev/null)" || return 1
  case "$url" in
    *://*)
      host="${url#*://}"
      case "${url%%://*}" in *ssh*) ssh=yes ;; esac ;;
    *:*)
      # scp-like user@host:path; a slash before the first colon makes it a local path.
      [[ "${url%%:*}" != */* ]] || return 1
      host="${url%%:*}"; ssh=yes ;;
    *) return 1 ;;
  esac
  host="${host%%/*}"; host="${host##*@}"; host="${host%%:*}"
  [[ -n "$host" ]] || return 1
  if [[ "$ssh" == yes ]] && command -v ssh >/dev/null 2>&1; then
    real="$(ssh -G "$host" </dev/null 2>/dev/null | awk '$1 == "hostname" { print $2; exit }' || true)"
    host="${real:-$host}"
  fi
  printf '%s\n' "$host"
}

# The `owner/name` a remote points at, as GitHub names the repository: the URL's
# last two path segments, without `.git`. Fails for a local-path remote.
gitauto_remote_repo() {
  local url path
  url="$(git remote get-url "${1:-origin}" 2>/dev/null)" || return 1
  case "$url" in
    *://*) path="${url#*://}"; path="${path#*/}" ;;
    *:*) [[ "${url%%:*}" != */* ]] || return 1; path="${url#*:}" ;;
    *) return 1 ;;
  esac
  path="${path%/}"; path="${path%.git}"
  [[ "$path" == */* ]] || return 1
  printf '%s/%s\n' "$(basename "$(dirname "$path")")" "$(basename "$path")"
}

# The environment variable gh reads a token from for a host: GH_TOKEN for
# github.com and GHE.com tenants, GH_ENTERPRISE_TOKEN for GitHub Enterprise Server.
gitauto_token_var() {
  case "$1" in
    github.com|*.ghe.com) printf 'GH_TOKEN\n' ;;
    *) printf 'GH_ENTERPRISE_TOKEN\n' ;;
  esac
}

# The per-clone gitauto settings (the gh account, see gitauto-account.sh). It
# lives in the common git dir, so every worktree shares it and git never tracks it.
gitauto_account_file() {
  local dir
  dir="$(git rev-parse --git-common-dir 2>/dev/null)" || return 1
  printf '%s/gitauto.json\n' "$(cd "$dir" && pwd)"
}

# Point every later gh call of this process at <account> on <host>, without
# touching gh's global active account.
gitauto_export_account() {
  local host="$1" account="$2" var token
  var="$(gitauto_token_var "$host")"
  token="$(gh auth token --hostname "$host" --user "$account" 2>/dev/null)" || return 1
  [[ -n "$token" ]] || return 1
  export "$var=$token"
}

# The one line of a gh error worth reporting: its last non-empty line, trimmed.
gitauto_gh_error() {
  local line
  line="$(printf '%s\n' "$1" | awk 'NF { l = $0 } END { print l }' | tr -s '[:space:]' ' ')"
  line="${line# }"; line="${line% }"
  printf '%s\n' "${line:-gh gave no error message}" | cut -c1-300
}

# gh is installed and logged in to the remote's host. A bare `gh auth status`
# checks every host gh knows, so a stale login on an unrelated host (another
# GitHub Enterprise) would block this repo; it is only the fallback when the
# remote's host is unknown.
gitauto_gh_authenticated() {
  local host
  command -v gh >/dev/null 2>&1 || return 1
  if host="$(gitauto_remote_host "${1:-origin}")"; then
    gh auth status --hostname "$host" >/dev/null 2>&1
  else
    gh auth status >/dev/null 2>&1
  fi
}

# The writing rules for each text a script needs from a model, printed as a
# `--- write` block with one `<key>: <rule>` line per text. Every harness adapter
# hands this block to its model unchanged, so the rules live only here.
#   gitauto_write_rules branch title subject body message subject-from-title
gitauto_write_rules() {
  local key subject='one Conventional Commit line, type(scope): summary (types: feat fix docs style refactor perf test build ci chore revert; add ! for a breaking change). It is saved in the PR, becomes the squash-merge subject, and drives the release-tag bump.'
  [[ $# -gt 0 ]] || return 0
  printf -- '--- write\n'
  for key in "$@"; do
    case "$key" in
      branch) printf 'branch: 3 distinct, concise, lowercase branch names, each feat/, fix/, docs/, or chore/ plus a kebab-case slug, drawn from the args (or hint) and the listed changes; a branch name given in the args goes first; with neither, use work/<adjective>-<noun>.\n' ;;
      title) printf 'title: one plain, imperative prose line a reviewer can read (e.g. Add a discovery view for albums).\n' ;;
      subject) printf 'subject: %s\n' "$subject" ;;
      subject-from-title) printf 'subject: %s Reshape the pr_title line into it.\n' "$subject" ;;
      body) printf 'body: Markdown with only these sections: ## Summary (the why: the problem and its impact, 1-3 sentences), ## What (2-5 bullets of the changes that matter, not a file list), and an optional ## Notes (caveats or intentional non-changes). No tests section, no AI or tool attribution.\n' ;;
      message) printf 'message: one-line Conventional Commit message, type(scope): summary.\n' ;;
    esac
  done
}

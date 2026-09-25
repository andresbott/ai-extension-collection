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

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

#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/gitauto-lib.sh"

branch=''; remote=origin; delete_remote=false
for arg in "$@"; do
  case "$arg" in
    branch=*) branch="${arg#branch=}" ;;
    remote=*) remote="${arg#remote=}" ;;
    deleteRemote=*) delete_remote="${arg#deleteRemote=}" ;;
    *) printf 'state=failed\nremote_branch=unknown\nworktree=unknown\nlocal_branch=kept\nreport=unknown argument\n'; exit 2 ;;
  esac
done
[[ -n "$branch" ]] || branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
if [[ -z "$branch" ]] || gitauto_remote_default_unresolved "$remote" || gitauto_is_protected_branch "$branch" "$remote"; then
  printf 'state=blocked\nremote_branch=kept\nworktree=kept\nlocal_branch=kept\nreport=cleanup requires a feature branch\n'
  exit 0
fi
if [[ "$delete_remote" != true && "$delete_remote" != false ]]; then
  printf 'state=failed\nremote_branch=unknown\nworktree=unknown\nlocal_branch=kept\nreport=deleteRemote must be true or false\n'
  exit 2
fi

remote_state=kept
partial=false
git fetch "$remote" --prune >/dev/null 2>&1 || partial=true
if [[ "$delete_remote" == true ]]; then
  if git ls-remote --exit-code --heads "$remote" "refs/heads/$branch" >/dev/null 2>&1; then
    if git push "$remote" --delete "$branch" >&2; then
      remote_state=deleted
    else
      remote_state=failed
      partial=true
    fi
  else
    remote_state=absent
  fi
fi

worktree_path="$(git worktree list --porcelain | awk -v target="refs/heads/$branch" '
  /^worktree / { path = substr($0, 10) }
  /^branch / && $2 == target { print path; exit }
')"
worktree_state=absent
if [[ -n "$worktree_path" ]]; then
  active="$(git rev-parse --show-toplevel)"
  if [[ "$worktree_path" == "$active" ]]; then
    worktree_state=deferred-active
    partial=true
  elif [[ -n "$(git -C "$worktree_path" status --porcelain=v1)" ]]; then
    worktree_state=deferred-dirty
    partial=true
  elif git worktree remove "$worktree_path" >&2; then
    git worktree prune
    worktree_state=removed
  else
    worktree_state=failed
    partial=true
  fi
fi

state=clean
report='cleanup completed; local branch kept'
if [[ "$partial" == true ]]; then
  state=partial
  report='cleanup partially completed; local branch kept'
fi
printf 'state=%s\nremote_branch=%s\nworktree=%s\nlocal_branch=kept\nreport=%s\n' "$state" "$remote_state" "$worktree_state" "$report"

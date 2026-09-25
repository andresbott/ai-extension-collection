#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/gitauto-lib.sh"

remote="${1:-origin}"
remote="${remote#remote=}"
branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"

if [[ -z "$branch" ]]; then
  printf 'state=blocked\nbranch=detached\nremote=%s\nreport=pushes are blocked on detached HEAD\n' "$remote"
  exit 0
fi

if gitauto_remote_default_unresolved "$remote" || gitauto_is_protected_branch "$branch" "$remote"; then
  printf 'state=blocked\nbranch=%s\nremote=%s\nreport=pushes are blocked on the default branch\n' "$branch" "$remote"
  exit 0
fi

if [[ -z "$remote" || "$remote" == -* ]] || ! git remote get-url "$remote" >/dev/null 2>&1; then
  printf 'state=failed\nbranch=%s\nremote=%s\nreport=remote is missing or invalid\n' "$branch" "$remote"
  exit 2
fi

branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
if [[ -z "$branch" ]] || gitauto_remote_default_unresolved "$remote" || gitauto_is_protected_branch "$branch" "$remote"; then
  printf 'state=blocked\nbranch=%s\nremote=%s\nreport=branch safety check failed immediately before push\n' "${branch:-detached}" "$remote"
  exit 0
fi

git push -u "$remote" "$branch" >&2
printf 'state=pushed\nbranch=%s\nremote=%s\nreport=feature branch pushed with upstream\n' "$branch" "$remote"

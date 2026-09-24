#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/gitauto-lib.sh"

branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
if [[ -z "$branch" ]]; then
  printf 'state=blocked\n'
  printf 'branch=detached\n'
  printf 'report=commits are blocked on detached HEAD\n'
  exit 0
fi

if gitauto_remote_default_unresolved origin || gitauto_is_protected_branch "$branch" origin; then
  printf 'state=blocked\n'
  printf 'branch=%s\n' "$branch"
  printf 'report=commits are blocked on protected branches\n'
  exit 0
fi

if [[ -z "$(git status --porcelain=v1)" ]]; then
  printf 'state=unchanged\n'
  printf 'branch=%s\n' "$branch"
  printf 'report=working tree is clean\n'
  exit 0
fi

message="${1:-}"
message="${message#message=}"
if [[ -z "$message" || "$message" == *$'\n'* || "$message" == *$'\r'* ]]; then
  printf 'state=failed\n'
  printf 'report=a non-empty one-line commit message is required\n'
  exit 2
fi

branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
if [[ -z "$branch" ]] || gitauto_remote_default_unresolved origin || gitauto_is_protected_branch "$branch" origin; then
  printf 'state=blocked\n'
  printf 'branch=%s\n' "${branch:-detached}"
  printf 'report=branch safety check failed immediately before staging\n'
  exit 0
fi
git add -A
git commit -m "$message" >&2
printf 'state=committed\n'
printf 'branch=%s\n' "$branch"
printf 'message=%s\n' "$message"

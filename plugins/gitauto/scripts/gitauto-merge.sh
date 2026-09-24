#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/gitauto-lib.sh"

pr=''; subject=''
for arg in "$@"; do
  case "$arg" in
    pr=*) pr="${arg#pr=}" ;;
    subject=*) subject="${arg#subject=}" ;;
    *) printf 'state=failed\nnumber=\nbranch=\nsubject=\nreport=unknown argument\n'; exit 2 ;;
  esac
done

branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
if [[ -z "$branch" ]] || gitauto_remote_default_unresolved origin || gitauto_is_protected_branch "$branch" origin; then
  printf 'state=blocked\nnumber=%s\nbranch=%s\nsubject=\nreport=merges require a feature branch\n' "$pr" "${branch:-detached}"
  exit 0
fi

if [[ -z "$pr" ]]; then
  pr="$(gh pr view "$branch" --json number --jq '.number' 2>/dev/null || true)"
fi
if [[ ! "$pr" =~ ^[0-9]+$ ]]; then
  printf 'state=blocked\nnumber=\nbranch=%s\nsubject=\nreport=no pull request could be resolved\n' "$branch"
  exit 0
fi

view="$(gh pr view "$pr" --json number,state,headRefName --jq '[.number,.state,.headRefName]|@tsv' 2>/dev/null || true)"
if [[ -z "$view" ]]; then
  printf 'state=blocked\nnumber=%s\nbranch=%s\nsubject=\nreport=pull request is missing\n' "$pr" "$branch"
  exit 0
fi
IFS=$'\t' read -r number state head <<< "$view"
if [[ "$state" == MERGED ]]; then
  printf 'state=already-merged\nnumber=%s\nbranch=%s\nsubject=\nreport=pull request was already merged\n' "$number" "$head"
  exit 0
fi
if [[ "$state" != OPEN ]]; then
  printf 'state=blocked\nnumber=%s\nbranch=%s\nsubject=\nreport=pull request is not open\n' "$number" "$head"
  exit 0
fi
if [[ "$head" != "$branch" ]]; then
  printf 'state=blocked\nnumber=%s\nbranch=%s\nsubject=\nreport=pull request head does not match current branch\n' "$number" "$branch"
  exit 0
fi

if [[ -z "$subject" || "$subject" == *$'\n'* || "$subject" == *$'\r'* || ! "$subject" =~ ^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-zA-Z0-9._/-]+\))?(!)?:[[:space:]]+[^[:space:]].*$ ]]; then
  printf 'state=failed\nnumber=%s\nbranch=%s\nsubject=\nreport=a valid one-line Conventional Commit subject is required\n' "$number" "$branch"
  exit 2
fi

set +e
checks="$(gh pr checks "$pr" 2>&1)"
checks_status=$?
set -e
[[ -z "$checks" ]] || printf '%s\n' "$checks" >&2
if [[ $checks_status -ne 0 ]] && ! printf '%s' "$checks" | grep -qiE 'no checks|no check runs'; then
  printf 'state=blocked\nnumber=%s\nbranch=%s\nsubject=\nreport=CI checks are not green\n' "$number" "$branch"
  exit 0
fi

branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
if [[ -z "$branch" || "$branch" != "$head" ]] || gitauto_remote_default_unresolved origin || gitauto_is_protected_branch "$branch" origin; then
  printf 'state=blocked\nnumber=%s\nbranch=%s\nsubject=\nreport=branch safety check failed immediately before merge\n' "$number" "${branch:-detached}"
  exit 0
fi

gh pr merge "$pr" --squash --subject "$subject (#$pr)" --body "" >&2
printf 'state=merged\nnumber=%s\nbranch=%s\nsubject=%s (#%s)\nreport=pull request squash-merged\n' "$number" "$branch" "$subject" "$pr"

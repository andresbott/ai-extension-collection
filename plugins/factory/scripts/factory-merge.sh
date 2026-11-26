#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/factory-lib.sh"

pr=''; subject=''
for arg in "$@"; do
  case "$arg" in
    pr=*) pr="${arg#pr=}" ;;
    subject=*) subject="${arg#subject=}" ;;
    *) printf 'state=failed\nnumber=\nbranch=\nsubject=\nreport=unknown argument\n'; exit 2 ;;
  esac
done

branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
if [[ -z "$branch" ]] || factory_remote_default_unresolved origin || factory_is_protected_branch "$branch" origin; then
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

# A flaky GitHub call must not read as a missing PR: retry it, and report gh's error.
attempt=1
while :; do
  factory_gh_capture gh pr view "$pr" --json number,state,headRefName --jq '[.number,.state,.headRefName]|@tsv'
  [[ -z "$gh_err" ]] || printf '%s\n' "$gh_err" >&2
  [[ $gh_status -ne 0 ]] || break
  if grep -qiE 'could not resolve to a PullRequest' <<< "$gh_err"; then
    printf 'state=blocked\nnumber=%s\nbranch=%s\nsubject=\nreport=pull request does not exist\n' "$pr" "$branch"
    exit 0
  fi
  if (( attempt >= ${FACTORY_GH_ATTEMPTS:-3} )); then
    printf 'state=failed\nnumber=%s\nbranch=%s\nsubject=\nreport=pull request lookup failed: %s\n' "$pr" "$branch" "$(factory_gh_error "$gh_err")"
    exit 2
  fi
  attempt=$((attempt + 1))
  sleep "${FACTORY_GH_RETRY_DELAY:-5}"
done
IFS=$'\t' read -r number state head <<< "$gh_out"
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
if base="$(factory_pr_conflicts "$number")"; then
  printf 'state=conflict\nnumber=%s\nbranch=%s\nsubject=\nreport=%s\n' "$number" "$branch" "$(factory_conflict_report "$number" "$base")"
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
# gh exits 8 while checks are pending: not a failure, so the caller can wait again.
if [[ $checks_status -eq 8 ]]; then
  printf 'state=pending\nnumber=%s\nbranch=%s\nsubject=\nreport=CI checks are still pending\n' "$number" "$branch"
  exit 0
fi
if [[ $checks_status -ne 0 ]] && ! printf '%s' "$checks" | grep -qiE 'no checks|no check runs'; then
  printf 'state=blocked\nnumber=%s\nbranch=%s\nsubject=\nreport=CI checks are not green\n' "$number" "$branch"
  exit 0
fi

branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
if [[ -z "$branch" || "$branch" != "$head" ]] || factory_remote_default_unresolved origin || factory_is_protected_branch "$branch" origin; then
  printf 'state=blocked\nnumber=%s\nbranch=%s\nsubject=\nreport=branch safety check failed immediately before merge\n' "$number" "${branch:-detached}"
  exit 0
fi

factory_gh_capture gh pr merge "$pr" --squash --subject "$subject (#$pr)" --body ""
[[ -z "$gh_out" ]] || printf '%s\n' "$gh_out" >&2
[[ -z "$gh_err" ]] || printf '%s\n' "$gh_err" >&2
if [[ $gh_status -ne 0 ]]; then
  # The base can move after the check above, so gh can still refuse for a conflict.
  if grep -qiE 'merge conflict|not mergeable' <<< "$gh_err"; then
    base="$(gh pr view "$pr" --json baseRefName --jq .baseRefName 2>/dev/null || true)"
    printf 'state=conflict\nnumber=%s\nbranch=%s\nsubject=\nreport=%s\n' "$number" "$branch" \
      "$(factory_conflict_report "$number" "${base:-the base branch}")"
    exit 0
  fi
  printf 'state=failed\nnumber=%s\nbranch=%s\nsubject=\nreport=merge failed: %s\n' "$number" "$branch" "$(factory_gh_error "$gh_err")"
  exit 2
fi
printf 'state=merged\nnumber=%s\nbranch=%s\nsubject=%s (#%s)\nreport=pull request squash-merged\n' "$number" "$branch" "$subject" "$pr"

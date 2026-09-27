#!/usr/bin/env bash
set -euo pipefail

pr="${1:-}"
pr="${pr#pr=}"
if [[ -z "$pr" ]]; then
  branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [[ -z "$branch" ]]; then
    printf 'state=blocked\nnumber=\nreport=cannot resolve a pull request from detached HEAD\n'
    exit 0
  fi
  pr="$(gh pr view "$branch" --json number --jq '.number' 2>/dev/null || true)"
fi

if [[ ! "$pr" =~ ^[0-9]+$ ]]; then
  printf 'state=blocked\nnumber=\nreport=no pull request could be resolved\n'
  exit 0
fi

no_checks() { printf '%s' "$1" | grep -qiE 'no checks|no check runs'; }

# A new PR has no checks until GitHub registers its first run (a pull_request
# workflow only starts once the PR exists), and gh says "no checks" until then.
# Keep asking for GITAUTO_CHECKS_GRACE seconds before calling the PR check-less.
grace="${GITAUTO_CHECKS_GRACE:-60}"
start=$SECONDS
while :; do
  set +e
  summary="$(gh pr checks "$pr" --watch --interval "${GITAUTO_CHECKS_INTERVAL:-30}" 2>&1)"
  status=$?
  set -e
  if [[ $status -eq 0 ]] || ! no_checks "$summary" || (( SECONDS - start >= grace )); then break; fi
  sleep "${GITAUTO_CHECKS_GRACE_INTERVAL:-5}"
done
[[ -z "$summary" ]] || printf '%s\n' "$summary" >&2

if [[ $status -eq 0 ]]; then
  printf 'state=green\nnumber=%s\nreport=all configured checks passed\n' "$pr"
  exit 0
fi
if no_checks "$summary"; then
  printf 'state=none\nnumber=%s\nreport=no CI checks are configured\n' "$pr"
  exit 0
fi
if [[ $status -eq 8 ]]; then
  printf 'state=pending\nnumber=%s\nreport=CI checks are still pending\n' "$pr"
  exit 0
fi
printf 'state=failed\nnumber=%s\nreport=one or more CI checks failed\n' "$pr"
exit "$status"

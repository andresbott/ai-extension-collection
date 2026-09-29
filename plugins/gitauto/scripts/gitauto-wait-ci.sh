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
# gh exits 1 both when a check failed and when it lost GitHub mid-watch (a reset
# connection), so a non-zero watch is confirmed against the check states. gh
# errors are retried GITAUTO_CHECKS_RETRIES times before giving up.
retries="${GITAUTO_CHECKS_RETRIES:-3}"
errors=0
error=''
start=$SECONDS
while :; do
  set +e
  summary="$(gh pr checks "$pr" --watch --interval "${GITAUTO_CHECKS_INTERVAL:-30}" 2>&1)"
  status=$?
  set -e
  [[ -z "$summary" ]] || printf '%s\n' "$summary" >&2
  [[ $status -ne 0 && $status -ne 8 ]] || break
  if no_checks "$summary"; then
    (( SECONDS - start < grace )) || break
    sleep "${GITAUTO_CHECKS_GRACE_INTERVAL:-5}"
    continue
  fi
  set +e
  buckets="$(gh pr checks "$pr" --json bucket --jq '.[].bucket' 2>&1)"
  bstatus=$?
  set -e
  if [[ $bstatus -eq 0 ]]; then
    grep -qxE 'fail|cancel' <<< "$buckets" && break
    grep -qx pending <<< "$buckets" || { status=0; break; }
    error="$(tail -n 1 <<< "$summary")"
  else
    printf '%s\n' "$buckets" >&2
    error="$(tail -n 1 <<< "$buckets")"
  fi
  if (( ++errors > retries )); then
    printf 'state=error\nnumber=%s\nreport=could not read CI status (%s); re-run to resume\n' "$pr" "${error:-gh exited $status}"
    exit 1
  fi
  sleep "${GITAUTO_CHECKS_RETRY_INTERVAL:-10}"
done

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

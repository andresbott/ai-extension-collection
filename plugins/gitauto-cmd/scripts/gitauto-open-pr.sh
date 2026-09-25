#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/gitauto-lib.sh"

title=''; body=''; base=''
for arg in "$@"; do
  case "$arg" in
    title=*) title="${arg#title=}" ;;
    body=*) body="${arg#body=}" ;;
    base=*) base="${arg#base=}" ;;
    *) printf 'state=failed\nreport=unknown argument\n' >&2; exit 2 ;;
  esac
done

branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
if [[ -z "$branch" ]] || gitauto_remote_default_unresolved origin || gitauto_is_protected_branch "$branch" origin; then
  printf 'state=blocked\nnumber=\nurl=\nbranch=%s\nreport=pull requests require a feature branch\n' "${branch:-detached}"
  exit 0
fi

if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
  printf 'state=failed\nnumber=\nurl=\nbranch=%s\nreport=GitHub CLI is unavailable or unauthenticated\n' "$branch"
  exit 2
fi

if [[ -z "$base" ]]; then
  base="$(gitauto_resolve_default_branch origin 2>/dev/null || true)"
fi
if [[ -z "$base" ]]; then
  printf 'state=failed\nnumber=\nurl=\nbranch=%s\nreport=default branch could not be resolved safely\n' "$branch"
  exit 2
fi

set +e
view="$(gh pr view "$branch" --json number,state,url --jq '[.number,.state,.url]|@tsv' 2>&1)"
view_status=$?
set -e
if [[ $view_status -ne 0 ]]; then
  if printf '%s' "$view" | grep -qiE 'no pull requests found|could not resolve to a PullRequest'; then
    view=''
  else
    printf 'state=failed\nnumber=\nurl=\nbranch=%s\nreport=pull request lookup failed\n' "$branch"
    exit 2
  fi
fi
if [[ -n "$view" ]]; then
  IFS=$'\t' read -r number state url <<< "$view"
  case "$state" in
    OPEN)
      printf 'state=reused\nnumber=%s\nurl=%s\nbranch=%s\nreport=existing open pull request reused\n' "$number" "$url" "$branch"
      exit 0
      ;;
    MERGED)
      printf 'state=already-merged\nnumber=%s\nurl=%s\nbranch=%s\nreport=pull request was already merged\n' "$number" "$url" "$branch"
      exit 0
      ;;
    CLOSED)
      printf 'state=closed\nnumber=%s\nurl=%s\nbranch=%s\nreport=pull request is closed without merge\n' "$number" "$url" "$branch"
      exit 0
      ;;
    *)
      printf 'state=failed\nnumber=%s\nurl=%s\nbranch=%s\nreport=unexpected pull request state\n' "$number" "$url" "$branch"
      exit 2
      ;;
  esac
fi

if [[ -z "$title" || -z "$body" || "$title" == *$'\n'* || "$title" == *$'\r'* ]]; then
  printf 'state=failed\nnumber=\nurl=\nbranch=%s\nreport=a one-line title and non-empty body are required\n' "$branch"
  exit 2
fi

branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
if [[ -z "$branch" ]] || gitauto_remote_default_unresolved origin || gitauto_is_protected_branch "$branch" origin; then
  printf 'state=blocked\nnumber=\nurl=\nbranch=%s\nreport=branch safety check failed immediately before PR creation\n' "${branch:-detached}"
  exit 0
fi

url="$(gh pr create --base "$base" --head "$branch" --title "$title" --body "$body")"
number="${url%/}"; number="${number##*/}"
[[ "$number" =~ ^[0-9]+$ ]] || number=''
printf 'state=created\nnumber=%s\nurl=%s\nbranch=%s\nreport=pull request created\n' "$number" "$url" "$branch"

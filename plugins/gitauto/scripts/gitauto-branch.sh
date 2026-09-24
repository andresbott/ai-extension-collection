#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/gitauto-lib.sh"

name="${1:-}"
current="$(git branch --show-current)"

if gitauto_remote_default_unresolved origin; then
  printf 'state=failed\nbranch=%s\nreport=default branch could not be resolved safely\n' "$current"
  exit 2
fi
if ! gitauto_is_protected_branch "$current" origin; then
  printf 'state=unchanged\nbranch=%s\n' "$current"
  exit 0
fi

if [[ -z "$name" ]]; then
  changed="$(git diff --name-only --cached | awk 'NF { print; exit }')"
  [[ -n "$changed" ]] || changed="$(git diff --name-only | awk 'NF { print; exit }')"
  [[ -n "$changed" ]] || changed="$(git ls-files --others --exclude-standard | awk 'NF { print; exit }')"

  if [[ -n "$changed" ]]; then
    base="$(basename "$changed")"
    base="${base%.*}"
    slug="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | tr -s '-' | sed 's/^-//; s/-$//')"
    [[ -n "$slug" ]] && name="work/$slug"
  fi
fi

[[ -n "$name" ]] || name="work/change"

if ! git check-ref-format --branch "$name" >/dev/null 2>&1; then
  printf "gitauto-branch: invalid branch name '%s'\n" "$name" >&2
  exit 2
fi

current="$(git branch --show-current)"
if ! gitauto_is_protected_branch "$current" origin; then
  printf 'state=failed\nbranch=%s\nreport=branch safety check changed before switch\n' "$current"
  exit 2
fi
git switch -c "$name" >&2
printf 'state=created\nprevious_branch=%s\nbranch=%s\n' "$current" "$name"

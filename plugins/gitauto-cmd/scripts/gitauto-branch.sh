#!/usr/bin/env bash
# Usage: gitauto-branch.sh <name> [<name>...]
#
# On main/master, creates and checks out the first candidate name that is a
# valid branch name and does not already exist locally or on origin. Candidates
# are tried in order. On any other branch it reports unchanged and exits 0.
#
# Outcomes (key=value lines on stdout):
#   state=created   exit 0  a candidate was checked out
#   state=unchanged exit 0  already on a feature branch
#   state=exists    exit 3  every valid candidate already exists; retry with new names
#   state=failed    exit 2  no candidates, all invalid, or a safety check failed
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/gitauto-lib.sh"

current="$(git branch --show-current)"

if gitauto_remote_default_unresolved origin; then
  printf 'state=failed\nbranch=%s\nreport=default branch could not be resolved safely\n' "$current"
  exit 2
fi
if ! gitauto_is_protected_branch "$current" origin; then
  printf 'state=unchanged\nbranch=%s\n' "$current"
  exit 0
fi

if [[ $# -eq 0 ]]; then
  printf 'state=failed\nbranch=%s\nreport=no branch name candidates supplied\n' "$current"
  exit 2
fi

branch_exists() {
  git show-ref --verify --quiet "refs/heads/$1" ||
    git show-ref --verify --quiet "refs/remotes/origin/$1"
}

name=""
existing=()
invalid=()
for candidate in "$@"; do
  if ! git check-ref-format --branch "$candidate" >/dev/null 2>&1; then
    invalid+=("$candidate")
  elif branch_exists "$candidate"; then
    existing+=("$candidate")
  else
    name="$candidate"
    break
  fi
done

join() { local IFS=,; printf '%s' "$*"; }

if [[ -z "$name" ]]; then
  if [[ ${#existing[@]} -gt 0 ]]; then
    printf 'state=exists\nbranch=%s\nexisting=%s\ninvalid=%s\nreport=every valid candidate already exists\n' \
      "$current" "$(join "${existing[@]}")" "$(join "${invalid[@]+"${invalid[@]}"}")"
    exit 3
  fi
  printf 'state=failed\nbranch=%s\ninvalid=%s\nreport=no valid branch name candidate\n' \
    "$current" "$(join "${invalid[@]}")"
  exit 2
fi

current="$(git branch --show-current)"
if ! gitauto_is_protected_branch "$current" origin; then
  printf 'state=failed\nbranch=%s\nreport=branch safety check changed before switch\n' "$current"
  exit 2
fi
git switch -c "$name" >&2
printf 'state=created\nprevious_branch=%s\nbranch=%s\nskipped_existing=%s\nskipped_invalid=%s\n' \
  "$current" "$name" "$(join "${existing[@]+"${existing[@]}"}")" "$(join "${invalid[@]+"${invalid[@]}"}")"

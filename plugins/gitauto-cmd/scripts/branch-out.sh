#!/usr/bin/env bash
# Token-cheap branch-out. Every outcome is a single stdout line.
#
#   branch-out.sh [name]            preflight (run by the command's ! line)
#   branch-out.sh --create n1 [n2]  create the first free candidate
#
# Lines:
#   DONE state=unchanged branch=<b>              already on a feature branch
#   DONE state=created branch=<b> from=<base>    branch created and checked out
#   DONE state=failed report=<why>               nothing changed
#   NEED_NAME ...                                model must supply candidates
#
# When every candidate is taken, -2..-9 suffixes on the first valid one are
# tried, so the model never needs a second round.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

fail() { printf 'DONE state=failed report=%s\n' "$*"; exit 2; }

git rev-parse --git-dir >/dev/null 2>&1 || fail "not a git repository"
current="$(git branch --show-current)"
[[ -n "$current" ]] || fail "detached HEAD"
gitauto_remote_default_unresolved origin && fail "default branch could not be resolved safely"
if ! gitauto_is_protected_branch "$current" origin; then
  printf 'DONE state=unchanged branch=%s\n' "$current"
  exit 0
fi

valid() { git check-ref-format --branch "$1" >/dev/null 2>&1; }
taken() {
  git show-ref --verify --quiet "refs/heads/$1" ||
    git show-ref --verify --quiet "refs/remotes/origin/$1"
}

create() {
  local first="" c n
  for c in "$@"; do
    valid "$c" || continue
    [[ -z "$first" ]] && first="$c"
    taken "$c" || { pick "$c"; return; }
  done
  [[ -n "$first" ]] || fail "no valid branch name candidate"
  for n in 2 3 4 5 6 7 8 9; do
    taken "$first-$n" || { pick "$first-$n"; return; }
  done
  fail "every candidate already exists"
}

pick() {
  # Re-check the guard immediately before the mutation.
  gitauto_is_protected_branch "$(git branch --show-current)" origin ||
    fail "branch safety check changed before switch"
  git switch -qc "$1" 2>/dev/null || fail "git switch -c $1 failed"
  printf 'DONE state=created branch=%s from=%s\n' "$1" "$current"
}

if [[ "${1:-}" == --create ]]; then
  shift
  [[ $# -gt 0 ]] || fail "no branch name candidates supplied"
  create "$@"
  exit 0
fi

# Preflight: an explicit, valid name needs no model at all.
arg="${1:-}"
if [[ -n "$arg" ]] && valid "$arg"; then
  create "$arg"
  exit 0
fi

# Hand the model the smallest useful context.
printf 'NEED_NAME on=%s' "$current"
[[ -n "$arg" ]] && printf ' hint=%q' "$arg"
printf '\n'
git status --short --untracked-files=all | head -n 25

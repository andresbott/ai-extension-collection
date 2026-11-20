#!/usr/bin/env bash
# Token-cheap new-branch. Every outcome except NEED_NAME is a result line for
# people (`success: ...` or `error: ...`), then the DONE line as the last line.
#
#   new-branch.sh [name]            preflight (run by the command's ! line)
#   new-branch.sh --create n1 [n2]  create the first free candidate
#
# Lines:
#   DONE state=unchanged branch=<b>              already on a feature branch
#   DONE state=created branch=<b> from=<base>    branch created and checked out
#   DONE state=failed report=<why>               nothing changed
#   NEED_NAME ...                                model must supply candidates;
#                                                status lines and a `--- write`
#                                                block with the naming rule follow
#
# With no args and a clean tree there is nothing to name the branch after, so
# the preflight creates a random free work/<adjective>-<noun> branch itself.
# Changes to todo-list files (TODO.md, .todo.json, ...) don't count: they are
# ignored both for that check and in the status the model names from.
# When every candidate is taken, -2..-9 suffixes on the first valid one are
# tried, so the model never needs a second round.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/factory-lib.sh"

fail() {
  printf 'error: failed to create a feature branch: %s\n' "$*"
  printf 'DONE state=failed report=%s\n' "$*"
  exit 2
}

git rev-parse --git-dir >/dev/null 2>&1 || fail "not a git repository"
current="$(git branch --show-current)"
[[ -n "$current" ]] || fail "detached HEAD"
factory_remote_default_unresolved origin && fail "default branch could not be resolved safely"
if ! factory_is_protected_branch "$current" origin; then
  printf 'success: already on the feature branch %s\n' "$current"
  printf 'DONE state=unchanged branch=%s\n' "$current"
  exit 0
fi

valid() { git check-ref-format --branch "$1" >/dev/null 2>&1; }
taken() { factory_branch_taken "$1"; }

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
  factory_is_protected_branch "$(git branch --show-current)" origin ||
    fail "branch safety check changed before switch"
  git switch -qc "$1" 2>/dev/null || fail "git switch -c $1 failed"
  printf 'success: created %s from %s and switched to it\n' "$1" "$current"
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

# Status lines minus the todo list (TODO.md, .todo.json, its lock, ...): it is
# edited all the time and says nothing about what the branch is for.
not_todo() {
  local line path
  while IFS= read -r line; do
    path="${line:3}"
    path="${path##* -> }"
    path="${path%\"}"
    path="${path#\"}"
    path="${path##*/}"
    [[ "$path" =~ ^\.?[Tt][Oo][Dd][Oo](\..*)?$ ]] || printf '%s\n' "$line"
  done
}

# Nothing to name it after (no args, no changes beyond the todo list): a
# random free work/ name.
status="$(git status --short --untracked-files=all | not_todo)"
if [[ -z "$arg" && -z "$status" ]]; then
  create "$(factory_random_branch)"
  exit 0
fi

# Hand the model the smallest useful context.
printf 'NEED_NAME on=%s' "$current"
[[ -n "$arg" ]] && printf ' hint=%q' "$arg"
printf '\n'
[[ -n "$status" ]] && head -n 25 <<<"$status"
factory_write_rules branch

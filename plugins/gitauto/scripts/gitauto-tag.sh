#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/gitauto-lib.sh"

version=''; subject=''; remote=origin; worktree='.'
for arg in "$@"; do
  case "$arg" in
    version=*) version="${arg#version=}" ;;
    subject=*) subject="${arg#subject=}" ;;
    remote=*) remote="${arg#remote=}" ;;
    worktree=*) worktree="${arg#worktree=}" ;;
    *) printf 'state=failed\nversion=\nlatest=\nreport=unknown argument\n'; exit 2 ;;
  esac
done

worktree="$(git -C "$worktree" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$worktree" ]]; then
  printf 'state=failed\nversion=\nlatest=\nreport=release worktree could not be resolved\n'
  exit 2
fi

makefile=''
for candidate in Makefile makefile GNUmakefile; do
  if [[ -f "$worktree/$candidate" ]] && awk '/^tag[[:space:]]*:/ { found=1 } END { exit(found ? 0 : 1) }' "$worktree/$candidate"; then
    makefile="$candidate"; break
  fi
done
if [[ -z "$makefile" ]]; then
  printf 'state=blocked\nversion=\nlatest=\nreport=no make tag target is available\n'
  exit 0
fi

branch="$(git -C "$worktree" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
default_branch="$(cd "$worktree" && gitauto_resolve_default_branch "$remote" 2>/dev/null || true)"
if [[ -z "$branch" || -z "$default_branch" || "$branch" != "$default_branch" ]]; then
  printf 'state=blocked\nversion=\nlatest=\nreport=release tagging requires the default branch\n'
  exit 0
fi
if ! git -C "$worktree" fetch "$remote" "$branch" >/dev/null 2>&1 || [[ "$(git -C "$worktree" rev-parse HEAD)" != "$(git -C "$worktree" rev-parse "$remote/$branch" 2>/dev/null || true)" ]]; then
  printf 'state=blocked\nversion=\nlatest=\nreport=local default branch is not synchronized with its remote\n'
  exit 0
fi

latest="$(git -C "$worktree" tag --list --sort=-v:refname | awk '/^v?[0-9]+\.[0-9]+\.[0-9]+$/ { print; exit }')"
prefix='v'
latest_core='0.0.0'
if [[ -n "$latest" ]]; then
  latest_core="${latest#v}"
  [[ "$latest" == v* ]] || prefix=''
fi
IFS=. read -r major minor patch <<< "$latest_core"

bump='patch'
if printf '%s' "$subject" | grep -Eq '^feat(\([^)]*\))?!?:'; then bump='minor'; fi
if printf '%s' "$subject" | grep -Eq '^[a-z]+(\([^)]*\))?!:'; then bump='major'; fi
if [[ "$major" -eq 0 && "$bump" == major ]]; then bump='minor'; fi
case "$bump" in
  major) recommended="$prefix$((major + 1)).0.0" ;;
  minor) recommended="$prefix$major.$((minor + 1)).0" ;;
  patch) recommended="$prefix$major.$minor.$((patch + 1))" ;;
esac
[[ -n "$latest" ]] || recommended="${prefix}0.1.0"

if [[ -z "$version" ]]; then
  printf 'state=recommended\nversion=%s\nlatest=%s\nreport=release version recommended; no tag created\n' "$recommended" "$latest"
  exit 0
fi
if [[ ! "$version" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'state=failed\nversion=%s\nlatest=%s\nreport=version must be SemVer\n' "$version" "$latest"
  exit 2
fi
if [[ -n "$latest" && "$version" == v* && "$prefix" != v ]] || [[ -n "$latest" && "$version" != v* && "$prefix" == v ]]; then
  printf 'state=failed\nversion=%s\nlatest=%s\nreport=version prefix must match existing tags\n' "$version" "$latest"
  exit 2
fi
version_core="${version#v}"
IFS=. read -r vmajor vminor vpatch <<< "$version_core"
if [[ "$vmajor" -lt "$major" ]] || { [[ "$vmajor" -eq "$major" ]] && [[ "$vminor" -lt "$minor" ]]; } || { [[ "$vmajor" -eq "$major" && "$vminor" -eq "$minor" ]] && [[ "$vpatch" -le "$patch" ]]; }; then
  printf 'state=failed\nversion=%s\nlatest=%s\nreport=version must be greater than the latest tag\n' "$version" "$latest"
  exit 2
fi

# Pass both spellings: repos read either `make tag version=...` or `VERSION=...`.
if ! make -C "$worktree" tag version="$version" VERSION="$version" >&2; then
  printf 'state=failed\nversion=%s\nlatest=%s\nreport=make tag failed\n' "$version" "$latest"
  exit 1
fi
printf 'state=tagged\nversion=%s\nlatest=%s\nreport=release tag target completed\n' "$version" "$latest"

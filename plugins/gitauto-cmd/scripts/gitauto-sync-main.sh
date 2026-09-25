#!/usr/bin/env bash
set -euo pipefail

remote=origin; main=''
for arg in "$@"; do
  case "$arg" in
    remote=*) remote="${arg#remote=}" ;;
    main=*) main="${arg#main=}" ;;
    *) printf 'state=failed\nbranch=\nsha=\nworktree=\nreport=unknown argument\n'; exit 2 ;;
  esac
done

primary="$(git worktree list --porcelain | awk '/^worktree / { print substr($0, 10); exit }')"
if [[ -z "$primary" || ! -d "$primary" ]]; then
  printf 'state=failed\nbranch=\nsha=\nworktree=\nreport=primary worktree could not be resolved\n'
  exit 2
fi
if [[ -n "$(git -C "$primary" status --porcelain=v1)" ]]; then
  printf 'state=blocked\nbranch=\nsha=%s\nworktree=%s\nreport=primary worktree is dirty\n' "$(git -C "$primary" rev-parse --short HEAD)" "$primary"
  exit 0
fi

if [[ -z "$main" ]]; then
  ref="$(git -C "$primary" symbolic-ref --quiet "refs/remotes/$remote/HEAD" 2>/dev/null || true)"
  main="${ref#refs/remotes/$remote/}"
fi
if [[ -z "$main" ]]; then
  main="$(git -C "$primary" ls-remote --symref "$remote" HEAD 2>/dev/null | awk '$1 == "ref:" { sub("refs/heads/", "", $2); print $2; exit }')"
fi
[[ -n "$main" ]] || main=main

if ! git -C "$primary" switch "$main" >&2; then
  printf 'state=failed\nbranch=%s\nsha=%s\nworktree=%s\nreport=could not switch primary worktree to default branch\n' "$main" "$(git -C "$primary" rev-parse --short HEAD)" "$primary"
  exit 2
fi
if ! git -C "$primary" fetch "$remote" "$main" >&2; then
  printf 'state=failed\nbranch=%s\nsha=%s\nworktree=%s\nreport=fetch failed\n' "$main" "$(git -C "$primary" rev-parse --short HEAD)" "$primary"
  exit 2
fi
if ! git -C "$primary" merge --ff-only "$remote/$main" >&2; then
  printf 'state=failed\nbranch=%s\nsha=%s\nworktree=%s\nreport=local default branch is not fast-forwardable\n' "$main" "$(git -C "$primary" rev-parse --short HEAD)" "$primary"
  exit 2
fi
printf 'state=synced\nbranch=%s\nsha=%s\nworktree=%s\nreport=default branch synchronized by fast-forward\n' "$main" "$(git -C "$primary" rev-parse --short HEAD)" "$primary"

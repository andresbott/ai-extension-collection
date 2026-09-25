#!/usr/bin/env bash
# Token-cheap ship flow. The model writes prose; this script does everything else.
#
#   ship.sh prepare [args]        preflight, run by the command's ! line (no mutation)
#   ship.sh draft --title T [--message M] --body-stdin
#                                 store a PR draft (used by the pr-writer agent)
#   ship.sh run [--branch n1 n2 ...] [--title T] [--message M] [--body-stdin]
#               [--tag V | --no-tag] [--delete-remote] [--until ship|pr]
#                                 branch → verify → commit → push → open-pr →
#                                 wait-ci → merge → sync-main → cleanup → tag check
#   ship.sh open-pr [same flags]  run --until pr: stop once CI is green (READY)
#   ship.sh tag <version>         create a release tag the user explicitly chose
#
# Without --tag, run never tags: when the repo has a `make tag` target it ends with
# tag=ask tag_recommended=... tag_options=... so the command can ask the user.
#
# prepare prints `DONE ...` (nothing for the model to do) or a `SHIP ...` context
# block. Its `--- write` block lists each text the model must write, with its
# rule (see gitauto_write_rules). run prints one final line: SHIPPED, PARTIAL,
# STOPPED, or WAITING; the full helper output goes to a log file whose path is on
# that line.
#
# run is built to fit one foreground tool call (Claude Code caps those at 10 min):
# the CI wait gets whatever remains of GITAUTO_CMD_RUN_BUDGET seconds, and if CI
# is still running it exits WAITING (exit 3). Re-running `ship.sh run` with no
# arguments resumes: a clean, already-pushed HEAD skips verify and commit, and
# the open PR is reused.
set -uo pipefail
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$D/gitauto-lib.sh"

# A PR description is "complex" (handed to the expensive writer) above any of these.
COMPLEX_FILES="${GITAUTO_CMD_COMPLEX_FILES:-10}"
COMPLEX_LINES="${GITAUTO_CMD_COMPLEX_LINES:-400}"
COMPLEX_DIRS="${GITAUTO_CMD_COMPLEX_DIRS:-3}"
PATCH_LINES="${GITAUTO_CMD_PATCH_LINES:-200}"
# Lines of verify output or failed CI log handed back to the session on failure.
FAIL_LINES="${GITAUTO_CMD_FAIL_LINES:-60}"
# Seconds one `run` may take before it hands back WAITING; the CI wait gets at
# least GITAUTO_CMD_CI_MIN of it.
RUN_BUDGET="${GITAUTO_CMD_RUN_BUDGET:-540}"
CI_MIN="${GITAUTO_CMD_CI_MIN:-30}"

fail() { printf 'DONE state=failed report=%s\n' "$*"; exit 2; }

git rev-parse --git-dir >/dev/null 2>&1 || fail "not a git repository"
draft_dir="$(git rev-parse --absolute-git-dir)/gitauto"

base_ref() {
  local base="$1"
  if git show-ref --verify --quiet "refs/remotes/origin/$base"; then printf 'origin/%s' "$base"; else printf '%s' "$base"; fi
}

untracked() { git ls-files --others --exclude-standard; }

# A Conventional Commit subject, as gitauto-merge.sh enforces it.
is_cc() {
  [[ "$1" =~ ^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-zA-Z0-9._/-]+\))?(!)?:[[:space:]]+[^[:space:]].*$ ]] &&
    [[ "$1" != *$'\n'* ]]
}
# The squash subject saved in a PR body by an earlier open-pr or ship run.
SUBJECT_TAG='gitauto-subject'
saved_subject() { sed -n "s/^<!-- $SUBJECT_TAG: \(.*\) -->\$/\1/p" <<< "$1" | tail -n 1; }

prepare() {
  local for=ship
  if [[ "${1:-}" == --for ]]; then for="${2:-ship}"; shift 2; fi
  local hint="${1:-}" current base ref mb protected=no pr=none pr_title='' dirty ahead files lines dirs need writer=cheap
  current="$(git branch --show-current)"
  [[ -n "$current" ]] || fail "detached HEAD"
  git remote get-url origin >/dev/null 2>&1 || fail "no origin remote"
  gitauto_remote_default_unresolved origin && fail "default branch could not be resolved safely"
  { command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; } || fail "GitHub CLI is unavailable or unauthenticated"
  base="$(gitauto_resolve_default_branch origin)"
  rm -rf "$draft_dir"

  if gitauto_is_protected_branch "$current" origin; then
    protected=yes
  else
    pr="$(gh pr view "$current" --json number,state,title \
      --jq '"\(.state|ascii_downcase)#\(.number) \(.title)"' 2>/dev/null)" || pr=none
    [[ -n "$pr" ]] || pr=none
  fi

  ref="$(base_ref "$base")"
  mb="$(git merge-base HEAD "$ref" 2>/dev/null || printf '%s' "$ref")"
  dirty="$(git status --porcelain | wc -l | tr -d ' ')"
  ahead="$(git rev-list --count "$mb..HEAD" 2>/dev/null || echo 0)"
  if [[ "$dirty" -eq 0 && "$ahead" -eq 0 && "$pr" == none ]]; then
    printf 'DONE state=nothing branch=%s report=nothing to ship\n' "$current"
    exit 0
  fi

  read -r files lines < <(git diff --numstat "$mb" | awk '{f++; l+=$1+$2} END {print f+0, l+0}')
  files=$((files + $(untracked | wc -l)))
  lines=$((lines + $(untracked | tr '\n' '\0' | xargs -0 -r cat 2>/dev/null | wc -l)))
  dirs="$({ git diff --name-only "$mb"; untracked; } | awk -F/ '{print (NF>1 ? $1 : ".")}' | sort -u | wc -l | tr -d ' ')"

  case "$pr" in
    merged#*)
      [[ "$dirty" -eq 0 ]] || fail "pull request ${pr%% *} is already merged; ship new work from a fresh branch off $base"
      need=none ;;
    open#*)
      if [[ "$dirty" -gt 0 ]]; then need=message; else need=none; fi
      # Hybrid subject: a saved one or a Conventional title needs no model; otherwise ask once.
      pr_title="${pr#* }"
      if [[ "$for" == ship ]] && ! is_cc "$pr_title" &&
         [[ -z "$(saved_subject "$(gh pr view "$current" --json body --jq .body 2>/dev/null)")" ]]; then
        if [[ "$need" == none ]]; then need=subject; else need=message+subject; fi
      fi ;;
    closed#*) fail "pull request is closed without merge: $pr" ;;
    *) need='pr'
       if (( files > COMPLEX_FILES || lines > COMPLEX_LINES || dirs > COMPLEX_DIRS )); then writer=expert; fi ;;
  esac
  [[ "$need" == pr ]] || writer=cheap

  printf 'SHIP branch=%s protected=%s base=%s pr=%s dirty=%s ahead=%s files=%s lines=%s dirs=%s need=%s writer=%s\n' \
    "$current" "$protected" "$base" "${pr// /_}" "$dirty" "$ahead" "$files" "$lines" "$dirs" "$need" "$writer"
  [[ -n "$hint" ]] && printf 'args: %s\n' "$hint"
  [[ "$need" == *subject ]] && printf 'pr_title: %s\n' "$pr_title"
  # Only the texts the next step needs, in the order `run` takes them.
  local write=()
  [[ "$protected" == yes ]] && write+=(branch)
  [[ "$need" == pr && "$writer" == cheap ]] && write+=(title subject body)
  [[ "$need" == message* ]] && write+=(message)
  [[ "$need" == *subject ]] && write+=(subject-from-title)
  gitauto_write_rules "${write[@]+"${write[@]}"}"
  # The expert writer reads the repo itself; nothing else to show.
  [[ "$need" == none || "$need" == subject || "$writer" == expert ]] && return 0

  printf -- '--- status\n'; git status --short --untracked-files=all | head -n 25
  if [[ "$ahead" -gt 0 ]]; then printf -- '--- commits\n'; git log --oneline "$mb..HEAD" | head -n 15; fi
  printf -- '--- diffstat\n'; git diff --stat=100 "$mb" | tail -n 30
  printf -- '--- patch (truncated)\n'
  {
    git diff "$mb"
    untracked | while IFS= read -r f; do printf '+++ new file %s\n' "$f"; head -n 20 -- "$f"; done
  } | head -n "$PATCH_LINES"
}

one_line() { [[ -n "$1" && "$1" != *$'\n'* && "$1" != *$'\r'* ]]; }

draft() {
  local title='' subject='' message='' body=''
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title) title="${2:-}"; shift ;;
      --subject) subject="${2:-}"; shift ;;
      --message) message="${2:-}"; shift ;;
      --body-stdin) body="$(cat)" ;;
      *) fail "unknown draft argument $1" ;;
    esac
    shift
  done
  one_line "$title" || fail "a one-line --title is required"
  [[ -z "$subject" ]] || is_cc "$subject" || fail "--subject must be a one-line Conventional Commit subject"
  [[ -n "$body" ]] || fail "a non-empty body on stdin is required"
  [[ -z "$message" ]] || one_line "$message" || fail "--message must be one line"
  mkdir -p "$draft_dir"
  printf '%s' "$title" > "$draft_dir/title"
  printf '%s' "$subject" > "$draft_dir/subject"
  printf '%s' "$message" > "$draft_dir/message"
  printf '%s\n' "$body" > "$draft_dir/body"
  printf 'DRAFTED title=%s%s\n' "$title" "${subject:+ subject=$subject}"
}

run() {
  local branches=() title='' subject='' message='' body='' tag='' no_tag=false delete_remote=false until=ship
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --branch) shift; while [[ $# -gt 0 && "$1" != --* ]]; do branches+=("$1"); shift; done; continue ;;
      --title) title="${2:-}"; shift ;;
      --subject) subject="${2:-}"; shift ;;
      --message) message="${2:-}"; shift ;;
      --body-stdin) body="$(cat)" ;;
      --tag) tag="${2:-}"; shift ;;
      --no-tag) no_tag=true ;;
      --delete-remote) delete_remote=true ;;
      --until) until="${2:-}"; shift ;;
      *) fail "unknown run argument $1" ;;
    esac
    shift
  done
  [[ "$until" == ship || "$until" == pr ]] || fail "--until must be ship or pr"
  local resume_cmd='ship.sh run'
  [[ "$until" == pr ]] && resume_cmd='ship.sh open-pr'
  if [[ -z "$title" && -f "$draft_dir/title" ]]; then
    title="$(cat "$draft_dir/title")"
    [[ -n "$subject" ]] || subject="$(cat "$draft_dir/subject" 2>/dev/null)"
    [[ -n "$message" ]] || message="$(cat "$draft_dir/message")"
    [[ -n "$body" ]] || body="$(cat "$draft_dir/body")"
  fi
  # Validate text before any mutation. A prose title is fine; the subject must be Conventional.
  [[ -z "$subject" ]] || is_cc "$subject" || fail "--subject must be a one-line Conventional Commit subject"
  [[ -z "$title" ]] || one_line "$title" || fail "--title must be one line"
  [[ -n "$subject" ]] || ! is_cc "$title" || subject="$title"
  [[ -n "$title" ]] || title="$subject"
  # Save the subject in the PR body so a later ship, in any session, merges without a model.
  [[ -z "$body" || -z "$subject" ]] || body+=$'\n\n'"<!-- $SUBJECT_TAG: $subject -->"

  local log merged=no out st rc=0 branch number='' url='' worktree='' summary n=0 mark=1
  log="$(mktemp "${TMPDIR:-/tmp}/gitauto-ship.XXXXXX")"
  printf 'ship: started; live output: tail -f %s\n' "$log"
  begin() { n=$((n + 1)); mark=$(($(wc -l < "$log") + 1)); printf '\n== %s\n' "$1" >> "$log"; printf 'ship: [%s] %s ...\n' "$n" "$1"; }
  end() { printf 'ship: [%s] %s -> %s\n' "$n" "$1" "${st:-none}"; }
  step() {
    local name="$1"; shift
    begin "$name"
    out="$("$@" 2>> "$log")"; rc=$?
    printf '%s\n' "$out" >> "$log"
    st="$(kv state)"
    [[ "$rc" -eq 124 && -z "$st" ]] && st=timeout
    end "$name"
  }
  kv() { printf '%s\n' "$out" | sed -n "s/^$1=//p" | tail -n 1; }
  stop() {
    local word='STOPPED'
    [[ "$merged" == yes ]] && word='PARTIAL'
    case "$1" in
      verify) printf -- '--- failure: verify (last %s lines)\n' "$FAIL_LINES"; tail -n "+$mark" "$log" | tail -n "$FAIL_LINES" ;;
      wait-ci) ci_failure ;;
    esac
    printf '%s stage=%s state=%s report=%s%s log=%s\n' "$word" "$1" "${st:-none}" "${2:-$(kv report)}" \
      "${url:+ url=$url}" "$log"
    exit 1
  }
  # Failed check names plus the tail of each failed run's log, timestamps stripped.
  ci_failure() {
    local checks id
    printf -- '--- failure: wait-ci\n'
    checks="$(gh pr checks "$number" --json name,bucket,link \
      --jq '.[] | select(.bucket == "fail") | "\(.name)\t\(.link)"' 2>/dev/null)"
    if [[ -z "$checks" ]]; then printf 'failed checks could not be listed; see %s\n' "$url"; return; fi
    cut -f1 <<< "$checks" | sed 's/^/failed check: /'
    cut -f2 <<< "$checks" | sed -n 's#.*/actions/runs/\([0-9][0-9]*\).*#\1#p' | sort -u | head -n 2 |
      while read -r id; do
        printf -- '--- run %s failed log (last %s lines)\n' "$id" "$FAIL_LINES"
        gh run view "$id" --log-failed 2>/dev/null | cut -f3- |
          sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z ?//' | tail -n "$FAIL_LINES"
      done
  }

  # branch
  branch="$(git branch --show-current)"
  if [[ -z "$branch" ]] || gitauto_is_protected_branch "$branch" origin; then
    [[ ${#branches[@]} -gt 0 ]] || { st=failed; stop branch "on ${branch:-detached HEAD}; --branch candidates are required"; }
    begin branch
    out="$("$D/branch-out.sh" --create "${branches[@]}" 2>> "$log")"
    printf '%s\n' "$out" >> "$log"
    st="$(sed -n 's/.*state=\([^ ]*\).*/\1/p' <<< "$out")"
    end branch
    [[ "$st" == created ]] || stop branch "${out#*report=}"
    branch="$(git branch --show-current)"
  fi

  # Resume: a clean HEAD that is already on its upstream was verified before it was pushed.
  if [[ -z "$(git status --porcelain)" ]] &&
     [[ "$(git rev-parse HEAD)" == "$(git rev-parse --verify --quiet '@{upstream}' 2>/dev/null)" ]]; then
    begin verify; st=skip; printf 'already pushed; verified before push\n' >> "$log"; end verify
  else
    step verify "$D/gitauto-verify.sh"
    [[ "$st" == pass || "$st" == skip ]] || stop verify "verification failed"
  fi

  if [[ -n "$(git status --porcelain)" ]]; then
    message="${message:-${subject:-$title}}"
    one_line "$message" || { st=failed; stop commit "a one-line --message or --title is required"; }
    step commit "$D/gitauto-commit.sh" "$message"
    [[ "$st" == committed ]] || stop commit
  fi

  step push "$D/gitauto-push.sh" origin
  [[ "$st" == pushed ]] || stop push

  local pr_args=()
  [[ -n "$title" ]] && pr_args+=("title=$title")
  [[ -n "$body" ]] && pr_args+=("body=$body")
  step open-pr "$D/gitauto-open-pr.sh" "${pr_args[@]+"${pr_args[@]}"}"
  number="$(kv number)"; url="$(kv url)"
  # Squash subject: --subject, then the one saved in the PR body, then a Conventional title.
  resolve_subject() {
    local t
    [[ -z "$subject" ]] || return 0
    subject="$(saved_subject "$(gh pr view "$number" --json body --jq .body 2>/dev/null)")"
    [[ -z "$subject" ]] || return 0
    t="$(gh pr view "$number" --json title --jq .title 2>/dev/null)"
    if is_cc "$t"; then subject="$t"; fi
  }
  case "$st" in
    created) rm -rf "$draft_dir" ;;
    reused) ;;
    already-merged)
      # A merged PR cannot carry commits it does not contain; never skip past them.
      [[ "$(gh pr view "$number" --json headRefOid --jq .headRefOid 2>/dev/null)" == "$(git rev-parse HEAD)" ]] ||
        { st=blocked; stop open-pr "pull request #$number is already merged without the current HEAD"; } ;;
    *) stop open-pr ;;
  esac

  if [[ "$st" == already-merged ]]; then
    merged=yes
    if [[ "$until" == pr ]]; then
      printf 'READY pr=#%s url=%s state=already-merged report=already merged; run /gitauto:ship to sync and clean up log=%s\n' \
        "$number" "$url" "$log"
      exit 0
    fi
    resolve_subject
  else
    # A ship needs a Conventional squash subject; fail before waiting on CI, not after.
    if [[ "$until" == ship ]]; then
      resolve_subject
      [[ -n "$subject" ]] || { st=needs-subject; stop merge "PR title is not a Conventional Commit and no subject is saved; re-run with --subject"; }
    fi
    # Give CI only what is left of the run budget, so run fits one foreground call.
    local budget=$((RUN_BUDGET - SECONDS)) tmo
    (( budget >= CI_MIN )) || budget="$CI_MIN"
    tmo="$(command -v timeout || command -v gtimeout || true)"
    if [[ -n "$tmo" ]]; then
      step wait-ci "$tmo" "$budget" "$D/gitauto-wait-ci.sh" "pr=$number"
    else
      step wait-ci "$D/gitauto-wait-ci.sh" "pr=$number"
    fi
    if [[ -n "$tmo" && "$rc" -eq 124 ]] || [[ "$st" == pending ]]; then
      printf 'ship: [%s] wait-ci -> still running after %ss\n' "$n" "$budget"
      printf 'WAITING stage=wait-ci pr=#%s url=%s report=CI still running; re-run %s to resume log=%s\n' \
        "$number" "$url" "$resume_cmd" "$log"
      exit 3
    fi
    [[ "$st" == green || "$st" == none ]] || stop wait-ci
    if [[ "$until" == pr ]]; then
      printf 'READY pr=#%s url=%s ci=%s log=%s\n' "$number" "$url" "$st" "$log"
      exit 0
    fi
    step merge "$D/gitauto-merge.sh" "pr=$number" "subject=$subject"
    [[ "$st" == merged || "$st" == already-merged ]] || stop merge
    merged=yes
  fi

  step sync-main "$D/gitauto-sync-main.sh" remote=origin
  [[ "$st" == synced ]] || stop sync-main
  worktree="$(kv worktree)"

  step cleanup "$D/gitauto-cleanup.sh" "branch=$branch" remote=origin "deleteRemote=$delete_remote"
  summary="pr=#$number url=$url sync=synced cleanup=$st remote_branch=$(kv remote_branch) worktree=$(kv worktree)"
  local final='SHIPPED'
  [[ "$st" == clean ]] || final='PARTIAL'

  if [[ -n "$tag" ]]; then
    step tag "$D/gitauto-tag.sh" "version=$tag" "subject=${subject:-}" remote=origin "worktree=${worktree:-.}"
    summary+=" tag=$st"
    [[ "$st" == tagged ]] || { final='PARTIAL'; summary+=" tag_report=$(kv report)"; }
  elif [[ "$no_tag" == true ]]; then
    summary+=" tag=declined"
  else
    # Never tag here: only recommend, so the command can ask. No `make tag` target means no question.
    step tag-check "$D/gitauto-tag.sh" "subject=${subject:-}" remote=origin "worktree=${worktree:-.}"
    if [[ "$st" == recommended ]]; then
      summary+=" tag=ask tag_recommended=$(kv version) tag_options=$(tag_options "$(kv latest)" "$(kv version)") latest=$(kv latest)"
    elif [[ "$(kv report)" == 'no make tag target is available' ]]; then
      summary+=" tag=none"
    else
      summary+=" tag=skip tag_report=$(kv report | tr ' ' '_')"
    fi
  fi
  printf '%s %s log=%s\n' "$final" "$summary" "$log"
}

# Recommended version first, then the other patch/minor/major bumps of latest.
tag_options() {
  local latest="$1" rec="$2" p='v' major minor patch opts c
  if [[ -z "$latest" ]]; then printf '%s,%s1.0.0' "$rec" "${rec%%[0-9]*}"; return; fi
  [[ "$latest" == v* ]] || p=''
  IFS=. read -r major minor patch <<< "${latest#v}"
  opts="$rec"
  for c in "$p$major.$minor.$((patch + 1))" "$p$major.$((minor + 1)).0" "$p$((major + 1)).0.0"; do
    [[ "$c" == "$rec" ]] || opts+=",$c"
  done
  printf '%s' "$opts"
}

# Create a release tag after a ship, from the primary worktree. Only ever called
# with a version the user explicitly picked.
tag_cmd() {
  local version="${1:-}" primary log out st
  [[ -n "$version" ]] || fail "usage: ship.sh tag <version>"
  primary="$(git worktree list --porcelain | awk '/^worktree / { print substr($0, 10); exit }')"
  log="$(mktemp "${TMPDIR:-/tmp}/gitauto-tag.XXXXXX")"
  out="$("$D/gitauto-tag.sh" "version=$version" remote=origin "worktree=${primary:-.}" 2>> "$log")"
  printf '%s\n' "$out" >> "$log"
  st="$(sed -n 's/^state=//p' <<< "$out" | tail -n 1)"
  if [[ "$st" == tagged ]]; then
    printf 'TAGGED version=%s latest=%s log=%s\n' "$version" "$(sed -n 's/^latest=//p' <<< "$out")" "$log"
  else
    printf 'STOPPED stage=tag state=%s report=%s log=%s\n' "${st:-none}" "$(sed -n 's/^report=//p' <<< "$out")" "$log"
    exit 1
  fi
}

cmd="${1:-}"; shift || true
case "$cmd" in
  prepare) prepare "$@" ;;
  draft) draft "$@" ;;
  run) run "$@" ;;
  open-pr) run --until pr "$@" ;;
  tag) tag_cmd "$@" ;;
  *) fail "usage: ship.sh prepare|draft|run|open-pr|tag" ;;
esac

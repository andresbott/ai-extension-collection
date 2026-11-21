#!/usr/bin/env bash

# Resolve a repository's default branch without mutating refs.
# Order: cached remote HEAD, remote HEAD symref, GitHub CLI, then local main/master
# only when the named remote is not configured.
factory_resolve_default_branch() {
  local remote="${1:-origin}" ref branch
  ref="$(git symbolic-ref --quiet "refs/remotes/$remote/HEAD" 2>/dev/null || true)"
  branch="${ref#refs/remotes/$remote/}"
  if [[ -n "$branch" ]]; then
    printf '%s\n' "$branch"
    return 0
  fi

  branch="$(git ls-remote --symref "$remote" HEAD 2>/dev/null | awk '$1 == "ref:" && !found { sub("refs/heads/", "", $2); print $2; found = 1 }')"
  if [[ -n "$branch" ]]; then
    printf '%s\n' "$branch"
    return 0
  fi

  if command -v gh >/dev/null 2>&1; then
    branch="$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || true)"
    if [[ -n "$branch" ]]; then
      printf '%s\n' "$branch"
      return 0
    fi
  fi

  if ! git remote get-url "$remote" >/dev/null 2>&1; then
    if git show-ref --verify --quiet refs/heads/main; then printf 'main\n'; return 0; fi
    if git show-ref --verify --quiet refs/heads/master; then printf 'master\n'; return 0; fi
  fi
  return 1
}

factory_remote_default_unresolved() {
  local remote="${1:-origin}"
  git remote get-url "$remote" >/dev/null 2>&1 && ! factory_resolve_default_branch "$remote" >/dev/null
}

factory_is_protected_branch() {
  local branch="$1" remote="${2:-origin}" default_branch
  [[ "$branch" == main || "$branch" == master ]] && return 0
  default_branch="$(factory_resolve_default_branch "$remote" 2>/dev/null || true)"
  [[ -n "$default_branch" && "$branch" == "$default_branch" ]]
}

# The host a remote points at, as gh sees it: an SSH config alias (Host work with
# HostName github.com) resolves to its real host through `ssh -G`, like gh does.
# Fails for a local-path remote or a missing one.
factory_remote_host() {
  local url host ssh=no real
  url="$(git remote get-url "${1:-origin}" 2>/dev/null)" || return 1
  case "$url" in
    *://*)
      host="${url#*://}"
      case "${url%%://*}" in *ssh*) ssh=yes ;; esac ;;
    *:*)
      # scp-like user@host:path; a slash before the first colon makes it a local path.
      [[ "${url%%:*}" != */* ]] || return 1
      host="${url%%:*}"; ssh=yes ;;
    *) return 1 ;;
  esac
  host="${host%%/*}"; host="${host##*@}"; host="${host%%:*}"
  [[ -n "$host" ]] || return 1
  if [[ "$ssh" == yes ]] && command -v ssh >/dev/null 2>&1; then
    real="$(ssh -G "$host" </dev/null 2>/dev/null | awk '$1 == "hostname" && !found { print $2; found = 1 }' || true)"
    host="${real:-$host}"
  fi
  printf '%s\n' "$host"
}

# The `owner/name` a remote points at, as GitHub names the repository: the URL's
# last two path segments, without `.git`. Fails for a local-path remote.
factory_remote_repo() {
  local url path
  url="$(git remote get-url "${1:-origin}" 2>/dev/null)" || return 1
  case "$url" in
    *://*) path="${url#*://}"; path="${path#*/}" ;;
    *:*) [[ "${url%%:*}" != */* ]] || return 1; path="${url#*:}" ;;
    *) return 1 ;;
  esac
  path="${path%/}"; path="${path%.git}"
  [[ "$path" == */* ]] || return 1
  printf '%s/%s\n' "$(basename "$(dirname "$path")")" "$(basename "$path")"
}

# The environment variable gh reads a token from for a host: GH_TOKEN for
# github.com and GHE.com tenants, GH_ENTERPRISE_TOKEN for GitHub Enterprise Server.
factory_token_var() {
  case "$1" in
    github.com|*.ghe.com) printf 'GH_TOKEN\n' ;;
    *) printf 'GH_ENTERPRISE_TOKEN\n' ;;
  esac
}

# The per-clone factory settings (the gh account, see factory-account.sh). It
# lives in the common git dir, so every worktree shares it and git never tracks it.
factory_account_file() {
  local dir
  dir="$(git rev-parse --git-common-dir 2>/dev/null)" || return 1
  printf '%s/factory.json\n' "$(cd "$dir" && pwd)"
}

# Point every later gh call of this process at <account> on <host>, without
# touching gh's global active account.
factory_export_account() {
  local host="$1" account="$2" var token
  var="$(factory_token_var "$host")"
  token="$(gh auth token --hostname "$host" --user "$account" 2>/dev/null)" || return 1
  [[ -n "$token" ]] || return 1
  export "$var=$token"
}

# Run a gh command (`factory_gh_capture gh ...` or `... env VAR=x gh ...`) with
# its stdout and stderr kept apart, so a notice gh prints on stderr (gh 2.105+
# adds a multi-line hint to every `pr view`, and still exits 0) is never parsed
# as its output. Sets gh_out, gh_err, and gh_status; always returns 0.
factory_gh_capture() {
  local err
  err="$(mktemp "${TMPDIR:-/tmp}/factory-gh.XXXXXX")"
  if gh_out="$("$@" 2>"$err")"; then gh_status=0; else gh_status=$?; fi
  gh_err="$(cat "$err")"
  rm -f "$err"
}

# The one line of a gh error worth reporting: its last non-empty line, trimmed.
factory_gh_error() {
  local line
  line="$(printf '%s\n' "$1" | awk 'NF { l = $0 } END { print l }' | tr -s '[:space:]' ' ')"
  line="${line# }"; line="${line% }"
  printf '%s\n' "${line:-gh gave no error message}" | cut -c1-300
}

# gh is installed and logged in to the remote's host. A bare `gh auth status`
# checks every host gh knows, so a stale login on an unrelated host (another
# GitHub Enterprise) would block this repo; it is only the fallback when the
# remote's host is unknown.
factory_gh_authenticated() {
  local host
  command -v gh >/dev/null 2>&1 || return 1
  if host="$(factory_remote_host "${1:-origin}")"; then
    gh auth status --hostname "$host" >/dev/null 2>&1
  else
    gh auth status >/dev/null 2>&1
  fi
}

# A branch exists locally or on origin.
factory_branch_taken() {
  git show-ref --verify --quiet "refs/heads/$1" ||
    git show-ref --verify --quiet "refs/remotes/origin/$1"
}

# A random work/<adjective>-<noun> name that no local or origin branch uses
# (about 15,000 combinations; $RANDOM is plenty, nothing here is secret).
FACTORY_ADJECTIVES=(
  agile amber ancient arctic azure bold brave breezy bright brisk
  calm candid clever cobalt cosmic cozy crisp curious daring dapper
  dashing deft eager early earnest electric elegant emerald epic fabled
  fancy fearless feisty fierce fluffy fond fresh frosty gentle giant
  gilded glad gleaming golden graceful grand happy hardy hazy hidden
  humble icy jade jolly jovial keen kind lively lucky lunar
  majestic mellow merry mighty misty modest nimble noble novel oaken
  olive orange patient peppy plucky polar proud quick quiet radiant
  rapid rosy royal rugged rustic sandy scarlet serene sharp shiny
  silent silver sleek smooth snowy solar spry steady stellar stormy
  sturdy sunny swift tidy tranquil trusty velvet vivid warm wild
  wise witty zany zealous zesty cheerful dusky lofty mossy
)
FACTORY_NOUNS=(
  acorn albatross anchor antelope aurora badger banjo beacon beaver bison
  blossom boulder breeze brook buffalo cactus canyon cedar cheetah cinder
  cliff clover comet condor coral cougar crane creek cricket crow
  dolphin dove dragon dune eagle ember falcon fern finch fjord
  flame fox galaxy gazelle geyser glacier grove gull harbor hawk
  hedgehog heron hill horizon iris island jaguar kestrel kite koala
  lagoon lantern lark lemur lily lion lotus lynx maple marmot
  meadow meteor mink moose moth nebula newt oak ocelot orchid
  osprey otter owl panda panther pebble pelican pine planet plume
  pony prairie puffin quail quartz rabbit raven reef ridge river
  robin sparrow salmon sequoia shore sparrowhawk spruce squirrel star stream
  summit swan thistle thunder tiger toucan tulip tundra valley walrus
  willow wolf wren yak zebra zephyr
)
factory_random_branch() {
  local name i
  for i in {1..50}; do
    name="work/${FACTORY_ADJECTIVES[RANDOM % ${#FACTORY_ADJECTIVES[@]}]}-${FACTORY_NOUNS[RANDOM % ${#FACTORY_NOUNS[@]}]}"
    factory_branch_taken "$name" || break
  done
  printf '%s\n' "$name"
}

# The writing rules for each text a script needs from a model, printed as a
# `--- write` block with one `<key>: <rule>` line per text. Every harness adapter
# hands this block to its model unchanged, so the rules live only here.
#   factory_write_rules branch title subject body message subject-from-title
factory_write_rules() {
  local key subject='one Conventional Commit line, type(scope): summary (types: feat fix docs style refactor perf test build ci chore revert; add ! for a breaking change). It is saved in the PR, becomes the squash-merge subject, and drives the release-tag bump.'
  [[ $# -gt 0 ]] || return 0
  printf -- '--- write\n'
  for key in "$@"; do
    case "$key" in
      branch) printf 'branch: 3 distinct, concise, lowercase branch names, each feat/, fix/, docs/, or chore/ plus a kebab-case slug, drawn from the args (or hint) and the listed changes; a branch name given in the args goes first; if the args or hint ask for a random name, or there is neither, use only %s.\n' "$(factory_random_branch)" ;;
      title) printf 'title: one plain, imperative prose line a reviewer can read (e.g. Add a discovery view for albums).\n' ;;
      subject) printf 'subject: %s\n' "$subject" ;;
      subject-from-title) printf 'subject: %s Reshape the pr_title line into it.\n' "$subject" ;;
      body) printf 'body: Markdown with only these sections: ## Summary (the why: the problem and its impact, 1-3 sentences), ## What (2-5 bullets of the changes that matter, not a file list), and an optional ## Notes (caveats or intentional non-changes). No tests section, no AI or tool attribution.\n' ;;
      message) printf 'message: one-line Conventional Commit message, type(scope): summary.\n' ;;
    esac
  done
}

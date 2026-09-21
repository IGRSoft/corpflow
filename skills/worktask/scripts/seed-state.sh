#!/usr/bin/env bash
# @description seed-state.sh — create .context/state.json for a new worktask run.
#
#   The only definition of the seed. It never overwrites: an existing ledger (even a
#   dangling symlink) is refused byte-unchanged, because re-runs are reset by PL0.
#
#   Context dir, first match wins; every candidate is physicalized:
#     --context-dir -> absolute CONTEXT_DIR -> absolute WORKSPACE_ROOT/.context
#     -> <cwd git toplevel>/.context -> CLAUDE_PROJECT_DIR/.context only when inside that
#     toplevel. Never cwd: from a linked worktree the shared ladder resolves the parent
#     checkout, whose ledger this must not clobber.
#
# Usage:
#   bash "$PLUGIN_ROOT/skills/worktask/scripts/seed-state.sh" --worktask-id <id> --goal <text> \
#     [--platform <p>] [--context-dir <dir>] [--workspace-path <abs>]
#   bash "$PLUGIN_ROOT/skills/worktask/scripts/seed-state.sh" --self-test | -h | --help
#
# @arg --worktask-id <id>      ^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$
# @arg --goal <text>           Control runs become one space, trimmed, capped at 240 chars.
# @arg --platform <p>          Comma list of ^[a-z][a-z0-9_-]*$ (default: all).
# @arg --context-dir <dir>     Trusted as given; must be an existing directory (else 4).
# @arg --workspace-path <abs>  Default: physical git toplevel of cwd, else pwd -P.
#
# stdout (key=value only): 0 -> result=seeded, state, run_index, plan_file;
#   3 -> result=exists, state. Every other exit prints one stderr line and no stdout.
#
# @exitcode 0 Seeded.
# @exitcode 1 Runtime failure: jq missing, lock timeout, temp/write/rename failure.
# @exitcode 2 Usage error; nothing written.
# @exitcode 3 Refused: state.json exists (byte-unchanged).
# @exitcode 4 No context dir resolves; nothing written.
#
# Env: STATE_LOCK_TIMEOUT_S (default 5) — the lock shared with state-patch.sh is waited
#   on, never broken.
#
# Minimum shell: bash 3.2+ (macOS default); jq 1.6+.

set -Eeuo pipefail
IFS=$'\n\t'

_ID_RE='^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$'
_PLATFORM_RE='^[a-z][a-z0-9_-]*(,[a-z][a-z0-9_-]*)*$'

# jq-1.6 builtins only (no trim); `+` quantifiers because 1.6 mishandles empty matches.
# Word-boundary cap, same rule as the publish-side title cap: keep the longest
# prefix ending in whitespace within the window, else hard-cut to 239 + ellipsis.
# shellcheck disable=SC2016 # $g is a jq variable, not a shell expansion
_GOAL_FILTER='$g | gsub("[[:cntrl:]]+"; " ") | sub("^ +"; "") | sub(" +$"; "")
  | if length <= 240 then .
    else
      (.[0:240] | sub("[^[:space:]]+$"; "") | sub("[[:space:],;:-]+$"; "")) as $w
      | if ($w | length) > 0 then $w + "\u2026" else .[0:239] + "\u2026" end
    end'

_TMP=""
_LOCK_HELD=""

usage() {
  sed -n '2,/^[^#]/s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"
}

die() {
  if [ "$1" -eq 2 ]; then
    printf >&2 'seed-state: %s (see --help)\n' "$2"
  else
    printf >&2 'seed-state: %s\n' "$2"
  fi
  exit "$1"
}

_matches() {
  local LC_ALL=C
  [[ $1 =~ $2 ]]
}

phys() {
  (CDPATH='' cd -P -- "$1" 2> /dev/null && pwd -P)
}

cleanup() {
  if [ -n "$_TMP" ]; then
    rm -f -- "$_TMP" 2> /dev/null || true
    _TMP=""
  fi
  # rmdir, never rm -rf: a lock that gained an owner file is not ours to remove.
  if [ -n "$_LOCK_HELD" ]; then
    rmdir -- "$_LOCK_HELD" 2> /dev/null || true
    _LOCK_HELD=""
  fi
}

parse_args() {
  while [ $# -gt 0 ]; do
    case $1 in
      -h | --help)
        usage
        exit 0
        ;;
      --worktask-id | --goal | --platform | --context-dir | --workspace-path)
        [ $# -ge 2 ] || die 2 "missing value for $1"
        set_opt "$1" "$2"
        shift 2
        ;;
      --*=*) die 2 "use '--flag value', not $1" ;;
      -*) die 2 "unknown flag: $1" ;;
      *) die 2 "unexpected argument: $1" ;;
    esac
  done
}

set_opt() {
  case $1 in
    --worktask-id)
      [ -z "${_OPT_ID+x}" ] || die 2 "repeated flag: $1"
      _OPT_ID=$2
      ;;
    --goal)
      [ -z "${_OPT_GOAL+x}" ] || die 2 "repeated flag: $1"
      _OPT_GOAL=$2
      ;;
    --platform)
      [ -z "${_OPT_PLATFORM+x}" ] || die 2 "repeated flag: $1"
      _OPT_PLATFORM=$2
      ;;
    --context-dir)
      [ -z "${_OPT_CONTEXT_DIR+x}" ] || die 2 "repeated flag: $1"
      _OPT_CONTEXT_DIR=$2
      ;;
    --workspace-path)
      [ -z "${_OPT_WORKSPACE_PATH+x}" ] || die 2 "repeated flag: $1"
      _OPT_WORKSPACE_PATH=$2
      ;;
  esac
}

validate() {
  [ -n "${_OPT_ID+x}" ] || die 2 "--worktask-id is required"
  [ -n "${_OPT_GOAL+x}" ] || die 2 "--goal is required"
  _matches "$_OPT_ID" "$_ID_RE" || die 2 "invalid --worktask-id: $_OPT_ID"
  [ -n "$_OPT_GOAL" ] || die 2 "--goal is empty"
  _OPT_PLATFORM=${_OPT_PLATFORM-all}
  _matches "$_OPT_PLATFORM" "$_PLATFORM_RE" || die 2 "invalid --platform: $_OPT_PLATFORM"
  if [ -n "${_OPT_WORKSPACE_PATH+x}" ]; then
    case $_OPT_WORKSPACE_PATH in
      /*) ;;
      *) die 2 "--workspace-path must be absolute: $_OPT_WORKSPACE_PATH" ;;
    esac
  fi
}

# Prints the physical context dir, or returns 4. Callers run it in `$( ) ||`, where
# errexit is off, hence the explicit returns.
resolve_ctx() {
  local p="" top=""
  if [ -n "${_OPT_CONTEXT_DIR+x}" ]; then
    p=$(phys "$_OPT_CONTEXT_DIR") || return 4
    printf '%s\n' "$p"
    return 0
  fi
  case ${CONTEXT_DIR:-} in
    /*)
      if p=$(phys "$CONTEXT_DIR"); then
        printf '%s\n' "$p"
        return 0
      fi
      ;;
  esac
  case ${WORKSPACE_ROOT:-} in
    /*)
      if p=$(phys "$WORKSPACE_ROOT/.context"); then
        printf '%s\n' "$p"
        return 0
      fi
      ;;
  esac
  top=$(git rev-parse --show-toplevel 2> /dev/null) || top=""
  if [ -n "$top" ]; then
    top=$(phys "$top") || top=""
  fi
  [ -n "$top" ] || return 4
  if p=$(phys "$top/.context"); then
    printf '%s\n' "$p"
    return 0
  fi
  [ -n "${CLAUDE_PROJECT_DIR:-}" ] || return 4
  p=$(phys "$CLAUDE_PROJECT_DIR/.context") || return 4
  if [ "$p" = "$top" ]; then
    printf '%s\n' "$p"
    return 0
  fi
  # The "/" keeps /repo-x from passing as inside /repo.
  case $p in
    "$top"/*)
      printf '%s\n' "$p"
      return 0
      ;;
  esac
  return 4
}

refuse_if_exists() {
  if [ -e "$1" ] || [ -L "$1" ]; then
    printf 'result=exists\nstate=%s\n' "$1"
    printf >&2 'seed-state: refused: %s exists; re-runs are reset by PL0 (pl0-procedure.md \302\247 Step 4)\n' "$1"
    exit 3
  fi
}

# Next free planning index; suffixes are validated before arithmetic because $(( ))
# evaluates names recursively and a leading zero would parse as octal.
next_index() {
  local f b s n max=-1
  for f in "$1"/planning-*.md; do
    [ -e "$f" ] || continue
    b=${f##*/}
    s=${b#planning-}
    s=${s%.md}
    case $s in
      '' | *[!0-9]*) continue ;;
    esac
    [ "${#s}" -le 6 ] || continue
    n=$((10#$s))
    if [ "$n" -gt "$max" ]; then
      max=$n
    fi
  done
  printf '%s\n' "$((max + 1))"
}

acquire_lock() {
  local lock=$1 t=${STATE_LOCK_TIMEOUT_S:-5} deadline owner=""
  case $t in
    '' | *[!0-9]*) t=5 ;;
  esac
  [ "${#t}" -le 6 ] || t=5
  deadline=$((SECONDS + 10#$t))
  while :; do
    if mkdir -- "$lock" 2> /dev/null; then
      _LOCK_HELD=$lock
      return 0
    fi
    [ -d "$lock" ] || die 1 "cannot create lock $lock"
    if [ "$SECONDS" -ge "$deadline" ]; then
      if [ -r "$lock/owner" ]; then
        owner=$(head -c 256 -- "$lock/owner" 2> /dev/null | LC_ALL=C tr -d '\000-\037') || owner=""
      fi
      die 1 "lock timeout after ${t}s: $lock is held (owner: ${owner:-unknown}); it is never broken"
    fi
    sleep 1
  done
}

main() {
  local ctx="" rc=0 state n norm ws top plan

  parse_args "$@"
  validate

  ctx=$(resolve_ctx) || rc=$?
  if [ "$rc" -ne 0 ]; then
    if [ -n "${_OPT_CONTEXT_DIR+x}" ]; then
      die 4 "--context-dir is not a directory: $_OPT_CONTEXT_DIR"
    fi
    die 4 "no .context/ resolves inside this worktree; nothing written"
  fi
  state="$ctx/state.json"
  refuse_if_exists "$state"

  command -v jq > /dev/null 2>&1 || die 1 "jq not found on PATH"

  norm=$(jq -nr --arg g "$_OPT_GOAL" "$_GOAL_FILTER") || die 1 "jq failed to normalize --goal"
  [ -n "$norm" ] || die 2 "--goal is empty after removing control characters and edge spaces"

  if [ -n "${_OPT_WORKSPACE_PATH+x}" ]; then
    ws=$_OPT_WORKSPACE_PATH
  else
    top=$(git rev-parse --show-toplevel 2> /dev/null) || top=""
    ws=""
    if [ -n "$top" ]; then
      ws=$(phys "$top") || ws=""
    fi
    if [ -z "$ws" ]; then
      ws=$(pwd -P) || die 1 "cannot resolve the working directory"
    fi
  fi

  n=$(next_index "$ctx")
  plan=".context/planning-$n.md"

  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  acquire_lock "$state.lock.d"
  refuse_if_exists "$state"

  local tmp="$ctx/.state.json.$$.${RANDOM}.tmp"
  # noclobber success is the proof the temp is ours; only then may cleanup delete it.
  (set -C && : > "$tmp") 2> /dev/null || die 1 "cannot create temp file $tmp"
  _TMP=$tmp
  jq -n \
    --arg id "$_OPT_ID" \
    --arg plan "$plan" \
    --arg platform "$_OPT_PLATFORM" \
    --argjson n "$n" \
    --arg ws "$ws" \
    --arg goal "$norm" \
    '{version: 2, worktask_id: $id, plan_file: $plan, platform: $platform, run_index: $n,
      metadata: {workspace_path: $ws},
      tasks: {PL0: {status: "in_progress"}},
      facts: {goal: $goal, files_modified: [], tests_added: [], decisions: [],
              open_questions: [], verdicts: {}, dispatched_agents: []},
      handoffs: {}}' > "$tmp" 2> /dev/null || die 1 "cannot write $tmp"
  sync "$tmp" 2> /dev/null || sync 2> /dev/null || true
  mv -f -- "$tmp" "$state" 2> /dev/null || die 1 "cannot rename $tmp to $state"
  _TMP=""
  cleanup

  printf 'result=seeded\nstate=%s\nrun_index=%s\nplan_file=%s\n' "$state" "$n" "$plan"
}

if [ "${1:-}" = "--self-test" ]; then
  [ $# -eq 1 ] || die 2 "--self-test takes no other arguments"
  _SELFTEST_LIB="$(dirname "${BASH_SOURCE[0]}")/seed-state-selftest.sh"
  # `[ -r ]` first: a failed `.` of a missing file exits the shell before any guard runs.
  if [ ! -r "$_SELFTEST_LIB" ]; then
    printf >&2 'seed-state: self-test harness unreadable at %s\n' "$_SELFTEST_LIB"
    exit 1
  fi
  # shellcheck source-path=SCRIPTDIR source=seed-state-selftest.sh
  . "$_SELFTEST_LIB"
  if self_test; then
    exit 0
  fi
  exit 1
fi

main "$@"

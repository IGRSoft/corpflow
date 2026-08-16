#!/usr/bin/env bash
# @description dv-tree-preflight.sh — DV pre-edit assertion that the resolved tree IS
#   the assigned tree.
#
#   D0 records the git root and D0.0 asserts the tree is isolated. Neither compares the
#   resolved root against the workspace the stage was ASSIGNED. Isolation does not imply
#   assignment: a stale worktree satisfies both existing gates. This script asserts the
#   missing half and nothing else.
#
#   Checks, in order:
#     1. MISMATCH (blocking)  — `git rev-parse --show-toplevel` != the assigned workspace.
#     2. LINKAGE (advisory)   — the tree is not a linked worktree.
#     3. ANCESTRY (advisory)  — HEAD does not descend from the integration branch.
#   Only check 1 blocks. An input that does not resolve degrades to a warning: a
#   pre-flight that false-blocks DV is worse than the failure it guards against.
#
# @arg --assigned <path>  The workspace DV was dispatched against. When omitted, falls
#                         back to state.json `.metadata.workspace_path`, then to
#                         $WORKSPACE_ROOT. Unresolved ⇒ warn, never block.
# @arg --state <path>     state.json path (default: .context/state.json).
# @arg --quiet            Suppress advisory warnings; a mismatch still prints and blocks.
# @arg --self-test        Run the built-in self-test and exit.
# @arg -h | --help        Show this header.
#
# @exitcode 0  Assigned tree confirmed (or inputs unresolved — warned, not blocked).
# @exitcode 1  MISMATCH: the resolved git root is not the assigned workspace. Do not edit.
# @exitcode 2  Usage error.
#
# Minimum shell: bash 3.2+ (macOS default).

set -euo pipefail
IFS=$'\n\t'

usage() {
  sed -n 's/^# \{0,1\}//p' "$0" | head -30
  exit 2
}

warn() { [[ -n "${QUIET:-}" ]] || printf >&2 'WARN: %s\n' "$1"; }

# Physical-path normalization. Load-bearing rather than defensive: /tmp is a symlink to
# /private/tmp on macOS, so a raw string compare calls two names for the same directory a
# mismatch and blocks DV in exactly the tmpdir the test suite runs in.
realpath_of() {
  local p="$1"
  [[ -z "$p" ]] && return 1
  (CDPATH= cd -- "$p" 2> /dev/null && pwd -P) || return 1
}

# Mirrors branch-name.sh is_host_workspace(), inverted: true when THIS tree is a linked
# worktree. Both dirs are resolved physically first — from a subdirectory git answers
# --git-dir absolutely and --git-common-dir relatively, and a raw compare then calls every
# nested cwd a worktree.
is_linked_worktree() {
  local d c
  d=$(git rev-parse --git-dir 2> /dev/null) || return 1
  c=$(git rev-parse --git-common-dir 2> /dev/null) || return 1
  [[ -n "$d" && -n "$c" ]] || return 1
  d=$(realpath_of "$d") || return 1
  c=$(realpath_of "$c") || return 1
  [[ "$d" != "$c" ]]
}

# Ranked resolution of the assigned workspace. metadata.workspace_path is a Task-System
# field that state.json is not schema-obliged to carry, so every rank may legitimately
# come back empty — hence the warn-not-block contract at the call site.
resolve_assigned() {
  local v="${ASSIGNED_ARG:-}"
  if [[ -z "$v" && -f "$STATE_PATH" ]] && command -v jq > /dev/null 2>&1; then
    v=$(jq -r '.metadata.workspace_path // empty' "$STATE_PATH" 2> /dev/null || printf '')
  fi
  [[ -z "$v" ]] && v="${WORKSPACE_ROOT:-}"
  [[ "$v" == "null" ]] && v=""
  printf '%s' "$v"
}

# Integration branch, same ranked order as branch-lib.sh resolve_base_ref(): no hardcoded
# literal, unresolved reported rather than guessed.
resolve_base_ref() {
  local v="${FN_BASE_REF:-}"
  if [[ -z "$v" && -f "$STATE_PATH" ]] && command -v jq > /dev/null 2>&1; then
    v=$(jq -r '.metadata.base_ref // empty' "$STATE_PATH" 2> /dev/null || printf '')
  fi
  if [[ -z "$v" ]]; then
    v=$(git symbolic-ref --short refs/remotes/origin/HEAD 2> /dev/null || printf '')
  fi
  [[ "$v" == "null" ]] && v=""
  printf '%s' "$v"
}

cmd_check() {
  local root assigned assigned_real base

  root=$(git rev-parse --show-toplevel 2> /dev/null || printf '')
  if [[ -z "$root" ]]; then
    warn "not inside a git work tree — cannot verify the assigned tree; skipping"
    return 0
  fi
  # An unresolvable git root is an unresolved INPUT, not a mismatch. Blanking it here would
  # compare unequal below and block DV over an unrelated failure — the one outcome this
  # script's contract rules out.
  root=$(realpath_of "$root") || {
    warn "could not resolve the git root to a physical path — cannot compare; proceeding"
    return 0
  }

  assigned=$(resolve_assigned)
  if [[ -z "$assigned" ]]; then
    warn "assigned workspace unresolved (no --assigned, no state.json .metadata.workspace_path, no \$WORKSPACE_ROOT) — cannot compare; proceeding"
    return 0
  fi
  assigned_real=$(realpath_of "$assigned") || {
    warn "assigned workspace does not exist on disk: $assigned — cannot compare; proceeding"
    return 0
  }

  # 1. The blocking check. Naming BOTH paths is the whole point: the source failure was
  #    an agent that knew its tree and never learned it was the wrong one.
  if [[ "$root" != "$assigned_real" ]]; then
    printf >&2 'MISMATCH: DV resolved a different tree than it was assigned.\n  resolved git root: %s\n  assigned workspace: %s\nDo NOT edit. Re-enter the assigned tree (EnterWorktree with the assigned path) and re-run D0.\n' \
      "$root" "$assigned_real"
    return 1
  fi

  # 1a. Worktree-parent ambiguity. Advisory — this stream is provably on the right
  #     tree (check 1 passed), so blocking it would stop a correct stream over a
  #     condition that harms a DIFFERENT one. But it is reported loudly, because it
  #     is the latent cause of check 1 firing at all.
  #
  #     When linked worktrees live under more than one parent directory, anything
  #     that reconstructs a worktree path BY CONVENTION — rather than reading the
  #     task's own metadata.workspace_path — has to guess a prefix. It globs one,
  #     and gets another stream's directory. Observed cost in one four-stream run:
  #     a stream was assigned `.claude/worktrees/dv3-web` and handed
  #     `.worktrees/dv0-service` at spawn on four consecutive dispatches, because
  #     `.worktrees/` held exactly one entry for the glob to land on. Normalising
  #     to a single parent fixed it on the next dispatch.
  #
  #     Cheap to check, and it names the condition before four streams pay for it.
  local _main_common _main_checkout _wt_line _wt_path _wt_parent _parents _n_parents
  _main_common=$(git rev-parse --git-common-dir 2> /dev/null || printf '')
  _main_checkout=""
  if [[ -n "$_main_common" ]]; then
    _main_checkout=$(cd "$(dirname "$_main_common")" 2> /dev/null && pwd) || _main_checkout=""
  fi
  _parents=""
  while IFS= read -r _wt_line; do
    [[ "$_wt_line" == worktree\ * ]] || continue
    _wt_path="${_wt_line#worktree }"
    # The main checkout is not a linked worktree; its parent says nothing about
    # where linked worktrees are placed.
    [[ -n "$_main_checkout" && "$_wt_path" == "$_main_checkout" ]] && continue
    _wt_parent=$(dirname "$_wt_path")
    case "
$_parents" in
      *"
$_wt_parent"*) : ;;
      *) _parents="$_parents
$_wt_parent" ;;
    esac
  done < <(git worktree list --porcelain 2> /dev/null)
  _n_parents=$(printf '%s' "$_parents" | grep -c . || true)
  if [[ "${_n_parents:-0}" -gt 1 ]]; then
    printf >&2 'WARN: linked worktrees are split across %s parent directories:\n' "$_n_parents"
    printf '%s\n' "$_parents" | grep . | while IFS= read -r _wt_parent; do
      printf >&2 '  %s/\n' "$_wt_parent"
    done
    printf >&2 'A path rebuilt by convention instead of from metadata.workspace_path can resolve into the wrong parent and hand a stage another stream'"'"'s tree. Normalise every stage worktree under ONE parent (%s is where EnterWorktree can reach).\n' \
      "${_main_checkout:+$_main_checkout/}.claude/worktrees"
  fi

  # 2/3. Advisory only — a true statement about a tree that is nonetheless the right one.
  is_linked_worktree || warn "tree is not a linked worktree (D0.0 isolation): $root"

  base=$(resolve_base_ref)
  if [[ -z "$base" ]]; then
    warn "integration branch unresolved — skipping ancestry check"
  elif git rev-parse --verify --quiet "$base" > /dev/null 2>&1; then
    git merge-base --is-ancestor "$base" HEAD 2> /dev/null \
      || warn "HEAD does not descend from $base — the branch may be stale; rebase before editing"
  else
    warn "integration branch $base is not resolvable in this tree — skipping ancestry check"
  fi

  return 0
}

run_self_test() {
  local SELF td repo wt rc out
  SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
  td=$(mktemp -d -t dv-tree-preflight-XXXXXX)
  # shellcheck disable=SC2064  # expand $td now so the trap removes the right dir
  trap "rm -rf '${td}'" EXIT

  repo="$td/repo"
  mkdir -p "$repo"
  (
    cd "$repo"
    git init -q .
    git config user.email t@t.t
    git config user.name t
    printf 'x\n' > f.txt
    git add f.txt
    git commit -qm init
  )

  # S1: matching tree passes silently.
  set +e
  out=$(cd "$repo" && bash "$SELF" --assigned "$repo" --quiet 2>&1)
  rc=$?
  set -e
  if [[ "$rc" -eq 0 && -z "$out" ]]; then
    printf 'S1: matching tree passes silently: ok\n'
  else
    printf 'S1: matching tree must pass silently (rc=%s out=%s): FAIL\n' "$rc" "$out" >&2
    exit 1
  fi

  # S2: a different tree blocks and names both paths.
  wt="$td/other"
  mkdir -p "$wt"
  set +e
  out=$(cd "$repo" && bash "$SELF" --assigned "$wt" 2>&1)
  rc=$?
  set -e
  if [[ "$rc" -eq 1 ]] && printf '%s' "$out" | grep -q 'MISMATCH'; then
    printf 'S2: mismatched tree blocks naming both paths: ok\n'
  else
    printf 'S2: mismatched tree must exit 1 (rc=%s): FAIL\n' "$rc" >&2
    exit 1
  fi

  # S3: unresolved assignment warns rather than blocking.
  set +e
  out=$(cd "$repo" && WORKSPACE_ROOT="" bash "$SELF" --state /nonexistent/state.json 2>&1)
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]] && printf '%s' "$out" | grep -q 'WARN'; then
    printf 'S3: unresolved assignment warns, never blocks: ok\n'
  else
    printf 'S3: unresolved assignment must warn and exit 0 (rc=%s): FAIL\n' "$rc" >&2
    exit 1
  fi

  printf 'self-test: ALL PASS\n'
  exit 0
}

ASSIGNED_ARG=""
STATE_PATH=".context/state.json"
QUIET=""
CMD="check"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --assigned)
      shift
      ASSIGNED_ARG="${1:-}"
      shift
      ;;
    --state)
      shift
      STATE_PATH="${1:-}"
      shift
      ;;
    --quiet)
      QUIET="1"
      shift
      ;;
    --self-test)
      CMD="self-test"
      shift
      ;;
    -h | --help) usage ;;
    *)
      printf >&2 'unknown argument: %s\n' "$1"
      usage
      ;;
  esac
done

# Dispatch table rather than a straight-line main: the blocking check is the same predicate
# a PreToolUse hook would need, so wiring one later is a new arm, not a rewrite.
case "$CMD" in
  check) cmd_check ;;
  self-test) run_self_test ;;
  *)
    printf >&2 'unknown command: %s\n' "$CMD"
    usage
    ;;
esac

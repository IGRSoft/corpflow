#!/usr/bin/env bash
# @description fn-preflight.sh — the FN-stage pre-`gh pr create` validator battery,
#   extracted from agents/project-manager.md so the agent body carries a pointer call
#   instead of ~40 lines of inline jq/git one-liners (Phase-4 Worktask-Integration diet).
#
#   Checks, each also runnable standalone:
#     attachments    both Conductor attachment files exist (gate trip-wire mirror).
#     resolve-issue  print the issue number from ranked sources (first-match-wins).
#     validate-pr    the composed PR body carries `Closes #<n>` for the resolved issue,
#                    OR (no issue resolvable) append an audit-defer row and pass.
#     pr-body        the composed body was produced by the mandated pipeline, not
#                    hand-authored: sanitises it in place with publish-pl-issue.sh's
#                    own `sanitise_body`, then requires a `Test plan` heading and,
#                    on a screenshot-requiring run, the visual-evidence helper's
#                    audit row for THIS run index. Then runs pr-body-lint.sh over
#                    the sanitised body (warn-only; never changes this verdict).
#     continuity     the worktree HEAD is an ancestor of the integration branch, else
#                    log a diverged→cherry-pick diagnostic + audit row (never blocks).
#     branch-divergence
#                    has anything outside the pipeline renamed the local branch since the
#                    naming step? Compares the local name against the `to` of the last
#                    `branch_renamed / ok` row — NOT against facts.branch, which is the
#                    planned REMOTE name and legitimately differs on several arms. Classes
#                    the result `third_party` or `expected`; only `third_party` is surfaced
#                    at the FN gate. Read-only, exit 0 always, never blocks.
#     issue-close-required
#                    is the integration branch something other than the repository
#                    default? If so the `Closes #N` merge trailer will never fire, so
#                    print the explicit `gh issue close` command FN must run post-merge.
#                    Read-only, exit 0 always; unresolved inputs report, never guess.
#     all            attachments → pr-body → validate-pr → continuity.
#
#   `branch-divergence` and `issue-close-required` are deliberately NOT in `all`: each is a
#   separate subcommand so it is independently testable and cannot perturb `continuity`'s
#   existing rows. `issue-close-required` additionally runs POST-merge, not pre-`pr create`.
#
#   `pr-body` runs BEFORE `validate-pr` because it rewrites the body in place: the
#   body whose `Closes #<n>` line is validated must be the byte-identical body that
#   reaches `gh pr create`.
#
#   Under batch (`/megatask`) and incident (`--emergency`) routing, `pr-body` still
#   sanitises — a working-folder path must not reach a published body on any route —
#   but drops its blocking checks: the composition requirements are skipped and an
#   unreachable sanitiser library degrades to a warning instead of exit 1. See
#   `fn_batch_scope` (branch-lib.sh) for the five signals.
#
#   Branch naming moved to the start of the planning stage (see
#   `skills/shared/git-conventions.md § Branch Naming`). This validator never
#   renames anything.
#
#   Behavior is byte-for-byte the logic documented in
#   agents/project-manager.md § FN Stage; this script is the single implementation the
#   agent and its tests share.  Zero network: no `gh`, no `git push`, no fetch.
#
# @arg --state <path>     state.json path (default: .context/state.json).
# @arg --context <dir>    .context dir (default: .context).
# @arg --body <path>      Composed PR body file (required by validate-pr / pr-body / all).
# @arg -h | --help        Show this header.
#
# @env FN_BASE_REF        Highest-priority integration-branch override (see resolve_base_ref).
# @env MILESTONE_MODE     1 => batch routing; `pr-body` sanitises but stops blocking.
# @env INCIDENT_MODE      1 => incident routing; same non-blocking mode.
#
# @exitcode 0   Check passed (or a non-blocking degrade: no issue resolvable / diverged /
#               scope-disabled).
# @exitcode 1   Blocking failure (missing attachment; body missing the closing keyword;
#               `pr-body`: missing `Test plan` heading, missing or contradicted
#               visual-evidence evidence, or an unreachable sanitiser library).
# @exitcode 2   Usage error (unknown command/flag; `pr-body`/`validate-pr` without --body).
# @exitcode 3   branch-lib.sh unreachable — no dispatch runs (plugin install broken).
#
# Minimum shell: bash 3.2+ (macOS default). Mirrors state-patch.sh conventions.

set -euo pipefail
IFS=$'\n\t'

STATE_PATH=".context/state.json"
CONTEXT_DIR=".context"
BODY_FILE=""

# Physical directory of this script. CDPATH= disables a benign-but-common
# CDPATH setting that otherwise makes `cd` echo an extra line into this very
# capture, corrupting the path silently; `pwd -P` plus the readlink loop follow
# a symlinked script to its real directory so sibling-library resolution cannot
# be redirected onto an attacker-planted file next to the symlink.
_resolve_script_dir() {
  local src="${BASH_SOURCE[0]:-$0}" dir
  while [ -h "$src" ]; do
    dir=$(CDPATH= cd -- "$(dirname -- "$src")" && pwd -P)
    src=$(readlink "$src")
    case "$src" in
      /*) ;;
      *) src="$dir/$src" ;;
    esac
  done
  CDPATH= cd -- "$(dirname -- "$src")" && pwd -P
}
SCRIPT_DIR="$(_resolve_script_dir 2> /dev/null)" || SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]:-$0}")"

# Sanitiser library, resolved from this script's own location (mirrors
# attach-visual-evidence.sh:69).
# shellcheck disable=SC2034  # read by sanitise_stream in fn-preflight-cmds.sh
LIB_PATH="${SCRIPT_DIR}/publish-pl-issue.sh"

# Shared helpers (meta_json, audit_fn, fn_batch_scope, resolve_base_ref). This
# file's only failure mode is absence — a same-directory, same-commit sibling
# missing means the plugin install is broken, in which case this script is
# equally suspect. Loud and immediate: no dispatch runs on a broken install.
BRANCH_LIB_PATH="${SCRIPT_DIR}/branch-lib.sh"
# `[ -f ]` first, not a bare `.`: sourcing a missing file with the `.` builtin is a
# special-builtin error that exits a `set -e` shell immediately, bypassing an
# `if ! . …; then` guard entirely (verified on bash 3.2 and 5.x).
if [ -n "$BRANCH_LIB_PATH" ] && [ -r "$BRANCH_LIB_PATH" ]; then
  # shellcheck disable=SC1090
  . "$BRANCH_LIB_PATH"
else
  printf >&2 'fn-preflight.sh: branch-lib.sh unreachable at %s — plugin install broken\n' \
    "$BRANCH_LIB_PATH"
  exit 3
fi

# Every cmd_* body and the four helpers they share. Sourced AFTER branch-lib.sh
# because those bodies call its audit_fn/meta_json/fn_batch_scope/resolve_base_ref,
# and because T4 pins branch-lib.sh as the first sibling a broken install reports.
# Same absence-is-the-only-failure-mode contract, same exit 3.
CMDS_LIB_PATH="${SCRIPT_DIR}/fn-preflight-cmds.sh"
# `[ -f ]` first, not a bare `.`: sourcing a missing file with the `.` builtin is a
# special-builtin error that exits a `set -e` shell immediately, bypassing an
# `if ! . …; then` guard entirely (verified on bash 3.2 and 5.x).
if [ -n "$CMDS_LIB_PATH" ] && [ -r "$CMDS_LIB_PATH" ]; then
  # shellcheck disable=SC1090
  . "$CMDS_LIB_PATH"
else
  printf >&2 'fn-preflight.sh: fn-preflight-cmds.sh unreachable at %s — plugin install broken\n' \
    "$CMDS_LIB_PATH"
  exit 3
fi

usage() {
  awk 'NR>1{ if (!/^#/) exit; sub(/^# ?/,""); print }' "$0"
  exit 2
}

# ---------- Argument parsing ----------
COMMAND=""
# shellcheck disable=SC2034  # STATE_PATH/CONTEXT_DIR/BODY_FILE are read by fn-preflight-cmds.sh
while [[ $# -gt 0 ]]; do
  case "$1" in
    --state)
      shift
      STATE_PATH="${1:-}"
      shift
      ;;
    --context)
      shift
      CONTEXT_DIR="${1:-}"
      shift
      ;;
    --body)
      shift
      BODY_FILE="${1:-}"
      shift
      ;;
    -h | --help) usage ;;
    attachments | resolve-issue | validate-pr | pr-body | continuity | branch-divergence | issue-close-required | all)
      COMMAND="$1"
      shift
      ;;
    *)
      printf >&2 'unknown argument: %s\n' "$1"
      usage
      ;;
  esac
done

[[ -n "$COMMAND" ]] || {
  printf >&2 'no command given\n'
  usage
}

case "$COMMAND" in
  attachments) cmd_attachments ;;
  resolve-issue) resolve_issue && printf '\n' ;;
  validate-pr) cmd_validate_pr ;;
  pr-body) cmd_pr_body ;;
  continuity) cmd_continuity ;;
  branch-divergence) cmd_branch_divergence ;;
  issue-close-required) cmd_issue_close_required ;;
  all)
    cmd_attachments && cmd_pr_body && cmd_validate_pr && cmd_continuity
    ;;
esac

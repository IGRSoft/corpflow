#!/usr/bin/env bash
# @description branch-name.sh — the PL-stage branch-naming entry point. Renames the
#   current branch onto `<type>/<slug>` (no ticket — see git-conventions.md § Branch
#   Naming), once, at the very start of the planning stage, before any commit exists.
#
#   Sources branch-lib.sh from its own directory for the guard ladder, the type
#   vocabulary, goal resolution, and the audit/scope helpers. This script never
#   resolves an issue number and never writes state.json — it prints `branch=<name>`
#   and the orchestrator stamps `facts.branch` through the normal state-patch path.
#
#   Every rename-mode outcome exits 0, including an unreachable library: a naming
#   problem must never stop a worktask from planning. `--check`/`--print-types` are
#   query modes with no git mutation and no audit row.
#
# @arg --goal <text>      Explicit goal text (Q1). Ranked fallbacks:
#                          argument > state.json .facts.goal > .worktask_id.
# @arg --state <path>     state.json path (default: .context/state.json).
# @arg --context <dir>    .context dir (default: .context).
# @arg --check <name>     Query: is <name> conventional? No git, no state, no audit row.
# @arg --print-types      Query: the type vocabulary, one token per line.
# @arg -h | --help        Show this header.
#
# @env BRANCH_NAME_PRINT  1 => dry run: print the bare target, rename nothing, no
#                         audit row, no `branch=` line. Evaluated AFTER the guard
#                         ladder so a dry run can never bypass a guard.
# @env MILESTONE_MODE     1 => batch routing; self-disables.
# @env INCIDENT_MODE      1 => incident routing; self-disables.
# @env WORKSPACE_ROOT     Read transitively by fn_batch_scope / resolve_base_ref.
# @env FN_BASE_REF        Highest-priority integration-branch override (unrenamed
#                         despite the prefix — see handoff-protocol.md § metadata.base_ref).
#
# @exitcode 0   Every rename-mode outcome (ok, noop, failed, skipped, unreachable
#               library). `--check`: not conventional.
# @exitcode 2   Usage error, or `--check` on an internal regex fault.
#
# Minimum shell: bash 3.2+ (macOS default).

set -euo pipefail
IFS=$'\n\t'

STATE_PATH=".context/state.json"
CONTEXT_DIR=".context"
GOAL_ARG=""
MODE="rename"
CHECK_NAME=""

usage() {
  awk 'NR>1{ if (!/^#/) exit; sub(/^# ?/,""); print }' "$0"
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --goal)
      shift
      [ $# -gt 0 ] || {
        printf >&2 'branch-name: --goal requires a value\n'
        exit 2
      }
      GOAL_ARG="$1"
      shift
      ;;
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
    --check)
      shift
      [ $# -gt 0 ] || {
        printf >&2 'branch-name: --check requires a value\n'
        exit 2
      }
      MODE="check"
      CHECK_NAME="$1"
      shift
      ;;
    --print-types)
      MODE="print-types"
      shift
      ;;
    -h | --help) usage ;;
    *)
      printf >&2 'branch-name: unknown argument: %s\n' "$1"
      usage
      ;;
  esac
done

# Resolved from this script's own location (mirrors fn-preflight.sh's sanitiser-lib
# resolution). BASH_SOURCE, not $0: correct when sourced by bats.
LIB_PATH="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2> /dev/null && pwd)/branch-lib.sh"

# shellcheck disable=SC1090
if ! . "$LIB_PATH" 2> /dev/null; then
  # The library's only failure mode is absence (architecture-0.md § R-4): a
  # same-directory, same-commit sibling missing means the plugin install itself is
  # broken. A query mode has nothing to answer without the predicate/list it needs;
  # rename mode degrades loud-but-non-blocking, matching R2's "never blocks" contract.
  if [ "$MODE" != "rename" ]; then
    exit 2
  fi
  printf >&2 'branch-name: branch-lib.sh unreachable at %s — skipping rename\n' "$LIB_PATH"
  cur=$(git rev-parse --abbrev-ref HEAD 2> /dev/null || printf '')
  mkdir -p "${CONTEXT_DIR}/logs" 2> /dev/null || true
  if command -v jq > /dev/null 2>&1; then
    # Self-contained audit row: the library that would supply audit_fn is exactly
    # what is missing, so this one path cannot delegate to it.
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    wid=$(jq -r '.worktask_id // "unknown"' "$STATE_PATH" 2> /dev/null || printf 'unknown')
    ri=$(jq -r '.run_index // 0' "$STATE_PATH" 2> /dev/null || printf '0')
    jq -cn --arg ts "$ts" --arg wid "$wid" --arg ri "$ri" \
      '{ts:$ts, actor:"product-manager", action:"branch_renamed", subject:("PL" + $ri),
        result:"noop", task_id:"PL0",
        metadata:{reason:"branch_lib_unreachable", origin_stage:"PL",
                  dedupe_key:($wid + ":" + $ri + ":branch_renamed")}}' \
      >> "${CONTEXT_DIR}/logs/audit.jsonl" 2> /dev/null || true
  fi
  printf 'branch-name: library unreachable — skipped\n'
  printf 'branch=%s\n' "$cur"
  exit 0
fi

cmd_check() {
  branch_is_conventional "$CHECK_NAME"
  exit $?
}

cmd_print_types() {
  local line
  local IFS=$'\n'
  for line in $BRANCH_TYPES; do
    [ -n "$line" ] && printf '%s\n' "$line"
  done
  exit 0
}

# Guard ladder — first hit wins, and every arm exits 0. This step is a courtesy
# rename, never a gate: no naming problem is worth failing a planning stage over.
cmd_rename() {
  local apply=1
  [ "${BRANCH_NAME_PRINT:-0}" = "1" ] && apply=0

  # Identity for audit_fn's call-time read (architecture-0.md § audit_fn
  # parameterization) — this is the PL-stage row, distinct from FN's defaults.
  AUDIT_ACTOR="product-manager"
  local ri
  ri=$(jq -r '.run_index // 0' "$STATE_PATH" 2> /dev/null || printf '0')
  AUDIT_SUBJECT="PL${ri}"
  AUDIT_STAGE="PL"

  if fn_batch_scope; then
    printf 'branch-name: skipped (%s)\n' "$SCOPE_REASON"
    audit_fn branch_renamed skipped "$(meta_json reason "$SCOPE_REASON")"
    printf 'branch=%s\n' "$(git rev-parse --abbrev-ref HEAD 2> /dev/null || printf '')"
    return 0
  fi

  git rev-parse --git-dir > /dev/null 2>&1 || {
    printf 'branch-name: not a git repo — skipped\n'
    printf 'branch=%s\n' ""
    return 0
  }

  local cur
  cur=$(git rev-parse --abbrev-ref HEAD 2> /dev/null || printf '')
  if [ -z "$cur" ] || [ "$cur" = "HEAD" ]; then
    printf 'branch-name: detached HEAD — skipped\n'
    printf 'branch=%s\n' "$cur"
    return 0
  fi

  # A conventional name is a deliberate name — never churn one. This is also the
  # arm that makes a real run here a no-op once BRANCH_TYPES includes `feature`.
  if branch_is_conventional "$cur"; then
    printf 'branch-name: already conventional (%s) — no-op\n' "$cur"
    audit_fn branch_renamed noop "$(meta_json reason already_conventional branch "$cur")"
    printf 'branch=%s\n' "$cur"
    return 0
  fi

  # Renaming a branch that already has an upstream orphans the remote ref.
  if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' > /dev/null 2>&1; then
    printf 'branch-name: upstream already tracked — no-op\n'
    audit_fn branch_renamed noop "$(meta_json reason upstream_tracked branch "$cur")"
    printf 'branch=%s\n' "$cur"
    return 0
  fi

  local base
  base=$(resolve_base_ref)
  if [ -n "$base" ] && [ "$cur" = "${base#origin/}" ]; then
    printf 'branch-name: on the integration branch (%s) — refusing to rename\n' "$cur"
    audit_fn branch_renamed noop "$(meta_json reason on_integration_branch branch "$cur")"
    printf 'branch=%s\n' "$cur"
    return 0
  fi

  # Without jq, fn_batch_scope cannot see the ledger/workspace batch signals, so
  # scope is unknowable and renaming would be unsafe — refuse rather than guess.
  if ! command -v jq > /dev/null 2>&1; then
    printf 'branch-name: target unresolvable — no-op\n'
    audit_fn branch_renamed noop "$(meta_json reason jq_unavailable)"
    printf 'branch=%s\n' "$cur"
    return 0
  fi

  local goal type slug target
  goal=$(resolve_goal "$GOAL_ARG")
  type=$(derive_type "$goal")
  slug=$(derive_slug "$goal")
  target=$(target_branch_name "$type" "$slug" 2> /dev/null || printf '')

  if [ -z "$target" ]; then
    printf 'branch-name: target unresolvable — no-op\n'
    audit_fn branch_renamed noop "$(meta_json reason target_unresolvable)"
    printf 'branch=%s\n' "$cur"
    return 0
  fi

  if [ "$cur" = "$target" ]; then
    printf 'branch-name: already %s — no-op\n' "$target"
    printf 'branch=%s\n' "$cur"
    return 0
  fi

  if [ "$apply" -eq 0 ]; then
    printf '%s\n' "$target"
    return 0
  fi

  if git show-ref --verify --quiet "refs/heads/$target"; then
    printf 'branch-name: %s already exists — no-op\n' "$target"
    audit_fn branch_renamed noop "$(meta_json reason target_exists target "$target")"
    printf 'branch=%s\n' "$cur"
    return 0
  fi

  if git branch -m "$target" 2> /dev/null; then
    printf 'branch-name: %s -> %s\n' "$cur" "$target"
    audit_fn branch_renamed ok "$(meta_json from "$cur" to "$target")"
    printf 'branch=%s\n' "$target"
  else
    printf >&2 'branch-name: rename failed (%s -> %s) — continuing\n' "$cur" "$target"
    audit_fn branch_renamed failed "$(meta_json from "$cur" to "$target")"
    printf 'branch=%s\n' "$cur"
  fi
  return 0
}

case "$MODE" in
  check) cmd_check ;;
  print-types) cmd_print_types ;;
  rename) cmd_rename ;;
esac

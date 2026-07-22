#!/usr/bin/env bash
# @description fn-preflight.sh — the FN-stage pre-`gh pr create` validator battery,
#   extracted from agents/project-manager.md so the agent body carries a pointer call
#   instead of ~40 lines of inline jq/git one-liners (Phase-4 Worktask-Integration diet).
#
#   Three checks, each also runnable standalone:
#     attachments    both Conductor attachment files exist (gate trip-wire mirror).
#     resolve-issue  print the issue number from ranked sources (first-match-wins).
#     validate-pr    the composed PR body carries `Closes #<n>` for the resolved issue,
#                    OR (no issue resolvable) append an audit-defer row and pass.
#     continuity     the worktree HEAD is an ancestor of the integration branch, else
#                    log a diverged→cherry-pick diagnostic + audit row (never blocks).
#     all            attachments → validate-pr → continuity (the FN preflight sequence).
#
#   Behavior is byte-for-byte the logic documented in
#   agents/project-manager.md § FN Stage; this script is the single implementation the
#   agent and its tests share.  Zero network: no `gh`, no `git push`, no fetch.
#
# @arg --state <path>     state.json path (default: .context/state.json).
# @arg --context <dir>    .context dir (default: .context).
# @arg --body <path>      Composed PR body file (required by validate-pr / all).
# @arg -h | --help        Show this header.
#
# @exitcode 0   Check passed (or a non-blocking degrade: no issue resolvable / diverged).
# @exitcode 1   Blocking failure (missing attachment; body missing the closing keyword).
# @exitcode 2   Usage error (unknown command/flag).
#
# Minimum shell: bash 3.2+ (macOS default). Mirrors state-patch.sh conventions.

set -euo pipefail
IFS=$'\n\t'

STATE_PATH=".context/state.json"
CONTEXT_DIR=".context"
BODY_FILE=""

usage() {
  sed -n 's/^# \{0,1\}//p' "$0" | head -40
  exit 2
}

# ---------- Issue resolver (ranked, first-match-wins) ----------
# 1. state.json .metadata.github_issue_url  — trailing integer of /issues/<N>.
# 2. .context/gh-issue.json .url (trailing int) or .number — follow-up-run anchor.
# 3. state.json .metadata.github_issue_number — megatask per-issue mode.
# 4. branch parse: feature/<slug>-<NNN> trailing int, else first #NNN in last 5 commits.
resolve_issue() {
  local n=""
  if command -v jq > /dev/null 2>&1; then
    n=$(jq -r '.metadata.github_issue_url // empty' "$STATE_PATH" 2> /dev/null \
      | grep -oE '[0-9]+$' || true)
    [[ -z "$n" ]] && n=$(jq -r 'if .url then .url elif .number then (.number|tostring) else empty end' \
      "${CONTEXT_DIR}/gh-issue.json" 2> /dev/null | grep -oE '[0-9]+$' || true)
    [[ -z "$n" ]] && n=$(jq -r '.metadata.github_issue_number // empty' "$STATE_PATH" 2> /dev/null || true)
  fi
  [[ -z "$n" ]] && n=$(git rev-parse --abbrev-ref HEAD 2> /dev/null | grep -oE '[0-9]+$' || true)
  [[ -z "$n" ]] && n=$(git log --oneline -n 5 2> /dev/null | grep -oE '#[0-9]+' | head -1 | tr -d '#' || true)
  printf '%s' "$n"
}

# ---------- Commands ----------
cmd_attachments() {
  local pr="${CONTEXT_DIR}/attachments/PR instructions.md"
  local rr="${CONTEXT_DIR}/attachments/Review request.md"
  if [[ -f "$pr" && -f "$rr" ]]; then
    printf 'attachments: both present\n'
    return 0
  fi
  printf >&2 'BLOCKED: missing Conductor attachment(s):%s%s\n' \
    "$([[ -f "$pr" ]] || printf ' "PR instructions.md"')" \
    "$([[ -f "$rr" ]] || printf ' "Review request.md"')"
  return 1
}

cmd_validate_pr() {
  [[ -n "$BODY_FILE" && -f "$BODY_FILE" ]] || {
    printf >&2 'validate-pr requires --body <path> to an existing file\n'
    exit 2
  }
  local issue_n
  issue_n=$(resolve_issue)

  if [[ -n "$issue_n" ]]; then
    if grep -E -i -q "^(Closes|Fixes|Resolves)[[:space:]]+#${issue_n}[[:space:]]*$" "$BODY_FILE"; then
      printf 'validate-pr: body closes #%s\n' "$issue_n"
      return 0
    fi
    printf >&2 'BLOCKED: PR body missing "Closes #%s" (resolved issue)\n' "$issue_n"
    return 1
  fi

  # No issue resolvable → audit-defer row, proceed WITHOUT a closing line.
  local ts wid ri tid
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  wid=$(jq -r '.worktask_id // "unknown"' "$STATE_PATH" 2> /dev/null || printf 'unknown')
  ri=$(jq -r '.run_index // 0' "$STATE_PATH" 2> /dev/null || printf '0')
  tid=$(jq -r '.stages.FN.task_id // "FN0"' "$STATE_PATH" 2> /dev/null || printf 'FN0')
  mkdir -p "${CONTEXT_DIR}/logs" 2> /dev/null || true
  printf '{"ts":"%s","actor":"project-manager","action":"pr_issue_link","subject":"FN0","result":"deferred","task_id":"%s","metadata":{"reason":"no_issue_resolved","dedupe_key":"%s:%s:pr_issue_link"}}\n' \
    "$ts" "$tid" "$wid" "$ri" >> "${CONTEXT_DIR}/logs/audit.jsonl"
  printf 'validate-pr: no issue resolved — audit-deferred, proceeding without closing line\n'
  return 0
}

cmd_continuity() {
  local wt_head int_branch
  wt_head=$(git rev-parse HEAD 2> /dev/null || printf '')
  int_branch=$(jq -r '.git.base_branch // "main"' "$STATE_PATH" 2> /dev/null || printf 'main')
  [[ -z "$int_branch" || "$int_branch" == "null" ]] && int_branch="main"

  if [[ -n "$wt_head" ]] && git merge-base --is-ancestor "$wt_head" "$int_branch" 2> /dev/null; then
    printf 'continuity: worktree HEAD is an ancestor of %s (fast-forward safe)\n' "$int_branch"
    return 0
  fi

  printf >&2 'worktree branch diverged — falling back to cherry-pick; verify commits are complete.\n'
  local ts n
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  n=$(git rev-list --count "${int_branch}..${wt_head}" 2> /dev/null || printf '0')
  mkdir -p "${CONTEXT_DIR}/logs" 2> /dev/null || true
  printf '{"ts":"%s","actor":"project-manager","action":"branch_continuity","subject":"FN0","result":"diverged_cherry_pick","metadata":{"worktree_head":"%s","integration_branch":"%s","commit_count":%s}}\n' \
    "$ts" "$wt_head" "$int_branch" "$n" >> "${CONTEXT_DIR}/logs/audit.jsonl"
  return 0 # diverged is a documented fallback, not a hard block
}

# ---------- Argument parsing ----------
COMMAND=""
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
    attachments | resolve-issue | validate-pr | continuity | all)
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
  continuity) cmd_continuity ;;
  all)
    cmd_attachments && cmd_validate_pr && cmd_continuity
    ;;
esac

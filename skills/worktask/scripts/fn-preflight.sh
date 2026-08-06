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
#     all            attachments → pr-body → validate-pr → continuity.
#
#   `branch-divergence` is deliberately NOT in `all`: it is a separate subcommand so it is
#   independently testable and cannot perturb `continuity`'s existing rows.
#
#   `pr-body` runs BEFORE `validate-pr` because it rewrites the body in place: the
#   body whose `Closes #<n>` line is validated must be the byte-identical body that
#   reaches `gh pr create`.
#
#   `pr-body` self-disables under batch (`/megatask`) and incident (`--emergency`)
#   routing, so those pipelines keep their current behaviour byte-for-byte. See
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
# @env MILESTONE_MODE     1 => batch routing; `pr-body` self-disables.
# @env INCIDENT_MODE      1 => incident routing; same self-disable.
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

usage() {
  awk 'NR>1{ if (!/^#/) exit; sub(/^# ?/,""); print }' "$0"
  exit 2
}

# ---------- Issue resolver (ranked, first-match-wins) ----------
# 1. state.json .metadata.github_issue_url  — trailing integer of /issues/<N>.
# 2. .context/gh-issue.json .url (trailing int) or .number — follow-up-run anchor.
# 3. state.json .metadata.github_issue_number — megatask per-issue mode.
# 4. branch parse: leading <type>/<NNN>-<slug> shape (externally-named-branch
#    fallback — the shape both branch generators actually produce), else first
#    #NNN in the last 5 commits. NOT a trailing integer: a ticket-less
#    `feature/<slug-ending-in-digit>` branch must not resolve a bogus issue number.
resolve_issue() {
  local n=""
  if command -v jq > /dev/null 2>&1; then
    n=$(jq -r '.metadata.github_issue_url // empty' "$STATE_PATH" 2> /dev/null \
      | grep -oE '[0-9]+$' || true)
    [[ -z "$n" ]] && n=$(jq -r 'if .url then .url elif .number then (.number|tostring) else empty end' \
      "${CONTEXT_DIR}/gh-issue.json" 2> /dev/null | grep -oE '[0-9]+$' || true)
    [[ -z "$n" ]] && n=$(jq -r '.metadata.github_issue_number // empty' "$STATE_PATH" 2> /dev/null || true)
  fi
  [[ -z "$n" ]] && n=$(git rev-parse --abbrev-ref HEAD 2> /dev/null \
    | sed -nE 's#^[a-zA-Z]+/([0-9]+)-.*#\1#p' || true)
  [[ -z "$n" ]] && n=$(git log --oneline -n 5 2> /dev/null | grep -oE '#[0-9]+' | head -1 | tr -d '#' || true)
  printf '%s' "$n"
}

# Parity with fn_batch_scope's shared signals is pinned by fn-preflight.bats "F14"
# and branch-lib.bats.

# ---------- sanitiser bridge ------------------------------------------------
# Reads a body on stdin, writes the sanitised body to stdout.
# The rule set is publish-pl-issue.sh's `sanitise_body`, reused verbatim — issue
# bodies and PR bodies must strip identically, and the fixture suite proves only
# that one implementation. Never reimplement or extend it here.
#
# The source happens in a subshell for three reasons: this script runs
# `set -euo pipefail` while the library is written for bare `set -u` (any non-zero
# status in its ~1600-line prologue would abort us); the library's globals stay out
# of our namespace; and its `exit`-capable `fatal`/`defer` cannot terminate the
# preflight. The dummy positional is required — the library iterates `"$@"`, which
# is an unbound-variable error on bash 3.2 when empty under `set -u`.
#
# Exit 97 = library unreachable or refused to source; 98 = symbol missing. Both are
# blocking: a working-folder path in a published body must be structurally
# impossible, and a fail-open degrade would turn that into "usually".
# The blast radius is bounded by fn_batch_scope — batch and incident runs never
# reach here, so a broken plugin cache cannot wedge /megatask.
sanitise_stream() {
  (
    set +e +o pipefail
    # shellcheck disable=SC1090
    PUBLISH_LIB_ONLY=1 . "$LIB_PATH" --fn-preflight > /dev/null 2>&1 || exit 97
    command -v sanitise_body > /dev/null 2>&1 || exit 98
    sanitise_body
  )
}

# ---------- visual-evidence audit-row reader --------------------------------
VE_ACTION="visual_evidence_pr_emitted"
# $1 = worktask_id, $2 = run_index. Echoes ok|skipped, or empty when no row.
# Matching on the run's dedupe key (not the action alone) is what stops a row from
# an earlier run index satisfying the gate.
# The key grammar is emitted by attach-visual-evidence.sh `emit_pr` — keep in sync.
ve_row_result() {
  local dk="$1:$2:visual_evidence:pr" audit="${CONTEXT_DIR}/logs/audit.jsonl" r=""
  [[ -f "$audit" ]] || {
    printf ''
    return 0
  }
  if command -v jq > /dev/null 2>&1; then
    r=$(jq -r --arg a "$VE_ACTION" --arg dk "$dk" \
      'select(.action == $a) | select(.metadata.dedupe_key == $dk) | .result' \
      "$audit" 2> /dev/null | tail -1 || true)
  fi
  if [[ -z "$r" ]]; then
    # jq-less / malformed-line fallback: substring match on the same two fields.
    r=$(grep -F "\"$VE_ACTION\"" "$audit" 2> /dev/null |
      grep -F "\"dedupe_key\":\"$dk\"" |
      tail -1 | grep -oE '"result":"[a-z_]+"' | cut -d'"' -f4 || true)
  fi
  printf '%s' "$r"
}

# A base ref may be stored bare (`master`) or remote-qualified (`origin/release/v2`
# — the form workspace-modes.md documents). Map either onto something git resolves,
# which is what lets both stored shapes work without normalising the stored value.
resolve_git_ref() {
  local name="$1" bare="${1#origin/}" c
  for c in "$name" "origin/$bare" "refs/remotes/origin/$bare" "refs/heads/$bare"; do
    if git rev-parse --verify --quiet "$c" > /dev/null 2>&1; then
      printf '%s' "$c"
      return 0
    fi
  done
  return 1
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

cmd_pr_body() {
  [[ -n "$BODY_FILE" && -f "$BODY_FILE" ]] || {
    printf >&2 'pr-body requires --body <path> to an existing file\n'
    exit 2
  }
  # The scope guard MUST stay the first executed check. Moving anything that can
  # touch the sanitiser library above it turns a broken library into a block on
  # every /megatask and --emergency finalization.
  if fn_batch_scope; then
    printf 'pr-body: skipped (%s)\n' "$SCOPE_REASON"
    audit_fn pr_body_gate skipped "$(meta_json reason "$SCOPE_REASON")"
    return 0
  fi

  local ri before after tmp rc=0
  ri=$(jq -r '.run_index // 0' "$STATE_PATH" 2> /dev/null || printf '0')
  before=$(wc -l < "$BODY_FILE" | tr -d ' ')
  tmp="${BODY_FILE}.sanitised.$$"
  sanitise_stream < "$BODY_FILE" > "$tmp" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    rm -f "$tmp"
    printf >&2 'BLOCKED: PR-body sanitiser unavailable (rc=%s): %s\n' "$rc" "$LIB_PATH"
    audit_fn pr_body_gate blocked "$(meta_json reason sanitiser_unavailable lib "$LIB_PATH")"
    return 1
  fi
  if cmp -s "$tmp" "$BODY_FILE"; then
    rm -f "$tmp"
    audit_fn pr_body_sanitised unchanged "$(meta_json lines "$before")"
  else
    # Snapshot before overwriting: the strip rules are deliberately blunt, and a
    # reviewer needs the pre-sanitise text to judge an over-strip. Mirrors the
    # issue-body-<n>.aborted.tmp precedent in publish-pl-issue.sh.
    mkdir -p "${CONTEXT_DIR}/logs" 2> /dev/null || true
    cp "$BODY_FILE" "${CONTEXT_DIR}/logs/pr-body-${ri}.presanitise.md" 2> /dev/null || true
    mv -f "$tmp" "$BODY_FILE"
    after=$(wc -l < "$BODY_FILE" | tr -d ' ')
    printf 'pr-body: sanitised (%s -> %s lines)\n' "$before" "$after"
    audit_fn pr_body_sanitised ok "$(meta_json lines_before "$before" lines_after "$after" \
      snapshot "${CONTEXT_DIR}/logs/pr-body-${ri}.presanitise.md")"
  fi

  # Read back what the sanitiser actually produced. Sanitising without inspecting
  # the result is how a body that lost every image and kept a dead local path was
  # audited "ok". Runs here, after the rewrite, so it lints the byte-identical
  # body that reaches `gh pr create`. Warn-only by contract: it never changes this
  # gate's verdict, so it can land mid-flight — promote it with --strict.
  if [ -x "${SCRIPT_DIR}/pr-body-lint.sh" ]; then
    bash "${SCRIPT_DIR}/pr-body-lint.sh" --body "$BODY_FILE" --state "$STATE_PATH" \
      --context "$CONTEXT_DIR" || true
  fi

  # Checked AFTER sanitising, so a heading the sanitiser removed reports as missing
  # — one diagnostic instead of two rules disagreeing about the same body.
  if ! grep -E -i -q '^#{1,6}[[:space:]]+Test plan[[:space:]]*$' "$BODY_FILE"; then
    printf >&2 'BLOCKED: PR body has no "## Test plan" heading (hand-authored body?)\n'
    audit_fn pr_body_gate blocked "$(meta_json reason missing_test_plan_heading)"
    return 1
  fi

  # Visual evidence, keyed on the audit row first: only the row proves the helper
  # ran THIS run, and only the heading proves its stdout reached the body. A row
  # reporting `skipped` legitimately produced nothing, so no heading is required.
  # Default mirrors attach-visual-evidence.sh state_requires_screenshots: absent
  # metadata means true.
  local req wid vres
  req=$(jq -r 'if (.metadata|type=="object") and (.metadata|has("requires_screenshots"))
               then (.metadata.requires_screenshots|tostring) else "true" end' \
    "$STATE_PATH" 2> /dev/null || printf 'true')
  if [[ "$req" != "false" ]]; then
    wid=$(jq -r '.worktask_id // "unknown"' "$STATE_PATH" 2> /dev/null || printf 'unknown')
    vres=$(ve_row_result "$wid" "$ri")
    if [[ -z "$vres" ]]; then
      printf >&2 'BLOCKED: no %s audit row for %s:%s — run attach-visual-evidence.sh --emit pr\n' \
        "$VE_ACTION" "$wid" "$ri"
      audit_fn pr_body_gate blocked "$(meta_json reason missing_visual_evidence_row)"
      return 1
    fi
    if [[ "$vres" == "ok" ]] &&
      ! grep -E -i -q '^#{1,6}[[:space:]]+Visual evidence[[:space:]]*$' "$BODY_FILE"; then
      printf >&2 'BLOCKED: %s reported result=ok but the body has no "## Visual evidence" section\n' \
        "$VE_ACTION"
      audit_fn pr_body_gate blocked "$(meta_json reason missing_visual_evidence_section)"
      return 1
    fi
  fi

  printf 'pr-body: composition gate passed\n'
  audit_fn pr_body_gate ok "$(meta_json requires_screenshots "$req")"
  return 0
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
  local wt_head int_branch ref
  wt_head=$(git rev-parse HEAD 2> /dev/null || printf '')
  int_branch=$(resolve_base_ref)
  if [[ -z "$int_branch" ]]; then
    printf >&2 'continuity: integration branch unresolvable (no metadata.base_ref, no workspace.json .git.base_branch, no origin/HEAD) — ancestor check skipped\n'
    audit_fn branch_continuity base_ref_unresolved "$(meta_json worktree_head "$wt_head")"
    return 0
  fi
  ref=$(resolve_git_ref "$int_branch" 2> /dev/null || printf '')
  if [[ -z "$ref" ]]; then
    printf >&2 'continuity: integration branch %s not present locally — ancestor check skipped\n' "$int_branch"
    audit_fn branch_continuity base_ref_unresolvable "$(meta_json integration_branch "$int_branch")"
    return 0
  fi

  # The printed name stays the resolved NAME, not the git ref it mapped to: that is
  # what an operator recognises, and what the existing contract test asserts.
  if [[ -n "$wt_head" ]] && git merge-base --is-ancestor "$wt_head" "$ref" 2> /dev/null; then
    printf 'continuity: worktree HEAD is an ancestor of %s (fast-forward safe)\n' "$int_branch"
    return 0
  fi

  printf >&2 'worktree branch diverged — falling back to cherry-pick; verify commits are complete.\n'
  local ts n
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  n=$(git rev-list --count "${ref}..${wt_head}" 2> /dev/null || printf '0')
  mkdir -p "${CONTEXT_DIR}/logs" 2> /dev/null || true
  printf '{"ts":"%s","actor":"project-manager","action":"branch_continuity","subject":"FN0","result":"diverged_cherry_pick","metadata":{"worktree_head":"%s","integration_branch":"%s","commit_count":%s}}\n' \
    "$ts" "$wt_head" "$int_branch" "$n" >> "${CONTEXT_DIR}/logs/audit.jsonl"
  return 0 # diverged is a documented fallback, not a hard block
}

# Has anything outside this pipeline renamed the local branch since the naming step?
#
# The comparison base is the `to` of the most recent `branch_renamed / ok` row, NOT
# `facts.branch`. That distinction is what makes the check useful: `facts.branch` is the
# PLANNED REMOTE name and is legitimately different from the local name on several arms, so
# comparing against it fires on every worktree run and gets ignored. It also makes R4
# structurally unable to trip this — R4 rewrites `facts.branch` and never touches git, so a
# refinement cannot look like an external rename.
#
# Read-only, exit 0 always, at most one row, never blocks: divergence is a legitimate
# designed state on the opt-out, upstream_tracked, target_exists and jq_unavailable arms.
cmd_branch_divergence() {
  local log="${CONTEXT_DIR}/logs/audit.jsonl" local_name ledger renamed_to class
  local_name=$(git rev-parse --abbrev-ref HEAD 2> /dev/null || printf '')
  if [[ "$local_name" == "HEAD" ]]; then local_name=""; fi

  if ! command -v jq > /dev/null 2>&1; then
    printf 'branch-divergence: jq unavailable — check skipped\n'
    return 0
  fi
  ledger=$(jq -r '.facts.branch // ""' "$STATE_PATH" 2> /dev/null || printf '')
  [[ "$ledger" == "null" ]] && ledger=""

  renamed_to=""
  if [[ -f "$log" ]]; then
    # `fromjson? | objects` — the first survives an unparsable line, the second a
    # well-formed NON-object one (`123`, `[1,2]`), which would otherwise abort the scan on
    # `.action` and silently suppress detection of a real third-party rename.
    # `last` takes the most recent ok row, so a re-run's row wins over an earlier one.
    renamed_to=$(jq -rs -R \
      '[ split("\n")[] | fromjson? | objects
         | select(.action == "branch_renamed" and .result == "ok") | .metadata.to ]
       | (last // "")' "$log" 2> /dev/null) || renamed_to=""
  fi

  # third_party requires an ok row to compare against; everything else is a designed
  # divergence (or none at all) and stays an audit row only.
  if [[ -n "$renamed_to" ]] && [[ -n "$local_name" ]] && [[ "$local_name" != "$renamed_to" ]]; then
    class="third_party"
  else
    class="expected"
  fi

  audit_fn branch_divergence_detected warn \
    "$(meta_json class "$class" ledger "$ledger" local "$local_name" \
      renamed_to "$renamed_to" source "${DIVERGENCE_SOURCE:-fn_preflight}")"

  if [[ "$class" == "third_party" ]]; then
    printf 'branch-divergence: local branch is %s but this run renamed it to %s — renamed by something outside the pipeline\n' \
      "$local_name" "$renamed_to"
  else
    printf 'branch-divergence: no external rename detected (class=expected)\n'
  fi
  return 0
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
    attachments | resolve-issue | validate-pr | pr-body | continuity | branch-divergence | all)
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
  all)
    cmd_attachments && cmd_pr_body && cmd_validate_pr && cmd_continuity
    ;;
esac

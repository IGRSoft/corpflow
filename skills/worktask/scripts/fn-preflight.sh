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
#                    audit row for THIS run index.
#     branch-name    move an anonymous worktree branch onto `<type>/<ticket>-<slug>`.
#                    Idempotent; never blocks; deliberately NOT part of `all`.
#     continuity     the worktree HEAD is an ancestor of the integration branch, else
#                    log a diverged→cherry-pick diagnostic + audit row (never blocks).
#     all            attachments → pr-body → validate-pr → continuity.
#
#   `pr-body` runs BEFORE `validate-pr` because it rewrites the body in place: the
#   body whose `Closes #<n>` line is validated must be the byte-identical body that
#   reaches `gh pr create`. `branch-name` is NOT in `all` because `all` runs after
#   the push step, and renaming a pushed branch orphans the remote ref — call it
#   between pre-flight and push (skills/worktask/references/conductor-attachments.md).
#
#   `pr-body` and `branch-name` self-disable under batch (`/megatask`) and incident
#   (`--emergency`) routing, so those pipelines keep their current behaviour
#   byte-for-byte. See `fn_batch_scope` for the five signals.
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
# @env BRANCH_NAME_PRINT  1 => `branch-name` prints the target and renames nothing.
# @env MILESTONE_MODE     1 => batch routing; `pr-body`/`branch-name` self-disable.
# @env INCIDENT_MODE      1 => incident routing; same self-disable.
#
# @exitcode 0   Check passed (or a non-blocking degrade: no issue resolvable / diverged /
#               scope-disabled / `branch-name` in every outcome).
# @exitcode 1   Blocking failure (missing attachment; body missing the closing keyword;
#               `pr-body`: missing `Test plan` heading, missing or contradicted
#               visual-evidence evidence, or an unreachable sanitiser library).
# @exitcode 2   Usage error (unknown command/flag; `pr-body`/`validate-pr` without --body).
#
# Minimum shell: bash 3.2+ (macOS default). Mirrors state-patch.sh conventions.

set -euo pipefail
IFS=$'\n\t'

STATE_PATH=".context/state.json"
CONTEXT_DIR=".context"
BODY_FILE=""

# Sanitiser library, resolved from this script's own location (mirrors
# attach-visual-evidence.sh:69). BASH_SOURCE, not $0: correct when sourced by bats.
LIB_PATH="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2> /dev/null && pwd)/publish-pl-issue.sh"

usage() {
  sed -n 's/^# \{0,1\}//p' "$0" | head -62
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

# ---------- batch / incident scope guard ------------------------------------
# Deliberate local mirror of publish-pl-issue.sh `is_milestone_mode` (~line 658),
# extended with the incident signals. NOT sourced: this guard has to answer before
# the sanitiser library is touched, otherwise an unreachable library (which
# `sanitise_stream` treats as a blocking failure) would fail the very guard that
# exists to exempt batch and incident runs from that failure.
# Parity with the library's three shared signals is pinned by
# tests/shell/worktask/fn-preflight.bats "F14".
# Signals (any hit => the new gates self-disable):
#   1. MILESTONE_MODE=1        env override (tests, /megatask)
#   2. INCIDENT_MODE=1         env override (tests, incident runners)
#   3. state.json .metadata.milestone non-empty
#   4. state.json .stages.IR present — the emergency pipeline's marker stage
#   5. workspace.json present at $WORKSPACE_ROOT or $PWD
# Deliberately NOT metadata.fn_gate == "bypass": that carrier is also stamped by
# --auto-finalization, an ordinary interactive run that merely skips the human
# checkpoint and is exactly the run that most needs these gates.
SCOPE_REASON=""
fn_batch_scope() {
  if [[ "${MILESTONE_MODE:-0}" == "1" ]]; then
    SCOPE_REASON="milestone_mode_env"
    return 0
  fi
  if [[ "${INCIDENT_MODE:-0}" == "1" ]]; then
    SCOPE_REASON="incident_mode_env"
    return 0
  fi
  if command -v jq > /dev/null 2>&1 && [[ -f "$STATE_PATH" ]]; then
    local m
    m=$(jq -r '.metadata.milestone // ""' "$STATE_PATH" 2> /dev/null || printf '')
    if [[ -n "$m" && "$m" != "null" ]]; then
      SCOPE_REASON="milestone_metadata"
      return 0
    fi
    if jq -e '.stages | has("IR")' "$STATE_PATH" > /dev/null 2>&1; then
      SCOPE_REASON="incident_pipeline"
      return 0
    fi
  fi
  if [[ -n "${WORKSPACE_ROOT:-}" && -f "${WORKSPACE_ROOT}/workspace.json" ]]; then
    SCOPE_REASON="workspace_record"
    return 0
  fi
  if [[ -f "${PWD}/workspace.json" ]]; then
    SCOPE_REASON="workspace_record"
    return 0
  fi
  return 1
}

# ---------- audit helpers ---------------------------------------------------
# meta_json k v k v … -> compact JSON object. Values are always strings.
# The <2-argument guard is not cosmetic: bash 3.2 (the stated floor) errors on an
# empty array expansion under `set -u`, so the array must never reach jq empty.
meta_json() {
  command -v jq > /dev/null 2>&1 || {
    printf '{}'
    return 0
  }
  if [[ $# -lt 2 ]]; then
    printf '{}'
    return 0
  fi
  local args=() prog="{}" i=1
  while [[ $# -gt 1 ]]; do
    args+=(--arg "k$i" "$1" --arg "v$i" "$2")
    prog="$prog + {(\$k$i): \$v$i}"
    shift 2
    i=$((i + 1))
  done
  jq -cn "${args[@]}" "$prog"
}

# One audit row per gate outcome. Mirrors the hand-built rows already in this file.
# Never fails the caller: an audit row is evidence, not a gate.
audit_fn() {
  local action="$1" result="$2" meta="${3:-}" ts wid ri tid dk
  [[ -n "$meta" ]] || meta='{}'
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  wid=$(jq -r '.worktask_id // "unknown"' "$STATE_PATH" 2> /dev/null || printf 'unknown')
  ri=$(jq -r '.run_index // 0' "$STATE_PATH" 2> /dev/null || printf '0')
  tid=$(jq -r '.stages.FN.task_id // "FN0"' "$STATE_PATH" 2> /dev/null || printf 'FN0')
  dk="$wid:$ri:$action"
  mkdir -p "${CONTEXT_DIR}/logs" 2> /dev/null || true
  if command -v jq > /dev/null 2>&1; then
    jq -cn --arg ts "$ts" --arg a "$action" --arg s "FN0" --arg r "$result" \
      --arg t "$tid" --arg dk "$dk" --argjson m "$meta" \
      '{ts:$ts, actor:"project-manager", action:$a, subject:$s, result:$r, task_id:$t,
        metadata:($m + {dedupe_key:$dk})}' >> "${CONTEXT_DIR}/logs/audit.jsonl" 2> /dev/null || true
  fi
  return 0
}

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

# ---------- integration-branch resolution -----------------------------------
# Single source of truth for "what is the integration branch", ranked:
#   1. $FN_BASE_REF                          explicit operator/test override
#   2. state.json .metadata.base_ref         stamped by PL0, mirrors task metadata
#   3. state.json .git.base_branch           legacy ledger field, orchestrator seed
#   4. workspace.json .git.base_branch       /megatask per-issue record
#   5. git symbolic-ref refs/remotes/origin/HEAD
#   -  unresolved                            reported, never guessed
# There is deliberately NO hardcoded literal. A wrong guess (`main` in a `master`
# repo) compares against a branch that does not exist, which is how the continuity
# check silently degraded to a no-op before 3.36.2. Callers degrade non-blocking.
resolve_base_ref() {
  local v="${FN_BASE_REF:-}"
  if [[ -z "$v" ]] && command -v jq > /dev/null 2>&1; then
    v=$(jq -r '.metadata.base_ref // empty' "$STATE_PATH" 2> /dev/null || printf '')
    if [[ -z "$v" ]]; then
      v=$(jq -r '.git.base_branch // empty' "$STATE_PATH" 2> /dev/null || printf '')
    fi
    if [[ -z "$v" ]]; then
      local ws="${WORKSPACE_ROOT:-$PWD}/workspace.json"
      if [[ -f "$ws" ]]; then
        v=$(jq -r '.git.base_branch // empty' "$ws" 2> /dev/null || printf '')
      fi
    fi
  fi
  if [[ -z "$v" ]]; then
    v=$(git symbolic-ref --short refs/remotes/origin/HEAD 2> /dev/null || printf '')
  fi
  [[ "$v" == "null" ]] && v=""
  printf '%s' "$v"
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

# ---------- branch-name derivation ------------------------------------------
# Conventional-commit type. The goal string on the state ledger is the real source:
# no plan template in this repo emits the `## Goal` anchor the attachments reference
# used to nominate. Unmatched goals fall back to `feat`.
derive_type() {
  local g="" t="feat"
  if command -v jq > /dev/null 2>&1; then
    g=$(jq -r '.facts.goal // ""' "$STATE_PATH" 2> /dev/null || printf '')
  fi
  g=$(printf '%s' "$g" | tr '[:upper:]' '[:lower:]')
  case "$g" in
    *revert*) t="revert" ;;
    *"fix "* | *bug* | *defect* | *hotfix* | *crash*) t="fix" ;;
    *refactor*) t="refactor" ;;
    *perf* | *optimi*) t="perf" ;;
    *docs* | *document*) t="docs" ;;
    *test* | *coverage*) t="test" ;;
    *ci\ * | *pipeline*) t="ci" ;;
    *build* | *packaging*) t="build" ;;
    *chore* | *bump* | *dependency*) t="chore" ;;
    *) t="feat" ;;
  esac
  printf '%s' "$t"
}

# Kebab slug from the goal (fallback: worktask_id). <=48 chars, no leading/trailing '-'.
derive_slug() {
  local g=""
  if command -v jq > /dev/null 2>&1; then
    g=$(jq -r '.facts.goal // .worktask_id // ""' "$STATE_PATH" 2> /dev/null || printf '')
  fi
  printf '%s' "$g" |
    tr '[:upper:]' '[:lower:]' |
    sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-*//' -e 's/-*$//' |
    cut -c1-48 | sed -e 's/-*$//'
}

# `<type>/<ticket>-<slug>`, or `<type>/<slug>` when no ticket resolves.
# Returns 1 (no output) when no slug can be derived — callers treat that as a no-op.
target_branch_name() {
  local t n s
  t=$(derive_type)
  s=$(derive_slug)
  n=$(resolve_issue)
  if [[ -z "$n" && -n "${EXTERNAL_TICKET:-}" ]]; then n="$EXTERNAL_TICKET"; fi
  if [[ -z "$s" ]]; then return 1; fi
  if [[ -n "$n" ]]; then
    printf '%s/%s-%s' "$t" "$n" "$s"
  else
    printf '%s/%s' "$t" "$s"
  fi
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

# Guard ladder — first hit wins, and every arm exits 0. This step is a courtesy
# rename, never a gate: no naming problem is worth failing a finalization over.
cmd_branch_name() {
  local apply=1
  [[ "${BRANCH_NAME_PRINT:-0}" == "1" ]] && apply=0
  if fn_batch_scope; then
    printf 'branch-name: skipped (%s)\n' "$SCOPE_REASON"
    audit_fn branch_renamed skipped "$(meta_json reason "$SCOPE_REASON")"
    return 0
  fi
  git rev-parse --git-dir > /dev/null 2>&1 || {
    printf 'branch-name: not a git repo — skipped\n'
    return 0
  }
  local cur
  cur=$(git rev-parse --abbrev-ref HEAD 2> /dev/null || printf '')
  if [[ -z "$cur" || "$cur" == "HEAD" ]]; then
    printf 'branch-name: detached HEAD — skipped\n'
    return 0
  fi
  # A conventional name is a deliberate name — never churn one.
  if printf '%s' "$cur" | grep -E -q '^(feat|fix|refactor|perf|docs|chore|test|ci|build|style|revert)/[a-z0-9._-]+$'; then
    printf 'branch-name: already conventional (%s) — no-op\n' "$cur"
    return 0
  fi
  # Renaming a branch that already has an upstream orphans the remote ref.
  if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' > /dev/null 2>&1; then
    printf 'branch-name: upstream already tracked — no-op\n'
    audit_fn branch_renamed noop "$(meta_json reason upstream_tracked branch "$cur")"
    return 0
  fi
  local base
  base=$(resolve_base_ref)
  if [[ -n "$base" && "$cur" == "${base#origin/}" ]]; then
    printf 'branch-name: on the integration branch (%s) — refusing to rename\n' "$cur"
    audit_fn branch_renamed noop "$(meta_json reason on_integration_branch branch "$cur")"
    return 0
  fi
  local target
  EXTERNAL_TICKET=$(jq -r '.metadata.external_ticket // ""' "$STATE_PATH" 2> /dev/null || printf '')
  target=$(target_branch_name 2> /dev/null || printf '')
  if [[ -z "$target" ]]; then
    printf 'branch-name: target unresolvable — no-op\n'
    audit_fn branch_renamed noop "$(meta_json reason target_unresolvable)"
    return 0
  fi
  if [[ "$cur" == "$target" ]]; then
    printf 'branch-name: already %s — no-op\n' "$target"
    return 0
  fi
  if [[ "$apply" -eq 0 ]]; then
    printf '%s\n' "$target"
    return 0
  fi
  if git show-ref --verify --quiet "refs/heads/$target"; then
    printf 'branch-name: %s already exists — no-op\n' "$target"
    audit_fn branch_renamed noop "$(meta_json reason target_exists target "$target")"
    return 0
  fi
  if git branch -m "$target" 2> /dev/null; then
    printf 'branch-name: %s -> %s\n' "$cur" "$target"
    audit_fn branch_renamed ok "$(meta_json from "$cur" to "$target")"
  else
    printf >&2 'branch-name: rename failed (%s -> %s) — continuing\n' "$cur" "$target"
    audit_fn branch_renamed failed "$(meta_json from "$cur" to "$target")"
  fi
  return 0
}

cmd_continuity() {
  local wt_head int_branch ref
  wt_head=$(git rev-parse HEAD 2> /dev/null || printf '')
  int_branch=$(resolve_base_ref)
  if [[ -z "$int_branch" ]]; then
    printf >&2 'continuity: integration branch unresolvable (no metadata.base_ref, no .git.base_branch, no origin/HEAD) — ancestor check skipped\n'
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
    attachments | resolve-issue | validate-pr | pr-body | branch-name | continuity | all)
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
  branch-name) cmd_branch_name ;;
  continuity) cmd_continuity ;;
  all)
    cmd_attachments && cmd_pr_body && cmd_validate_pr && cmd_continuity
    ;;
esac

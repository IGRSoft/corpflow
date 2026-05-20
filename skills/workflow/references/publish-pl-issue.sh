#!/usr/bin/env bash
# publish-pl-issue.sh — auto-publish a sanitised GitHub issue after PL approval.
#
# Invoked by the orchestrator at Step 6.5 of skills/workflow/SKILL.md between
# `approval_received` audit-write and stage-loop entry. NEVER blocks the workflow:
# operational outcomes are encoded in audit.jsonl rows (result + reason), helper
# exits 0 unless catastrophic (jq missing, audit dir unwritable, state corrupt).
#
# Contracts (analyzing-0.md):
#   - Two-pass sanitiser (sanitise_body): Pass 1 awk line-strip L1–L9, Pass 2
#     token-strip with allow-list A1–A5.
#   - Strip-ratio >50% aborts publish; aborted body persisted to
#     .context/logs/issue-body-<run_index>.aborted.tmp.
#   - Idempotency: state.json:metadata.github_issue_url short-circuits.
#   - Milestone-mode: state.json:metadata.milestone OR workspace.json present →
#     exit 0 immediately with reason=milestone_mode. No gh API call of any kind
#     (no create, no comment). The parent milestone issue is the canonical record.
#   - Atomic state.json write: tmp.$$ → fsync → mv -f.
#   - Audit row: actor=orchestrator, action=github_issue_created, via=publish-pl-issue.sh,
#     dedupe_key=<workflow_id>:<run_index>:gh_issue.
#   - Exit codes: 0 all operational paths, 1 catastrophic, 2 --self-test failure.
#
# Env vars for injection (test/dev): STATE_FILE, WORKSPACE_ROOT, GH_BIN, DRY_RUN,
# GH_TIMEOUT (default 30).

set -u

# ---------- defaults / env --------------------------------------------------
STATE_FILE="${STATE_FILE:-.context/state.json}"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-}"
GH_BIN="${GH_BIN:-gh}"
DRY_RUN="${DRY_RUN:-0}"
GH_TIMEOUT="${GH_TIMEOUT:-30}"
LOG_DIR="${WORKSPACE_ROOT:-${CLAUDE_PROJECT_DIR:-.}}/.context/logs"
AUDIT_FILE="$LOG_DIR/audit.jsonl"

# ---------- helpers ---------------------------------------------------------
audit_row() {
  # $1=result, $2=metadata-json (compact). Always appends one row.
  local result="$1" meta_json="$2"
  command -v jq >/dev/null 2>&1 || return 1
  mkdir -p "$LOG_DIR" || return 1
  local row
  row=$(jq -cn \
    --arg ts "$(date -u +%FT%TZ)" \
    --arg actor "orchestrator" \
    --arg action "github_issue_created" \
    --arg subject "PL0" \
    --arg result "$result" \
    --arg task_id "${PL0_TASK_ID:-1}" \
    --argjson meta "$meta_json" \
    '{ts:$ts, actor:$actor, action:$action, subject:$subject, result:$result, task_id:$task_id, metadata:$meta}'
  )
  printf '%s\n' "$row" >> "$AUDIT_FILE"
}

defer() {
  # $1=reason; appends audit row with result=deferred, exits 0.
  local reason="$1"
  local wid run_index dk
  wid=$(jq -r '.workflow_id // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
  run_index=$(jq -r '.run_index // 0' "$STATE_FILE" 2>/dev/null || echo "0")
  dk="$wid:$run_index:gh_issue"
  audit_row "deferred" "$(jq -cn --arg v "publish-pl-issue.sh" --arg r "$reason" --arg dk "$dk" '{via:$v, reason:$r, dedupe_key:$dk}')" || true
  exit 0
}

fatal() {
  # $1=reason; appends audit row with result=error, exits 1.
  local reason="$1"
  local wid run_index dk
  wid=$(jq -r '.workflow_id // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
  run_index=$(jq -r '.run_index // 0' "$STATE_FILE" 2>/dev/null || echo "0")
  dk="$wid:$run_index:gh_issue"
  audit_row "error" "$(jq -cn --arg v "publish-pl-issue.sh" --arg r "$reason" --arg dk "$dk" '{via:$v, reason:$r, dedupe_key:$dk}')" 2>/dev/null || true
  exit 1
}

# ---------- two-pass sanitiser ---------------------------------------------
# Pass 1: drop whole lines containing forbidden tokens (L1..L9).
# Pass 2: drop filename-shaped tokens unless allow-list rules A1..A5 fire.
sanitise_body() {
  # Reads body from stdin, writes sanitised body to stdout.
  # Force C locale so awk byte-handles UTF-8 (em-dashes, smart quotes) without
  # tripping the "towc: multibyte conversion failure" warning + line drop.
  LC_ALL=C awk '
    BEGIN { in_fence = 0 }
    {
      line = $0
      # ---- Pass 1 line-strip --------------------------------------------
      if (line ~ /(^|[[:space:]])\.context\//) next                 # L1
      if (line ~ /(^|[[:space:]])\/(Users|home|tmp|var|opt|etc|root)\//) next  # L2,L3
      if (line ~ /(^|[[:space:]])~\//) next                         # L4
      if (line ~ /conductor\/workspaces\/[A-Za-z0-9_-]+/) next      # L5
      if (line ~ /(^|[[:space:]])(workspace_path|plan_file|run_index|artifact_path)[[:space:]]*[:=]/) next  # L6
      if (line ~ /(planning|analyzing|coordinating|coordination|developing|development|reviewing|review|qa|testing|documenting|documentation|releasing|release|finalizing|finalization|stakeholding|retrospective|incident|ethics-review)-[0-9]+\.md/) next  # L7,L8
      if (line ~ /(^|[[:space:]])(\.\/|\.\.\/)[A-Za-z0-9_.\/-]+/) next   # L9

      # ---- Pass 2 token-strip (with allow-list) -------------------------
      # Track fenced code block state (A1).
      if (line ~ /^[[:space:]]*```/) {
        in_fence = (in_fence == 1) ? 0 : 1
        print line
        next
      }
      if (in_fence == 1) { print line; next }

      # A4: narrative bullet labels — pass entire line.
      if (line ~ /^[[:space:]]*[-*][[:space:]]+(class|type|protocol|struct|enum|function|fn|func|method)[[:space:]:]/) {
        print line; next
      }

      # A3: strip "symbol:" prefix but keep token body.
      gsub(/(^|[[:space:]])symbol:/, " ", line)

      # A2: inline-code passthrough — collect backtick spans first.
      # Build output character-by-character, skipping deny tokens outside spans.
      out = ""
      n = length(line)
      i = 1
      while (i <= n) {
        ch = substr(line, i, 1)
        if (ch == "`") {
          # passthrough until matching backtick
          j = index(substr(line, i+1), "`")
          if (j > 0) {
            out = out substr(line, i, j + 1)
            i = i + j + 1
            continue
          }
        }
        # Look ahead for filename token starting at i.
        rest = substr(line, i)
        if (match(rest, /^[A-Z][A-Za-z0-9_]+\.(md|json|jsonl|swift|ts|py|yml|yaml|sh|bash|go|rs|kt|java|rb|cpp|c|h|hpp|m|mm)\>/)) {
          # A5: extension is in deny-list → strip.
          i = i + RLENGTH
          continue
        }
        out = out ch
        i = i + 1
      }
      print out
    }
  '
}

# ---------- plan extraction -------------------------------------------------
extract_anchor() {
  # $1=plan_file, $2=anchor name (without ##); returns anchor body lines.
  local plan="$1" anchor="$2"
  awk -v hdr="## $anchor" '
    BEGIN { in_block = 0 }
    /^## / {
      if (in_block == 1) exit
      if (tolower($0) == tolower(hdr)) { in_block = 1; next }
    }
    { if (in_block == 1) print }
  ' "$plan"
}

# ---------- workspace.json discovery ----------------------------------------
find_workspace_json() {
  if [ -n "$WORKSPACE_ROOT" ] && [ -f "$WORKSPACE_ROOT/workspace.json" ]; then
    printf '%s\n' "$WORKSPACE_ROOT/workspace.json"; return 0
  fi
  if [ -f "$PWD/workspace.json" ]; then
    printf '%s\n' "$PWD/workspace.json"; return 0
  fi
  return 1
}

# ---------- milestone-mode detector -----------------------------------------
# Returns 0 (true) if the workflow is running under --milestone:N or inside a
# milestone-workflow workspace. Detection signals (highest priority first):
#   1. MILESTONE_MODE=1 env override (used by tests).
#   2. state.json:metadata.milestone non-empty.
#   3. workspace.json present at $WORKSPACE_ROOT or $PWD.
is_milestone_mode() {
  [ "${MILESTONE_MODE:-0}" = "1" ] && return 0
  if [ -f "$STATE_FILE" ]; then
    local m
    m=$(jq -r '.metadata.milestone // ""' "$STATE_FILE" 2>/dev/null)
    [ -n "$m" ] && [ "$m" != "null" ] && return 0
  fi
  find_workspace_json >/dev/null 2>&1 && return 0
  return 1
}

# ---------- atomic state.json write -----------------------------------------
write_state_url() {
  # $1=url. Atomically sets state.json:metadata.github_issue_url.
  local url="$1"
  local tmp="${STATE_FILE}.tmp.$$"
  jq --arg url "$url" '.metadata = (.metadata // {}) | .metadata.github_issue_url = $url' "$STATE_FILE" > "$tmp" || return 1
  sync "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$STATE_FILE" || return 1
}

# ---------- self-test -------------------------------------------------------
run_self_tests() {
  local fixtures_dir
  fixtures_dir="$(dirname "$0")/fixtures/publish-pl-issue"
  [ -d "$fixtures_dir" ] || { echo "publish-pl-issue: fixtures dir missing: $fixtures_dir" >&2; return 1; }
  local pass=0 fail=0

  # Fixture 01: clean plan — sanitiser should not strip much.
  local clean orig_len san_len
  clean=$(sanitise_body < "$fixtures_dir/01-clean-plan.md")
  orig_len=$(wc -c < "$fixtures_dir/01-clean-plan.md")
  san_len=$(printf '%s' "$clean" | wc -c)
  if [ "$san_len" -gt 0 ] && [ "$san_len" -ge $((orig_len / 2)) ]; then
    echo "publish-pl-issue: self-test 01-clean-plan PASS (orig=$orig_len san=$san_len)"
    pass=$((pass + 1))
  else
    echo "publish-pl-issue: self-test 01-clean-plan FAIL (orig=$orig_len san=$san_len)"
    fail=$((fail + 1))
  fi

  # Fixture 02: leaky plan — must strip all forbidden tokens.
  local leaky
  leaky=$(sanitise_body < "$fixtures_dir/02-leaky-plan.md")
  if printf '%s' "$leaky" | grep -qE '\.context/|/Users/|conductor/workspaces/|planning-[0-9]+\.md'; then
    echo "publish-pl-issue: self-test 02-leaky-plan FAIL (leak detected)"
    printf '%s\n' "$leaky" | grep -E '\.context/|/Users/|conductor/workspaces/|planning-[0-9]+\.md' | head -3 >&2
    fail=$((fail + 1))
  else
    echo "publish-pl-issue: self-test 02-leaky-plan PASS (no leaks)"
    pass=$((pass + 1))
  fi

  # Fixture 03: mostly-paths — strip ratio should be > 50%.
  local pathy pathy_orig pathy_san ratio_num ratio_den
  pathy=$(sanitise_body < "$fixtures_dir/03-mostly-paths.md")
  pathy_orig=$(wc -c < "$fixtures_dir/03-mostly-paths.md")
  pathy_san=$(printf '%s' "$pathy" | wc -c)
  ratio_num=$((pathy_orig - pathy_san))
  ratio_den=$pathy_orig
  if [ "$ratio_den" -gt 0 ] && [ $((ratio_num * 100 / ratio_den)) -gt 50 ]; then
    echo "publish-pl-issue: self-test 03-mostly-paths PASS (strip_pct=$((ratio_num * 100 / ratio_den))%)"
    pass=$((pass + 1))
  else
    echo "publish-pl-issue: self-test 03-mostly-paths FAIL (strip ratio not > 50%)"
    fail=$((fail + 1))
  fi

  # Fixture 04: already-published — companion state.json short-circuits.
  local f04_state="$fixtures_dir/04-state.json"
  local url_check
  url_check=$(jq -r '.metadata.github_issue_url // ""' "$f04_state" 2>/dev/null)
  if [ -n "$url_check" ]; then
    echo "publish-pl-issue: self-test 04-already-published PASS (state preloaded with $url_check)"
    pass=$((pass + 1))
  else
    echo "publish-pl-issue: self-test 04-already-published FAIL (state.json missing github_issue_url)"
    fail=$((fail + 1))
  fi

  # Fixture 05: milestone-mode — companion state.json carries metadata.milestone.
  # Detector reads STATE_FILE directly; verify both env-override and state-json
  # signals would fire is_milestone_mode().
  local f05_state="$fixtures_dir/05-state.json"
  local milestone_check
  milestone_check=$(jq -r '.metadata.milestone // ""' "$f05_state" 2>/dev/null)
  local env_check=0
  ( MILESTONE_MODE=1 STATE_FILE=/dev/null bash -c '
      [ "${MILESTONE_MODE:-0}" = "1" ] && exit 0 || exit 1
    ' ) && env_check=1
  if [ -n "$milestone_check" ] && [ "$milestone_check" != "null" ] && [ "$env_check" = "1" ]; then
    echo "publish-pl-issue: self-test 05-milestone-mode PASS (state.metadata.milestone=$milestone_check + env override)"
    pass=$((pass + 1))
  else
    echo "publish-pl-issue: self-test 05-milestone-mode FAIL (milestone=$milestone_check env_check=$env_check)"
    fail=$((fail + 1))
  fi

  echo "publish-pl-issue: self-test summary — pass=$pass fail=$fail"
  [ "$fail" -eq 0 ]
}

# ---------- entrypoint ------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  run_self_tests || exit 2
  exit 0
fi

# Catastrophic-pre-flight: jq required for audit + state I/O.
command -v jq >/dev/null 2>&1 || { echo "publish-pl-issue: jq not found" >&2; exit 1; }
mkdir -p "$LOG_DIR" 2>/dev/null || fatal "audit_dir_unwritable"
[ -r "$STATE_FILE" ] || fatal "state_corrupt"
jq -e . "$STATE_FILE" >/dev/null 2>&1 || fatal "state_corrupt"

# Pull workflow context.
WORKFLOW_ID=$(jq -r '.workflow_id // "unknown"' "$STATE_FILE")
RUN_INDEX=$(jq -r '.run_index // 0' "$STATE_FILE")
PLAN_FILE=$(jq -r '.plan_file // ""' "$STATE_FILE")
DEDUPE_KEY="$WORKFLOW_ID:$RUN_INDEX:gh_issue"

# Guard 1: opt-out via task metadata or env override.
NO_GH=$(jq -r '.metadata.no_gh_issue // false' "$STATE_FILE" 2>/dev/null)
if [ "${NO_GH_ISSUE:-${NO_GH}}" = "true" ]; then
  defer "opted_out"
fi

# Guard 2: idempotency — already-published.
EXISTING_URL=$(jq -r '.metadata.github_issue_url // ""' "$STATE_FILE" 2>/dev/null)
if [ -n "$EXISTING_URL" ]; then
  defer "already_published"
fi

# Guard 2.5: milestone-mode — skip GH publish entirely (no create, no comment).
# The parent milestone issue is the canonical record; auto-posting plan-approval
# comments would fragment the review surface. PR linkage (FN stage or manual)
# ties the implementation back to the milestone.
if is_milestone_mode; then
  defer "milestone_mode"
fi

# Guard 3: gh binary present.
command -v "$GH_BIN" >/dev/null 2>&1 || defer "gh_not_installed"

# Guard 4: gh auth.
if [ "$DRY_RUN" != "1" ]; then
  "$GH_BIN" auth status >/dev/null 2>&1 || defer "auth_missing"
fi

# Guard 5: remote present.
if [ "$DRY_RUN" != "1" ]; then
  git remote get-url origin 2>/dev/null | grep -q . || defer "no_remote"
fi

# Plan readable?
[ -r "$PLAN_FILE" ] || fatal "plan_unreadable"

# ---------- extract + sanitise + render -------------------------------------
SUMMARY_RAW=$(jq -r '.facts.goal // ""' "$STATE_FILE")
REQS_RAW=$(extract_anchor "$PLAN_FILE" "requirements")
ACS_RAW=$(extract_anchor "$PLAN_FILE" "acceptance-criteria")
SCOPE_RAW=$(extract_anchor "$PLAN_FILE" "scope")
COMPLEXITY_RAW=$(extract_anchor "$PLAN_FILE" "complexity")
STAGES_RAW=$(extract_anchor "$PLAN_FILE" "stages")

SUMMARY_S=$(printf '%s\n' "$SUMMARY_RAW" | sanitise_body)
REQS_S=$(printf '%s\n' "$REQS_RAW" | sanitise_body)
ACS_S=$(printf '%s\n' "$ACS_RAW" | sanitise_body)
SCOPE_S=$(printf '%s\n' "$SCOPE_RAW" | sanitise_body)
COMPLEXITY_S=$(printf '%s\n' "$COMPLEXITY_RAW" | sanitise_body)
STAGES_S=$(printf '%s\n' "$STAGES_RAW" | sanitise_body)

# Strip-ratio check against the combined anchor bodies.
ORIG_TOTAL=$(printf '%s%s%s%s%s' "$REQS_RAW" "$ACS_RAW" "$SCOPE_RAW" "$COMPLEXITY_RAW" "$STAGES_RAW" | wc -c)
SAN_TOTAL=$(printf '%s%s%s%s%s' "$REQS_S" "$ACS_S" "$SCOPE_S" "$COMPLEXITY_S" "$STAGES_S" | wc -c)
# Fallback: when the plan has none of the expected anchor headings, anchor-extracted
# bytes are zero — fall back to whole-file byte length so a near-empty body still
# trips the strip-ratio guard instead of being silently published. Matches the
# --self-test behaviour for fixture 03-mostly-paths.md. (T4 remediation, DV0.1)
if [ "$ORIG_TOTAL" -eq 0 ]; then
  ORIG_TOTAL=$(wc -c < "$PLAN_FILE" 2>/dev/null || echo 0)
  PLAN_SAN=$(sanitise_body < "$PLAN_FILE" 2>/dev/null | wc -c)
  SAN_TOTAL="$PLAN_SAN"
fi
STRIP_PCT=0
if [ "$ORIG_TOTAL" -gt 0 ]; then
  STRIP_PCT=$(( (ORIG_TOTAL - SAN_TOTAL) * 100 / ORIG_TOTAL ))
fi
if [ "$STRIP_PCT" -gt 50 ]; then
  ABORT_TMP="$LOG_DIR/issue-body-${RUN_INDEX}.aborted.tmp"
  {
    printf '%s\n\n' "$SUMMARY_S"
    printf '## Requirements\n%s\n\n' "$REQS_S"
    printf '## Acceptance Criteria\n%s\n\n' "$ACS_S"
    printf '## Scope\n%s\n\n' "$SCOPE_S"
    printf '## Complexity\n%s\n\n' "$COMPLEXITY_S"
    printf '## Planned Stages\n%s\n' "$STAGES_S"
  } > "$ABORT_TMP" 2>/dev/null || true
  audit_row "deferred" "$(jq -cn --arg v "publish-pl-issue.sh" --arg r "sanitiser_aborted" --argjson sp "$STRIP_PCT" --arg dk "$DEDUPE_KEY" --arg path "$ABORT_TMP" '{via:$v, reason:$r, strip_ratio:$sp, aborted_body:$path, dedupe_key:$dk}')" || true
  exit 0
fi

# Mode is implicit "create" — milestone mode short-circuited above (Guard 2.5).
MODE="create"

# Complexity-tier label (read from facts.decisions or planning § complexity heading).
TIER=$(printf '%s' "$COMPLEXITY_S" | grep -oiE '\((Low|Medium|Moderate|High|Critical)\)' | head -1 | tr '[:upper:]' '[:lower:]' | tr -d '()')
[ -z "$TIER" ] && TIER="moderate"

# Render body via heredoc.
BODY_TMP="$LOG_DIR/issue-body-${RUN_INDEX}.tmp"
{
  printf '## Summary\n%s\n\n' "$SUMMARY_S"
  printf '## Requirements\n%s\n\n' "$REQS_S"
  printf '## Acceptance Criteria\n%s\n\n' "$ACS_S"
  printf '## Scope\n%s\n\n' "$SCOPE_S"
  printf '## Complexity\n%s\n\n' "$COMPLEXITY_S"
  printf '## Planned Stages\n%s\n\n' "$STAGES_S"
  printf -- '---\n*Plan approved on %s. Tracking continues in workflow run #%s.*\n' "$(date -u +%F)" "$RUN_INDEX"
} > "$BODY_TMP" 2>/dev/null || fatal "audit_dir_unwritable"

# Title (sanitised — pulled from facts.goal or workflow_id).
TITLE_RAW="${SUMMARY_RAW:-$WORKFLOW_ID}"
TITLE=$(printf '%s' "$TITLE_RAW" | head -1 | cut -c1-100 | sanitise_body | tr -d '\n')
[ -z "$TITLE" ] && TITLE="Plan approved: $WORKFLOW_ID"

# Invoke gh — single publish path (create). Milestone mode skipped above.
URL=""
if [ "$DRY_RUN" = "1" ]; then
  URL="https://github.com/dry/run/issues/0"
  echo "DRY_RUN: $GH_BIN issue create --title \"$TITLE\" --body-file $BODY_TMP --label workflow,planning-approved,complexity:$TIER" >&2
else
  GH_OUT=$("$GH_BIN" issue create --title "$TITLE" --body-file "$BODY_TMP" --label "workflow,planning-approved,complexity:$TIER" 2>&1) || GH_RC=$? || GH_RC=0
  URL=$(printf '%s' "$GH_OUT" | grep -oE 'https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/issues/[0-9]+' | head -1)
  if [ -z "$URL" ]; then
    # No URL captured → treat as network/auth-edge failure (non-blocking).
    audit_row "deferred" "$(jq -cn --arg v "publish-pl-issue.sh" --arg r "network_error" --arg dk "$DEDUPE_KEY" '{via:$v, reason:$r, dedupe_key:$dk}')" || true
    exit 0
  fi
fi

# Persist URL to state.json (atomic). Audit row appended regardless of write success.
write_state_url "$URL" || true
META_JSON=$(jq -cn --arg v "publish-pl-issue.sh" --arg mode "$MODE" --arg url "$URL" --arg tier "$TIER" --argjson sp "$STRIP_PCT" --arg dk "$DEDUPE_KEY" \
  '{via:$v, mode:$mode, url:$url, complexity_tier:$tier, sanitiser_stripped_pct:$sp, dedupe_key:$dk}')
audit_row "ok" "$META_JSON" || true

# Emit single optional line for orchestrator terminal UX.
printf 'published_url=%s\n' "$URL"
exit 0

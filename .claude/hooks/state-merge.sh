#!/usr/bin/env bash
# state-merge.sh — SubagentStop hook (OPTIONAL belt-and-suspenders for
# the handoff protocol). Reads the artifact's `handoff:` frontmatter and
# atomic-merges it into .context/state.json.
#
# Contract (per analyzing.md#integration-points § IP-2):
#   - Exit 0 ALWAYS (must NOT block stage transition). Failures log to
#     .context/logs/state-merge.log + stderr.
#   - Idempotent: if state.json already reflects this frontmatter, exit 0
#     silently. Otherwise atomic-merge and exit 0.
#   - YAML parsing: prefer `yq`; fallback to inline awk subset (we own the
#     handoff: schema so a strict subset parser is safe).
#   - state.json absent: log INFO and exit 0 (path F1 — legacy mode).
#   - Frontmatter missing: derive minimal handoff from $CLAUDE_AGENT_NAME
#     and $CLAUDE_ARTIFACT_PATH; merge minimal record.
#
# Env vars (provided by Claude Code on SubagentStop):
#   CLAUDE_TASK_ID, CLAUDE_AGENT_NAME, CLAUDE_ARTIFACT_PATH,
#   CLAUDE_WORKFLOW_ID, CLAUDE_DURATION_MS, CLAUDE_TASK_METADATA_STAGE
#
# Usage (manual self-test):
#   state-merge.sh --self-test
#
# Usage (manual invocation):
#   CLAUDE_ARTIFACT_PATH=.context/development.md \
#   CLAUDE_TASK_METADATA_STAGE=DV \
#   .claude/hooks/state-merge.sh

set -euo pipefail

LOG_DIR=".context/logs"
STATE_JSON=".context/state.json"

mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG="$LOG_DIR/state-merge.log"

log() {
  printf '%s [%s] %s\n' "$(date -u +%FT%TZ)" "${1:-INFO}" "${2:-}" >> "$LOG" 2>/dev/null || true
}

# ---------- Self-test ----------
if [[ "${1:-}" == "--self-test" ]]; then
  # Resolve script path BEFORE cd, so subprocess invocations work.
  SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
  td=$(mktemp -d -t state-merge-XXXXXX)
  trap "rm -rf '$td'" EXIT
  cd "$td"
  mkdir -p .context/logs
  cat > .context/state.json <<'EOF'
{"version":1,"workflow_id":"selftest","plan_file":".context/planning-0.md","platform":"all","stages":{"PL":{"status":"completed","verdict":"ok"}},"facts":{"files_modified":[],"tests_added":[],"decisions":[],"open_questions":[],"verdicts":{"PL":"ok"}},"handoffs":{}}
EOF
  cat > .context/development.md <<'EOF'
---
handoff:
  stage: DV
  verdict: ok
  summary: "self-test artifact"
  files_touched: [a.md]
  next_stage_focus: "DR reviews"
  refs: { dev: development.md#files-changed }
---

# Development
EOF
  CLAUDE_ARTIFACT_PATH=".context/development.md" \
  CLAUDE_AGENT_NAME="developer" \
  CLAUDE_TASK_METADATA_STAGE="DV" \
  bash "$SELF" || { echo "self-test: hook returned non-zero" >&2; exit 1; }
  if jq -e '.stages.DV.status == "completed"' .context/state.json >/dev/null; then
    echo "self-test: state.json patched with DV completed: ok"
  else
    echo "self-test: state.json missing DV.status=completed: FAIL" >&2
    exit 1
  fi
  # Idempotency: re-run, state must remain identical
  cp .context/state.json .context/state.json.snap
  CLAUDE_ARTIFACT_PATH=".context/development.md" \
  CLAUDE_AGENT_NAME="developer" \
  CLAUDE_TASK_METADATA_STAGE="DV" \
  bash "$SELF"
  if diff -q .context/state.json .context/state.json.snap >/dev/null; then
    echo "self-test: idempotent re-run: ok"
  else
    echo "self-test: idempotent re-run: FAIL (state changed)" >&2
    exit 1
  fi
  echo "self-test: ALL PASS"
  exit 0
fi

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  sed -n 's/^# \{0,1\}//p' "$0" | sed -n '1,/^$/p'
  exit 0
fi

# ---------- Discover artifact path ----------
ART="${CLAUDE_ARTIFACT_PATH:-}"
STAGE="${CLAUDE_TASK_METADATA_STAGE:-}"
AGENT="${CLAUDE_AGENT_NAME:-}"

# Stage-code → artifact-name map (RK-9 mitigation: glob fallback).
# POSIX-compatible lookup (bash 3.2 has no associative arrays).
artifact_for_stage() {
  case "$1" in
    PL) echo ".context/planning-0.md" ;;
    AR) echo ".context/analyzing.md" ;;
    TL) echo ".context/coordination.md" ;;
    DV) echo ".context/development.md" ;;
    DR) echo ".context/developer-review.md" ;;
    SR) echo ".context/security-review.md" ;;
    QA) echo ".context/testing.md" ;;
    DC) echo ".context/documentation.md" ;;
    RE) echo ".context/release.md" ;;
    FN) echo ".context/complete-summary.md" ;;
    ST) echo ".context/retrospective.md" ;;
    IR) echo ".context/incident.md" ;;
    ET) echo ".context/ethics-review.md" ;;
    *) echo "" ;;
  esac
}

if [[ -z "$ART" && -n "$STAGE" ]]; then
  ART=$(artifact_for_stage "$STAGE")
  if [[ "$STAGE" == "PL" ]]; then
    # Pick newest planning-N.md
    ART=$(ls -1t .context/planning-*.md 2>/dev/null | head -1 || echo ".context/planning-0.md")
  fi
fi

if [[ -z "$ART" || ! -f "$ART" ]]; then
  log WARN "no artifact path resolved (CLAUDE_ARTIFACT_PATH=${CLAUDE_ARTIFACT_PATH:-} stage=$STAGE)"
  exit 0
fi

if [[ ! -f "$STATE_JSON" ]]; then
  log INFO "state.json absent — F1 fallback active, no merge needed (artifact=$ART)"
  exit 0
fi

# ---------- Parse frontmatter ----------
parse_yq() {
  yq eval '.handoff' "$1" 2>/dev/null
}

# Awk subset fallback: extract block between first two `^---$` lines.
parse_awk() {
  awk '/^---$/{ c++; next } c==1' "$1"
}

FM=""
if command -v yq >/dev/null 2>&1; then
  FM=$(parse_yq "$ART" || true)
fi

if [[ -z "$FM" || "$FM" == "null" ]]; then
  # awk fallback strips the outer `handoff:` key — extract the value of `stage:` etc.
  RAW=$(parse_awk "$ART" || true)
  if [[ -z "$RAW" ]]; then
    log WARN "no frontmatter in $ART — F3 fallback (deriving minimal record)"
    PARSED_STAGE="${STAGE:-${AGENT:-UNKNOWN}}"
    PARSED_VERDICT="ok"
    PARSED_SUMMARY="auto-generated by state-merge.sh (frontmatter missing)"
  else
    PARSED_STAGE=$(awk -F: '/^[[:space:]]*stage:/ { gsub(/[[:space:]"]+/, "", $2); print $2; exit }' <<< "$RAW")
    PARSED_VERDICT=$(awk -F: '/^[[:space:]]*verdict:/ { gsub(/[[:space:]"]+/, "", $2); print $2; exit }' <<< "$RAW")
    PARSED_SUMMARY=$(awk -F: '/^[[:space:]]*summary:/ { sub(/^[[:space:]]*summary:[[:space:]]*/, ""); gsub(/^"|"$/, ""); print; exit }' <<< "$RAW")
    [[ -z "$PARSED_VERDICT" ]] && PARSED_VERDICT="ok"
    [[ -z "$PARSED_SUMMARY" ]] && PARSED_SUMMARY="(auto)"
  fi
else
  PARSED_STAGE=$(yq eval '.handoff.stage // ""' "$ART")
  PARSED_VERDICT=$(yq eval '.handoff.verdict // "ok"' "$ART")
  PARSED_SUMMARY=$(yq eval '.handoff.summary // ""' "$ART")
fi

if [[ -z "$PARSED_STAGE" ]]; then
  log WARN "could not extract stage from $ART; aborting merge silently"
  exit 0
fi

# ---------- Idempotency check ----------
CURRENT_STATUS=$(jq -r --arg s "$PARSED_STAGE" '.stages[$s].status // ""' "$STATE_JSON" 2>/dev/null || echo "")
CURRENT_VERDICT=$(jq -r --arg s "$PARSED_STAGE" '.stages[$s].verdict // ""' "$STATE_JSON" 2>/dev/null || echo "")

if [[ "$CURRENT_STATUS" == "completed" && "$CURRENT_VERDICT" == "$PARSED_VERDICT" ]]; then
  log INFO "idempotent: stages.$PARSED_STAGE already reflects artifact=$ART verdict=$PARSED_VERDICT"
  exit 0
fi

# ---------- Build patch ----------
PATCH=$(jq -cn \
  --arg stage "$PARSED_STAGE" \
  --arg artifact "$ART" \
  --arg verdict "$PARSED_VERDICT" \
  '{stages: {($stage): {status: "completed", artifact: $artifact, verdict: $verdict}}}')

# ---------- Atomic write ----------
TMP=".context/.state.json.$$.${RANDOM}.tmp"
if jq --argjson p "$PATCH" '. * $p' "$STATE_JSON" > "$TMP" 2>>"$LOG"; then
  sync "$TMP" 2>/dev/null || sync 2>/dev/null || true
  mv -f "$TMP" "$STATE_JSON"
  log INFO "merged stages.$PARSED_STAGE artifact=$ART verdict=$PARSED_VERDICT (summary: ${PARSED_SUMMARY:0:80})"
else
  rm -f "$TMP" 2>/dev/null || true
  log ERROR "jq merge failed for stage=$PARSED_STAGE artifact=$ART; left state.json unchanged"
fi

# Always exit 0 — MUST NOT block stage transition.
exit 0

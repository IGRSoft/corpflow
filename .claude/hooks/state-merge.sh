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
#   CLAUDE_WORKTASK_ID, CLAUDE_DURATION_MS, CLAUDE_TASK_METADATA_STAGE
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
{"version":1,"worktask_id":"selftest","plan_file":".context/planning-0.md","platform":"all","stages":{"PL":{"status":"completed","verdict":"ok"}},"facts":{"files_modified":[],"tests_added":[],"decisions":[],"open_questions":[],"verdicts":{"PL":"ok"}},"handoffs":{}}
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

  # --- (a) NUMBERED artifact resolution via stage map (no CLAUDE_ARTIFACT_PATH) ---
  # state.json has run_index=0; write analyzing-0.md and analyzing-1.md (higher N)
  # to prove highest-N wins, then assert exact run_index match is preferred.
  cat > .context/state.json <<'EOF'
{"version":1,"worktask_id":"selftest","plan_file":".context/planning-0.md","platform":"all","run_index":0,"stages":{"PL":{"status":"completed","verdict":"ok"}},"facts":{"verdicts":{"PL":"ok"}},"handoffs":{}}
EOF
  cat > .context/analyzing-0.md <<'EOF'
---
handoff:
  stage: AR
  verdict: ok
  summary: "numbered artifact run 0"
---
# Architecture
EOF
  cat > .context/analyzing-1.md <<'EOF'
---
handoff:
  stage: AR
  verdict: blocked
  summary: "numbered artifact run 1"
---
# Architecture
EOF
  # No CLAUDE_ARTIFACT_PATH — force stage-map resolution. run_index=0 → analyzing-0.md.
  CLAUDE_TASK_METADATA_STAGE="AR" bash "$SELF" \
    || { echo "self-test: numbered hook returned non-zero" >&2; exit 1; }
  if jq -e '.stages.AR.status == "completed" and .stages.AR.verdict == "ok" and (.stages.AR.artifact | endswith("analyzing-0.md"))' .context/state.json >/dev/null; then
    echo "self-test: numbered artifact resolves to run_index match (analyzing-0.md): ok"
  else
    echo "self-test: numbered artifact resolution: FAIL (expected analyzing-0.md verdict=ok)" >&2
    jq '.stages.AR' .context/state.json >&2
    exit 1
  fi

  # --- (a') highest-N fallback when run_index absent ---
  cat > .context/state.json <<'EOF'
{"version":1,"worktask_id":"selftest","plan_file":".context/planning-0.md","platform":"all","stages":{"PL":{"status":"completed","verdict":"ok"}},"facts":{"verdicts":{"PL":"ok"}},"handoffs":{}}
EOF
  CLAUDE_TASK_METADATA_STAGE="AR" bash "$SELF" \
    || { echo "self-test: highest-N hook returned non-zero" >&2; exit 1; }
  if jq -e '.stages.AR.verdict == "blocked" and (.stages.AR.artifact | endswith("analyzing-1.md"))' .context/state.json >/dev/null; then
    echo "self-test: no run_index → highest-N wins (analyzing-1.md): ok"
  else
    echo "self-test: highest-N resolution: FAIL (expected analyzing-1.md verdict=blocked)" >&2
    jq '.stages.AR' .context/state.json >&2
    exit 1
  fi

  # --- (b) BARE legacy fallback still works ---
  rm -f .context/analyzing-0.md .context/analyzing-1.md
  cat > .context/state.json <<'EOF'
{"version":1,"worktask_id":"selftest","plan_file":".context/planning-0.md","platform":"all","stages":{"PL":{"status":"completed","verdict":"ok"}},"facts":{"verdicts":{"PL":"ok"}},"handoffs":{}}
EOF
  cat > .context/coordination.md <<'EOF'
---
handoff:
  stage: TL
  verdict: ok
  summary: "legacy bare artifact"
---
# Coordination
EOF
  CLAUDE_TASK_METADATA_STAGE="TL" bash "$SELF" \
    || { echo "self-test: bare-fallback hook returned non-zero" >&2; exit 1; }
  if jq -e '.stages.TL.status == "completed" and (.stages.TL.artifact | endswith("coordination.md"))' .context/state.json >/dev/null; then
    echo "self-test: bare legacy artifact fallback (coordination.md): ok"
  else
    echo "self-test: bare fallback: FAIL (expected coordination.md)" >&2
    jq '.stages.TL' .context/state.json >&2
    exit 1
  fi

  # --- (c) ABSENT artifact → empty/no-op (no literal '*', state unchanged) ---
  cp .context/state.json .context/state.json.snap2
  CLAUDE_TASK_METADATA_STAGE="QA" bash "$SELF" \
    || { echo "self-test: absent-artifact hook returned non-zero" >&2; exit 1; }
  if diff -q .context/state.json .context/state.json.snap2 >/dev/null \
     && ! jq -e 'has("stages") and (.stages | has("QA"))' .context/state.json >/dev/null; then
    echo "self-test: absent artifact → no-op (no QA stage, state unchanged): ok"
  else
    echo "self-test: absent artifact no-op: FAIL (state changed or QA appeared)" >&2
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

# Stage-code → artifact BASENAME map (per handoff-protocol.md#stage-artifact-map).
# Artifacts are canonically NUMBERED (<basename>-N.md, N = run_index); the bare
# <basename>.md is a one-release-cycle legacy fallback. POSIX-compatible lookup
# (bash 3.2 has no associative arrays).
basename_for_stage() {
  case "$1" in
    PL) echo "planning" ;;
    AR) echo "analyzing" ;;
    TL) echo "coordination" ;;
    DV) echo "development" ;;
    DR) echo "developer-review" ;;
    SR) echo "security-review" ;;
    QA) echo "testing" ;;
    DC) echo "documentation" ;;
    RE) echo "release" ;;
    FN) echo "complete-summary" ;;
    ST) echo "retrospective" ;;
    IR) echo "incident" ;;
    ET) echo "ethics-review" ;;
    *) echo "" ;;
  esac
}

# Resolve the on-disk artifact for a stage basename, preferring the NUMBERED form.
# Resolution order (per handoff-protocol.md#stage-artifact-map):
#   1. Exact <basename>-<RUN_INDEX>.md when run_index is known.
#   2. Highest-N match of <basename>-*.md (newest run_index).
#   3. Legacy bare <basename>.md (backward-compat, one release cycle).
#   4. Empty (no match) — guarded so an absent artifact never yields a literal '*'.
resolve_artifact() {
  local base="$1" exact="" newest=""
  [[ -z "$base" ]] && { echo ""; return 0; }

  # 1. Exact run_index match.
  if [[ -n "${RUN_INDEX:-}" && -f ".context/${base}-${RUN_INDEX}.md" ]]; then
    echo ".context/${base}-${RUN_INDEX}.md"
    return 0
  fi

  # 2. Highest-N numbered artifact. Sort numerically on the trailing -N suffix so
  #    'development-10.md' beats 'development-2.md' (lexical -t would not).
  newest=$(ls -1 ".context/${base}-"*.md 2>/dev/null \
    | sed -E 's/.*-([0-9]+)\.md$/\1 &/' \
    | grep -E '^[0-9]+ ' \
    | sort -k1,1 -n \
    | tail -1 \
    | sed -E 's/^[0-9]+ //')
  if [[ -n "$newest" && -f "$newest" ]]; then
    echo "$newest"
    return 0
  fi

  # 3. Legacy bare basename.
  if [[ -f ".context/${base}.md" ]]; then
    echo ".context/${base}.md"
    return 0
  fi

  # 4. No match.
  echo ""
}

if [[ -z "$ART" && -n "$STAGE" ]]; then
  # run_index from state.json (canonical); the hook receives no dedicated env var.
  RUN_INDEX=""
  if [[ -f "$STATE_JSON" ]] && command -v jq >/dev/null 2>&1; then
    RUN_INDEX=$(jq -r '.run_index // empty' "$STATE_JSON" 2>/dev/null || echo "")
  fi
  ART=$(resolve_artifact "$(basename_for_stage "$STAGE")")
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
# select(documentIndex == 0): an artifact is `--- handoff: … --- # Body`, which
# yq reads as TWO YAML documents. Without the selector, expressions like
# `.handoff.verdict // "ok"` evaluate per-document and emit the value twice
# (e.g. "ok\nok"), corrupting the merged verdict. Pin to the frontmatter doc.
parse_yq() {
  yq eval 'select(documentIndex == 0) | .handoff' "$1" 2>/dev/null
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
  PARSED_STAGE=$(yq eval 'select(documentIndex == 0) | .handoff.stage // ""' "$ART")
  PARSED_VERDICT=$(yq eval 'select(documentIndex == 0) | .handoff.verdict // "ok"' "$ART")
  PARSED_SUMMARY=$(yq eval 'select(documentIndex == 0) | .handoff.summary // ""' "$ART")
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

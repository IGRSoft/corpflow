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
# Implementation:
#   All merge logic lives in skills/worktask/scripts/state-patch.sh.
#   This hook is a thin delegating wrapper — exit 0 guard wraps the call.
#   Path: HOOK_DIR goes up two levels (out of hooks/, out of .claude/) to
#   reach the repo root, then into skills/worktask/scripts/state-patch.sh.
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
mkdir -p "$LOG_DIR" 2> /dev/null || true
LOG="$LOG_DIR/state-merge.log"

log() {
  printf '%s [%s] %s\n' "$(date -u +%FT%TZ)" "${1:-INFO}" "${2:-}" >> "$LOG" 2> /dev/null || true
}

# ---------- Legacy inline fallback ----------
# Used only when state-patch.sh is absent (e.g. transitional period / plugin update).
# Defined before main flow so shellcheck sees it as reachable.

_basename_for_stage() {
  case "$1" in
    PL) printf 'planning' ;;
    AR) printf 'analyzing' ;;
    TL) printf 'coordination' ;;
    DV) printf 'development' ;;
    DR) printf 'developer-review' ;;
    SR) printf 'security-review' ;;
    QA) printf 'testing' ;;
    DC) printf 'documentation' ;;
    RE) printf 'release' ;;
    FN) printf 'complete-summary' ;;
    ST) printf 'retrospective' ;;
    IR) printf 'incident' ;;
    ET) printf 'ethics-review' ;;
    *) printf '' ;;
  esac
}

_inline_merge() {
  local ART="${CLAUDE_ARTIFACT_PATH:-}"
  local STAGE="${CLAUDE_TASK_METADATA_STAGE:-}"
  local AGENT="${CLAUDE_AGENT_NAME:-}"
  local STATE_JSON=".context/state.json"

  _resolve_artifact_inline() {
    local base="$1" ri="" newest=""
    [[ -z "$base" ]] && {
      printf ''
      return 0
    }
    if [[ -f "$STATE_JSON" ]] && command -v jq > /dev/null 2>&1; then
      ri=$(jq -r '.run_index // empty' "$STATE_JSON" 2> /dev/null || printf '')
    fi
    if [[ -n "${ri:-}" && -f ".context/${base}-${ri}.md" ]]; then
      printf '.context/%s-%s.md' "$base" "$ri"
      return 0
    fi
    # shellcheck disable=SC2012  # ls needed for numeric-sort on controlled names
    newest=$(ls -1 ".context/${base}-"*.md 2> /dev/null \
      | sed -E 's/.*-([0-9]+)\.md$/\1 &/' \
      | grep -E '^[0-9]+ ' \
      | sort -k1,1 -n \
      | tail -1 \
      | sed -E 's/^[0-9]+ //') || newest=""
    if [[ -n "$newest" && -f "$newest" ]]; then
      printf '%s' "$newest"
      return 0
    fi
    if [[ -f ".context/${base}.md" ]]; then
      printf '.context/%s.md' "$base"
      return 0
    fi
    printf ''
  }

  if [[ -z "$ART" && -n "$STAGE" ]]; then
    ART=$(_resolve_artifact_inline "$(_basename_for_stage "$STAGE")")
  fi
  if [[ -z "$ART" || ! -f "$ART" ]]; then
    log WARN "inline: no artifact resolved (stage=$STAGE)"
    exit 0
  fi
  if [[ ! -f "$STATE_JSON" ]]; then
    log INFO "inline: state.json absent — F1 fallback"
    exit 0
  fi

  local FM="" PARSED_STAGE="" PARSED_VERDICT="" PARSED_SUMMARY=""
  if command -v yq > /dev/null 2>&1; then
    FM=$(yq eval 'select(documentIndex == 0) | .handoff' "$ART" 2> /dev/null || true)
  fi
  if [[ -z "$FM" || "$FM" == "null" ]]; then
    local RAW=""
    RAW=$(awk '/^---$/{ c++; next } c==1' "$ART" 2> /dev/null || true)
    if [[ -z "$RAW" ]]; then
      PARSED_STAGE="${STAGE:-${AGENT:-UNKNOWN}}"
      PARSED_VERDICT="ok"
      PARSED_SUMMARY="auto-generated (fallback)"
    else
      PARSED_STAGE=$(awk -F: '/^[[:space:]]*stage:/ { gsub(/[[:space:]"]+/,"",$2); print $2; exit }' <<< "$RAW")
      PARSED_VERDICT=$(awk -F: '/^[[:space:]]*verdict:/ { gsub(/[[:space:]"]+/,"",$2); print $2; exit }' <<< "$RAW")
      PARSED_SUMMARY=$(awk -F: '/^[[:space:]]*summary:/ { sub(/^[[:space:]]*summary:[[:space:]]*/,""); gsub(/^"|"$/,""); print; exit }' <<< "$RAW")
      [[ -z "$PARSED_VERDICT" ]] && PARSED_VERDICT="ok"
      [[ -z "$PARSED_SUMMARY" ]] && PARSED_SUMMARY="(auto)"
    fi
  else
    PARSED_STAGE=$(yq eval 'select(documentIndex == 0) | .handoff.stage // ""' "$ART" 2> /dev/null || true)
    PARSED_VERDICT=$(yq eval 'select(documentIndex == 0) | .handoff.verdict // "ok"' "$ART" 2> /dev/null || true)
    PARSED_SUMMARY=$(yq eval 'select(documentIndex == 0) | .handoff.summary // ""' "$ART" 2> /dev/null || true)
    [[ -z "$PARSED_VERDICT" ]] && PARSED_VERDICT="ok"
    [[ -z "$PARSED_SUMMARY" ]] && PARSED_SUMMARY="(auto)"
  fi

  [[ -z "$PARSED_STAGE" ]] && {
    log WARN "inline: no stage extracted"
    exit 0
  }

  local CS="" CV=""
  CS=$(jq -r --arg s "$PARSED_STAGE" '.stages[$s].status // ""' "$STATE_JSON" 2> /dev/null || printf '')
  CV=$(jq -r --arg s "$PARSED_STAGE" '.stages[$s].verdict // ""' "$STATE_JSON" 2> /dev/null || printf '')
  if [[ "$CS" == "completed" && "$CV" == "$PARSED_VERDICT" ]]; then
    log INFO "inline: idempotent"
    exit 0
  fi

  local PATCH TMP
  PATCH=$(jq -cn --arg stage "$PARSED_STAGE" --arg artifact "$ART" --arg verdict "$PARSED_VERDICT" \
    '{stages:{($stage):{status:"completed",artifact:$artifact,verdict:$verdict}}}')
  TMP=".context/.state.json.$$.${RANDOM}.tmp"
  if jq --argjson p "$PATCH" '. * $p' "$STATE_JSON" > "$TMP" 2>> "$LOG"; then
    sync "$TMP" 2> /dev/null || sync 2> /dev/null || true
    mv -f "$TMP" "$STATE_JSON"
    log INFO "inline: merged stages.$PARSED_STAGE verdict=$PARSED_VERDICT"
  else
    rm -f "$TMP" 2> /dev/null || true
    log ERROR "inline: jq merge failed"
  fi
  # Suppress unused-variable warning: PARSED_SUMMARY is informational only.
  : "$PARSED_SUMMARY"
  exit 0
}

# ---------- Self-test ----------
# Re-run all original hook self-test cases by delegating to state-patch.sh --self-test.
# The cases cover: explicit artifact, idempotency, numbered artifact resolution (exact
# run_index + highest-N), legacy bare fallback, and absent-artifact no-op.
if [[ "${1:-}" == "--self-test" ]]; then
  HOOK_DIR=$(cd "$(dirname "$0")" && pwd)
  # .claude/hooks/ is two levels below the repo root; go up two levels to reach
  # the repo root, then descend into skills/worktask/scripts/.
  PATCH_SCRIPT="${HOOK_DIR}/../../skills/worktask/scripts/state-patch.sh"
  if [[ ! -f "$PATCH_SCRIPT" ]]; then
    printf 'self-test: state-patch.sh not found at %s\n' "$PATCH_SCRIPT" >&2
    exit 1
  fi

  # Run the canonical self-test from state-patch.sh (covers all paths this hook uses).
  if bash "$PATCH_SCRIPT" --self-test; then
    printf 'self-test (via state-patch.sh): ALL PASS\n'
    exit 0
  else
    printf 'self-test: state-patch.sh --self-test FAILED\n' >&2
    exit 1
  fi
fi

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  sed -n 's/^# \{0,1\}//p' "$0" | sed -n '1,/^$/p'
  exit 0
fi

# ---------- Locate state-patch.sh ----------
HOOK_DIR=$(cd "$(dirname "$0")" && pwd)
# Up two levels: out of hooks/, out of .claude/ → repo root → skills/...
PATCH_SCRIPT="${HOOK_DIR}/../../skills/worktask/scripts/state-patch.sh"

if [[ ! -f "$PATCH_SCRIPT" ]]; then
  log WARN "state-patch.sh not found at $PATCH_SCRIPT — falling back to legacy inline merge"
  # Legacy inline fallback so the hook continues to work if the skills tree is
  # absent (e.g. during a plugin update that hasn't landed state-patch.sh yet).
  _inline_merge
fi

# ---------- Delegate to state-patch.sh ----------
# Build CLI args from the SubagentStop env vars.  state-patch.sh is the single
# implementation; the hook just translates env → argv and enforces exit 0.
PATCH_ARGS=()
[[ -n "${CLAUDE_TASK_METADATA_STAGE:-}" ]] && PATCH_ARGS+=(--stage "$CLAUDE_TASK_METADATA_STAGE")
[[ -n "${CLAUDE_ARTIFACT_PATH:-}" ]] && PATCH_ARGS+=(--artifact "$CLAUDE_ARTIFACT_PATH")
PATCH_ARGS+=(--log "$LOG")
# completed_via provenance: this delegating hook is enforcement Layer 2 ("hook").
# The orchestrator's synchronous Step-6.5 path overrides via STATE_MERGE_VIA=step6_5
# so the two layers are distinguishable in state.json. (Additive; absence = Layer 1.)
PATCH_ARGS+=(--via "${STATE_MERGE_VIA:-hook}")

bash "$PATCH_SCRIPT" "${PATCH_ARGS[@]}" 2>> "$LOG" || {
  log ERROR "state-patch.sh exited non-zero (stage=${CLAUDE_TASK_METADATA_STAGE:-} art=${CLAUDE_ARTIFACT_PATH:-}); continuing"
}

# Always exit 0 — MUST NOT block stage transition.
exit 0

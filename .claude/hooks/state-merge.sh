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
#   - state.json absent: log INFO and exit 0 (path F1 — `context_files` mode).
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
#   Path: $CLAUDE_PLUGIN_ROOT first (a project-local copy of this hook has no
#   skills/ tree beside it), else HOOK_DIR up two levels to the repo root.
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

_basename_for_stage() {
  case "$1" in
    PL) printf 'planning' ;;
    AR) printf 'architecture' ;;
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

# ---------- Self-test ----------
# Re-run all original hook self-test cases by delegating to state-patch.sh --self-test.
# The cases cover: explicit artifact, idempotency, numbered artifact resolution (exact
# run_index + highest-N), and absent-artifact no-op.
if [[ "${1:-}" == "--self-test" ]]; then
  HOOK_DIR=$(cd "$(dirname "$0")" && pwd)
  # .claude/hooks/ is two levels below the repo root; go up two levels to reach
  # the repo root, then descend into skills/worktask/scripts/.
  PATCH_SCRIPT="${CLAUDE_PLUGIN_ROOT:-${HOOK_DIR}/../..}/skills/worktask/scripts/state-patch.sh"
  if [[ ! -f "$PATCH_SCRIPT" ]]; then
    PATCH_SCRIPT="${HOOK_DIR}/../../skills/worktask/scripts/state-patch.sh"
  fi
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
# Plugin root first: worktask.md Step 3b copies this hook into <project>/.claude/hooks/,
# where the relative arm resolves to a skills/ tree that does not exist. state-patch.sh is
# the only merge implementation, so failing to find it silently disables the Layer-2 net.
PATCH_SCRIPT="${CLAUDE_PLUGIN_ROOT:-${HOOK_DIR}/../..}/skills/worktask/scripts/state-patch.sh"
if [[ ! -f "$PATCH_SCRIPT" ]]; then
  PATCH_SCRIPT="${HOOK_DIR}/../../skills/worktask/scripts/state-patch.sh"
fi

if [[ ! -f "$PATCH_SCRIPT" ]]; then
  # Exit 0, never non-zero: a SubagentStop hook must not block the stage transition.
  log WARN "state-patch.sh not found at $PATCH_SCRIPT — skipping state merge"
  exit 0
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

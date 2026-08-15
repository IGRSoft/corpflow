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
#   - state.json corrupt: back the original up to state.json.corrupt.<ts>, rebuild a
#     skeleton so the merge below can proceed, and audit it. The backup is never
#     skipped and the original is never destroyed; if it cannot be verified the
#     repair aborts and the corrupt file is left exactly as found.
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

# ---------- Corrupt-ledger repair ----------
# state-patch.sh cannot merge into a ledger it cannot parse: it logs the jq failure and
# leaves the file alone, so one corrupt write silently swallows every later stage. The
# repair rebuilds the SKELETON ONLY and re-enters the delegation below, which still owns
# the field merge — nothing here parses handoff fields, and state-patch.sh is unchanged.
#
# Invariant: the corrupt original is copied aside and verified byte-equal BEFORE anything
# is written, and an unverifiable backup aborts the repair. A corrupt ledger is
# recoverable; a destroyed one is not.
STATE_FILE=".context/state.json"

# First unused name in the base, base-1, base-2 … series.
# `-L` as well as `-e`: `-e` is false for a DANGLING symlink, so a pre-planted broken
# link would read as a free name, `cp` would follow it to the link's target, and the
# `cmp -s` guard would dereference the same link and pass — a silent write-through.
_repair_backup_path() {
  local candidate="$1" i=1
  while [[ -e "$candidate" || -L "$candidate" ]]; do
    candidate="$1-$i"
    i=$((i + 1))
  done
  printf '%s' "$candidate"
}

# Scrape a JSON string field out of bytes that no longer parse. Best-effort by
# construction: empty output means "no salvage", not "field absent".
_salvage_field() {
  local out
  if out=$(sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$1" 2> /dev/null); then
    printf '%s' "${out%%$'\n'*}"
  fi
}

# ALWAYS returns 0. Every non-repair path returns silently and leaves the corrupt file
# untouched, which is the pre-existing behaviour this must stay byte-identical to; only
# a repair that starts and then fails is worth a log line.
_repair_corrupt_state() {
  local art="${CLAUDE_ARTIFACT_PATH:-}" fm backup tmp wt_id platform row n=0 suffix

  [[ -n "$art" && -f "$art" ]] || return 0
  fm=$(sed -n '1,40p' "$art" 2> /dev/null) || return 0
  # Subset check only — enough to know a rebuild is warranted. state-patch.sh below is
  # the authoritative parser.
  [[ $fm == *handoff:* ]] || return 0
  [[ $fm =~ [[:space:]]stage:[[:space:]]*[A-Za-z] ]] || return 0

  # run_index from the artifact's -N.md suffix: the same source state-patch.sh resolves
  # artifacts by, so the rebuilt skeleton cannot be labelled for a different run.
  suffix="${art##*-}"
  suffix="${suffix%.md}"
  if [[ $suffix =~ ^[0-9]+$ ]]; then n="$suffix"; fi

  backup=$(_repair_backup_path "$STATE_FILE.corrupt.$(date -u +%Y%m%dT%H%M%SZ)")
  if ! cp "$STATE_FILE" "$backup" 2> /dev/null || ! cmp -s "$STATE_FILE" "$backup"; then
    log WARN "corrupt state.json: backup to $backup failed or unverifiable — repair aborted, file untouched"
    if [[ -e "$backup" ]] && ! rm -f "$backup" 2> /dev/null; then
      log WARN "corrupt state.json: partial backup left at $backup"
    fi
    return 0
  fi

  wt_id=$(_salvage_field "$STATE_FILE" worktask_id)
  [[ -n "$wt_id" ]] || wt_id="${CLAUDE_WORKTASK_ID:-unknown}"
  platform=$(_salvage_field "$STATE_FILE" platform)
  [[ -n "$platform" ]] || platform="all"

  # Same directory as the target so the rename is atomic.
  tmp=".context/.state.json.repair.$$.tmp"
  if ! jq -cn --arg id "$wt_id" --arg plat "$platform" --argjson n "$n" '
      { version: 2, worktask_id: $id,
        plan_file: (".context/planning-" + ($n | tostring) + ".md"),
        platform: $plat, run_index: $n,
        tasks: {}, facts: {}, handoffs: {}, metadata: {} }' > "$tmp" 2> /dev/null; then
    log WARN "corrupt state.json: skeleton write failed — file untouched (backup at $backup)"
    if [[ -e "$tmp" ]] && ! rm -f "$tmp" 2> /dev/null; then
      log WARN "corrupt state.json: stale temp left at $tmp"
    fi
    return 0
  fi
  if ! mv -f "$tmp" "$STATE_FILE"; then
    log WARN "corrupt state.json: rename failed — file untouched (backup at $backup)"
    return 0
  fi

  if row=$(jq -cn --arg ts "$(date -u +%FT%TZ)" --arg id "$wt_id" --arg backup "$backup" \
    --argjson n "$n" --arg stage "${CLAUDE_TASK_METADATA_STAGE:-}" --arg art "$art" '
      { ts: $ts, actor: "hook:state-merge", action: "state_repair", subject: $id,
        result: "repaired",
        metadata: { reason: "corrupt_state_json", backup: $backup, run_index: $n,
                    stage: $stage, artifact: $art } }' 2> /dev/null); then
    printf '%s\n' "$row" >> "$LOG_DIR/audit.jsonl"
  fi
  log INFO "corrupt state.json rebuilt from $art (backup=$backup run_index=$n) — delegating merge"
  return 0
}

# Idempotent by construction: after a repair the ledger parses, so a re-run does not
# re-enter this block — no second backup, no second audit row.
if [[ -f "$STATE_FILE" ]] && command -v jq > /dev/null 2>&1 \
  && ! jq -e . "$STATE_FILE" > /dev/null 2>&1; then
  _repair_corrupt_state
fi

# ---------- Delegate to state-patch.sh ----------
# Build CLI args from the SubagentStop env vars.  state-patch.sh is the single
# implementation; the hook just translates env → argv and enforces exit 0.
PATCH_ARGS=()
[[ -n "${CLAUDE_TASK_METADATA_STAGE:-}" ]] && PATCH_ARGS+=(--stage "$CLAUDE_TASK_METADATA_STAGE")
[[ -n "${CLAUDE_ARTIFACT_PATH:-}" ]] && PATCH_ARGS+=(--artifact "$CLAUDE_ARTIFACT_PATH")
# The stage code alone cannot name a split stage's instance, so forward the runtime's task
# id when it supplies one; the shape guard keeps a malformed value from becoming a new key.
[[ "${CLAUDE_TASK_ID:-}" =~ ^[A-Z]{2}[0-9]+$ ]] && PATCH_ARGS+=(--task-id "$CLAUDE_TASK_ID")
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

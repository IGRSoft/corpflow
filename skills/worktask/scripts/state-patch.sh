#!/usr/bin/env bash
# @description state-patch.sh — synchronous Step-6.5 state.json completion patch.
#
#   Resolves the artifact path for a stage, parses its `handoff:` frontmatter,
#   builds the completion patch, and performs an atomic tmp → fsync → rename
#   merge into .context/state.json.  Includes the ENOSPC / DISK_MIN_GB guard
#   (< DISK_MIN_GB halts; < DISK_WARN_GB warns) so callers share one policy.
#
#   This is the SINGLE IMPLEMENTATION of the state-patch logic.  The
#   SubagentStop hook at .claude/hooks/state-merge.sh delegates to this script
#   via `bash <path>/state-patch.sh [opts]` — no merge logic lives in the hook
#   itself beyond the delegation call.
#
# @arg --stage <CODE>       Stage code (PL AR TL DV DR SR QA DC RE FN ST IR ET).
#                           Required unless --artifact is given with parseable frontmatter.
# @arg --artifact <path>    Explicit artifact path.  When omitted, resolved from
#                           --stage + run_index from state.json.
# @arg --state <path>       state.json path (default: .context/state.json).
# @arg --log <path>         Append log to this file (default: .context/logs/state-merge.log).
# @arg --disk-check         Run the ENOSPC guard before writing.  Pass the workspace
#                           filesystem root as the argument value (defaults to ".").
#                           When the guard fires (halt), exits 2; on warn exits 0.
# @arg --self-test          Run the built-in self-test and exit.
# @arg -h | --help          Show this header.
#
# @exitcode 0   Patch applied (or already idempotent; or artifact absent / state absent).
# @exitcode 1   Internal error (jq merge failed; use --log to inspect).
# @exitcode 2   DISK_MIN_GB hard-halt triggered (caller must remediate before retrying).
#
# Env vars honoured:
#   DISK_MIN_GB   (default 5)  — hard halt threshold in GiB
#   DISK_WARN_GB  (default 8)  — hygiene warn threshold in GiB
#   RUN_INDEX     — override run_index (for callers that know it without reading state.json)
#
# Single-writer / idempotent-merge invariant: state.json is written only when the
# patch changes its content.  Temp file is PID+RANDOM-namespaced to guard against
# PID reuse in Task subagents (CR-7 from handoff-protocol.md#atomic-write).
#
# Minimum shell: bash 3.2+ (macOS default); relies on no bash 4+ features so the
# SubagentStop hook environment on older macOS is fully supported.

set -euo pipefail
IFS=$'\n\t'
trap 'printf >&2 "error: %s:%d: exit %d\n" "${BASH_SOURCE[0]}" "$LINENO" "$?"' ERR

# ---------- Constants ----------
DISK_MIN_GB="${DISK_MIN_GB:-5}"
DISK_WARN_GB="${DISK_WARN_GB:-8}"

# ---------- Usage ----------
usage() {
  sed -n 's/^# \{0,1\}//p' "$0" | head -50
  exit 2
}

# ---------- Helpers ----------
log_msg() {
  # log_msg <LEVEL> <message>
  local level="${1:-INFO}" msg="${2:-}"
  printf '%s [%s] %s\n' "$(date -u +%FT%TZ)" "$level" "$msg" >> "$LOG_FILE" 2> /dev/null || true
}

# Stage code → artifact BASENAME (mirrors state-merge.sh and handoff-protocol.md#stage-artifact-map).
basename_for_stage() {
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

# Resolve on-disk artifact for a stage BASENAME.
# Resolution order (per handoff-protocol.md#stage-artifact-map):
#   1. Exact .context/<base>-<RUN_INDEX>.md when RUN_INDEX is known.
#   2. Highest-N numbered artifact (newest run_index).
#   3. Legacy bare .context/<base>.md.
#   4. Empty (absent) — never yields a literal '*'.
resolve_artifact() {
  local base="$1" ctx="${2:-.context}"
  [[ -z "$base" ]] && {
    printf ''
    return 0
  }

  # 1. Exact run_index match.
  if [[ -n "${RUN_INDEX:-}" && -f "${ctx}/${base}-${RUN_INDEX}.md" ]]; then
    printf '%s' "${ctx}/${base}-${RUN_INDEX}.md"
    return 0
  fi

  # 2. Highest-N numbered artifact — sort numerically on trailing -N suffix.
  #    ls is required here: find output is unordered and we need numeric sort
  #    on the -N suffix. Artifact basenames are controlled (no special chars).
  local newest=""
  # shellcheck disable=SC2012  # ls needed for numeric-sort pipeline on controlled names
  newest=$(ls -1 "${ctx}/${base}-"*.md 2> /dev/null \
    | sed -E 's/.*-([0-9]+)\.md$/\1 &/' \
    | grep -E '^[0-9]+ ' \
    | sort -k1,1 -n \
    | tail -1 \
    | sed -E 's/^[0-9]+ //')
  if [[ -n "$newest" && -f "$newest" ]]; then
    printf '%s' "$newest"
    return 0
  fi

  # 3. Legacy bare basename.
  if [[ -f "${ctx}/${base}.md" ]]; then
    printf '%s' "${ctx}/${base}.md"
    return 0
  fi

  # 4. No match.
  printf ''
}

# Parse frontmatter with yq (preferred) or awk fallback.
# Sets PARSED_STAGE, PARSED_VERDICT, PARSED_SUMMARY in the caller's scope.
parse_frontmatter() {
  local art="$1"
  PARSED_STAGE="" PARSED_VERDICT="" PARSED_SUMMARY=""

  local fm=""
  if command -v yq > /dev/null 2>&1; then
    # select(documentIndex == 0): guard against double-document YAML artifacts.
    fm=$(yq eval 'select(documentIndex == 0) | .handoff' "$art" 2> /dev/null || true)
  fi

  if [[ -z "$fm" || "$fm" == "null" ]]; then
    # Awk fallback: extract block between first two ^---$ fences.
    local raw=""
    raw=$(awk '/^---$/{ c++; next } c==1' "$art" 2> /dev/null || true)

    if [[ -z "$raw" ]]; then
      log_msg WARN "no frontmatter in $art — F3 fallback"
      PARSED_STAGE="${STAGE_ARG:-}"
      PARSED_VERDICT="ok"
      PARSED_SUMMARY="auto-generated by state-patch.sh (frontmatter missing)"
      return 0
    fi

    PARSED_STAGE=$(awk -F: '/^[[:space:]]*stage:/ { gsub(/[[:space:]"]+/,"",$2); print $2; exit }' \
      <<< "$raw")
    PARSED_VERDICT=$(awk -F: '/^[[:space:]]*verdict:/ { gsub(/[[:space:]"]+/,"",$2); print $2; exit }' \
      <<< "$raw")
    PARSED_SUMMARY=$(awk -F: '/^[[:space:]]*summary:/ { sub(/^[[:space:]]*summary:[[:space:]]*/,""); gsub(/^"|"$/,""); print; exit }' \
      <<< "$raw")
  else
    # yq path: parse individual fields.
    PARSED_STAGE=$(yq eval 'select(documentIndex == 0) | .handoff.stage // ""' "$art" 2> /dev/null || true)
    PARSED_VERDICT=$(yq eval 'select(documentIndex == 0) | .handoff.verdict // "ok"' "$art" 2> /dev/null || true)
    PARSED_SUMMARY=$(yq eval 'select(documentIndex == 0) | .handoff.summary // ""' "$art" 2> /dev/null || true)
  fi

  [[ -z "$PARSED_VERDICT" ]] && PARSED_VERDICT="ok"
  [[ -z "$PARSED_SUMMARY" ]] && PARSED_SUMMARY="(auto)"
  return 0
}

# ENOSPC guard.  Returns 0 (ok/warn), exits 2 (halt).
disk_guard() {
  local root="${1:-.}"
  local avail_gb=""
  avail_gb=$(df -Pg "$root" 2> /dev/null | awk 'NR==2 {print $4+0}') || avail_gb=""

  [[ -z "$avail_gb" ]] && return 0 # df unparseable → degrade silently, never block

  if ((avail_gb < DISK_MIN_GB)); then
    log_msg ERROR "DISK_HALT: only ${avail_gb}GB free (< ${DISK_MIN_GB}GB) on $root"
    printf >&2 'HALT: only %dGB free (< %dGB) on %s.\nReclaim space:\n  swift package clean\n  rm -rf ~/Library/Developer/Xcode/DerivedData/*\n' \
      "$avail_gb" "$DISK_MIN_GB" "$root"
    exit 2
  elif ((avail_gb < DISK_WARN_GB)); then
    log_msg WARN "DISK_WARN: ${avail_gb}GB free (< ${DISK_WARN_GB}GB) on $root — consider swift package clean"
  fi
}

# Atomic state.json merge (read → merge → temp → fsync → rename).
atomic_merge() {
  local state="$1" patch="$2"
  local tmp="${state%/*}/.state.json.$$.${RANDOM}.tmp"

  if jq --argjson p "$patch" '. * $p' "$state" > "$tmp" 2>> "$LOG_FILE"; then
    sync "$tmp" 2> /dev/null || sync 2> /dev/null || true
    mv -f "$tmp" "$state"
    return 0
  else
    rm -f "$tmp" 2> /dev/null || true
    return 1
  fi
}

# ---------- Self-test ----------
run_self_test() {
  # Resolve path BEFORE any cd so subprocess calls work.
  local SELF
  SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")

  local td
  td=$(mktemp -d -t state-patch-selftest-XXXXXX)
  # shellcheck disable=SC2064   # expand $td now so the trap removes the right dir
  trap "rm -rf '${td}'" EXIT

  cd "$td"
  mkdir -p .context/logs

  # ---- Fixture helpers ----
  make_state() {
    cat > .context/state.json << 'EOSTATE'
{"version":1,"worktask_id":"selftest","plan_file":".context/planning-0.md","platform":"all","run_index":0,"stages":{"PL":{"status":"completed","verdict":"ok"}},"facts":{"files_modified":[],"tests_added":[],"decisions":[],"open_questions":[],"verdicts":{"PL":"ok"}},"handoffs":{}}
EOSTATE
  }

  # ---- T1: explicit --artifact path, frontmatter present ----
  make_state
  cat > .context/development-0.md << 'EOART'
---
handoff:
  stage: DV
  verdict: ok
  summary: "self-test artifact T1"
  files_touched: [a.md]
  next_stage_focus: "DR reviews"
  refs: { dev: development.md#files-changed }
---

# Development
EOART
  bash "$SELF" --stage DV --artifact .context/development-0.md \
    || {
      printf 'T1: state-patch returned non-zero\n' >&2
      exit 1
    }
  if jq -e '.stages.DV.status == "completed" and .stages.DV.verdict == "ok"' \
    .context/state.json > /dev/null; then
    printf 'T1: explicit artifact → patched: ok\n'
  else
    printf 'T1: explicit artifact → patch missing: FAIL\n' >&2
    exit 1
  fi

  # ---- T2: idempotency — re-run must leave state.json byte-identical ----
  cp .context/state.json .context/state.json.snap
  bash "$SELF" --stage DV --artifact .context/development-0.md
  if diff -q .context/state.json .context/state.json.snap > /dev/null; then
    printf 'T2: idempotent re-run: ok\n'
  else
    printf 'T2: idempotent re-run: FAIL (state changed)\n' >&2
    exit 1
  fi

  # ---- T3: no --artifact, resolve via run_index=0 from state.json ----
  make_state
  # development-0.md already exists from T1.
  bash "$SELF" --stage DV \
    || {
      printf 'T3: state-patch returned non-zero\n' >&2
      exit 1
    }
  if jq -e '.stages.DV.status == "completed" and (.stages.DV.artifact | endswith("development-0.md"))' \
    .context/state.json > /dev/null; then
    printf 'T3: run_index-resolved artifact: ok\n'
  else
    printf 'T3: run_index-resolved artifact: FAIL\n' >&2
    exit 1
  fi

  # ---- T4: highest-N fallback when run_index absent from state.json ----
  cat > .context/state.json << 'EOSTATE'
{"version":1,"worktask_id":"selftest","plan_file":".context/planning-0.md","platform":"all","stages":{"PL":{"status":"completed","verdict":"ok"}},"facts":{"verdicts":{"PL":"ok"}},"handoffs":{}}
EOSTATE
  cat > .context/analyzing-1.md << 'EOART'
---
handoff:
  stage: AR
  verdict: blocked
  summary: "highest-N artifact"
  refs: { plan: planning-0.md#requirements }
---
EOART
  cat > .context/analyzing-0.md << 'EOART'
---
handoff:
  stage: AR
  verdict: ok
  summary: "lower-N artifact"
  refs: { plan: planning-0.md#requirements }
---
EOART
  bash "$SELF" --stage AR \
    || {
      printf 'T4: state-patch returned non-zero\n' >&2
      exit 1
    }
  if jq -e '.stages.AR.verdict == "blocked" and (.stages.AR.artifact | endswith("analyzing-1.md"))' \
    .context/state.json > /dev/null; then
    printf 'T4: highest-N wins when run_index absent: ok\n'
  else
    printf 'T4: highest-N resolution: FAIL\n' >&2
    jq '.stages.AR' .context/state.json >&2
    exit 1
  fi

  # ---- T5: absent artifact → no-op, state unchanged ----
  cat > .context/state.json << 'EOSTATE'
{"version":1,"worktask_id":"selftest","plan_file":".context/planning-0.md","platform":"all","stages":{"PL":{"status":"completed","verdict":"ok"}},"facts":{"verdicts":{"PL":"ok"}},"handoffs":{}}
EOSTATE
  cp .context/state.json .context/state.json.snap2
  # No QA artifact exists.
  bash "$SELF" --stage QA \
    || {
      printf 'T5: state-patch returned non-zero\n' >&2
      exit 1
    }
  if diff -q .context/state.json .context/state.json.snap2 > /dev/null; then
    printf 'T5: absent artifact → no-op: ok\n'
  else
    printf 'T5: absent artifact → no-op: FAIL (state changed)\n' >&2
    exit 1
  fi

  # ---- T6: disk guard — warn threshold only (no halt) ----
  # We can't safely drop disk space in a test, so we prove the guard degrades
  # gracefully when df output is unparseable (empty avail_gb).
  make_state
  cat > .context/testing-0.md << 'EOART'
---
handoff:
  stage: QA
  verdict: go
  summary: "disk guard T6"
  refs: { dev: development-0.md#files-changed }
---
EOART
  bash "$SELF" --stage QA --artifact .context/testing-0.md --disk-check /nonexistent_mountpoint_selftest \
    || {
      printf 'T6: disk-guard degrade: non-zero exit\n' >&2
      exit 1
    }
  if jq -e '.stages.QA.status == "completed"' .context/state.json > /dev/null; then
    printf 'T6: disk-guard degrade on unparseable df → patch applied: ok\n'
  else
    printf 'T6: disk-guard degrade: FAIL\n' >&2
    exit 1
  fi

  # ---- T7: legacy bare artifact fallback ----
  cat > .context/state.json << 'EOSTATE'
{"version":1,"worktask_id":"selftest","plan_file":".context/planning-0.md","platform":"all","stages":{"PL":{"status":"completed","verdict":"ok"}},"facts":{"verdicts":{"PL":"ok"}},"handoffs":{}}
EOSTATE
  cat > .context/coordination.md << 'EOART'
---
handoff:
  stage: TL
  verdict: ok
  summary: "legacy bare artifact"
  refs: { plan: planning-0.md#requirements }
---
EOART
  bash "$SELF" --stage TL \
    || {
      printf 'T7: state-patch returned non-zero\n' >&2
      exit 1
    }
  if jq -e '.stages.TL.status == "completed" and (.stages.TL.artifact | endswith("coordination.md"))' \
    .context/state.json > /dev/null; then
    printf 'T7: legacy bare artifact fallback: ok\n'
  else
    printf 'T7: legacy bare artifact fallback: FAIL\n' >&2
    exit 1
  fi

  printf 'self-test: ALL PASS\n'
  exit 0
}

# ---------- Argument parsing ----------
STAGE_ARG=""
ARTIFACT_ARG=""
STATE_PATH=".context/state.json"
LOG_FILE=".context/logs/state-merge.log"
DISK_CHECK_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stage)
      shift
      STAGE_ARG="${1:-}"
      shift
      ;;
    --artifact)
      shift
      ARTIFACT_ARG="${1:-}"
      shift
      ;;
    --state)
      shift
      STATE_PATH="${1:-}"
      shift
      ;;
    --log)
      shift
      LOG_FILE="${1:-}"
      shift
      ;;
    --disk-check)
      DISK_CHECK_ROOT="."
      shift
      ;;
    --self-test) run_self_test ;;
    -h | --help) usage ;;
    *)
      printf >&2 'unknown argument: %s\n' "$1"
      usage
      ;;
  esac
done

# ---------- Pre-flight ----------
mkdir -p "$(dirname "$LOG_FILE")" 2> /dev/null || true

# ENOSPC guard (optional — only when caller requests it).
[[ -n "$DISK_CHECK_ROOT" ]] && disk_guard "$DISK_CHECK_ROOT"

# ---------- Resolve artifact ----------
ART="$ARTIFACT_ARG"

if [[ -z "$ART" && -n "$STAGE_ARG" ]]; then
  # Pull run_index from state.json when available.
  if [[ -f "$STATE_PATH" ]] && command -v jq > /dev/null 2>&1; then
    RUN_INDEX=$(jq -r '.run_index // empty' "$STATE_PATH" 2> /dev/null || printf '')
  fi

  _local_base=$(basename_for_stage "$STAGE_ARG")
  ART=$(resolve_artifact "$_local_base")
fi

if [[ -z "$ART" || ! -f "$ART" ]]; then
  log_msg WARN "no artifact resolved (stage=${STAGE_ARG:-} artifact=${ARTIFACT_ARG:-}) — no-op"
  exit 0
fi

if [[ ! -f "$STATE_PATH" ]]; then
  log_msg INFO "state.json absent — F1 fallback active, no merge needed (artifact=$ART)"
  exit 0
fi

# ---------- Parse frontmatter ----------
parse_frontmatter "$ART"

if [[ -z "$PARSED_STAGE" ]]; then
  log_msg WARN "could not extract stage from $ART; aborting merge silently"
  exit 0
fi

# ---------- Idempotency check ----------
if command -v jq > /dev/null 2>&1; then
  CURRENT_STATUS=$(jq -r --arg s "$PARSED_STAGE" '.stages[$s].status // ""' \
    "$STATE_PATH" 2> /dev/null || printf '')
  CURRENT_VERDICT=$(jq -r --arg s "$PARSED_STAGE" '.stages[$s].verdict // ""' \
    "$STATE_PATH" 2> /dev/null || printf '')
else
  CURRENT_STATUS="" CURRENT_VERDICT=""
fi

if [[ "$CURRENT_STATUS" == "completed" && "$CURRENT_VERDICT" == "$PARSED_VERDICT" ]]; then
  log_msg INFO "idempotent: stages.${PARSED_STAGE} already completed verdict=${PARSED_VERDICT}"
  exit 0
fi

# ---------- Build patch + atomic write ----------
PATCH=$(jq -cn \
  --arg stage "$PARSED_STAGE" \
  --arg artifact "$ART" \
  --arg verdict "$PARSED_VERDICT" \
  '{stages: {($stage): {status: "completed", artifact: $artifact, verdict: $verdict}}}')

if atomic_merge "$STATE_PATH" "$PATCH"; then
  log_msg INFO "merged stages.${PARSED_STAGE} artifact=${ART} verdict=${PARSED_VERDICT} (summary: ${PARSED_SUMMARY:0:80})"
else
  log_msg ERROR "jq merge failed for stage=${PARSED_STAGE} artifact=${ART}; state.json unchanged"
  exit 1
fi

exit 0

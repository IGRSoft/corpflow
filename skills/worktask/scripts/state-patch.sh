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
# @arg --prev <CODE>        Previous stage code.  When present, ALSO writes
#                           handoffs["<PREV>→<CODE>"] = "<summary> ref:<artifact basename>"
#                           from the parsed frontmatter summary (the ledger edge the 13
#                           stage agents used to hand-roll in inline jq).  ABSENT = today's
#                           behavior exactly (stages patch only, byte-stable); hook callers
#                           never pass it, so the SubagentStop path is untouched.
# @arg --state <path>       state.json path (default: .context/state.json).
# @arg --log <path>         Append log to this file (default: .context/logs/state-merge.log).
# @arg --disk-check [root]  Run the ENOSPC guard before writing.  Optional filesystem-root
#                           value (defaults to "."); a following token that begins with "-"
#                           is NOT consumed as the root.  When the guard fires (halt), exits 2;
#                           on warn exits 0.
# @arg --via <hook|step6_5> Stamp stages.<CODE>.completed_via with the enforcement
#                           layer that fired.  Omit for agent self-patch (Layer 1);
#                           F3 stamps "f3" via its own patch.  Absence encodes Layer 1
#                           / pre-upgrade (additive, version:1 unchanged).
# @arg --self-test          Run the built-in self-test and exit.
# @arg -h | --help          Show this header.
#
# @exitcode 0   Patch applied (or already idempotent; or artifact absent / state absent).
# @exitcode 1   Internal error (jq merge failed; use --log to inspect).
# @exitcode 2   DISK_MIN_GB hard-halt triggered (caller must remediate before retrying).
#
# Env vars honoured:
#   DISK_MIN_GB         (default 5)   — hard halt threshold in GiB
#   DISK_WARN_GB        (default 8)   — hygiene warn threshold in GiB
#   RUN_INDEX           — override run_index (for callers that know it without reading state.json)
#   STATE_LOCK_TIMEOUT_S (default 5)  — max seconds to wait for the merge lock before
#                                       proceeding UNLOCKED + WARN (never a silent no-op)
#   STATE_LOCK_STALE_S  (default 60)  — a lock dir older than this (by mtime) is treated
#                                       as leaked and broken so a crashed writer cannot wedge merges
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
STATE_LOCK_TIMEOUT_S="${STATE_LOCK_TIMEOUT_S:-5}"
STATE_LOCK_STALE_S="${STATE_LOCK_STALE_S:-60}"

# Set by _lock_acquire so the EXIT trap and _lock_release know which dir to remove.
_LOCK_DIR=""
_LOCK_HELD=""

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
# Sets PARSED_STAGE, PARSED_VERDICT, PARSED_SUMMARY and (additive, optional)
# PARSED_WT_PATH / PARSED_WT_BRANCH in the caller's scope.
parse_frontmatter() {
  local art="$1"
  PARSED_STAGE="" PARSED_VERDICT="" PARSED_SUMMARY=""
  PARSED_WT_PATH="" PARSED_WT_BRANCH=""

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
    # Optional worktree record (additive). Value may be a bare or quoted path/branch.
    PARSED_WT_PATH=$(awk -F: '/^[[:space:]]*worktree_path:/ { sub(/^[[:space:]]*worktree_path:[[:space:]]*/,""); gsub(/^"|"$/,""); gsub(/[[:space:]]+$/,""); print; exit }' \
      <<< "$raw")
    PARSED_WT_BRANCH=$(awk -F: '/^[[:space:]]*worktree_branch:/ { sub(/^[[:space:]]*worktree_branch:[[:space:]]*/,""); gsub(/^"|"$/,""); gsub(/[[:space:]]+$/,""); print; exit }' \
      <<< "$raw")
  else
    # yq path: parse individual fields.
    PARSED_STAGE=$(yq eval 'select(documentIndex == 0) | .handoff.stage // ""' "$art" 2> /dev/null || true)
    PARSED_VERDICT=$(yq eval 'select(documentIndex == 0) | .handoff.verdict // "ok"' "$art" 2> /dev/null || true)
    PARSED_SUMMARY=$(yq eval 'select(documentIndex == 0) | .handoff.summary // ""' "$art" 2> /dev/null || true)
    PARSED_WT_PATH=$(yq eval 'select(documentIndex == 0) | .handoff.worktree_path // ""' "$art" 2> /dev/null || true)
    PARSED_WT_BRANCH=$(yq eval 'select(documentIndex == 0) | .handoff.worktree_branch // ""' "$art" 2> /dev/null || true)
    [[ "$PARSED_WT_PATH" == "null" ]] && PARSED_WT_PATH=""
    [[ "$PARSED_WT_BRANCH" == "null" ]] && PARSED_WT_BRANCH=""
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

# ---------- Merge lock (mkdir-spinlock) ----------
# Serializes the read → merge → rename window of atomic_merge() so legal sibling
# overlap (parallel DVN tracks, DC+QA — one writer per stage KEY) cannot drop a
# patch to last-rename-wins.  mkdir is atomic on POSIX; no flock(1) needed (macOS
# lacks it).  Timeout ⇒ proceed UNLOCKED + WARN (never worse than the pre-lock
# lockless path; an exit-0 no-op would let a leaked lock silently swallow merges).
# The hook inherits this by delegating to state-patch.sh (zero hook changes).

# _lock_break_if_stale <lockdir> — break a lock older than STATE_LOCK_STALE_S (by
# dir mtime) so a crashed writer cannot wedge every later merge.
_lock_break_if_stale() {
  local lockdir="$1" mtime now age
  [[ -d "$lockdir" ]] || return 0
  # stat -f %m (BSD/macOS) then -c %Y (GNU); degrade silently if neither parses.
  mtime=$(stat -f %m "$lockdir" 2> /dev/null || stat -c %Y "$lockdir" 2> /dev/null || printf '')
  [[ -z "$mtime" ]] && return 0
  now=$(date +%s 2> /dev/null || printf '')
  [[ -z "$now" ]] && return 0
  age=$((now - mtime))
  if ((age >= STATE_LOCK_STALE_S)); then
    log_msg WARN "lock stale (${age}s ≥ ${STATE_LOCK_STALE_S}s) — breaking $lockdir"
    rmdir "$lockdir" 2> /dev/null || rm -rf "$lockdir" 2> /dev/null || true
  fi
}

# _lock_acquire <statepath> — returns 0 with the lock held, or 1 (proceed unlocked).
_lock_acquire() {
  local state="$1"
  local lockdir="${state}.lock.d"
  local waited=0
  _LOCK_DIR="$lockdir"
  _LOCK_HELD=""
  while :; do
    if mkdir "$lockdir" 2> /dev/null; then
      _LOCK_HELD="1"
      return 0
    fi
    _lock_break_if_stale "$lockdir"
    # Retry immediately after a stale-break before counting against the budget.
    if mkdir "$lockdir" 2> /dev/null; then
      _LOCK_HELD="1"
      return 0
    fi
    if ((waited >= STATE_LOCK_TIMEOUT_S)); then
      log_msg WARN "lock timeout (${waited}s ≥ ${STATE_LOCK_TIMEOUT_S}s) on $lockdir — proceeding UNLOCKED"
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
}

# _lock_release — idempotent; safe to call from the EXIT trap and inline.
_lock_release() {
  [[ -n "${_LOCK_HELD:-}" && -n "${_LOCK_DIR:-}" && -d "$_LOCK_DIR" ]] || return 0
  rmdir "$_LOCK_DIR" 2> /dev/null || rm -rf "$_LOCK_DIR" 2> /dev/null || true
  _LOCK_HELD=""
}

# Release any held lock on process end/failure (added to the existing ERR trap flow).
trap '_lock_release' EXIT

# Atomic state.json merge (read → merge → temp → fsync → rename), serialized by the
# mkdir-spinlock so concurrent sibling writers cannot drop a patch.
#
# B3 state bounds are enforced HERE (the single write chokepoint, AD-7) rather than
# scattered across the 13 stage agents: after the `. * $p` merge, the two unbounded
# arrays are clamped so a long run cannot grow state.json past its ~500-token budget.
#   facts.decisions          → newest 8 (tail, matches the eviction-order rule).
#   facts.dispatched_agents  → 6, launched-survive-first (live agents resume needs are
#                              retained ahead of terminal rows, which are eviction bait).
# Both clamps fire ONLY when the array already exists AND exceeds its bound, so a normal
# small state is byte-identical to the pre-bounds merge (idempotency + no-op paths hold).
atomic_merge() {
  local state="$1" patch="$2"
  local tmp="${state%/*}/.state.json.$$.${RANDOM}.tmp"

  # Acquire the lock around the whole read-merge-rename window (timeout ⇒ unlocked+WARN).
  _lock_acquire "$state" || true

  local rc=0
  if jq --argjson p "$patch" '
      (. * $p)
      | (if ((.facts.decisions? // []) | length) > 8
         then .facts.decisions |= .[-8:] else . end)
      | (if ((.facts.dispatched_agents? // []) | length) > 6
         then .facts.dispatched_agents |=
              (([ .[] | select(.status == "launched") ]
              + [ .[] | select(.status != "launched") ])[0:6])
         else . end)
    ' "$state" > "$tmp" 2>> "$LOG_FILE"; then
    sync "$tmp" 2> /dev/null || sync 2> /dev/null || true
    mv -f "$tmp" "$state"
    rc=0
  else
    rm -f "$tmp" 2> /dev/null || true
    rc=1
  fi

  _lock_release
  return "$rc"
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

  # ---- T8: --prev writes handoffs["PREV→CODE"] from the parsed summary + ref ----
  make_state
  cat > .context/analyzing-0.md << 'EOART'
---
handoff:
  stage: AR
  verdict: ok
  summary: "approach validated; DV split confirmed"
  refs: { plan: planning-0.md#requirements }
---
EOART
  bash "$SELF" --stage AR --prev PL --artifact .context/analyzing-0.md \
    || {
      printf 'T8: state-patch returned non-zero\n' >&2
      exit 1
    }
  if jq -e '(.handoffs["PL→AR"] // "") | test("approach validated") and test("ref:analyzing-0.md")' \
    .context/state.json > /dev/null; then
    printf 'T8: --prev writes handoffs edge from summary+ref: ok\n'
  else
    printf 'T8: --prev handoffs edge: FAIL\n' >&2
    jq '.handoffs' .context/state.json >&2
    exit 1
  fi
  # Absent --prev must NOT synthesize a handoffs edge (byte-stable default path).
  make_state
  bash "$SELF" --stage AR --artifact .context/analyzing-0.md
  if jq -e '(.handoffs | length) == 0' .context/state.json > /dev/null; then
    printf 'T8: absent --prev leaves handoffs untouched: ok\n'
  else
    printf 'T8: absent --prev must not add handoffs: FAIL\n' >&2
    exit 1
  fi

  # ---- T9: B3 bounds — decisions clamp to newest-8, dispatched_agents to 6 ----
  # Seed 10 decisions (d0..d9) + 8 dispatched_agents (mix launched/completed), then
  # patch any stage; atomic_merge must clamp both arrays at the single chokepoint.
  jq -n '
    {version:1, worktask_id:"selftest", plan_file:".context/planning-0.md",
     platform:"all", run_index:0,
     stages:{PL:{status:"completed", verdict:"ok"}},
     facts:{
       files_modified:[], tests_added:[], open_questions:[], verdicts:{PL:"ok"},
       decisions:[ range(0;10) | {id:("d"+(.|tostring)), summary:("dec "+(.|tostring)), ref:"x.md#y"} ],
       dispatched_agents:(
         [ range(0;6) | {stage:"DV", task_id:("t"+(.|tostring)), subagent_type:"a", status:"completed"} ]
         + [ range(6;8) | {stage:"DV", task_id:("t"+(.|tostring)), subagent_type:"a", status:"launched"} ])
     },
     handoffs:{}}' > .context/state.json
  bash "$SELF" --stage DV --artifact .context/development-0.md \
    || {
      printf 'T9: state-patch returned non-zero\n' >&2
      exit 1
    }
  if jq -e '(.facts.decisions | length) == 8 and (.facts.decisions[-1].id == "d9") and (.facts.decisions[0].id == "d2")' \
    .context/state.json > /dev/null; then
    printf 'T9: facts.decisions clamped to newest-8: ok\n'
  else
    printf 'T9: decisions bound: FAIL\n' >&2
    jq '.facts.decisions | map(.id)' .context/state.json >&2
    exit 1
  fi
  if jq -e '(.facts.dispatched_agents | length) == 6 and ([.facts.dispatched_agents[] | select(.status == "launched")] | length) == 2' \
    .context/state.json > /dev/null; then
    printf 'T9: dispatched_agents clamped to 6, launched survive: ok\n'
  else
    printf 'T9: dispatched_agents bound: FAIL\n' >&2
    jq '.facts.dispatched_agents | map({task_id, status})' .context/state.json >&2
    exit 1
  fi

  printf 'self-test: ALL PASS\n'
  exit 0
}

# ---------- Argument parsing ----------
STAGE_ARG=""
ARTIFACT_ARG=""
PREV_ARG=""
STATE_PATH=".context/state.json"
LOG_FILE=".context/logs/state-merge.log"
DISK_CHECK_ROOT=""
VIA_ARG=""

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
    --prev)
      shift
      PREV_ARG="${1:-}"
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
      shift
      # Optional root value: consume the next token only when it is NOT another flag.
      if [[ $# -gt 0 && "${1:-}" != -* ]]; then
        DISK_CHECK_ROOT="$1"
        shift
      else
        DISK_CHECK_ROOT="."
      fi
      ;;
    --via)
      shift
      VIA_ARG="${1:-}"
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

# Validate --via (enum hook|step6_5). An unknown value is a caller bug — surface it.
if [[ -n "$VIA_ARG" && "$VIA_ARG" != "hook" && "$VIA_ARG" != "step6_5" ]]; then
  printf >&2 'invalid --via value: %s (expected hook|step6_5)\n' "$VIA_ARG"
  usage
fi

# Validate --prev (must be a known stage code). Unknown ⇒ caller bug — surface it.
if [[ -n "$PREV_ARG" && -z "$(basename_for_stage "$PREV_ARG")" ]]; then
  printf >&2 'invalid --prev value: %s (expected a stage code: PL AR TL DV DR SR QA DC RE FN ST IR ET)\n' "$PREV_ARG"
  usage
fi

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
# Base stage object; additive keys (completed_via, worktree) are folded in only when
# present so absence stays absence (version:1, no renames, tolerant consumers).
# When --prev is given, ALSO emit handoffs["<PREV>→<CODE>"] from the parsed summary +
# artifact basename (schema: maxLength 300, must contain "ref:"). Absent --prev ⇒ no
# handoffs key ⇒ byte-identical to the pre-flag patch.
ART_BASE=$(basename "$ART")
PATCH=$(jq -cn \
  --arg stage "$PARSED_STAGE" \
  --arg artifact "$ART" \
  --arg verdict "$PARSED_VERDICT" \
  --arg via "$VIA_ARG" \
  --arg wt_path "$PARSED_WT_PATH" \
  --arg wt_branch "$PARSED_WT_BRANCH" \
  --arg prev "$PREV_ARG" \
  --arg summary "$PARSED_SUMMARY" \
  --arg ref "$ART_BASE" \
  '
  ({status: "completed", artifact: $artifact, verdict: $verdict}
    + (if $via != "" then {completed_via: $via} else {} end)
    + (if ($wt_path != "" or $wt_branch != "")
       then {worktree: (
              (if $wt_path   != "" then {path:   $wt_path}   else {} end)
            + (if $wt_branch != "" then {branch: $wt_branch} else {} end))}
       else {} end)
  ) as $stageObj
  | {stages: {($stage): $stageObj}}
  + (if $prev != ""
     then {handoffs: {($prev + "→" + $stage): ((($summary) + " ref:" + $ref) | .[0:300])}}
     else {} end)')

if atomic_merge "$STATE_PATH" "$PATCH"; then
  log_msg INFO "merged stages.${PARSED_STAGE} artifact=${ART} verdict=${PARSED_VERDICT} (summary: ${PARSED_SUMMARY:0:80})"
else
  log_msg ERROR "jq merge failed for stage=${PARSED_STAGE} artifact=${ART}; state.json unchanged"
  exit 1
fi

exit 0

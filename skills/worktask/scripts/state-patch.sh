#!/usr/bin/env bash
# @description state-patch.sh — synchronous Step-6.5 state.json completion patch.
#
#   Resolves the artifact path for a stage, parses its `handoff:` frontmatter,
#   builds the completion patch, and performs an atomic tmp → fsync → rename
#   merge into .context/state.json.  Includes the ENOSPC / DISK_MIN_GB guard
#   (< DISK_MIN_GB halts; < DISK_WARN_GB warns) so callers share one policy.
#
#   This is the SINGLE IMPLEMENTATION of the state-patch logic.  The
#   SubagentStop hook at hooks/state-merge.sh delegates to this script
#   via `bash <path>/state-patch.sh [opts]` — no merge logic lives in the hook
#   itself beyond the delegation call.
#
# @arg --stage <CODE>       Stage code (PL AR TL DV DR SR QA DC RE FN ST IR ET).
#                           Required unless --artifact is given with parseable frontmatter.
# @arg --artifact <path>    Explicit artifact path.  When omitted, resolved from
#                           --stage + run_index from state.json.
# @arg --prev <CODE>        Previous stage code, or USER for the documented USER→PL /
#                           USER→IR origin edges.  When present, ALSO writes
#                           handoffs["<PREV>→<CODE>"] = "<summary> ref:<artifact basename>"
#                           from the parsed frontmatter summary (the ledger edge the 13
#                           stage agents used to hand-roll in inline jq).  ABSENT = ledger
#                           patch only, byte-stable; hook callers
#                           never pass it, so the SubagentStop path is untouched.
#                           USER is predecessor-only: it never resolves an artifact and is
#                           NOT a valid --stage.
# @arg --state <path>       state.json path (default: .context/state.json).
# @arg --log <path>         Append log to this file (default: .context/logs/state-merge.log).
# @arg --disk-check [root]  Run the ENOSPC guard before writing.  Optional filesystem-root
#                           value (defaults to "."); a following token that begins with "-"
#                           is NOT consumed as the root.  When the guard fires (halt), exits 2;
#                           on warn exits 0.
# @arg --via <hook|step6_5> Stamp tasks.<ID>.completed_via with the enforcement
#                           layer that fired.  Omit for agent self-patch (Layer 1);
#                           F3 stamps "f3" via its own patch.  Absence encodes Layer 1.
# @arg --task-id <ID>       Explicit ledger key (e.g. DV1).  When omitted the id is resolved
#                           from the stage code: the open instance of a split stage, else
#                           the highest existing, else <CODE>0.
# @arg --allow-missing-artifact
#                           Suppress the exit-3 assertion and restore the exit-0 no-op for a
#                           caller that knows the artifact is absent.  It does NOT patch:
#                           with no artifact there is no frontmatter to build a patch from,
#                           so NEITHER the stage entry NOR the handoff edge is written.
#                           To record a stage whose artifact does not exist, write
#                           state.json directly (handoff-protocol.md#layer-1-fallback).
# @arg --facts <json>       Union-merge compressed facts into facts.*.  Object keyed by any
#                           subset of decisions | open_questions | files_modified |
#                           tests_added.  COMPOSES with --stage: applied first, in its own
#                           atomic window, so one call patches both the ledger row and the
#                           facts a stage recorded; standalone it exits 0 after the merge.
#                           Union, never replace — identity rule at § Facts union below.
#                           open_questions items must be FULL sweep stubs (string .id, .class
#                           and .ref); a partial one exits 2 with state.json untouched.
#
#   Ledger ops — direct tasks{} writes.  Each short-circuits the artifact path and exits.
#   --task-create is the ONLY op that may introduce a key; the rest reject an unknown ID
#   rather than autovivifying a task nobody seeded.
#
# @arg --task-create  <ID> --metadata <json>  Seed tasks.<ID> as pending; no-op if it exists.
#                                             --metadata is optional (defaults to {}).
# @arg --task-status  <ID> <status>           pending|in_progress|completed|blocked|skipped.
# @arg --task-block   <ID> --on  <ID[,ID...]> Union into blocked_by[].
# @arg --task-unblock <ID> --off <ID[,ID...]> Subtract from blocked_by[].
# @arg --task-meta    <ID> --set <json>       Merge into tasks.<ID>.metadata.
# @arg --task-replay  <ID> [--cascade]        Reset one settled/failed task to pending so the
#                                             stage loop dispatches it again.  Clears
#                                             metadata.retry_count, metadata.error_escalated_to
#                                             and completed_via; artifact, verdict, worktree and
#                                             handoffs survive (the completion merge rewrites
#                                             them together).  Every guard runs BEFORE any
#                                             mutation, so a refusal leaves state.json
#                                             byte-identical.  --cascade also resets the
#                                             transitive dependents reachable through
#                                             blocked_by, skipping FN/RE with a warning.
# @arg --agents-json <path>                   Passed through to stale-check.sh for the replay
#                                             liveness guard.  Test/diagnostic seam only.
#
# @arg --resolve-task-id <CODE>
#                           Print the ledger key a bare stage CODE resolves to and exit.
#                           Read-only: takes no lock and writes nothing.  Sibling scripts
#                           call this instead of re-implementing the preference ladder.
#
# @arg --self-test          Run the built-in self-test and exit.
# @arg -h | --help          Show this header.
#
# @exitcode 0   Patch applied (or already idempotent; or artifact absent / state absent).
# @exitcode 1   Internal error (jq merge failed; use --log to inspect), unsupported ledger
#               version, or a ledger op rejected for an unknown/malformed task id.
# @exitcode 2   DISK_MIN_GB hard-halt triggered (caller must remediate before retrying).
# @exitcode 3   Artifact unresolved on the agent self-patch path (--prev given, --via absent).
#               An agent patching the artifact it just wrote and finding nothing on disk is a
#               real failure; every other unresolved case keeps the exit-0 no-op contract.
# @exitcode 4   Replay refused by a pre-mutation guard (target live/parked, liveness
#               indeterminate, planning incomplete, or a blocked cascade member).
#               state.json is untouched.  Unknown ids stay 1 and malformed ids stay 2.
#
# Note: --task-replay's liveness guard shells out to stale-check.sh, which needs python3.
# The dependency is out-of-process and fail-closed — without it the replay refuses (exit 4)
# rather than proceeding.  Every other op still needs only bash 3.2 + jq.
#
# Env vars honoured:
#   DISK_MIN_GB         (default 5)   — hard halt threshold in GiB
#   DISK_WARN_GB        (default 8)   — hygiene warn threshold in GiB
#   RUN_INDEX           — override run_index (for callers that know it without reading state.json)
#   CONTEXT_DIR         (default .context) — root for the audit log written on the --via hook path
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

# Stage codes whose completion acts outside the ledger (FN commits/pushes/opens a PR, RE
# tags a release), so resetting one invites a second commit or tag for one unit of work.
# Canonical list: skills/shared/stage-codes.md § Side-effect-bearing stages — bash cannot
# read that table, so QA asserts the two agree.
REPLAY_SIDE_EFFECT_STAGES="FN,RE"

# Set by _lock_acquire so the EXIT trap and _lock_release know which dir to remove.
_LOCK_DIR=""
_LOCK_HELD=""

# ---------- Usage ----------
usage() {
  # Stop at the first non-comment line rather than a hardcoded count: the header block ends
  # where the code begins, and a line count silently truncates help text whenever it grows.
  awk '/^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
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

# Stage code → newline-separated fallback basenames, accepted when resolving and NEVER
# emitted. Deliberately a sibling of basename_for_stage() rather than extra arms inside it:
# the seven-way parity guard slices that function's body and must keep seeing exactly one
# canonical name per stage.
alias_basenames_for_stage() {
  case "$1" in
    DR) printf 'review' ;;
    QA) printf 'qa' ;;
    FN) printf 'finalization' ;;
    *) printf '' ;;
  esac
}

# Every basename a stage's artifact may be found under, primary first.
searched_basenames_for_stage() {
  local primary alias_list
  primary=$(basename_for_stage "$1")
  [[ -n "$primary" ]] && printf '%s\n' "$primary"
  alias_list=$(alias_basenames_for_stage "$1")
  [[ -n "$alias_list" ]] && printf '%s\n' "$alias_list"
  return 0
}

# Resolve on-disk artifact for a stage BASENAME.
# Resolution order (per handoff-protocol.md#stage-artifact-map):
#   1. Exact .context/<base>-<RUN_INDEX>.md when RUN_INDEX is known.
#   2. Highest-N numbered artifact (newest run_index).
#   3. Empty (absent) — never yields a literal '*'.
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
  #    The stem must be EXACTLY <base>: the glob alone accepts any trailing -<digits>, so
  #    `qa-notes-3.md` would answer for basename `qa`. Harmless while every basename was a
  #    long canonical word; the short aliases make it reachable.
  newest=$(ls -1 "${ctx}/${base}-"*.md 2> /dev/null \
    | grep -E "/${base}-[0-9]+\.md$" \
    | sed -E 's/.*-([0-9]+)\.md$/\1 &/' \
    | grep -E '^[0-9]+ ' \
    | sort -k1,1 -n \
    | tail -1 \
    | sed -E 's/^[0-9]+ //')
  if [[ -n "$newest" && -f "$newest" ]]; then
    printf '%s' "$newest"
    return 0
  fi

  # 3. No match.
  printf ''
}

# Resolve a stage's artifact across its primary basename and then its aliases, each
# through the full run_index → highest-N ladder. Canonical always wins: an alias is only
# reached once the primary has failed both tiers.
resolve_artifact_for_stage() {
  local stage="$1" ctx="${2:-.context}" base found
  while IFS= read -r base; do
    [[ -z "$base" ]] && continue
    found=$(resolve_artifact "$base" "$ctx")
    if [[ -n "$found" ]]; then
      printf '%s' "$found"
      return 0
    fi
  done <<< "$(searched_basenames_for_stage "$stage")"
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

# Predecessor codes are a SUPERSET of stage codes: USER is the documented origin of the
# USER→PL and USER→IR edges but owns no artifact, so it must never reach basename_for_stage().
is_valid_prev() {
  [[ "$1" == "USER" ]] && return 0
  [[ -n "$(basename_for_stage "$1")" ]]
}

# Ledger keys are numbered ids (DV0, DV1); handoff edges stay bare codes (PL→AR).
# Frontmatter carries only the code, so pick the instance the caller most plausibly means:
# the one actually running, else the next one queued, else one that is parked — lowest N
# within each tier, because a split stage is worked in order.  A `completed` instance is
# never reused and `skipped` is never resurrected: both were settled deliberately.
# Falls back to the highest existing instance, then to <CODE>0 for a never-seeded stage.
# Callers must have already established that $STATE_PATH exists.
resolve_task_id() {
  local code="$1" resolved=""
  if [[ -n "${TASK_ID_ARG:-}" ]]; then
    printf '%s' "$TASK_ID_ARG"
    return 0
  fi
  if command -v jq > /dev/null 2>&1; then
    resolved=$(jq -r --arg c "$code" '
      ( [ (.tasks // {}) | to_entries[]
          | select(.key | test("^" + $c + "[0-9]+$")) ]
        | sort_by(.key | ltrimstr($c) | tonumber) ) as $all
      | ( [ $all[] | select(.value.status == "in_progress") ] | first )
        // ( [ $all[] | select(.value.status == "pending")  ] | first )
        // ( [ $all[] | select(.value.status == "blocked")  ] | first )
        // ( $all | last )
      | if . == null then "" else .key end' \
      "$STATE_PATH" 2> /dev/null || printf '')
  fi
  printf '%s' "${resolved:-${code}0}"
}

# require_task_exists <ID> <op> — abort unless tasks.<ID> is already in the ledger.
# --task-create is the ONLY op allowed to introduce a key.  Every other op assigns through
# .tasks[$id], which jq would happily autovivify: a typo'd id would land a status-only or
# blocked_by-only ghost that carries no metadata yet still answers every downstream
# readiness check — and, for the dependency ops, gates a real stage on a task nobody runs.
require_task_exists() {
  local id="$1" op="$2"
  if [[ ! -f "$STATE_PATH" ]] \
    || ! jq -e --arg id "$id" '(.tasks // {}) | has($id)' "$STATE_PATH" > /dev/null 2>&1; then
    printf >&2 'unknown task id: %s (--task-%s needs an existing task; create it first)\n' "$id" "$op"
    log_msg ERROR "${op} op on unknown tasks.${id}; state.json unchanged"
    exit 1
  fi
}

# ---------- Replay guards ----------
# Every exit-4 line starts `replay refused: <class-token> — ` so callers and tests match the
# token rather than the prose.
replay_refuse() {
  local token="$1" detail="$2"
  printf >&2 'replay refused: %s — %s\n' "$token" "$detail"
  log_msg ERROR "replay refused (${token}) on tasks.${TASK_OP_ID}: ${detail}; state.json unchanged"
  exit 4
}

replay_warn() {
  printf >&2 'replay warning: %s — %s\n' "$1" "$2"
  log_msg WARN "replay warning (${1}) on tasks.${TASK_OP_ID}: ${2}"
}

# Read-only survey of the ledger: cascade closure, per-member prior fields, stale dependents.
# Pure function of the file, so it can run before the lock without racing a mutation it owns.
replay_survey() {
  jq -c --arg id "$1" --arg se "$REPLAY_SIDE_EFFECT_STAGES" \
    --argjson cascade "${REPLAY_CASCADE:-false}" '
    def deps_of($st; $tid):
      [ ($st.tasks // {}) | to_entries[]
        | select((.value.blocked_by // []) | index($tid)) | .key ];
    def is_side_effect($tid; $codes):
      any($codes[]; . as $c | $tid | test("^" + $c + "[0-9]+$"));
    def member_row($st; $tid):
      ($st.tasks[$tid]) as $t
      | { id: $tid,
          prior_status: ($t.status // null),
          prior_retry: ($t.metadata.retry_count // null),
          prior_escalated: ($t.metadata.error_escalated_to // null),
          cleared: [ "retry_count", "error_escalated_to", "completed_via"
                     | . as $k
                     | select(if $k == "completed_via"
                              then ($t | has("completed_via"))
                              else (($t.metadata // {}) | has($k)) end) ] };
    . as $st
    | ($se | split(",")) as $codes
    # blocked_by has no acyclicity enforcement anywhere, so the visited set alone is not
    # allowed to be the only termination proof; the task count bounds the frontier walk.
    | (($st.tasks // {}) | length) as $bound
    | ( if $cascade
        then ( { frontier: [$id], visited: [$id], order: [], n: 0 }
               | until((.frontier | length) == 0 or .n >= $bound;
                   . as $s
                   | ( [ $s.frontier[] | deps_of($st; .) ] | add // [] | unique ) as $next
                   | ( [ $next[] | . as $d | select(($s.visited | index($d)) == null) ]
                       | sort ) as $new
                   | { frontier: $new,
                       visited: ($s.visited + $new),
                       order: ($s.order + $new),
                       n: ($s.n + 1) })
               | .order )
        else [] end ) as $downstream
    | ([$id] + [ $downstream[] | select(is_side_effect(.; $codes) | not) ]) as $reset
    | { root: $id,
        cascade: $cascade,
        plan_status: ($st.tasks.PL0.status // null),
        run_index: ($st.run_index // 0),
        worktask_id: ($st.worktask_id // "unknown"),
        target_side_effect: is_side_effect($id; $codes),
        skipped: [ $downstream[] | select(is_side_effect(.; $codes)) ],
        # Only dependents this write is NOT resetting can be stale.  Naming a member would
        # assert the opposite of what the same atomic apply is about to do to it, and that
        # false claim would land in the durable audit row a later diagnosis reads.
        stale_dependents: ( [ deps_of($st; $id)[] | . as $d
                              | select((($st.tasks[$d].status) // "") == "completed")
                              | select(($reset | index($d)) == null) ] | sort ),
        members: [ $reset[] | member_row($st; .) ] }' \
    "$STATE_PATH"
}

# Liveness comes from stale-check.sh's per-task FINDING, never from its exit code: rc 1
# ("attention") can be about an unrelated task, so mapping rc→verdict would both refuse
# legitimate replays and allow rc-0 shapes it never examined.  Prints the payload, or the
# empty string when the payload cannot be trusted at all.
replay_liveness_payload() {
  local sc out="" rc=0
  sc="$(dirname "$0")/stale-check.sh"
  [[ -f "$sc" ]] || return 1
  if [[ -n "${AGENTS_JSON_ARG:-}" ]]; then
    out=$(bash "$sc" --state "$STATE_PATH" --context "${CONTEXT_DIR:-.context}" --json \
      --agents-json "$AGENTS_JSON_ARG" 2> /dev/null) || rc=$?
  else
    out=$(bash "$sc" --state "$STATE_PATH" --context "${CONTEXT_DIR:-.context}" --json \
      2> /dev/null) || rc=$?
  fi
  # rc 2 is stale-check's usage/unreadable-input error (and the shape a missing python3
  # produces); only 0/1/3 mean it actually classified the ledger.
  case "$rc" in
    0 | 1 | 3) ;;
    *) return 1 ;;
  esac
  jq -e '(.findings | type) == "array" and .liveness == "ok"' <<< "$out" > /dev/null 2>&1 \
    || return 1
  printf '%s' "$out"
}

# One row per reset member, root first then BFS order — and none at all on a refusal.
# That asymmetry is load-bearing: stale-check.sh's budget-halt classifier reads ANY
# result:"error" row as evidence of a real stage failure, so a refusal row would
# mis-diagnose every later look at this worktask.  Best-effort, mirroring --via hook.
replay_audit() {
  local dir="${CONTEXT_DIR:-.context}/logs" ts
  ts=$(date -u +%FT%TZ)
  mkdir -p "$dir" 2> /dev/null || return 0
  jq -c --arg ts "$ts" --arg root "$TASK_OP_ID" --argjson cascade "$REPLAY_CASCADE" '
    (.worktask_id + ":" + (.run_index | tostring)) as $pfx
    | (if $cascade then $pfx + ":" + $root + ":cascade:" + $ts else null end) as $cid
    | .stale_dependents as $stale
    | .skipped as $skipped
    | [ .members[].id ] as $ids
    | .members[]
    | (.id == $root) as $isroot
    | {ts: $ts, actor: "orchestrator", action: "stage_replay", subject: .id,
       result: "ok", task_id: .id,
       metadata: {
         via: "state-patch --task-replay",
         prior_status: .prior_status,
         cleared: .cleared,
         escalation_cap_override: ((.prior_retry // 0) >= 3 or (.prior_escalated != null)),
         prior_retry_count: .prior_retry,
         prior_escalated_to: .prior_escalated,
         liveness: .liveness,
         stale_dependents: (if $isroot then $stale else [] end),
         cascade: $cascade,
         cascade_root: (if $cascade then $root else null end),
         cascade_id: $cid,
         cascade_members: (if ($isroot and $cascade) then $ids else [] end),
         cascade_skipped: (if ($isroot and $cascade) then $skipped else [] end),
         # A replay is intentionally repeatable, so the key carries $ts: unlike the
         # completion row, two legitimate replays must not collapse into one.
         dedupe_key: ($pfx + ":" + .id + ":replay:" + $ts)}}' \
    <<< "$REPLAY_PLAN" >> "$dir/audit.jsonl" 2> /dev/null \
    || log_msg WARN "audit append failed for replay of tasks.${TASK_OP_ID} (reset already applied)"
}

# ENOSPC guard.  Returns 0 (ok/warn), exits 2 (halt).
disk_guard() {
  local root="${1:-.}"
  local avail_gb=""
  # -g is BSD-only; GNU df rejects it and prints nothing, which silently degraded
  # the guard to a no-op on Linux. -Pk is POSIX on both, so convert here instead.
  avail_gb=$(df -Pk "$root" 2> /dev/null | awk 'NR==2 {printf "%d", $4/1048576}') || avail_gb=""

  [[ -z "$avail_gb" ]] && return 0 # df unparseable → degrade silently, never block

  if ((avail_gb < DISK_MIN_GB)); then
    log_msg ERROR "DISK_HALT: only ${avail_gb}GB free (< ${DISK_MIN_GB}GB) on $root"
    # The guard runs on every platform, so the advice names the build-cache class
    # rather than one stack: the reader picks the line that matches their tree.
    printf >&2 'HALT: only %dGB free (< %dGB) on %s.\nReclaim space from this project stack build caches, e.g.\n  node_modules/, .gradle/, target/, build/, __pycache__/, .venv/\n  Apple: swift package clean; rm -rf ~/Library/Developer/Xcode/DerivedData/*\n' \
      "$avail_gb" "$DISK_MIN_GB" "$root"
    exit 2
  elif ((avail_gb < DISK_WARN_GB)); then
    log_msg WARN "DISK_WARN: ${avail_gb}GB free (< ${DISK_WARN_GB}GB) on $root — consider clearing this project stack build caches"
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
  # stat -f%m (BSD/macOS) then -c%Y (GNU). The format MUST stay attached to the
  # flag: separated, GNU reads -f as --file-system, which takes no argument, so
  # the path becomes an operand and stat prints a filesystem block to stdout
  # while exiting non-zero — `||` tests only status, so the fallback's value is
  # appended to that block and $mtime becomes junk rather than empty.
  mtime=$(stat -f%m "$lockdir" 2> /dev/null || stat -c%Y "$lockdir" 2> /dev/null || printf '')
  # Non-numeric means neither probe parsed; treat as "cannot age the lock".
  [[ "$mtime" =~ ^[0-9]+$ ]] || return 0
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

# B3 state bounds are enforced HERE (the single write chokepoint, AD-7) rather than
# scattered across the 13 stage agents: after every mutation the unbounded arrays are
# clamped so a long run cannot grow state.json past its ~500-token budget.
#   facts.decisions          → newest 8 (tail, matches the eviction-order rule).
#   facts.open_questions     → newest 12, resolved-evicted-first. Every stage now writes
#                              its closing sweep here, so the array grows ~13x faster than
#                              it did; resolved items go first because eviction-order rule 2
#                              already drops them and only unresolved ones still have to
#                              reach the FN gate.
#   facts.dispatched_agents  → 6, launched-survive-first (live agents resume needs are
#                              retained ahead of terminal rows, which are eviction bait).
# Every clamp fires ONLY when the array already exists AND exceeds its bound, so a normal
# small state is byte-identical to an unbounded merge (idempotency + no-op paths hold).
_STATE_BOUNDS_FILTER='
      (if ((.facts.decisions? // []) | length) > 8
       then .facts.decisions |= .[-8:] else . end)
    | (if ((.facts.open_questions? // []) | length) > 12
       then .facts.open_questions |=
            (([ .[] | select((.status // "open") != "resolved") ] | .[-12:]) as $keep
             | $keep
               + ([ .[] | select((.status // "open") == "resolved") ]
                  | .[ ((length - (12 - ($keep | length))) | if . < 0 then 0 else . end) : ]))
       else . end)
    | (if ((.facts.dispatched_agents? // []) | length) > 6
       then .facts.dispatched_agents |=
            (([ .[] | select(.status == "launched") ]
            + [ .[] | select(.status != "launched") ])[0:6])
       else . end)'

# open_questions unions through _union_sweep, not _union_keyed: last-writer-wins would let a
# re-emitted stub carrying `status: open` destroy an answer already recorded against that id, and
# since sw-DR0-3 moved sweep answers out of facts.decisions[] that element is the ONLY record of it.
# `open < resolved` is joined monotonically — a later write may raise, never downgrade — the same
# lattice shape this feature already ships for `decision < escalate`. The two fields are guarded
# INDEPENDENTLY: an incoming stub that omits `resolution` inherits the incumbent's even when both
# sides say `resolved`, because dropping the answer body is a downgrade too. Scoped to
# open_questions alone: _union_keyed stays untouched for facts.decisions, whose semantics do not
# change.
#
# Union semantics for the facts.* arrays. Object-merge (`. * $patch`) REPLACES arrays, so
# a downstream stage's patch would silently drop every entry an upstream stage recorded.
# Identity is `.id` for the keyed arrays and the string itself for the scalar ones.
# Keyed survivors move to the TAIL because _STATE_BOUNDS_FILTER keeps `.[-8:]` — appending
# is what makes "newest 8 survive" true after a union; sorting (unique_by) would hand the
# clamp an arbitrary 8. Scalars keep first-seen order: no clamp reads them.
_FACTS_UNION_FILTER='
      def _union_keyed(k):
        reduce .[] as $e ([]; map(select((. | k) != ($e | k))) + [$e]);
      def _union_scalar:
        reduce .[] as $e ([]; if (index($e) != null) then . else . + [$e] end);
      def _sweep_join($prev; $new):
        $new
        + (if (($prev.status // "open") == "resolved") and (($new.status // "open") != "resolved")
           then { status: "resolved" } else {} end)
        + (if ($new.resolution // null) == null and ($prev.resolution // null) != null
           then { resolution: $prev.resolution } else {} end);
      def _union_sweep:
        reduce .[] as $e ([];
          ((map(select(.id == $e.id)) | first) // null) as $prev
          | map(select(.id != $e.id)) + [ _sweep_join($prev; $e) ]);
      .facts = ((.facts // {})
        | (if ($f.decisions // null) != null
           then .decisions = (((.decisions // []) + $f.decisions) | _union_keyed(.id))
           else . end)
        | (if ($f.open_questions // null) != null
           then .open_questions =
                (((.open_questions // []) + $f.open_questions) | _union_sweep)
           else . end)
        | (if ($f.files_modified // null) != null
           then .files_modified = (((.files_modified // []) + $f.files_modified) | _union_scalar)
           else . end)
        | (if ($f.tests_added // null) != null
           then .tests_added = (((.tests_added // []) + $f.tests_added) | _union_scalar)
           else . end))'

# Shape gate for --facts, run BEFORE the lock: a malformed payload is a caller bug, and the
# union filter would otherwise persist an array no downstream reader can parse.
# open_questions is held to the FULL sweep stub (.id, .class, .ref), not just .id: a partial
# item reaches the FN render with no anchor to resolve its options[] from, and the union would
# have already replaced the incumbent object that did carry one. decisions stays id-only.
_FACTS_VALIDATE_FILTER='
      def _allowed: ["decisions","files_modified","open_questions","tests_added"];
      if type != "object" then "must be a JSON object"
      elif (keys | length) == 0 then "object has no keys"
      else
        (keys - _allowed) as $unknown
        | [ to_entries[]
            | select(.key == "decisions")
            | select((.value | type) != "array"
                     or ((.value | map(select((type != "object")
                                              or ((.id | type) != "string")))) | length) > 0)
            | .key ] as $badkeyed
        | [ to_entries[]
            | select(.key == "open_questions")
            | select((.value | type) != "array"
                     or ((.value | map(select((type != "object")
                                              or ((.id | type) != "string")
                                              or ((.class | type) != "string")
                                              or ((.ref | type) != "string")))) | length) > 0)
            | .key ] as $badstub
        | [ to_entries[]
            | select(.key == "files_modified" or .key == "tests_added")
            | select((.value | type) != "array"
                     or ((.value | map(select(type != "string"))) | length) > 0)
            | .key ] as $badscalar
        | if ($unknown | length) > 0
          then "unknown key(s): " + ($unknown | join(", "))
               + " (allowed: " + (_allowed | join(", ")) + ")"
          elif ($badkeyed | length) > 0
          then "bad shape for " + ($badkeyed | join(", "))
               + " (expected an array of objects each with a string .id)"
          elif ($badstub | length) > 0
          then "bad shape for open_questions (expected an array of sweep stubs, each with string .id, .class and .ref)"
          elif ($badscalar | length) > 0
          then "bad shape for " + ($badscalar | join(", "))
               + " (expected an array of strings)"
          else "" end
      end'

# Atomic state.json mutation (read → apply → temp → fsync → rename), serialized by the
# mkdir-spinlock so concurrent sibling writers cannot drop a patch.
#
# atomic_apply <state> <jq-filter> [jq-args...]
#
# The filter is evaluated against the file contents INSIDE the lock. Read-modify-write ops
# (blocked_by union/subtraction) MUST come through here rather than precomputing from an
# unlocked read: a pre-lock read races a sibling writer and silently drops its edges.
atomic_apply() {
  local state="$1" filter="$2"
  shift 2
  local tmp="${state%/*}/.state.json.$$.${RANDOM}.tmp"

  # Acquire the lock around the whole read-apply-rename window (timeout ⇒ unlocked+WARN).
  _lock_acquire "$state" || true

  local rc=0
  if jq "$@" "( ${filter} ) | ${_STATE_BOUNDS_FILTER}" "$state" > "$tmp" 2>> "$LOG_FILE"; then
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

# Merge a precomputed patch object; both entry points share one lock/rename window.
atomic_merge() {
  local state="$1" patch="$2"
  atomic_apply "$state" '. * $p' --argjson p "$patch"
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
{"version":2,"worktask_id":"selftest","plan_file":".context/planning-0.md","platform":"all","run_index":0,"tasks":{"PL0":{"status":"completed","verdict":"ok"}},"facts":{"files_modified":[],"tests_added":[],"decisions":[],"open_questions":[],"verdicts":{"PL":"ok"}},"handoffs":{}}
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
  if jq -e '.tasks.DV0.status == "completed" and .tasks.DV0.verdict == "ok"' \
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
  if jq -e '.tasks.DV0.status == "completed" and (.tasks.DV0.artifact | endswith("development-0.md"))' \
    .context/state.json > /dev/null; then
    printf 'T3: run_index-resolved artifact: ok\n'
  else
    printf 'T3: run_index-resolved artifact: FAIL\n' >&2
    exit 1
  fi

  # ---- T4: highest-N fallback when run_index absent from state.json ----
  cat > .context/state.json << 'EOSTATE'
{"version":2,"worktask_id":"selftest","plan_file":".context/planning-0.md","platform":"all","tasks":{"PL0":{"status":"completed","verdict":"ok"}},"facts":{"verdicts":{"PL":"ok"}},"handoffs":{}}
EOSTATE
  cat > .context/architecture-1.md << 'EOART'
---
handoff:
  stage: AR
  verdict: blocked
  summary: "highest-N artifact"
  refs: { plan: planning-0.md#requirements }
---
EOART
  cat > .context/architecture-0.md << 'EOART'
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
  if jq -e '.tasks.AR0.verdict == "blocked" and (.tasks.AR0.artifact | endswith("architecture-1.md"))' \
    .context/state.json > /dev/null; then
    printf 'T4: highest-N wins when run_index absent: ok\n'
  else
    printf 'T4: highest-N resolution: FAIL\n' >&2
    jq '.tasks.AR0' .context/state.json >&2
    exit 1
  fi

  # ---- T5: absent artifact → no-op, state unchanged ----
  cat > .context/state.json << 'EOSTATE'
{"version":2,"worktask_id":"selftest","plan_file":".context/planning-0.md","platform":"all","tasks":{"PL0":{"status":"completed","verdict":"ok"}},"facts":{"verdicts":{"PL":"ok"}},"handoffs":{}}
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
  if jq -e '.tasks.QA0.status == "completed"' .context/state.json > /dev/null; then
    printf 'T6: disk-guard degrade on unparseable df → patch applied: ok\n'
  else
    printf 'T6: disk-guard degrade: FAIL\n' >&2
    exit 1
  fi

  # ---- T8: --prev writes handoffs["PREV→CODE"] from the parsed summary + ref ----
  make_state
  cat > .context/architecture-0.md << 'EOART'
---
handoff:
  stage: AR
  verdict: ok
  summary: "approach validated; DV split confirmed"
  refs: { plan: planning-0.md#requirements }
---
EOART
  bash "$SELF" --stage AR --prev PL --artifact .context/architecture-0.md \
    || {
      printf 'T8: state-patch returned non-zero\n' >&2
      exit 1
    }
  if jq -e '(.handoffs["PL→AR"] // "") | test("approach validated") and test("ref:architecture-0.md")' \
    .context/state.json > /dev/null; then
    printf 'T8: --prev writes handoffs edge from summary+ref: ok\n'
  else
    printf 'T8: --prev handoffs edge: FAIL\n' >&2
    jq '.handoffs' .context/state.json >&2
    exit 1
  fi
  # Absent --prev must NOT synthesize a handoffs edge (byte-stable default path).
  make_state
  bash "$SELF" --stage AR --artifact .context/architecture-0.md
  if jq -e '(.handoffs | length) == 0' .context/state.json > /dev/null; then
    printf 'T8: absent --prev leaves handoffs untouched: ok\n'
  else
    printf 'T8: absent --prev must not add handoffs: FAIL\n' >&2
    exit 1
  fi

  # ---- T10: remediation re-merge — same verdict, new summary must refresh the handoff edge ----
  make_state
  cat > .context/development-0.md << 'EOART'
---
handoff:
  stage: DV
  verdict: ok
  summary: "first pass, pre-review"
  refs: { dev: development.md#files-changed }
---
EOART
  bash "$SELF" --stage DV --prev AR --artifact .context/development-0.md \
    || {
      printf 'T10: state-patch returned non-zero (round 1)\n' >&2
      exit 1
    }
  cat > .context/development-0.md << 'EOART'
---
handoff:
  stage: DV
  verdict: ok
  summary: "remediated after DR round 1"
  refs: { dev: development.md#files-changed }
---
EOART
  bash "$SELF" --stage DV --prev AR --artifact .context/development-0.md \
    || {
      printf 'T10: state-patch returned non-zero (round 2)\n' >&2
      exit 1
    }
  if jq -e '(.handoffs["AR→DV"] // "") | test("remediated after DR round 1")' \
    .context/state.json > /dev/null; then
    printf 'T10: same-verdict remediation refreshes handoff edge: ok\n'
  else
    printf 'T10: same-verdict remediation left a stale handoff edge: FAIL\n' >&2
    jq '.handoffs' .context/state.json >&2
    exit 1
  fi
  # A third identical run must still be a byte-identical no-op (T2 invariant preserved).
  cp .context/state.json .context/state.before
  bash "$SELF" --stage DV --prev AR --artifact .context/development-0.md
  if cmp -s .context/state.json .context/state.before; then
    printf 'T10: unchanged re-run stays idempotent: ok\n'
  else
    printf 'T10: unchanged re-run must not rewrite state: FAIL\n' >&2
    exit 1
  fi

  # ---- T9: B3 bounds — decisions clamp to newest-8, dispatched_agents to 6 ----
  # Seed 10 decisions (d0..d9) + 8 dispatched_agents (mix launched/completed), then
  # patch any stage; atomic_merge must clamp both arrays at the single chokepoint.
  jq -n '
    {version:2, worktask_id:"selftest", plan_file:".context/planning-0.md",
     platform:"all", run_index:0,
     tasks:{PL0:{status:"completed", verdict:"ok", metadata:{}}},
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

  # ---- T11: alias basename resolves; canonical still wins when both exist ----
  make_state
  rm -f .context/testing-*.md .context/qa-*.md
  cat > .context/qa-0.md << 'EOART'
---
handoff:
  stage: QA
  verdict: go
  summary: "alias-named artifact"
  refs: { dev: development-0.md#files-changed }
---
EOART
  bash "$SELF" --stage QA \
    || {
      printf 'T11: state-patch returned non-zero\n' >&2
      exit 1
    }
  if jq -e '.tasks.QA0.status == "completed" and (.tasks.QA0.artifact | endswith("qa-0.md"))' \
    .context/state.json > /dev/null; then
    printf 'T11: alias basename resolves: ok\n'
  else
    printf 'T11: alias basename resolution: FAIL\n' >&2
    exit 1
  fi
  make_state
  cat > .context/testing-0.md << 'EOART'
---
handoff:
  stage: QA
  verdict: go
  summary: "canonical artifact"
  refs: { dev: development-0.md#files-changed }
---
EOART
  bash "$SELF" --stage QA
  if jq -e '(.tasks.QA0.artifact | endswith("testing-0.md"))' .context/state.json > /dev/null; then
    printf 'T11: canonical preferred over alias: ok\n'
  else
    printf 'T11: canonical must outrank alias: FAIL\n' >&2
    exit 1
  fi
  rm -f .context/qa-0.md

  # ---- T12: self-patch (--prev, no --via) with no artifact ⇒ exit 3, state unchanged ----
  make_state
  rm -f .context/retrospective-*.md
  cp .context/state.json .context/state.json.snap3
  set +e
  st12_out=$(bash "$SELF" --stage ST --prev FN 2>&1)
  st12_rc=$?
  set -e
  if [[ "$st12_rc" -eq 3 ]] && printf '%s' "$st12_out" | grep -q 'retrospective-N.md'; then
    printf 'T12: unresolved self-patch exits 3 naming the basenames: ok\n'
  else
    printf 'T12: unresolved self-patch must exit 3 (got %s): FAIL\n' "$st12_rc" >&2
    exit 1
  fi
  if diff -q .context/state.json .context/state.json.snap3 > /dev/null; then
    printf 'T12: exit 3 leaves state untouched: ok\n'
  else
    printf 'T12: exit 3 must not alter state: FAIL\n' >&2
    exit 1
  fi
  # The hook path (--via) keeps the exit-0 no-op contract even with --prev present.
  set +e
  bash "$SELF" --stage ST --prev FN --via hook > /dev/null 2>&1
  st12b_rc=$?
  set -e
  if [[ "$st12b_rc" -eq 0 ]]; then
    printf 'T12: --via keeps the unresolved no-op at exit 0: ok\n'
  else
    printf 'T12: --via must not fail loudly (got %s): FAIL\n' "$st12b_rc" >&2
    exit 1
  fi

  # ---- T13: --prev USER writes the origin edge ----
  make_state
  cat > .context/planning-0.md << 'EOART'
---
handoff:
  stage: PL
  verdict: ok
  summary: "origin edge from the user"
  refs: { plan: planning-0.md#requirements }
---
EOART
  bash "$SELF" --stage PL --prev USER --artifact .context/planning-0.md \
    || {
      printf 'T13: state-patch returned non-zero\n' >&2
      exit 1
    }
  if jq -e '(.handoffs["USER→PL"] // "") | test("origin edge from the user")' \
    .context/state.json > /dev/null; then
    printf 'T13: --prev USER writes the USER→PL edge: ok\n'
  else
    printf 'T13: --prev USER edge: FAIL\n' >&2
    jq '.handoffs' .context/state.json >&2
    exit 1
  fi

  # ---- T14: ledger ops (create / block union / status) ----
  make_state
  bash "$SELF" --task-create DV0 --metadata '{"stage":"DV","agent":"corpflow:developer"}' \
    && bash "$SELF" --task-create DV1 --metadata '{"stage":"DV","agent":"corpflow:developer"}' \
    && bash "$SELF" --task-create DR0 --metadata '{"stage":"DR","agent":"corpflow:technical-lead"}' \
    && bash "$SELF" --task-block DR0 --on DV0,DV1 \
    && bash "$SELF" --task-block DR0 --on DV0 \
    && bash "$SELF" --task-status DV0 in_progress \
    || {
      printf 'T14: ledger op returned non-zero\n' >&2
      exit 1
    }
  if jq -e '(.tasks.DR0.blocked_by == ["DV0","DV1"]) and .tasks.DV0.status == "in_progress"
            and .tasks.DV1.status == "pending"' .context/state.json > /dev/null; then
    printf 'T14: ledger create/status + blocked_by union: ok\n'
  else
    printf 'T14: ledger ops: FAIL\n' >&2
    jq '.tasks' .context/state.json >&2
    exit 1
  fi

  bash "$SELF" --task-create DV0 --metadata '{"clobbered":true}' > /dev/null
  if jq -e '.tasks.DV0.metadata.agent == "corpflow:developer"
            and (.tasks.DV0.metadata | has("clobbered") | not)' \
    .context/state.json > /dev/null; then
    printf 'T14: duplicate --task-create is a no-op: ok\n'
  else
    printf 'T14: duplicate create clobbered metadata: FAIL\n' >&2
    exit 1
  fi

  bash "$SELF" --task-create QA0 \
    || {
      printf 'T14: --task-create without --metadata returned non-zero\n' >&2
      exit 1
    }
  if jq -e '.tasks.QA0.status == "pending" and .tasks.QA0.metadata == {}' \
    .context/state.json > /dev/null; then
    printf 'T14: --task-create without --metadata defaults to {}: ok\n'
  else
    printf 'T14: bare --task-create: FAIL\n' >&2
    jq '.tasks.QA0' .context/state.json >&2
    exit 1
  fi

  bash "$SELF" --task-unblock DR0 --off DV1 \
    || {
      printf 'T14: --task-unblock returned non-zero\n' >&2
      exit 1
    }
  if jq -e '.tasks.DR0.blocked_by == ["DV0"]' .context/state.json > /dev/null; then
    printf 'T14: --task-unblock subtracts the edge: ok\n'
  else
    printf 'T14: unblock subtraction: FAIL\n' >&2
    jq '.tasks.DR0' .context/state.json >&2
    exit 1
  fi

  bash "$SELF" --task-unblock DR0 --off ST0 \
    || {
      printf 'T14: --task-unblock of an absent edge returned non-zero\n' >&2
      exit 1
    }
  if jq -e '.tasks.DR0.blocked_by == ["DV0"]' .context/state.json > /dev/null; then
    printf 'T14: --task-unblock of an absent edge is a no-op: ok\n'
  else
    printf 'T14: unblock no-op: FAIL\n' >&2
    exit 1
  fi

  st14_rc=0
  bash "$SELF" --task-status ZZ0 pending > /dev/null 2>&1 || st14_rc=$?
  if [[ "$st14_rc" != "0" ]]; then
    printf 'T14: --task-status on a malformed id fails loudly: ok\n'
  else
    printf 'T14: malformed id must not be accepted: FAIL\n' >&2
    exit 1
  fi

  # Only --task-create may introduce a key, so every other op must reject an unknown id
  # rather than autovivify a ghost through its .tasks[$id] assignment.  The stderr match
  # pins WHICH guard fired: a plain non-zero exit would also be satisfied by a parse error,
  # which would leave the real behaviour untested.
  cp .context/state.json .context/state.json.snap14
  assert_ghost_rejected() {
    local label="$1"
    shift
    local rc=0 err=""
    err=$(bash "$SELF" "$@" 2>&1 > /dev/null) || rc=$?
    if [[ "$rc" == "0" ]] || [[ "$err" != *"unknown task id"* ]] \
      || ! diff -q .context/state.json .context/state.json.snap14 > /dev/null; then
      printf 'T14: %s on an unknown id must hit the existence guard (rc=%s err=%s): FAIL\n' \
        "$label" "$rc" "$err" >&2
      jq '.tasks | keys' .context/state.json >&2
      exit 1
    fi
  }
  assert_ghost_rejected status --task-status FN0 pending
  assert_ghost_rejected block --task-block FN0 --on DV0
  assert_ghost_rejected unblock --task-unblock FN0 --off DV0
  assert_ghost_rejected meta --task-meta FN0 --set '{}'
  printf 'T14: status/block/unblock/meta on an unknown id all fail, state untouched: ok\n'

  # ---- T15: split-stage id resolution (the case bare stage codes could not express) ----
  # DV0 in_progress + DV1 pending: the running instance outranks the queued one, so a
  # bare --stage DV cannot stamp the higher-numbered track that has not started.
  t15_id=$(bash "$SELF" --resolve-task-id DV)
  if [[ "$t15_id" == "DV0" ]]; then
    printf 'T15: in_progress instance outranks pending: ok\n'
  else
    printf 'T15: in_progress must win (got %s): FAIL\n' "$t15_id" >&2
    jq '.tasks' .context/state.json >&2
    exit 1
  fi

  bash "$SELF" --task-status DV0 completed > /dev/null
  t15_id=$(bash "$SELF" --resolve-task-id DV)
  if [[ "$t15_id" == "DV1" ]]; then
    printf 'T15: settled instance yields to the pending one: ok\n'
  else
    printf 'T15: pending must win once DV0 settles (got %s): FAIL\n' "$t15_id" >&2
    exit 1
  fi
  cat > .context/development-0.md << 'EOSPLIT'
---
handoff:
  stage: DV
  verdict: ok
  summary: "second track"
---
EOSPLIT
  bash "$SELF" --stage DV --via step6_5 \
    || {
      printf 'T15: state-patch returned non-zero\n' >&2
      exit 1
    }
  if jq -e '.tasks.DV1.status == "completed" and .tasks.DV1.verdict == "ok"
            and (.tasks.DV0.artifact // "") == ""' .context/state.json > /dev/null; then
    printf 'T15: --stage resolves to the open split instance: ok\n'
  else
    printf 'T15: split-stage resolution: FAIL\n' >&2
    jq '.tasks' .context/state.json >&2
    exit 1
  fi

  bash "$SELF" --stage DV --task-id DV0 --via step6_5 > /dev/null
  if jq -e '(.tasks.DV0.artifact // "") | endswith("development-0.md")' \
    .context/state.json > /dev/null; then
    printf 'T15: explicit --task-id overrides resolution: ok\n'
  else
    printf 'T15: --task-id override: FAIL\n' >&2
    exit 1
  fi

  # ---- T16: unsupported ledger version halts before any write ----
  cat > .context/state.json << 'EOSTATE'
{"version":1,"worktask_id":"selftest","plan_file":".context/planning-0.md","platform":"all","run_index":0,"tasks":{"PL0":{"status":"completed","verdict":"ok"}},"facts":{},"handoffs":{}}
EOSTATE
  cp .context/state.json .context/state.json.snap16
  st16_rc=0
  bash "$SELF" --task-status PL0 in_progress > /dev/null 2>&1 || st16_rc=$?
  if [[ "$st16_rc" != "0" ]] \
    && diff -q .context/state.json .context/state.json.snap16 > /dev/null; then
    printf 'T16: v1 ledger rejected on the ledger-op path, file untouched: ok\n'
  else
    printf 'T16: ledger-op version guard (rc=%s): FAIL\n' "$st16_rc" >&2
    exit 1
  fi

  st16b_rc=0
  bash "$SELF" --stage DV --artifact .context/development-0.md --via hook > /dev/null 2>&1 \
    || st16b_rc=$?
  if [[ "$st16b_rc" != "0" ]] \
    && diff -q .context/state.json .context/state.json.snap16 > /dev/null; then
    printf 'T16: v1 ledger rejected on the --stage path, file untouched: ok\n'
  else
    printf 'T16: --stage version guard (rc=%s): FAIL\n' "$st16b_rc" >&2
    exit 1
  fi

  # ---- T17: --via hook appends exactly one audit row; other paths stay silent ----
  make_state
  rm -f .context/logs/audit.jsonl
  bash "$SELF" --stage DV --artifact .context/development-0.md --via hook > /dev/null
  if [[ -f .context/logs/audit.jsonl ]] \
    && jq -e 'select(.action == "stage_transition" and .actor == "hook:state-merge")
              | .task_id == "DV0" and .metadata.via == "hook"' \
      .context/logs/audit.jsonl > /dev/null; then
    printf 'T17: hook completion writes its stage_transition row: ok\n'
  else
    printf 'T17: hook audit row missing: FAIL\n' >&2
    cat .context/logs/audit.jsonl >&2 2> /dev/null || true
    exit 1
  fi

  make_state
  rm -f .context/logs/audit.jsonl
  bash "$SELF" --stage DV --artifact .context/development-0.md --via step6_5 > /dev/null
  if [[ ! -s .context/logs/audit.jsonl ]]; then
    printf 'T17: step6_5 completion writes no row (Bash scrape owns it): ok\n'
  else
    printf 'T17: non-hook path must not append: FAIL\n' >&2
    exit 1
  fi

  # ---- T18: --task-replay resets one task, and refuses while its agent is alive ----
  # Liveness is fixture-injected so the self-test needs no live agent and no claude CLI.
  make_state
  rm -f .context/logs/audit.jsonl
  printf '[]\n' > agents-gone.json
  printf '%s\n' '[{"id":"sess-dv0","sessionId":"sess-dv0deadbeef","name":"dv","state":"active"}]' \
    > agents-busy.json
  bash "$SELF" --task-create DV0 \
    --metadata '{"stage":"DV","agent":"corpflow:developer","retry_count":3,"error_escalated_to":"AR"}' \
    > /dev/null
  bash "$SELF" --task-status DV0 in_progress > /dev/null
  # An in_progress task with no dispatch row classifies no-dispatch-record, which the guard
  # (correctly) refuses — absence of a record proves nothing about liveness. Seed one.
  jq '.facts.dispatched_agents = [{stage:"DV", task_id:"DV0",
        subagent_type:"corpflow:developer", agent_id:"sess-dv0", status:"launched"}]' \
    .context/state.json > .context/state.next && mv .context/state.next .context/state.json
  bash "$SELF" --task-replay DV0 --agents-json agents-gone.json 2> /dev/null \
    || {
      printf 'T18: --task-replay returned non-zero\n' >&2
      exit 1
    }
  if jq -e '.tasks.DV0.status == "pending"
            and (.tasks.DV0.metadata | has("retry_count") | not)
            and (.tasks.DV0.metadata | has("error_escalated_to") | not)
            and .tasks.PL0.status == "completed"' .context/state.json > /dev/null; then
    printf 'T18: replay resets the target and leaves PL0 alone: ok\n'
  else
    printf 'T18: replay blast radius: FAIL\n' >&2
    jq '.tasks' .context/state.json >&2
    exit 1
  fi
  if jq -e 'select(.action == "stage_replay")
            | .task_id == "DV0" and .metadata.escalation_cap_override == true' \
    .context/logs/audit.jsonl > /dev/null; then
    printf 'T18: replay audits the cap override on success: ok\n'
  else
    printf 'T18: stage_replay audit row missing: FAIL\n' >&2
    cat .context/logs/audit.jsonl >&2 2> /dev/null || true
    exit 1
  fi

  jq '.tasks.DV0.status = "in_progress"
      | .facts.dispatched_agents = [{stage:"DV", task_id:"DV0",
          subagent_type:"corpflow:developer", agent_id:"sess-dv0", status:"launched"}]' \
    .context/state.json > .context/state.next && mv .context/state.next .context/state.json
  cp .context/state.json .context/state.json.snap18
  st18_rc=0
  bash "$SELF" --task-replay DV0 --agents-json agents-busy.json > /dev/null 2>&1 || st18_rc=$?
  if [[ "$st18_rc" -eq 4 ]] \
    && diff -q .context/state.json .context/state.json.snap18 > /dev/null; then
    printf 'T18: live target refuses with exit 4, state byte-unchanged: ok\n'
  else
    printf 'T18: live-target guard (rc=%s): FAIL\n' "$st18_rc" >&2
    exit 1
  fi

  # ---- T19: a partial sweep stub via --facts is rejected before the lock ----
  # The union REPLACES the incumbent object for that id, so admitting {id} alone would
  # silently drop the class/ref the FN render resolves options[] through.
  make_state
  bash "$SELF" --facts '{"open_questions":[{"id":"sw-PL0-1","class":"decision","ref":"planning-0.md#elicitation-sweep"}]}' \
    > /dev/null || {
      printf 'T19: a full sweep stub was rejected\n' >&2
      exit 1
    }
  cp .context/state.json .context/state.json.snap19
  st19_rc=0
  bash "$SELF" --facts '{"open_questions":[{"id":"sw-PL0-1"}]}' > /dev/null 2>&1 || st19_rc=$?
  if [[ "$st19_rc" -eq 2 ]] \
    && diff -q .context/state.json .context/state.json.snap19 > /dev/null; then
    printf 'T19: partial sweep stub exits 2, state byte-unchanged: ok\n'
  else
    printf 'T19: partial-stub guard (rc=%s): FAIL\n' "$st19_rc" >&2
    exit 1
  fi
  # decisions keeps the id-only contract: the tightening is scoped to open_questions.
  bash "$SELF" --facts '{"decisions":[{"id":"d1","summary":"s","ref":"planning-0.md#stages"}]}' \
    > /dev/null || {
      printf 'T19: decisions payload was rejected: FAIL\n' >&2
      exit 1
    }

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
ALLOW_MISSING_ARTIFACT=""
TASK_ID_ARG=""
TASK_OP=""
TASK_OP_ID=""
TASK_OP_VALUE=""
RESOLVE_CODE_ARG=""
FACTS_ARG=""
REPLAY_CASCADE="false"
AGENTS_JSON_ARG=""

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
    --allow-missing-artifact)
      ALLOW_MISSING_ARTIFACT="1"
      shift
      ;;
    --facts)
      shift
      FACTS_ARG="${1:-}"
      shift
      ;;
    --task-id)
      shift
      TASK_ID_ARG="${1:-}"
      shift
      ;;
    --task-create)
      shift
      TASK_OP="create"
      TASK_OP_ID="${1:-}"
      shift
      ;;
    --task-status)
      shift
      TASK_OP="status"
      TASK_OP_ID="${1:-}"
      shift
      TASK_OP_VALUE="${1:-}"
      shift
      ;;
    --task-block)
      shift
      TASK_OP="block"
      TASK_OP_ID="${1:-}"
      shift
      ;;
    --task-unblock)
      shift
      TASK_OP="unblock"
      TASK_OP_ID="${1:-}"
      shift
      ;;
    --task-meta)
      shift
      TASK_OP="meta"
      TASK_OP_ID="${1:-}"
      shift
      ;;
    --task-replay)
      shift
      TASK_OP="replay"
      TASK_OP_ID="${1:-}"
      shift
      ;;
    --cascade)
      REPLAY_CASCADE="true"
      shift
      ;;
    --agents-json)
      shift
      AGENTS_JSON_ARG="${1:-}"
      shift
      ;;
    --on | --off | --metadata | --set)
      shift
      TASK_OP_VALUE="${1:-}"
      shift
      ;;
    --resolve-task-id)
      shift
      RESOLVE_CODE_ARG="${1:-}"
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

# Validate --prev (must be a known stage code or USER). Unknown ⇒ caller bug — surface it.
if [[ -n "$PREV_ARG" ]] && ! is_valid_prev "$PREV_ARG"; then
  printf >&2 'invalid --prev value: %s (expected a stage code: PL AR TL DV DR SR QA DC RE FN ST IR ET — or USER)\n' "$PREV_ARG"
  usage
fi

# ENOSPC guard (optional — only when caller requests it).
[[ -n "$DISK_CHECK_ROOT" ]] && disk_guard "$DISK_CHECK_ROOT"

# Ledger schema guard. This script is the single writer, so the version check belongs here
# rather than in each caller. An absent .version is a pre-versioning seed and is tolerated;
# an unreadable file is left to the callers below, which already no-op on it.
if [[ -f "$STATE_PATH" ]] && command -v jq > /dev/null 2>&1; then
  if STATE_VERSION=$(jq -r '.version // empty' "$STATE_PATH" 2> /dev/null); then
    if [[ -n "$STATE_VERSION" && "$STATE_VERSION" != "2" ]]; then
      printf >&2 'ledger version %s unsupported (expected 2)\n' "$STATE_VERSION"
      log_msg ERROR "ledger version ${STATE_VERSION} unsupported (expected 2); state.json unchanged"
      exit 1
    fi
  fi
fi

# ---------- Query mode ----------
# Read-only id resolution for sibling scripts that would otherwise re-implement the
# preference ladder in their own jq. No lock: nothing is written.
if [[ -n "$RESOLVE_CODE_ARG" ]]; then
  if [[ -z "$(basename_for_stage "$RESOLVE_CODE_ARG")" ]]; then
    printf >&2 'invalid --resolve-task-id code: %s (expected a stage code: PL AR TL DV DR SR QA DC RE FN ST IR ET)\n' \
      "$RESOLVE_CODE_ARG"
    exit 1
  fi
  if [[ ! -f "$STATE_PATH" ]]; then
    printf >&2 'no state.json at %s — cannot resolve a task id\n' "$STATE_PATH"
    exit 1
  fi
  printf '%s\n' "$(resolve_task_id "$RESOLVE_CODE_ARG")"
  exit 0
fi

# ---------- Ledger ops ----------
# Direct tasks{} writes for the orchestrator loop; they short-circuit the
# artifact/frontmatter path entirely.
#
# Each op yields a jq filter rather than a precomputed patch so that atomic_apply evaluates
# it against the file INSIDE the merge lock — mandatory for the read-modify-write ops.
if [[ -n "$TASK_OP" ]]; then
  if ! [[ "$TASK_OP_ID" =~ ^(PL|AR|TL|DV|DR|SR|QA|DC|RE|FN|ST|IR|ET)[0-9]+$ ]]; then
    printf >&2 'invalid task id: %s (expected <STAGE><N>, e.g. DV0)\n' "$TASK_OP_ID"
    usage
  fi
  command -v jq > /dev/null 2>&1 || {
    log_msg ERROR "ledger op needs jq; state.json unchanged"
    exit 1
  }
  # Both modifiers are parsed globally, so silently accepting them on the other five ops
  # would let `--task-status DV0 pending --cascade` read as a cascade that never happened.
  if [[ "$TASK_OP" != "replay" ]] \
    && { [[ "$REPLAY_CASCADE" == "true" ]] || [[ -n "$AGENTS_JSON_ARG" ]]; }; then
    printf >&2 -- '--cascade / --agents-json apply to --task-replay only (got --task-%s)\n' "$TASK_OP"
    usage
  fi

  TASK_FILTER=""
  TASK_JQ_ARGS=()
  case "$TASK_OP" in
    create)
      # Seeding is idempotent: an existing task keeps the metadata it has accumulated, so a
      # re-run of a seed script cannot roll it back to the seed's view.
      if [[ -f "$STATE_PATH" ]] \
        && jq -e --arg id "$TASK_OP_ID" 'has("tasks") and (.tasks | has($id))' \
          "$STATE_PATH" > /dev/null 2>&1; then
        log_msg INFO "idempotent: tasks.${TASK_OP_ID} already exists"
        exit 0
      fi
      # --metadata is optional; absent ⇒ an empty object, never a parse abort.
      TASK_FILTER='.tasks[$id] = {status: "pending", metadata: ($meta // {})}'
      TASK_JQ_ARGS=(--arg id "$TASK_OP_ID" --argjson meta "${TASK_OP_VALUE:-null}")
      ;;
    status)
      case "$TASK_OP_VALUE" in
        pending | in_progress | completed | blocked | skipped) ;;
        *)
          printf >&2 'invalid status: %s\n' "$TASK_OP_VALUE"
          usage
          ;;
      esac
      require_task_exists "$TASK_OP_ID" status
      TASK_FILTER='.tasks[$id].status = $st'
      TASK_JQ_ARGS=(--arg id "$TASK_OP_ID" --arg st "$TASK_OP_VALUE")
      ;;
    block)
      [[ -n "$TASK_OP_VALUE" ]] || {
        printf >&2 'missing value: --task-block %s requires --on <ID[,ID...]>\n' "$TASK_OP_ID"
        usage
      }
      require_task_exists "$TASK_OP_ID" block
      # Union, not append: re-running a seed must not duplicate an edge.
      TASK_FILTER='.tasks[$id].blocked_by =
        (((.tasks[$id].blocked_by // []) + ($on | split(","))) | unique)'
      TASK_JQ_ARGS=(--arg id "$TASK_OP_ID" --arg on "$TASK_OP_VALUE")
      ;;
    unblock)
      [[ -n "$TASK_OP_VALUE" ]] || {
        printf >&2 'missing value: --task-unblock %s requires --off <ID[,ID...]>\n' "$TASK_OP_ID"
        usage
      }
      require_task_exists "$TASK_OP_ID" unblock
      # Set subtraction mirroring --task-block: dropping an edge that was never there is a no-op.
      TASK_FILTER='.tasks[$id].blocked_by =
        (((.tasks[$id].blocked_by // []) - ($off | split(","))) | unique)'
      TASK_JQ_ARGS=(--arg id "$TASK_OP_ID" --arg off "$TASK_OP_VALUE")
      ;;
    meta)
      require_task_exists "$TASK_OP_ID" meta
      # Recursive merge, so a partial --set updates named keys without dropping the rest.
      TASK_FILTER='.tasks[$id].metadata = ((.tasks[$id].metadata // {}) * ($meta // {}))'
      TASK_JQ_ARGS=(--arg id "$TASK_OP_ID" --argjson meta "${TASK_OP_VALUE:-null}")
      ;;
    replay)
      require_task_exists "$TASK_OP_ID" replay
      REPLAY_SURVEY=$(replay_survey "$TASK_OP_ID") || {
        printf >&2 'replay survey failed on tasks.%s; state.json unchanged\n' "$TASK_OP_ID"
        log_msg ERROR "replay survey failed on tasks.${TASK_OP_ID}; state.json unchanged"
        exit 1
      }

      REPLAY_PLAN_STATUS=$(jq -r '.plan_status // ""' <<< "$REPLAY_SURVEY")
      [[ "$REPLAY_PLAN_STATUS" == "completed" ]] || replay_refuse plan-incomplete \
        "PL0 is ${REPLAY_PLAN_STATUS:-absent}; this is the fresh-run path, use /worktask"

      # One subprocess for the whole cascade: N findings are read from the single payload.
      REPLAY_LIVENESS=$(replay_liveness_payload) || replay_refuse liveness-indeterminate \
        "stale-check.sh returned no usable verdict (absent, failed, or unparseable) — the guard cannot prove the target is not still writing"

      REPLAY_CLASS_MAP=""
      while IFS= read -r _member; do
        [[ -n "$_member" ]] || continue
        _class=$(jq -r --arg id "$_member" \
          '[.findings[]? | select(.task_id == $id)]
           | if length == 0 then "none" else .[0].classification end' <<< "$REPLAY_LIVENESS")
        # Allow-list, not deny-list: a class this script has never heard of — including one
        # resume.md adds later — must refuse rather than fall through as permitted.
        case "$_class" in
          none | gone | budget-halt | dispatch-settled) ;;
          *)
            case "$_class" in
              alive-busy) _token="target-live" _why="${_member} agent is busy" ;;
              alive-parked) _token="target-parked" _why="reattach via SendMessage, see resume.md" ;;
              *) _token="liveness-indeterminate" _why="${_member} classified ${_class}" ;;
            esac
            if [[ "$_member" == "$TASK_OP_ID" ]]; then
              replay_refuse "$_token" "$_why"
            fi
            replay_refuse cascade-member-blocked "${_member}: ${_token}"
            ;;
        esac
        REPLAY_CLASS_MAP="${REPLAY_CLASS_MAP}${_member}=${_class}"$'\n'
      done <<< "$(jq -r '.members[].id' <<< "$REPLAY_SURVEY")"
      # A survey that yielded no ids would run the loop zero times and reach the mutation
      # having checked nothing.  Unreachable while the filter always builds members, which
      # is exactly why it must be asserted rather than assumed.
      [[ -n "$REPLAY_CLASS_MAP" ]] || replay_refuse liveness-indeterminate \
        "the survey produced no member to check"

      REPLAY_PLAN=$(jq -c --arg map "$REPLAY_CLASS_MAP" '
        ($map | split("\n") | map(select(length > 0) | split("=") | {key: .[0], value: .[1]})
         | from_entries) as $cls
        | .members |= map(. + {liveness: ($cls[.id] // "none")})' <<< "$REPLAY_SURVEY")

      if jq -e '(.stale_dependents | length) > 0' <<< "$REPLAY_SURVEY" > /dev/null; then
        replay_warn stale-dependents \
          "already-completed dependents may now be stale (never auto-reset): $(jq -r '.stale_dependents | join(", ")' <<< "$REPLAY_SURVEY")"
      fi
      if jq -e '(.skipped | length) > 0' <<< "$REPLAY_SURVEY" > /dev/null; then
        replay_warn side-effect-skipped \
          "traversed but NOT reset (their completion acted outside the ledger): $(jq -r '.skipped | join(", ")' <<< "$REPLAY_SURVEY")"
      fi
      if jq -e '.target_side_effect' <<< "$REPLAY_SURVEY" > /dev/null; then
        replay_warn side-effect-target \
          "${TASK_OP_ID} commits/tags outside the ledger; re-running it may produce a second commit, PR or tag"
      fi
      REPLAY_RUN_IDX=$(jq -r '.run_index' <<< "$REPLAY_SURVEY")
      if ! jq -e --arg s "PL${REPLAY_RUN_IDX}" \
        'select(.action == "approval_received" and .subject == $s)' \
        "${CONTEXT_DIR:-.context}/logs/audit.jsonl" > /dev/null 2>&1; then
        replay_warn plan-unapproved \
          "no approval_received row for PL${REPLAY_RUN_IDX} — the plan behind this stage was never approved at the gate"
      fi

      # The existence re-assertion lives INSIDE the filter, so a key that vanished
      # between the survey and the lock makes jq error, atomic_apply drop the tmp, and the
      # rename never happen — the multi-member write stays genuinely all-or-nothing.
      TASK_FILTER='
        def blast:
            .status = "pending"
          | del(.completed_via)
          | (if (.metadata | type) == "object"
             then .metadata |= (del(.retry_count) | del(.error_escalated_to))
             else . end);
        . as $st
        | [ $members[] | . as $m | select((($st.tasks // {}) | has($m)) | not) ] as $missing
        | if ($missing | length) > 0
          then error("replay member(s) absent under the lock: " + ($missing | join(",")))
          else reduce ($members[]) as $m (.; .tasks[$m] |= blast) end'
      TASK_JQ_ARGS=(--argjson members "$(jq -c '[.members[].id]' <<< "$REPLAY_PLAN")")
      ;;
  esac

  if atomic_apply "$STATE_PATH" "$TASK_FILTER" "${TASK_JQ_ARGS[@]}"; then
    log_msg INFO "ledger ${TASK_OP}: tasks.${TASK_OP_ID} ${TASK_OP_VALUE}"
    if [[ "$TASK_OP" == "replay" ]]; then
      replay_audit
    fi
    exit 0
  fi
  printf >&2 'ledger %s failed on tasks.%s; state.json unchanged (see %s)\n' \
    "$TASK_OP" "$TASK_OP_ID" "$LOG_FILE"
  log_msg ERROR "jq apply failed for ledger ${TASK_OP} on tasks.${TASK_OP_ID}; state.json unchanged"
  exit 1
fi

# ---------- Facts union ----------
# The compressed-fact channel's write path: facts.* is what stage-contracts.md tells every
# downstream stage to read first, and until this op it had no scripted writer at all.
# Runs before the ledger patch so a stage's facts land even when the ledger row is already
# current and the completion merge below short-circuits as idempotent.
if [[ -n "$FACTS_ARG" ]]; then
  command -v jq > /dev/null 2>&1 || {
    printf >&2 '--facts needs jq; state.json unchanged\n'
    log_msg ERROR "--facts needs jq; state.json unchanged"
    exit 1
  }

  FACTS_ERR=$(printf '%s' "$FACTS_ARG" | jq -r "$_FACTS_VALIDATE_FILTER" 2> /dev/null) \
    || FACTS_ERR="not valid JSON"
  if [[ -n "$FACTS_ERR" ]]; then
    printf >&2 'invalid --facts: %s\n' "$FACTS_ERR"
    log_msg ERROR "invalid --facts (${FACTS_ERR}); state.json unchanged"
    usage
  fi

  if [[ ! -f "$STATE_PATH" ]]; then
    log_msg INFO "state.json absent — --facts is a no-op"
  elif atomic_apply "$STATE_PATH" "$_FACTS_UNION_FILTER" --argjson f "$FACTS_ARG"; then
    log_msg INFO "facts union: $(printf '%s' "$FACTS_ARG" | jq -r 'keys | join(",")')"
  else
    printf >&2 'facts union failed; state.json unchanged (see %s)\n' "$LOG_FILE"
    log_msg ERROR "jq apply failed for --facts; state.json unchanged"
    exit 1
  fi

  # Standalone --facts is done here; with --stage/--artifact it falls through to the
  # completion merge, which takes its own lock.
  if [[ -z "$STAGE_ARG" && -z "$ARTIFACT_ARG" ]]; then
    exit 0
  fi
fi

# ---------- Resolve artifact ----------
ART="$ARTIFACT_ARG"

if [[ -z "$ART" && -n "$STAGE_ARG" ]]; then
  # Pull run_index from state.json when available.
  if [[ -f "$STATE_PATH" ]] && command -v jq > /dev/null 2>&1; then
    RUN_INDEX=$(jq -r '.run_index // empty' "$STATE_PATH" 2> /dev/null || printf '')
  fi

  ART=$(resolve_artifact_for_stage "$STAGE_ARG")
fi

if [[ -z "$ART" || ! -f "$ART" ]]; then
  log_msg WARN "no artifact resolved (stage=${STAGE_ARG:-} artifact=${ARTIFACT_ARG:-}) — no-op"
  # `--prev` present with `--via` absent is the documented signature of a Layer-1 agent
  # self-patch (handoff-protocol.md:837,846), i.e. a stage patching the artifact it just
  # wrote. Finding nothing there is a real failure, so it is the one unresolved case that
  # must not exit 0. Hook and Step-6.5 callers pass --via and keep the no-op contract.
  if [[ -n "$PREV_ARG" && -z "$VIA_ARG" && -z "$ALLOW_MISSING_ARTIFACT" ]]; then
    _searched=""
    if [[ -n "$STAGE_ARG" ]]; then
      _searched=$(searched_basenames_for_stage "$STAGE_ARG" | sed 's/$/-N.md/' | tr '\n' ' ')
    fi
    [[ -n "$ARTIFACT_ARG" ]] && _searched="${_searched}${ARTIFACT_ARG} "
    printf >&2 'ERROR: self-patch for stage %s found no artifact.\n  searched (in .context/): %s\n  Write the artifact, then re-run. If you cannot, write state.json directly (handoff-protocol.md#layer-1-fallback);\n  --allow-missing-artifact only silences this error and still patches NOTHING.\n' \
      "${STAGE_ARG:-<unset>}" "${_searched:-<none>}"
    log_msg ERROR "self-patch unresolved (stage=${STAGE_ARG:-} prev=${PREV_ARG}) — exit 3"
    exit 3
  fi
  exit 0
fi

if [[ ! -f "$STATE_PATH" ]]; then
  log_msg INFO "state.json absent — nothing to merge (artifact=$ART)"
  exit 0
fi

# ---------- Parse frontmatter ----------
parse_frontmatter "$ART"

if [[ -z "$PARSED_STAGE" ]]; then
  log_msg WARN "could not extract stage from $ART; aborting merge silently"
  exit 0
fi

# ---------- Resolve the ledger key ----------
TASK_ID=$(resolve_task_id "$PARSED_STAGE")

# ---------- Idempotency check ----------
# One @tsv read for all three fields: this runs on every hook-driven stage completion, so
# each extra jq spawn is paid per stage per run. Artifact paths never contain a tab.
CURRENT_STATUS="" CURRENT_VERDICT="" CURRENT_ARTIFACT=""
if command -v jq > /dev/null 2>&1; then
  IDEM_TSV=$(jq -r --arg s "$TASK_ID" \
    '[.tasks[$s].status // "", .tasks[$s].verdict // "", .tasks[$s].artifact // ""] | @tsv' \
    "$STATE_PATH" 2> /dev/null || printf '\t\t')
  IFS=$'\t' read -r CURRENT_STATUS CURRENT_VERDICT CURRENT_ARTIFACT <<< "$IDEM_TSV" || true
fi

# A remediation loop re-completes a stage at the same verdict with a fresh artifact and summary,
# so skip only when the patch would change nothing — verdict, artifact, and handoff edge all current.
if [[ "$CURRENT_STATUS" == "completed" && "$CURRENT_VERDICT" == "$PARSED_VERDICT" ]]; then
  PATCH_IS_NOOP=1
  if [[ "$CURRENT_ARTIFACT" != "$ART" ]]; then
    PATCH_IS_NOOP=0
  fi
  if [[ -n "$PREV_ARG" ]] && command -v jq > /dev/null 2>&1; then
    # Mirrors the handoff value built below; keep the two in step.
    WOULD_HANDOFF=$(jq -rn --arg summary "$PARSED_SUMMARY" --arg ref "$(basename "$ART")" \
      '(($summary) + " ref:" + $ref) | .[0:300]' 2> /dev/null || printf '')
    CURRENT_HANDOFF=$(jq -r --arg k "${PREV_ARG}→${PARSED_STAGE}" '.handoffs[$k] // ""' \
      "$STATE_PATH" 2> /dev/null || printf '')
    if [[ "$CURRENT_HANDOFF" != "$WOULD_HANDOFF" ]]; then
      PATCH_IS_NOOP=0
    fi
  fi

  if [[ "$PATCH_IS_NOOP" == "1" ]]; then
    log_msg INFO "idempotent: tasks.${TASK_ID} already completed verdict=${PARSED_VERDICT}"
    exit 0
  fi
  log_msg INFO \
    "re-merge: tasks.${TASK_ID} verdict unchanged (${PARSED_VERDICT}) but artifact/handoff differ"
fi

# ---------- Build patch + atomic write ----------
# Additive keys (completed_via, worktree) fold in only when present, so absence stays
# absence. --prev additionally emits handoffs["<PREV>→<CODE>"] (maxLength 300, must
# contain "ref:"); absent --prev ⇒ no handoffs key at all.
ART_BASE=$(basename "$ART")
PATCH=$(jq -cn \
  --arg stage "$PARSED_STAGE" \
  --arg taskid "$TASK_ID" \
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
  | {tasks: {($taskid): $stageObj}}
  + (if $prev != ""
     then {handoffs: {($prev + "→" + $stage): ((($summary) + " ref:" + $ref) | .[0:300])}}
     else {} end)')

if atomic_merge "$STATE_PATH" "$PATCH"; then
  log_msg INFO "merged tasks.${TASK_ID} artifact=${ART} verdict=${PARSED_VERDICT} (summary: ${PARSED_SUMMARY:0:80})"
else
  log_msg ERROR "jq merge failed for task=${TASK_ID} artifact=${ART}; state.json unchanged"
  exit 1
fi

# ---------- Audit (hook path only) ----------
# The SubagentStop hook completes a stage without any Bash tool call, so the tool-use
# scraper that produces every other stage_transition row never sees it — this is the only
# place that transition can be recorded. Restricted to --via hook precisely so the scraped
# paths are not double-counted; dedupe_key lets a reader collapse a replayed hook.
# Best-effort: an unwritable log must never undo a merge that already landed.
if [[ "$VIA_ARG" == "hook" ]]; then
  AUDIT_DIR="${CONTEXT_DIR:-.context}/logs"
  if mkdir -p "$AUDIT_DIR" 2> /dev/null; then
    AUDIT_WT_ID=$(jq -r '.worktask_id // "unknown"' "$STATE_PATH" 2> /dev/null || printf 'unknown')
    AUDIT_RUN_IDX=$(jq -r '.run_index // 0' "$STATE_PATH" 2> /dev/null || printf '0')
    jq -cn \
      --arg ts "$(date -u +%FT%TZ)" \
      --arg subject "$TASK_ID" \
      --arg verdict "$PARSED_VERDICT" \
      --arg dedupe "${AUDIT_WT_ID}:${AUDIT_RUN_IDX}:${TASK_ID}:completed" \
      '{ts: $ts, actor: "hook:state-merge", action: "stage_transition", subject: $subject,
         result: "ok", task_id: $subject,
         metadata: {verdict: $verdict, via: "hook", dedupe_key: $dedupe}}' \
      >> "${AUDIT_DIR}/audit.jsonl" 2> /dev/null \
      || log_msg WARN "audit append failed for tasks.${TASK_ID} (merge already applied)"
  fi
fi

exit 0

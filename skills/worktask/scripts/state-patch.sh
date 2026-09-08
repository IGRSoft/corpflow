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
#                           handoffs["<PREV>→<TASK_ID>"] = "<summary> ref:<artifact basename>"
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
#                           from the stage code: the instance whose recorded (else planned)
#                           artifact matches --artifact, else the open instance of a split
#                           stage, else the highest existing, else <CODE>0.  Two open
#                           instances of one stage with nothing to disambiguate them exit 4
#                           before any write.
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
#                           and .ref, boolean .blocks_next_stage); a partial one exits 2 with
#                           state.json untouched.
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
# @arg --ledger-meta  --set <json>            Merge into the ledger's TOP-LEVEL metadata{}.
#                                             The only op that writes outside tasks{} and
#                                             facts{}: base_ref, milestone and the other
#                                             run-wide keys readers resolve from there had
#                                             no scripted writer, so they were hand-edited
#                                             into state.json around this script.
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
# @exitcode 0   Patch applied (or already idempotent; or artifact absent; or state absent on
#               every path EXCEPT --facts; or a --facts payload that was legitimately empty).
# @exitcode 1   Internal error (jq merge failed; use --log to inspect), unsupported ledger
#               version, a ledger op rejected for an unknown/malformed task id, or --facts
#               with no ledger at --state (that write landed nothing and says so).
# @exitcode 2   DISK_MIN_GB hard-halt (caller must remediate before retrying), OR a --facts
#               payload that was refused whole (bad JSON, unknown key, non-array value) with
#               state.json byte-unchanged, OR a --facts payload that PARTIALLY succeeded: the
#               valid items were persisted and the rejected ones are named on stderr. Read
#               stderr to tell them apart — a partial success is the only exit 2 that wrote.
# @exitcode 3   Artifact unresolved on the agent self-patch path (--prev given, --via absent).
#               An agent patching the artifact it just wrote and finding nothing on disk is a
#               real failure; every other unresolved case keeps the exit-0 no-op contract.
# @exitcode 4   Write refused by a pre-mutation guard, state.json untouched: a replay whose
#               target is live/parked, of indeterminate liveness, whose planning is
#               incomplete or whose cascade includes a blocked member; or a stage code that
#               resolves to more than one open instance with nothing to disambiguate it.  Unknown ids stay 1 and malformed ids stay 2.
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

set -Eeuo pipefail
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

# Set when a --facts payload carried no items at all — the sanctioned empty sweep.
FACTS_EMPTY_NOOP=0

# Set when --facts dropped at least one item. A partially accepted payload persists its valid
# remainder AND exits non-zero: every caller branches on exit status, so a silent 0 would hide
# the rejection from all of them.
FACTS_REJECTED=0

usage() {
  # Stop at the first non-comment line rather than a hardcoded count: the header block ends
  # where the code begins, and a line count silently truncates help text whenever it grows.
  awk '/^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
  exit 2
}

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

  # 2. Highest-N numbered artifact. A glob walk rather than `ls | sort -n`: it survives a
  #    filename the shell would word-split, and it costs no forks on a path taken once per
  #    stage completion.
  #
  #    The stem must be EXACTLY <base>: the glob alone accepts any trailing -<digits>, so
  #    `qa-notes-3.md` would answer for basename `qa`. Harmless while every basename was a
  #    long canonical word; the short aliases make it reachable.
  local newest="" newest_n=-1 cand cand_base cand_n
  for cand in "${ctx}/${base}-"*.md; do
    [[ -f "$cand" ]] || continue
    cand_base="${cand##*/}"
    [[ "$cand_base" =~ ^${base}-([0-9]+)\.md$ ]] || continue
    # 10# forces base 10: a `-08` suffix is an octal literal to bash arithmetic and aborts.
    cand_n=$((10#${BASH_REMATCH[1]}))
    if [[ "$cand_n" -gt "$newest_n" ]]; then
      newest_n="$cand_n"
      newest="$cand"
    fi
  done
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

# Bare stage CODE → ledger key. Precedence: explicit --task-id, then the artifact match,
# then the status ladder the jq below spells (lowest N first — a split stage is worked in
# order). `completed` is never reused and `skipped` never resurrected: both were settled
# deliberately. Caller must have already established that $STATE_PATH exists.
#
# The artifact tier reads ARTIFACT_ARG — what the CALLER passed — never the stage-resolved
# $ART, which is a basename guess rather than a caller assertion and is not assigned until
# ~1100 lines below. Within it the RECORDED `.artifact` beats the PLANNED
# `.metadata.artifact`: PL0 seeds the planned name and a split stage routinely writes a
# different file (planned development-0-ledger.md, written development-1.md), so reading
# metadata first slots the patch by a stale guess — the mis-slotting this resolution exists
# to prevent. Metadata stays the fallback: it is the only artifact key a stage that has not
# completed yet carries.
#
# Ambiguity INSIDE the winning tier is fatal rather than arbitrary — two indistinguishable
# `in_progress` instances would land the patch on a coin flip. Ambiguity ACROSS tiers is not:
# the ladder orders those deliberately. Returns 1 before any lock is taken.
resolve_task_id() {
  local code="$1" resolved="" raw base
  if [[ -n "${TASK_ID_ARG:-}" ]]; then
    printf '%s' "$TASK_ID_ARG"
    return 0
  fi
  command -v jq > /dev/null 2>&1 || { printf '%s' "${code}0"; return 0; }

  # Ledger paths are `.context/...`-relative; callers pass absolute or `./`-prefixed ones.
  # Compare normalised full paths OR basenames, and require exactly one hit — a basename
  # collision across two instances is an ambiguity, not a match.
  if [[ -n "${ARTIFACT_ARG:-}" ]]; then
    raw="${ARTIFACT_ARG#./}"
    base="${raw##*/}"
    resolved=$(jq -r --arg c "$code" --arg raw "$raw" --arg base "$base" '
      def norm: (. // "") | tostring | sub("^\\./"; "");
      def hit($p): ($p | norm) as $n
        | $n != "" and ($n == $raw or ($n | split("/") | last) == $base);
      [ (.tasks // {}) | to_entries[]
        | select(.key | test("^" + $c + "[0-9]+$")) ] as $all
      | [ $all[] | select(hit(.value.artifact))          ] as $actual
      | [ $all[] | select(hit(.value.metadata.artifact)) ] as $planned
      | if   ($actual  | length) == 1 then $actual[0].key
        elif ($planned | length) == 1 then $planned[0].key
        else "" end' \
      "$STATE_PATH" 2> /dev/null || printf '')
    if [[ -n "$resolved" ]]; then
      printf '%s' "$resolved"
      return 0
    fi
  fi

  # Ladder tier + its size in one read: the size is what makes the abort arm possible.
  local tier
  tier=$(jq -r --arg c "$code" '
    ( [ (.tasks // {}) | to_entries[]
        | select(.key | test("^" + $c + "[0-9]+$")) ]
      | sort_by(.key | ltrimstr($c) | tonumber) ) as $all
    | ( [ $all[] | select(.value.status == "in_progress") ]
        | select(length > 0) )
      // ( [ $all[] | select(.value.status == "pending") ]
           | select(length > 0) )
      // ( [ $all[] | select(.value.status == "blocked") ]
           | select(length > 0) )
      // ( [ $all | last | select(. != null) ] )
    | (length | tostring) + " " + ([ .[].key ] | join(","))' \
    "$STATE_PATH" 2> /dev/null || printf '')

  local n keys
  n="${tier%% *}"
  keys="${tier#* }"
  if [[ "${n:-0}" =~ ^[0-9]+$ ]] && [[ "$n" -gt 1 ]]; then
    printf >&2 'ERROR: stage %s is ambiguous — %s open instances share status: %s\n  Pass --task-id <ID>, or --artifact <path> matching exactly one instance.\n  state.json is unchanged.\n' \
      "$code" "$n" "$keys"
    log_msg ERROR "ambiguous stage ${code}: candidates ${keys} — refusing to guess"
    return 1
  fi
  [[ "${n:-0}" == "1" ]] && resolved="$keys"
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
  # Refuse a symlinked audit.jsonl: following it makes this append a write primitive
  # against an arbitrary target. A lost row never blocks the write that already landed.
  mkdir -p "$dir" 2> /dev/null || return 0
  [[ ! -L "$dir/audit.jsonl" ]] || return 0
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
#   facts.decisions          → newest 8 PER TASK (tail-newest, matching the eviction rule).
#   facts.open_questions     → newest 4 PER TASK, resolved-evicted-first WITHIN each task.
#                              4 is the contract's own per-stage emission ceiling
#                              (stage-contracts.md § Ledger bounds), so the transport bound
#                              and the emission bound are the same number and a conforming
#                              writer never spills.
#   facts.dispatched_agents  → 6, launched-survive-first. Not a per-writer field, so it
#                              keeps its global bound.
#
# The partition key is the FULL TASK ID (`DV1`), never the bare stage code: the writer is
# the task, and a four-way DV split is four independent writers who must not be able to
# evict one another. Questions carry that id in their own `sw-<TASK_ID>-<n>` id; decisions
# carry it in the `.stage` _FACTS_UNION_FILTER stamps from the writer's identity. An item
# with neither falls into the reserved "_" bucket, which keeps a pre-partition ledger in one
# shared bucket rather than scattering it across confident mis-attributions.
#
# `.stage` on a QUESTION keeps its bare-code meaning for the FN gate's grouping; that is a
# different job from partitioning, which is why the question's partition key is derived
# from the id (index retained) instead of read from `.stage`.
#
# Resolved-evicted-first is evaluated INSIDE each bucket. A global resolved-first pass with
# a per-bucket tail would let one task's resolved items protect another's — the cross-task
# coupling this partition exists to remove.
#
# Each clamp fires ONLY when some bucket exceeds its bound, and survivors keep their
# original positions, so a state inside the bounds is byte-identical to an unbounded merge
# (idempotency + no-op paths hold).
#
# The global ceiling is retired deliberately: worst-case size now scales with the task
# count. The backstop is validate_state's advisory token-budget warning plus the spill
# files — a loud oversized ledger beats a silently lost decision.
_STATE_BOUNDS_FILTER='
      def _task_of_decision: (.stage // "_");
      def _task_of_question:
        (([ (.id // "") | scan("^sw-([A-Za-z]+[0-9]*)-") ] | first | first)
         // (.stage // "_"));
      def _bucket_overflow(keyf; $n):
        (length > $n) and (((group_by(keyf) | map(length) | max) // 0) > $n);
      def _keep_newest_per(keyf; $n):
        . as $arr
        | [ range(0; ($arr | length)) | {i: ., k: ($arr[.] | keyf)} ]
        | group_by(.k) | map(.[-$n:]) | add | map(.i) | sort
        | [ $arr[.[]] ];
      def _keep_newest_unresolved_first(keyf; $n):
        . as $arr
        | [ range(0; ($arr | length))
            | {i: ., k: ($arr[.] | keyf),
               r: ((($arr[.].status) // "open") == "resolved")} ]
        | group_by(.k)
        | map(([ .[] | select(.r | not) ] | .[-$n:]) as $keep
              | $keep
                + ([ .[] | select(.r) ]
                   | .[ ((length - ($n - ($keep | length))) | if . < 0 then 0 else . end) : ]))
        | add | map(.i) | sort
        | [ $arr[.[]] ];
      (if ((.facts.decisions? // []) | _bucket_overflow(_task_of_decision; 8))
       then .facts.decisions |= _keep_newest_per(_task_of_decision; 8) else . end)
    | (if ((.facts.open_questions? // []) | _bucket_overflow(_task_of_question; 4))
       then .facts.open_questions |= _keep_newest_unresolved_first(_task_of_question; 4)
       else . end)
    | (if ((.facts.dispatched_agents? // []) | length) > 6
       then .facts.dispatched_agents |=
            (([ .[] | select(.status == "launched") ]
            + [ .[] | select(.status != "launched") ])[0:6])
       else . end)'

# `stage` and `status` are defaulted, never left null, on incumbents as well as incoming
# items: the FN gate groups unresolved items by stage and reads a missing status as
# unanswered, so a null in either renders an item nobody can attribute or act on. `stage`
# comes from the item's own id — `sw-<TASK_ID>-<n>` is the mandated shape, so the id IS the
# slot — falling back to the writing stage's code for a legacy id that predates it.
#
# open_questions unions through _union_sweep, not _union_keyed: last-writer-wins would let a
# re-emitted stub carrying `status: open` destroy an answer recorded against that id, and the
# element is the ONLY record of a sweep answer. `open < resolved` joins monotonically — a
# later write may raise, never downgrade — and the fields are guarded INDEPENDENTLY, because
# dropping the answer body is a downgrade too. `blocks_next_stage` is sticky only when the
# stub re-emits WITHOUT the key, so a rework round that drops it cannot demote a
# boundary-blocking item; an explicit `false` is the author speaking and CLEARS it. `has`,
# never truthiness, tells those apart — conflating them made `true` unclearable. Legacy
# payloads only: `--facts` requires the key. facts.decisions keeps _union_keyed.
#
# Object-merge (`. * $patch`) REPLACES arrays, so without this a downstream patch would drop
# every entry an upstream stage recorded. Identity is `.id`, or the string itself for the
# scalar arrays. Keyed survivors move to the TAIL because _STATE_BOUNDS_FILTER keeps the
# newest 8 of each task's bucket: appending is what makes "newest survives" true, where
# unique_by would hand the clamp an arbitrary 8. Scalars keep first-seen order — no clamp
# reads them.
#
# Decisions carry no id convention, so their partition key is stamped here: `.stage` is
# defaulted from the WRITER's own task id on the INCOMING array only, before concatenation.
# Defaulting the union would re-stamp every incumbent with the current writer and
# re-attribute PL's `pd1` to whoever writes next; incumbents without a stage stay in the
# reserved "_" bucket. An explicit `.stage` from the author always wins.
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
           then { resolution: $prev.resolution } else {} end)
        + (if ($prev.blocks_next_stage // false) == true and (($new | has("blocks_next_stage")) | not)
           then { blocks_next_stage: true } else {} end);
      def _sweep_defaults:
        # $ARGS.named, not a bare $sweep_stage: a hard reference makes the whole
        # filter fail to COMPILE for any caller that does not pass --arg, which
        # every test extracting this text is.
        ( ([ (.id // "") | scan("^sw-([A-Za-z]+)[0-9]*-") ] | first | first)
          // (($ARGS.named.sweep_stage // "") | if . == "" then null else . end) ) as $slot
        | . + { status: (.status // "open") }
            + (if (.stage // null) == null and $slot != null
               then { stage: $slot } else {} end);
      def _dec_defaults:
        (($ARGS.named.decision_task // "") | if . == "" then null else . end) as $tid
        | . + (if (.stage // null) == null and $tid != null
               then { stage: $tid } else {} end);
      def _union_sweep:
        reduce (.[] | _sweep_defaults) as $e ([];
          ((map(select(.id == $e.id)) | first) // null) as $prev
          | map(select(.id != $e.id)) + [ _sweep_join($prev; $e) ]);
      .facts = ((.facts // {})
        | (if ($f.decisions // null) != null
           then .decisions =
                (((.decisions // []) + [ $f.decisions[] | _dec_defaults ]) | _union_keyed(.id))
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

# Per-item gate for --facts. Returns {fatal, clean, rejects[]}: `fatal` is a whole-payload
# refusal, `clean` carries only the items that passed, `rejects` names each dropped item and
# why. One bad class value used to discard the entire write — decisions, changed files and
# every valid sweep stub in the same object — which is how a stage lost work it had done.
#
# Structural problems stay whole-payload: a non-object, an empty object, an unknown key, or a
# key whose value is not an array. In those cases the caller is writing to a slot that does
# not exist or in a shape nothing can be salvaged from, so no part of it can be trusted to
# land where it was meant to. Everything item-shaped is per-item.
#
# Predicates arrive as jq arguments (never spliced into the program text) for the same reason
# the shape gate did it: a spliced regex would make the program caller-controlled.
_FACTS_PARTITION_FILTER='
      def _allowed: ["decisions","files_modified","open_questions","tests_added"];
      def _label: if (type == "object") and ((.id | type) == "string")
                  then .id else (tojson[0:40]) end;
      def _oq_bad:
        if type != "object" then "not an object"
        elif (.id | type) != "string" then "missing string .id"
        elif (.class | type) != "string" then "missing string .class"
        elif (.ref | type) != "string" then "missing string .ref"
        elif (.blocks_next_stage | type) != "boolean" then "missing boolean .blocks_next_stage"
        elif ((.id | test($idre)) | not) then "id is not sw-<TASK_ID>-<n>"
        elif ((.class as $c | $classes | index($c)) == null)
          then "class is not " + ($classes | join("|"))
        elif ((.ref | test($refre)) | not)
          then "ref is not an optional <artifact>.md path plus one non-empty #anchor"
        else "" end;
      def _dec_bad:
        if type != "object" then "not an object"
        elif (.id | type) != "string" then "missing string .id"
        else "" end;
      def _fatal($m): {fatal: $m, clean: {}, rejects: []};
      if type != "object" then _fatal("must be a JSON object")
      elif (keys | length) == 0 then _fatal("object has no keys")
      elif ((keys - _allowed) | length) > 0
        then _fatal("unknown key(s): " + ((keys - _allowed) | join(", "))
                    + " (allowed: " + (_allowed | join(", ")) + ")")
      elif ([ to_entries[] | select((.value | type) != "array") | .key ] | length) > 0
        then _fatal("bad shape for "
                    + ([ to_entries[] | select((.value | type) != "array") | .key ] | join(", "))
                    + " (expected an array)")
      else . as $p
        | { fatal: "",
            clean:
              ( (if $p | has("decisions")
                 then {decisions: [ $p.decisions[] | select(_dec_bad == "") ]} else {} end)
              + (if $p | has("open_questions")
                 then {open_questions: [ $p.open_questions[] | select(_oq_bad == "") ]} else {} end)
              + (if $p | has("files_modified")
                 then {files_modified: [ $p.files_modified[] | select(type == "string") ]} else {} end)
              + (if $p | has("tests_added")
                 then {tests_added: [ $p.tests_added[] | select(type == "string") ]} else {} end) ),
            rejects:
              ( [ ($p.decisions // [])[] | select(_dec_bad != "")
                  | {key: "decisions", label: _label, reason: _dec_bad} ]
              + [ ($p.open_questions // [])[] | select(_oq_bad != "")
                  | {key: "open_questions", label: _label, reason: _oq_bad} ]
              + [ ($p.files_modified // [])[] | select(type != "string")
                  | {key: "files_modified", label: (tojson[0:40]), reason: "not a string"} ]
              + [ ($p.tests_added // [])[] | select(type != "string")
                  | {key: "tests_added", label: (tojson[0:40]), reason: "not a string"} ] ) }
      end'

# Items a bounds clamp evicted are appended to `.context/<file>-<run_index>.jsonl` before
# the rename, so the eviction leaves a record the ledger no longer has room for.  The
# question spill is read by the FN gate, which can still render a dropped question; the
# decision spill has NO reader by design and is a recovery and audit artifact.
#
# ADDITIVE around _STATE_BOUNDS_FILTER, which is deliberately NOT edited: the spill is the
# set difference (pre-clamp − post-clamp) by `.id`, computed by re-evaluating the caller's
# filter without the bounds tail.  The ordering jq is untouched, so it cannot regress, and
# output is byte-identical for any state in which no bucket overflows.
#
# Ordered before the rename on purpose: a crash can then leave a spill line whose eviction
# never committed — a duplicate the union collapses — but never an eviction whose spill line
# is missing, which would be loss.  Append-only, never rewritten, never deduped on write.
# Every failure here is swallowed: a spill that cannot be written must not undo a merge.
#
# _spill_evicted_items <state> <tmp> <merged-json> <field> <file-stem> <annotate-resolved>
_spill_evicted_items() {
  local state="$1" tmp="$2" merged="$3" field="$4" stem="$5" annotate="$6"

  # Trigger on pre > post, never on the clamp's literal bound: hard-coding 12 made the
  # spill die silently the moment the bound moved. An empty post-clamp array cannot have
  # evicted anything, which keeps the common path at one cheap length query.
  local post_len pre_len
  post_len=$(jq -r --arg f "$field" '(.facts[$f]? // []) | length' "$tmp" 2> /dev/null || printf '0')
  [[ "$post_len" -gt 0 ]] || return 0
  pre_len=$(printf '%s' "$merged" | jq -r --arg f "$field" '(.facts[$f]? // []) | length' 2> /dev/null || printf '0')
  [[ "$pre_len" -gt "$post_len" ]] || return 0

  # Attribution, in the order the writer's own identity becomes known: parsed frontmatter,
  # then --stage, then the code behind --task-id (the only identity a --facts-only call has).
  local from_stage
  from_stage="${PARSED_STAGE:-${STAGE_ARG:-${SWEEP_STAGE_FALLBACK:-}}}"
  [[ -n "$from_stage" ]] || from_stage="unknown"

  local run_idx spill_dir spill_path spilled
  run_idx=$(jq -r '.run_index // 0' "$tmp" 2> /dev/null || printf '0')
  spill_dir="${state%/*}"
  [[ "$spill_dir" == "$state" ]] && spill_dir="."
  spill_path="${spill_dir}/${stem}-${run_idx}.jsonl"

  # EVERY eviction spills, resolved ones included, flagged by `was_resolved`. Filtering
  # answered items out destroyed the one field the sweep exists to produce and inverted the
  # incentive: answering a question was what made it disappear without a trace. The flag is
  # sweep-only — a decision has no resolution status to record.
  spilled=$(printf '%s' "$merged" \
    | jq -c --slurpfile post "$tmp" \
           --arg ts "$(date -u +%FT%TZ)" \
           --arg from "$from_stage" \
           --arg f "$field" \
           --argjson annotate "$annotate" '
        ((($post[0].facts[$f]) // []) | map(.id)) as $keep
        | (.facts[$f] // [])
        | map(select(([.id] - $keep) | length > 0))
        | map(. + {spilled_at: $ts, spilled_from_stage: $from}
                + (if $annotate
                   then {was_resolved: ((.status // "open") == "resolved")} else {} end))
        | .[]' 2> /dev/null) || {
    # A failed spill computation used to `return 0`, which read as "nothing was evicted".
    log_msg WARN "${field} spill computation failed; up to $((pre_len - post_len)) evicted item(s) may be unrecorded (merge unaffected)"
    printf >&2 'warn: %s spill computation failed; up to %d evicted item(s) unrecorded\n' \
      "$field" "$((pre_len - post_len))"
    return 0
  }

  [[ -n "$spilled" ]] || return 0
  local spill_n
  spill_n=$(printf '%s' "$spilled" | grep -c '^')
  # The INFO line is CONDITIONAL on the append. Logged unconditionally it contradicted the WARN
  # two lines above and recorded a spill that never reached the file — a write that landed
  # nothing, indistinguishable from one that landed. Stderr as well as the log, matching the
  # computation-failure arm above: log_msg writes only to $LOG_FILE, so a log-only warning is
  # silent at the call site, which is where the loss has to be visible.
  if printf '%s\n' "$spilled" >> "$spill_path" 2> /dev/null; then
    log_msg INFO "spilled ${spill_n} evicted ${field} item(s) to ${spill_path}"
  else
    log_msg WARN "${field} spill append failed for ${spill_path}; ${spill_n} evicted item(s) unrecorded (merge unaffected)"
    printf >&2 'warn: %s spill append to %s failed; %d evicted item(s) unrecorded\n' \
      "$field" "$spill_path" "$spill_n"
  fi
}

# Both rings spill through one seam. The pre-clamp merge is computed ONCE here and handed to
# each ring, so a two-field spill costs one extra jq rather than two.
#
# _spill_evicted <state> <tmp> <filter> [jq-args...]
_spill_evicted() {
  local state="$1" tmp="$2" filter="$3"
  shift 3
  local populated merged
  populated=$(jq -r '((.facts.open_questions? // []) | length) + ((.facts.decisions? // []) | length)' \
    "$tmp" 2> /dev/null || printf '0')
  [[ "$populated" -gt 0 ]] || return 0
  merged=$(jq "$@" "( ${filter} )" "$state" 2> /dev/null) || {
    log_msg WARN "eviction spill: pre-clamp re-evaluation failed; evictions (if any) unrecorded (merge unaffected)"
    return 0
  }
  _spill_evicted_items "$state" "$tmp" "$merged" open_questions open-questions true
  _spill_evicted_items "$state" "$tmp" "$merged" decisions decisions false
}

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
  # `${state%/*}` returns $state unchanged when the path has no directory component,
  # so a bare `--state state.json` derived `state.json/.state.json….tmp` — ENOTDIR,
  # and every ledger op failed with the file untouched. Same guard the spill path
  # below already carries; the two derivations must agree.
  local dir="${state%/*}"
  [ "$dir" = "$state" ] && dir="."
  local tmp="${dir}/.state.json.$$.${RANDOM}.tmp"

  # Acquire the lock around the whole read-apply-rename window (timeout ⇒ unlocked+WARN).
  _lock_acquire "$state" || true

  local rc=0
  if jq "$@" "( ${filter} ) | ${_STATE_BOUNDS_FILTER}" "$state" > "$tmp" 2>> "$LOG_FILE"; then
    _spill_evicted "$state" "$tmp" "$filter" "$@"
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

# A stage completing with sweep ids in its artifact that the ledger does not hold has lost
# them — to a clamp, to a swallowed rejection, or to a --facts call that was never made.
# The loss used to surface a whole boundary later, at the harness's parity arm.
#
# Runs AFTER the merge, against the WRITTEN state. The same invocation routinely carries
# --facts, so a pre-write comparison false-warns on every correct combined call — the exact
# false-positive class this check exists to remove. Warns to the log AND stderr, because
# log_msg writes only to $LOG_FILE and the call site is where the loss has to be visible.
# It NEVER moves the exit code: a warning that did would break every `set -e` caller.
#
# The id shape is schema-pinned, so a grep over the frontmatter slice is enough and this
# script gains no yq dependency.
#
# Compared against ledger ∪ spill, the union check_sweep_ledger and the FN gate read: an id
# the clamp evicted to `open-questions-<run_index>.jsonl` is recorded, not lost. A missing
# or unreadable spill contributes the empty set.
#
# _warn_unledgered_sweep_ids <artifact> <state>
_warn_unledgered_sweep_ids() {
  local artifact="$1" state="$2"
  [[ -f "$artifact" && -f "$state" ]] || return 0
  command -v jq > /dev/null 2>&1 || return 0

  local declared missing spill_dir run_idx spill_path spilled_ids
  declared=$(awk 'NR == 1 && $0 !~ /^---[[:space:]]*$/ { exit }
                  NR > 1 && /^---[[:space:]]*$/ { exit }
                  NR > 1 { print }' "$artifact" 2> /dev/null \
    | grep -oE 'sw-[A-Za-z]+[0-9]*-[0-9]+' | sort -u || true)
  [[ -n "$declared" ]] || return 0

  run_idx=$(jq -r '.run_index // 0' "$state" 2> /dev/null || printf '0')
  spill_dir="${state%/*}"
  [[ "$spill_dir" == "$state" ]] && spill_dir="."
  spill_path="${spill_dir}/open-questions-${run_idx}.jsonl"
  spilled_ids="[]"
  if [[ -f "$spill_path" && ! -L "$spill_path" ]]; then
    spilled_ids=$(jq -c -s 'map(.id? // empty)' "$spill_path" 2> /dev/null || printf '[]')
  fi

  missing=$(printf '%s\n' "$declared" \
    | jq -Rsr --slurpfile st "$state" --argjson spilled "$spilled_ids" '
      (split("\n") | map(select(length > 0))) as $want
      | (((($st[0].facts.open_questions) // []) | map(.id)) + $spilled) as $have
      | ($want - $have) | join(", ")' 2> /dev/null || printf '')
  [[ -n "$missing" ]] || return 0
  log_msg WARN "sweep ids declared by ${artifact} are absent from the ledger: ${missing}"
  printf >&2 'warn: %s declares sweep id(s) the ledger does not hold: %s\n' "$artifact" "$missing"
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
LEDGER_META_OP=""
TASK_OP_ID=""
TASK_OP_VALUE=""
RESOLVE_CODE_ARG=""
FACTS_ARG=""
REPLAY_CASCADE="false"
AGENTS_JSON_ARG=""

while [[ $# -gt 0 ]]; do
  # One line per flag. Every value-taking arm was the same five lines —
  # `shift`, assign `${1:-}`, `shift` — repeated eleven times, which made the
  # two arms that are NOT that shape (--disk-check's optional value and
  # --self-test's guarded source) invisible in the scroll.
  case "$1" in
    --stage) shift; STAGE_ARG="${1:-}"; shift ;;
    --artifact) shift; ARTIFACT_ARG="${1:-}"; shift ;;
    --prev) shift; PREV_ARG="${1:-}"; shift ;;
    --state) shift; STATE_PATH="${1:-}"; shift ;;
    --log) shift; LOG_FILE="${1:-}"; shift ;;
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
    --via) shift; VIA_ARG="${1:-}"; shift ;;
    --allow-missing-artifact) ALLOW_MISSING_ARTIFACT="1"; shift ;;
    --facts) shift; FACTS_ARG="${1:-}"; shift ;;
    --task-id) shift; TASK_ID_ARG="${1:-}"; shift ;;
    --task-create) shift; TASK_OP="create"; TASK_OP_ID="${1:-}"; shift ;;
    --task-status) shift; TASK_OP="status"; TASK_OP_ID="${1:-}"; shift; TASK_OP_VALUE="${1:-}"; shift ;;
    --task-block) shift; TASK_OP="block"; TASK_OP_ID="${1:-}"; shift ;;
    --task-unblock) shift; TASK_OP="unblock"; TASK_OP_ID="${1:-}"; shift ;;
    --task-meta) shift; TASK_OP="meta"; TASK_OP_ID="${1:-}"; shift ;;
    --ledger-meta) shift; LEDGER_META_OP="1" ;;
    --task-replay) shift; TASK_OP="replay"; TASK_OP_ID="${1:-}"; shift ;;
    --cascade) REPLAY_CASCADE="true"; shift ;;
    --agents-json) shift; AGENTS_JSON_ARG="${1:-}"; shift ;;
    --on | --off | --metadata | --set) shift; TASK_OP_VALUE="${1:-}"; shift ;;
    --resolve-task-id) shift; RESOLVE_CODE_ARG="${1:-}"; shift ;;
    --self-test)
      # Sourced HERE, not at the top: the harness is ~1k lines the ledger-write
      # path never runs. `[ -r ]` first, not a bare `.`: sourcing a missing file
      # with the `.` builtin is a special-builtin error that exits the shell
      # immediately, bypassing an `if ! . …` guard entirely.
      SELFTEST_LIB_PATH="$(dirname "$0")/state-patch-selftest.sh"
      if [ -r "$SELFTEST_LIB_PATH" ]; then
        # shellcheck source=state-patch-selftest.sh
        # shellcheck disable=SC1090
        . "$SELFTEST_LIB_PATH"
      else
        printf >&2 'state-patch: self-test harness unreachable at %s — plugin install broken\n' \
          "$SELFTEST_LIB_PATH"
        exit 2
      fi
      run_self_test
      ;;
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
  # Ambiguity is exit 4 here too: --resolve-code is what the orchestrator asks before it
  # patches, so answering with a guess would only move the mis-slot one call later.
  if ! _RESOLVED=$(resolve_task_id "$RESOLVE_CODE_ARG"); then
    exit 4
  fi
  printf '%s\n' "$_RESOLVED"
  exit 0
fi

# ---------- Top-level metadata ----------
# The ledger's metadata{} is run-wide, not per-task: base_ref, milestone, the gate flags.
# resolve_base_ref (branch-lib.sh) reads .metadata.base_ref and nothing else, but until this
# op the writer had only --task-meta, so the key had to be hand-edited into state.json
# beside the single writer that exists to keep hand edits out. An unresolved base_ref falls
# through to origin/HEAD — the repository default branch — which is exactly the wrong-base
# finalization the base-sanity check exists to catch.
#
# Merge, not assign: a partial --set updates the named keys and leaves the rest, matching
# --task-meta. One level deep only (jq `*` is recursive, which is what --task-meta uses and
# what a caller updating one nested flag expects).
if [[ -n "$LEDGER_META_OP" ]]; then
  if [[ -n "$TASK_OP" ]]; then
    printf >&2 -- '--ledger-meta and --task-%s are separate writes; issue them separately\n' "$TASK_OP"
    usage
  fi
  command -v jq > /dev/null 2>&1 || {
    printf >&2 -- '--ledger-meta needs jq; state.json unchanged\n'
    log_msg ERROR "--ledger-meta needs jq; state.json unchanged"
    exit 1
  }
  [[ -n "$TASK_OP_VALUE" ]] || {
    printf >&2 -- 'missing value: --ledger-meta requires --set <json>\n'
    usage
  }
  # An object, not merely valid JSON: `--set '"develop"'` parses, and `. * "develop"` would
  # replace the whole metadata block with a string.
  if ! printf '%s' "$TASK_OP_VALUE" | jq -e 'type == "object"' > /dev/null 2>&1; then
    printf >&2 -- 'invalid --ledger-meta: --set must be a JSON object; state.json unchanged\n'
    log_msg ERROR "invalid --ledger-meta (--set is not a JSON object); state.json unchanged"
    exit 1
  fi
  if [[ ! -f "$STATE_PATH" ]]; then
    printf >&2 -- 'no state.json at %s; --ledger-meta writes into an existing ledger only\n' "$STATE_PATH"
    log_msg ERROR "--ledger-meta: no state.json at ${STATE_PATH}; nothing written"
    exit 1
  fi
  if atomic_apply "$STATE_PATH" '.metadata = ((.metadata // {}) * $meta)' \
    --argjson meta "$TASK_OP_VALUE"; then
    log_msg INFO "ledger meta: metadata merged"
    exit 0
  fi
  printf >&2 -- 'ledger meta failed; state.json unchanged (see %s)\n' "$LOG_FILE"
  log_msg ERROR "jq apply failed for --ledger-meta; state.json unchanged"
  exit 1
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

  # `metadata.effort` is a dispatch parameter the ledger carries, not free text: the Step
  # C.0a resolver bumps it one rung (`skills/shared/stage-contracts.md § Blocking items are
  # resolved, not asked`), and an off-ladder value would surface there as a failed dispatch
  # a stage or more later rather than at the write that introduced it. Checked on the two
  # ops that persist metadata. Absent is fine — the field is optional and older ledgers
  # predate it; present-but-unknown is not.
  if [[ "$TASK_OP" == "create" || "$TASK_OP" == "meta" ]] && [[ -n "$TASK_OP_VALUE" ]]; then
    # `has` + `tostring`, not `//`: the alternative operator reads JSON null and false as
    # absent, and a required field must not be erasable through its own gate.
    _TASK_EFFORT=$(printf '%s' "$TASK_OP_VALUE" \
      | jq -r 'if type == "object" and has("effort") then (.effort | tostring) else empty end' \
        2> /dev/null) \
      || _TASK_EFFORT=""
    if [[ -n "$_TASK_EFFORT" ]]; then
      _EFFORT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/effort-ladder.sh"
      if [ -r "$_EFFORT_LIB" ]; then
        # shellcheck source=/dev/null
        . "$_EFFORT_LIB"
      fi
      # Only the two metadata ops need the ladder, so its absence fails them alone and
      # leaves --task-status/--task-block/--task-replay untouched.
      if [[ -z "${EFFORT_ENUM:-}" ]]; then
        printf >&2 'invalid --task-%s: effort-ladder.sh unreachable at %s; state.json unchanged\n' \
          "$TASK_OP" "$_EFFORT_LIB"
        log_msg ERROR "effort-ladder.sh unreachable; --task-${TASK_OP} refused, state.json unchanged"
        exit 1
      fi
      if ! effort_rank "$_TASK_EFFORT" > /dev/null; then
        printf >&2 'invalid effort: %s (expected one of: %s); state.json unchanged\n' \
          "$_TASK_EFFORT" "$EFFORT_ENUM"
        log_msg ERROR "invalid metadata.effort (${_TASK_EFFORT}); state.json unchanged"
        exit 2
      fi
    fi
  fi

  # R-4.4 — the ONLY two paths that persist a task description. Dispatch-time appends
  # (the orchestrator's test-scope, ban and FN banners) mutate an in-memory copy and are
  # never written back, so capping post-append would strip banners that no ledger holds.
  # Truncate, never reject: a refused --task-create would break PL0 stage creation.
  # 240 chars matches the facts.goal precedent in initialization-patterns.md.
  _DESC_CAP='def _cap_desc:
      if (type == "object") and ((.description? | type) == "string")
         and ((.description | length) > 240)
      then .description = (.description[0:239] + "…") else . end;'

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
      TASK_FILTER="${_DESC_CAP}"'.tasks[$id] = {status: "pending", metadata: (($meta // {}) | _cap_desc)}'
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
      TASK_FILTER="${_DESC_CAP}"'.tasks[$id].metadata = (((.tasks[$id].metadata // {}) * ($meta // {})) | _cap_desc)'
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

  _SWEEP_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sweep-stub-lib.sh"
  if [ -r "$_SWEEP_LIB" ]; then
    # shellcheck source=/dev/null
    . "$_SWEEP_LIB"
  fi
  # --facts is the only op that needs the predicate, so its absence fails this op alone and
  # leaves --stage/--prev/--task-create untouched.
  if [[ -z "${SWEEP_ID_RE:-}" || -z "${SWEEP_CLASS_ENUM:-}" || -z "${SWEEP_REF_RE:-}" ]]; then
    printf >&2 'invalid --facts: sweep-stub-lib.sh unreachable at %s; state.json unchanged\n' "$_SWEEP_LIB"
    log_msg ERROR "sweep-stub-lib.sh unreachable; --facts refused, state.json unchanged"
    usage
  fi
  SWEEP_CLASS_JSON=$(printf '%s' "$SWEEP_CLASS_ENUM" | tr ' ' '\n' | jq -R . | jq -s .)

  FACTS_PART=$(printf '%s' "$FACTS_ARG" \
    | jq -c --arg idre "$SWEEP_ID_RE" --arg refre "$SWEEP_REF_RE" \
            --argjson classes "$SWEEP_CLASS_JSON" "$_FACTS_PARTITION_FILTER" 2> /dev/null) \
    || FACTS_PART=""
  if [[ -z "$FACTS_PART" ]]; then
    printf >&2 'invalid --facts: not valid JSON; state.json unchanged\n'
    log_msg ERROR "invalid --facts (not valid JSON); state.json unchanged"
    exit 2
  fi

  FACTS_FATAL=$(printf '%s' "$FACTS_PART" | jq -r '.fatal')
  if [[ -n "$FACTS_FATAL" ]]; then
    # Plain exit, never usage(): the help block is ~100 lines and scrolls the one line the
    # caller needs off the top of the transcript.
    printf >&2 'invalid --facts: %s; state.json unchanged\n' "$FACTS_FATAL"
    log_msg ERROR "invalid --facts (${FACTS_FATAL}); state.json unchanged"
    exit 2
  fi

  FACTS_REJECT_N=$(printf '%s' "$FACTS_PART" | jq -r '.rejects | length')
  if [[ "$FACTS_REJECT_N" -gt 0 ]]; then
    FACTS_REJECTED=1
    # Built ONCE, then written to each stream. Two independent emissions read as two
    # separate rejections in any caller that merges the streams. Stdout as well as stderr
    # because a caller whose harness swallows stderr otherwise ships a stage one item short,
    # and the artifact/ledger divergence then surfaces a boundary later than its cause.
    FACTS_REJECT_LIST=$(printf '%s' "$FACTS_PART" \
      | jq -r '.rejects[] | "  - " + .key + " " + .label + ": " + .reason')
    FACTS_REJECT_MSG="invalid --facts: ${FACTS_REJECT_N} item(s) rejected, the rest still persist:
${FACTS_REJECT_LIST}"
    printf '%s\n' "$FACTS_REJECT_MSG" >&2
    printf '%s\n' "$FACTS_REJECT_MSG"
    log_msg ERROR "--facts: ${FACTS_REJECT_N} item(s) rejected; valid remainder persisted"
  fi

  FACTS_ARG=$(printf '%s' "$FACTS_PART" | jq -c '.clean')
  FACTS_KEPT=$(printf '%s' "$FACTS_ARG" | jq -r '[ .[] | length ] | add // 0')
  if [[ "$FACTS_KEPT" -eq 0 ]] && [[ "$FACTS_REJECT_N" -gt 0 ]]; then
    # Every item was rejected: nothing to persist, and the caller must see the refusal.
    printf >&2 'invalid --facts: no valid items in the payload; state.json unchanged\n'
    log_msg ERROR "--facts: no valid items; state.json unchanged"
    exit 2
  fi
  # Nothing kept AND nothing rejected means the payload was legitimately EMPTY —
  # `{"open_questions":[]}` is what stage-contracts.md § Closing Elicitation Sweep tells a stage
  # with nothing to ask to emit. Refusing it turned a no-op into a hard stop that also aborted the
  # stage-completion merge the same call was paired with. The union is skipped (it would be a
  # no-op anyway) and execution falls through to that merge.
  if [[ "$FACTS_KEPT" -eq 0 ]]; then
    log_msg INFO "--facts: empty payload, nothing to union (no-op)"
    FACTS_EMPTY_NOOP=1
  fi

  # Fallback slot for a stub whose id predates the `sw-<TASK_ID>-<n>` shape: the stage this
  # invocation is patching, by the same explicit-then-inferred order the id resolution uses.
  SWEEP_STAGE_FALLBACK="${STAGE_ARG:-$(printf '%s' "${TASK_ID_ARG:-}" | sed 's/[0-9]*$//')}"

  # The decisions ring partitions by the FULL task id, which the sweep fallback above
  # deliberately strips. Explicit --task-id wins, then the id the ledger resolves for
  # --stage, then the bare code. Empty means no stamp at all: an unattributable decision
  # belongs in the reserved bucket, never under whoever happens to write next.
  DECISION_TASK_ID="${TASK_ID_ARG:-}"
  if [[ -z "$DECISION_TASK_ID" && -n "$STAGE_ARG" ]]; then
    [[ -f "$STATE_PATH" ]] && DECISION_TASK_ID=$(resolve_task_id "$STAGE_ARG" 2> /dev/null || printf '')
    [[ -n "$DECISION_TASK_ID" ]] || DECISION_TASK_ID="$STAGE_ARG"
  fi

  if [[ "$FACTS_EMPTY_NOOP" -eq 1 ]]; then
    : # no-op: nothing to write, and an absent ledger is not an error for an empty payload
  elif [[ ! -f "$STATE_PATH" ]]; then
    # log_msg writes only to $LOG_FILE, so this used to be an INFO line and exit 0 — a write
    # that landed nothing, indistinguishable at the call site from one that landed.
    printf >&2 'no ledger at %s — --facts landed nothing\n' "$STATE_PATH"
    log_msg ERROR "no ledger at ${STATE_PATH}; --facts landed nothing"
    exit 1
  elif atomic_apply "$STATE_PATH" "$_FACTS_UNION_FILTER" \
    --argjson f "$FACTS_ARG" --arg sweep_stage "$SWEEP_STAGE_FALLBACK" \
    --arg decision_task "$DECISION_TASK_ID"; then
    log_msg INFO "facts union: $(printf '%s' "$FACTS_ARG" | jq -r 'keys | join(",")')"
    # Post-write assertion: keys in the log are not evidence the ids landed. An id that went
    # in and is not there afterwards was evicted by a clamp, which is exactly the silent loss
    # this stage exists to remove. Loud on stderr; the merge itself stands.
    FACTS_LOST=$(jq -r --argjson f "$FACTS_ARG" '
        (([ ($f.decisions // [])[].id ] - [ (.facts.decisions // [])[].id ])
       + ([ ($f.open_questions // [])[].id ] - [ (.facts.open_questions // [])[].id ]))
       | join(", ")' "$STATE_PATH" 2> /dev/null || printf '')
    if [[ -n "$FACTS_LOST" ]]; then
      printf >&2 'warn: --facts wrote but these ids are not in the ledger (clamp eviction): %s\n' "$FACTS_LOST"
      log_msg ERROR "--facts ids absent after write: ${FACTS_LOST}"
    fi
  else
    printf >&2 'facts union failed; state.json unchanged (see %s)\n' "$LOG_FILE"
    log_msg ERROR "jq apply failed for --facts; state.json unchanged"
    exit 1
  fi

  # Standalone --facts is done here; with --stage/--artifact it falls through to the
  # completion merge, which takes its own lock.
  if [[ -z "$STAGE_ARG" && -z "$ARTIFACT_ARG" ]]; then
    exit $((FACTS_REJECTED == 1 ? 2 : 0))
  fi
fi

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
  # Every no-op return on the paired path still carries a --facts rejection out.
  exit $((FACTS_REJECTED == 1 ? 2 : 0))
fi

if [[ ! -f "$STATE_PATH" ]]; then
  log_msg INFO "state.json absent — nothing to merge (artifact=$ART)"
  exit $((FACTS_REJECTED == 1 ? 2 : 0))
fi

parse_frontmatter "$ART"

if [[ -z "$PARSED_STAGE" ]]; then
  log_msg WARN "could not extract stage from $ART; aborting merge silently"
  exit $((FACTS_REJECTED == 1 ? 2 : 0))
fi

if ! TASK_ID=$(resolve_task_id "$PARSED_STAGE"); then
  exit 4
fi

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
    CURRENT_HANDOFF=$(jq -r --arg k "${PREV_ARG}→${TASK_ID}" '.handoffs[$k] // ""' \
      "$STATE_PATH" 2> /dev/null || printf '')
    if [[ "$CURRENT_HANDOFF" != "$WOULD_HANDOFF" ]]; then
      PATCH_IS_NOOP=0
    fi
  fi

  if [[ "$PATCH_IS_NOOP" == "1" ]]; then
    log_msg INFO "idempotent: tasks.${TASK_ID} already completed verdict=${PARSED_VERDICT}"
    exit $((FACTS_REJECTED == 1 ? 2 : 0))
  fi
  log_msg INFO \
    "re-merge: tasks.${TASK_ID} verdict unchanged (${PARSED_VERDICT}) but artifact/handoff differ"
fi

# ---------- Build patch + atomic write ----------
# Additive keys (completed_via, worktree) fold in only when present, so absence stays
# absence.  facts.verdicts[<CODE>] is mirrored here because this is the only writer a
# completed stage passes through: the schema has carried the field since v2 and nothing ever
# filled it, so every consumer reading it saw an empty object.  Keyed by CODE, not task id,
# and deliberately NOT re-keyed alongside the handoff edges: a stage has one verdict, and
# its readers ask whether DV passed, never whether DV2 did.  A split stage's last instance
# to complete owns the entry.  --prev additionally emits handoffs["<PREV>→<TASK_ID>"]
# (maxLength 300, must contain "ref:"); absent --prev ⇒ no handoffs key at all.  The
# destination is the WRITING TASK, so an N-way split writes N edges instead of collapsing to
# one last-writer-wins entry; the source stays a bare code because it answers which stage
# this followed, and only the destination ever collided.
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
  + {facts: {verdicts: {($stage): $verdict}}}
  + (if $prev != ""
     then {handoffs: {($prev + "→" + $taskid): ((($summary) + " ref:" + $ref) | .[0:300])}}
     else {} end)')

if atomic_merge "$STATE_PATH" "$PATCH"; then
  log_msg INFO "merged tasks.${TASK_ID} artifact=${ART} verdict=${PARSED_VERDICT} (summary: ${PARSED_SUMMARY:0:80})"
  _warn_unledgered_sweep_ids "$ART" "$STATE_PATH"
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
  # Refuse a symlinked audit.jsonl: following it makes this append a write primitive
  # against an arbitrary target. A lost row never blocks the write that already landed.
  if mkdir -p "$AUDIT_DIR" 2> /dev/null && [[ ! -L "${AUDIT_DIR}/audit.jsonl" ]]; then
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

exit $((FACTS_REJECTED == 1 ? 2 : 0))

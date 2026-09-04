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
#
# Precedence is explicit id > explicit artifact > the status ladder.  The artifact tier
# reads ARTIFACT_ARG — what the CALLER passed — never the stage-resolved $ART, which is not
# assigned until ~1500 lines below this definition and is a basename guess rather than a
# caller assertion.  A bare `--stage` (hooks/agent-stop.sh passes no artifact) leaves
# ARTIFACT_ARG empty and falls through to the ladder byte-identically.
#
# Within the artifact tier the RECORDED `.artifact` is consulted before the PLANNED
# `.metadata.artifact`: PL0 seeds the metadata name from the plan, and a split stage
# routinely writes a different file than the plan guessed (this run: planned
# development-0-ledger.md, written development-1.md).  Reading metadata first would slot the
# patch by the plan's stale guess instead of the file the caller just named — the very
# mis-slotting this resolution exists to prevent.  Metadata stays as the fallback because it
# is the only artifact key a stage that has not completed yet carries.
#
# Ambiguity inside the winning ladder tier is fatal rather than arbitrary: two `in_progress`
# instances with nothing to tell them apart means the caller's patch would land on a coin
# flip.  Ambiguity ACROSS tiers is not — the ladder orders those deliberately, so the
# ordinary split-stage shape (DV0 in_progress, DV1..DV3 pending) keeps resolving to DV0.
# Returns 1 on ambiguity, before any lock is taken, leaving state.json untouched.
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

# `stage` and `status` are defaulted, never left null: the FN gate groups unresolved items by
# stage and treats a missing status as unanswered, so a null in either field renders an item
# nobody can attribute or act on. `stage` comes from the item's own id (`sw-<TASK_ID>-<n>` is
# the mandated shape, so the id IS the slot), falling back to the writing stage's code for a
# legacy id that predates it. Applied to incumbents as well as incoming items, so an array
# already carrying nulls is backfilled on the next write rather than staying broken forever.
#
# open_questions unions through _union_sweep, not _union_keyed: last-writer-wins would let a
# re-emitted stub carrying `status: open` destroy an answer already recorded against that id, and
# since sw-DR0-3 moved sweep answers out of facts.decisions[] that element is the ONLY record of it.
# `open < resolved` is joined monotonically — a later write may raise, never downgrade — the same
# lattice shape this feature already ships for `decision < escalate`. The fields are guarded
# INDEPENDENTLY: an incoming stub that omits `resolution` inherits the incumbent's even when both
# sides say `resolved`, because dropping the answer body is a downgrade too, and
# `blocks_next_stage` is sticky ONLY when the incoming stub re-emits WITHOUT the key, so a rework
# round that drops it cannot silently demote a boundary-blocking item to an FN-batched one. An
# explicit `false` is the author speaking and CLEARS the flag: the two cases are distinguished by
# `has`, never by truthiness, because conflating them made `true` unclearable and turned a
# bookkeeping divergence into a real gate. `--facts` now requires the key, so the sticky arm covers
# only legacy payloads written before that. Scoped to
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
      def _union_sweep:
        reduce (.[] | _sweep_defaults) as $e ([];
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

# Sweep items the open_questions clamp evicted while still UNRESOLVED are appended to
# `.context/open-questions-<run_index>.jsonl` before the rename, so the FN gate can still
# render a question the ledger no longer has room for.  Nothing else recovers them: the
# clamp keeps unresolved items ahead of resolved ones, but past 12 unresolved it starts
# dropping live questions and the eviction is the only record that they existed.
#
# ADDITIVE around _STATE_BOUNDS_FILTER, which is deliberately NOT edited: the spill is the
# set difference (pre-clamp unresolved − post-clamp), computed by re-evaluating the caller's
# filter without the bounds tail.  The ordering jq is untouched, so it cannot regress, and
# output is byte-identical for any array of 12 or fewer and for any overflow whose evictions
# are all resolved.
#
# Ordered before the rename on purpose: a crash can then leave a spill line whose eviction
# never committed — a duplicate the union collapses — but never an eviction whose spill line
# is missing, which would be loss.  Append-only, never rewritten, never deduped on write.
# Every failure here is swallowed: a spill that cannot be written must not undo a merge.
#
# _spill_evicted_questions <state> <tmp> <filter> [jq-args...]
_spill_evicted_questions() {
  local state="$1" tmp="$2" filter="$3"
  shift 3

  # Trigger on pre > post, never on the clamp's literal bound: hard-coding 12 made the
  # spill die silently the moment the bound moved. An empty post-clamp array cannot have
  # evicted anything, which keeps the common path at one cheap length query.
  local post_len pre_len merged
  post_len=$(jq -r '(.facts.open_questions? // []) | length' "$tmp" 2> /dev/null || printf '0')
  [[ "$post_len" -gt 0 ]] || return 0
  merged=$(jq "$@" "( ${filter} )" "$state" 2> /dev/null) || {
    log_msg WARN "open_questions spill: pre-clamp re-evaluation failed; evictions (if any) unrecorded (merge unaffected)"
    return 0
  }
  pre_len=$(printf '%s' "$merged" | jq -r '(.facts.open_questions? // []) | length' 2> /dev/null || printf '0')
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
  spill_path="${spill_dir}/open-questions-${run_idx}.jsonl"

  # EVERY eviction spills, resolved ones included, flagged by `was_resolved`. Filtering
  # answered items out destroyed the one field the sweep exists to produce and inverted the
  # incentive: answering a question was what made it disappear without a trace.
  spilled=$(printf '%s' "$merged" \
    | jq -c --slurpfile post "$tmp" \
           --arg ts "$(date -u +%FT%TZ)" \
           --arg from "$from_stage" '
        (($post[0].facts.open_questions // []) | map(.id)) as $keep
        | (.facts.open_questions // [])
        | map(select(([.id] - $keep) | length > 0))
        | map(. + {spilled_at: $ts, spilled_from_stage: $from,
                   was_resolved: ((.status // "open") == "resolved")})
        | .[]' 2> /dev/null) || {
    # A failed spill computation used to `return 0`, which read as "nothing was evicted".
    log_msg WARN "open_questions spill computation failed; up to $((pre_len - post_len)) evicted item(s) may be unrecorded (merge unaffected)"
    printf >&2 'warn: open_questions spill computation failed; up to %d evicted item(s) unrecorded\n' "$((pre_len - post_len))"
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
    log_msg INFO "spilled ${spill_n} evicted open_question(s) to ${spill_path}"
  else
    log_msg WARN "open_questions spill append failed for ${spill_path}; ${spill_n} evicted item(s) unrecorded (merge unaffected)"
    printf >&2 'warn: open_questions spill append to %s failed; %d evicted item(s) unrecorded\n' \
      "$spill_path" "$spill_n"
  fi
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
    _spill_evicted_questions "$state" "$tmp" "$filter" "$@"
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

  # ---- T15b/c/d/e: artifact-first resolution for a genuinely ambiguous split stage ----
  # T15 above only ever has ONE open instance, so it passes with or without the artifact
  # tier — which is how the mis-slotting defect stayed invisible.  These four put two
  # `in_progress` instances in the ledger, the shape a fanned-out DV run actually has.
  cat > .context/state.json << 'EOSTATE'
{"version":2,"worktask_id":"selftest","plan_file":".context/planning-0.md","platform":"all","run_index":0,"tasks":{"DV0":{"status":"in_progress","metadata":{"artifact":".context/development-0-gate.md"}},"DV1":{"status":"in_progress","metadata":{"artifact":".context/development-0-ledger.md"}}},"facts":{},"handoffs":{}}
EOSTATE
  t15b_id=$(bash "$SELF" --resolve-task-id DV --artifact .context/development-0-ledger.md)
  if [[ "$t15b_id" == "DV1" ]]; then
    printf 'T15b: --artifact picks the matching instance out of two in_progress: ok\n'
  else
    printf 'T15b: artifact-first resolution (got %s, want DV1): FAIL\n' "$t15b_id" >&2
    exit 1
  fi

  # Absolute and ./-prefixed callers must land on the same key as the stored relative path.
  t15e_id=$(bash "$SELF" --resolve-task-id DV --artifact "$PWD/.context/development-0-ledger.md")
  t15e_id2=$(bash "$SELF" --resolve-task-id DV --artifact ./.context/development-0-ledger.md)
  if [[ "$t15e_id" == "DV1" && "$t15e_id2" == "DV1" ]]; then
    printf 'T15e: absolute and ./-prefixed artifacts resolve like the relative one: ok\n'
  else
    printf 'T15e: path normalisation (abs=%s dot=%s, want DV1): FAIL\n' "$t15e_id" "$t15e_id2" >&2
    exit 1
  fi

  # The recorded artifact beats another instance's PLANNED one: PL0 seeds metadata from the
  # plan, and a split stage routinely writes a file the plan did not predict.
  jq '.tasks.DV0.artifact = ".context/development-1.md"
      | .tasks.DV1.metadata.artifact = ".context/development-1.md"' \
    .context/state.json > .context/state.json.t15f && mv .context/state.json.t15f .context/state.json
  t15f_id=$(bash "$SELF" --resolve-task-id DV --artifact .context/development-1.md)
  if [[ "$t15f_id" == "DV0" ]]; then
    printf 'T15f: recorded artifact outranks a stale planned one: ok\n'
  else
    printf 'T15f: recorded-before-planned precedence (got %s, want DV0): FAIL\n' "$t15f_id" >&2
    exit 1
  fi

  # No discriminator: refuse, name both candidates, and leave the ledger byte-identical.
  cat > .context/state.json << 'EOSTATE'
{"version":2,"worktask_id":"selftest","plan_file":".context/planning-0.md","platform":"all","run_index":0,"tasks":{"DV0":{"status":"in_progress"},"DV1":{"status":"in_progress"}},"facts":{},"handoffs":{}}
EOSTATE
  cp .context/state.json .context/state.json.snap15c
  t15c_rc=0
  t15c_err=$(bash "$SELF" --stage DV --artifact .context/development-0.md --via step6_5 2>&1 > /dev/null) \
    || t15c_rc=$?
  if [[ "$t15c_rc" == "4" ]] \
    && printf '%s' "$t15c_err" | grep -q 'DV0,DV1' \
    && diff -q .context/state.json .context/state.json.snap15c > /dev/null; then
    printf 'T15c: ambiguous stage refuses with exit 4, both named, state byte-unchanged: ok\n'
  else
    printf 'T15c: ambiguity must fail closed (rc=%s err=%s): FAIL\n' "$t15c_rc" "$t15c_err" >&2
    exit 1
  fi
  rm -f .context/state.json.snap15c

  # T15d is the hooks/agent-stop.sh regression guard: one open instance, no --artifact,
  # behaviour identical to before the artifact tier existed.
  cat > .context/state.json << 'EOSTATE'
{"version":2,"worktask_id":"selftest","plan_file":".context/planning-0.md","platform":"all","run_index":0,"tasks":{"DV0":{"status":"in_progress"},"DV1":{"status":"pending"}},"facts":{},"handoffs":{}}
EOSTATE
  t15d_id=$(bash "$SELF" --resolve-task-id DV)
  t15d_rc=0
  bash "$SELF" --stage DV --via step6_5 > /dev/null 2>&1 || t15d_rc=$?
  if [[ "$t15d_id" == "DV0" && "$t15d_rc" == "0" ]] \
    && jq -e '.tasks.DV0.status == "completed" and .tasks.DV1.status == "pending"' \
      .context/state.json > /dev/null; then
    printf 'T15d: bare --stage with one open instance is unchanged: ok\n'
  else
    printf 'T15d: bare --stage regression (id=%s rc=%s): FAIL\n' "$t15d_id" "$t15d_rc" >&2
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
  bash "$SELF" --facts '{"open_questions":[{"id":"sw-PL0-1","class":"decision","ref":"planning-0.md#elicitation-sweep","blocks_next_stage":false}]}' \
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
  # blocks_next_stage is required too: a stub that omits it is the demotion-by-omission the
  # union's sticky arm used to absorb, refused here instead — at the door, before any merge.
  cp .context/state.json .context/state.json.snap19b
  st19b_rc=0
  bash "$SELF" --facts '{"open_questions":[{"id":"sw-PL0-1","class":"decision","ref":"planning-0.md#elicitation-sweep"}]}' \
    > /dev/null 2>&1 || st19b_rc=$?
  if [[ "$st19b_rc" -eq 2 ]] \
    && diff -q .context/state.json .context/state.json.snap19b > /dev/null; then
    printf 'T19: a stub omitting blocks_next_stage exits 2, state byte-unchanged: ok\n'
  else
    printf 'T19: missing-blocks_next_stage guard (rc=%s): FAIL\n' "$st19b_rc" >&2
    exit 1
  fi
  # decisions keeps the id-only contract: the tightening is scoped to open_questions.
  bash "$SELF" --facts '{"decisions":[{"id":"d1","summary":"s","ref":"planning-0.md#stages"}]}' \
    > /dev/null || {
      printf 'T19: decisions payload was rejected: FAIL\n' >&2
      exit 1
    }

  # ---- T20: raising blocks_next_stage is honoured ----
  # The lattice's live half: an item written non-blocking can be raised to blocking later.
  # Its other half — a stub that OMITS the key cannot demote — is now enforced one layer
  # earlier by the T19 shape gate, so it can no longer be reached through --facts at all;
  # the union's sticky arm survives for legacy payloads and is covered directly against the
  # filter in tests/shell/skills/elicitation-sweep-contracts.bats.
  make_state
  bash "$SELF" --facts '{"open_questions":[{"id":"sw-DV0-1","class":"decision","ref":"development-0.md#elicitation-sweep","blocks_next_stage":false}]}' > /dev/null
  bash "$SELF" --facts '{"open_questions":[{"id":"sw-DV0-1","class":"decision","ref":"development-0.md#elicitation-sweep","blocks_next_stage":true}]}' > /dev/null
  if jq -e '.facts.open_questions[0].blocks_next_stage == true' .context/state.json > /dev/null; then
    printf 'T20: raising blocks_next_stage is honoured: ok\n'
  else
    printf 'T20: a raise to blocking was refused: FAIL\n' >&2
    exit 1
  fi

  # ---- T20b: an EXPLICIT false clears an incumbent true ----
  # The OV-183 defect: the join ORed the flag, so once `true` landed no payload could clear
  # it — not even the author's own artifact value — and the ledger permanently outvoted the
  # stub it was derived from. Absent still sticks (T19 refuses it); explicit false does not.
  make_state
  bash "$SELF" --facts '{"open_questions":[{"id":"sw-DV0-1","class":"decision","ref":"development-0.md#elicitation-sweep","blocks_next_stage":true}]}' > /dev/null
  bash "$SELF" --facts '{"open_questions":[{"id":"sw-DV0-1","class":"decision","ref":"development-0.md#elicitation-sweep","blocks_next_stage":false}]}' > /dev/null
  if jq -e '.facts.open_questions[0].blocks_next_stage == false' .context/state.json > /dev/null; then
    printf 'T20b: an explicit false clears an incumbent true: ok\n'
  else
    printf 'T20b: explicit false could not clear the flag: FAIL\n' >&2
    exit 1
  fi

  # ---- T21/T22/T23: the open_questions clamp spills unresolved evictions (AD-4) ----
  # Fixture builder: N open_questions, the first $2 of them resolved, run_index 3.
  t21_seed() {
    jq -n --argjson n "$1" --argjson res "$2" '
      { version: 2, worktask_id: "selftest", plan_file: ".context/planning-0.md",
        platform: "all", run_index: 3,
        tasks: { DV1: { status: "in_progress" } },
        facts: { open_questions:
          [ range(1; $n + 1) as $i
            | { id: ("sw-PL0-" + ($i | tostring)), class: "decision",
                ref: "planning-0.md#elicitation-sweep", stage: "PL",
                status: (if $i <= $res then "resolved" else "open" end) }
            + (if $i <= $res then { resolution: "answered" } else {} end) ] },
        handoffs: {} }' > .context/state.json
    rm -f .context/open-questions-3.jsonl
  }
  t21_add() {
    bash "$SELF" --task-id DV1 --facts \
      "{\"open_questions\":[{\"id\":\"$1\",\"class\":\"decision\",\"ref\":\"development-1.md#elicitation-sweep\",\"blocks_next_stage\":false}]}" \
      > /dev/null
  }

  # An array that stays at or below the bound must behave exactly as it did before the spill
  # existed: no file, and a ledger byte-identical to the unspilled merge.
  t21_seed 5 0
  t21_add sw-DV1-1
  cp .context/state.json .context/state.json.t21
  if [[ ! -e .context/open-questions-3.jsonl ]]; then
    printf 'T21: no spill file while the array is within bounds: ok\n'
  else
    printf 'T21: spilled without an eviction: FAIL\n' >&2
    exit 1
  fi

  # 12 open + 1 more evicts the OLDEST UNRESOLVED item — the loss #3 reports.
  t21_seed 12 0
  t21_add sw-DV1-1
  if [[ "$(jq -r '.id' .context/open-questions-3.jsonl 2> /dev/null)" == "sw-PL0-1" ]] \
    && [[ "$(grep -c '^' .context/open-questions-3.jsonl)" == "1" ]] \
    && jq -e '.spilled_at and .spilled_from_stage and .class and .ref and .stage and .status' \
      .context/open-questions-3.jsonl > /dev/null \
    && jq -e '(.facts.open_questions | map(.id)) == ["sw-PL0-2","sw-PL0-3","sw-PL0-4","sw-PL0-5","sw-PL0-6","sw-PL0-7","sw-PL0-8","sw-PL0-9","sw-PL0-10","sw-PL0-11","sw-PL0-12","sw-DV1-1"]' \
      .context/state.json > /dev/null; then
    printf 'T22: unresolved eviction spills the full stub, ledger order unchanged: ok\n'
  else
    printf 'T22: unresolved eviction was not spilled: FAIL\n' >&2
    cat .context/open-questions-3.jsonl >&2 2> /dev/null
    jq -c '.facts.open_questions | map(.id)' .context/state.json >&2
    exit 1
  fi

  # A resolved eviction is the one the sweep worked hardest for: it carries the answer.
  # Spilling only unresolved items meant answering a question was what made it vanish.
  t21_seed 12 2
  t21_add sw-DV1-1
  if [[ -e .context/open-questions-3.jsonl ]] \
    && [[ "$(jq -r '.id' .context/open-questions-3.jsonl 2> /dev/null)" == "sw-PL0-1" ]] \
    && jq -e '.was_resolved == true and .resolution == "answered" and .spilled_at' \
      .context/open-questions-3.jsonl > /dev/null; then
    printf 'T23: a resolved eviction spills, flagged was_resolved, answer intact: ok\n'
  else
    printf 'T23: resolved eviction was discarded: FAIL\n' >&2
    cat .context/open-questions-3.jsonl >&2 2> /dev/null
    exit 1
  fi

  # ---- T23b: the spill trigger is bound-free ----
  # It used to fire only on a post-clamp length of exactly 12, so the spill died silently
  # whenever the bound moved. An unevicted merge must still write nothing.
  t21_seed 12 0
  cp .context/state.json .context/state.json.t23b
  bash "$SELF" --task-id DV1 --facts \
    '{"open_questions":[{"id":"sw-PL0-1","class":"decision","ref":"planning-0.md#elicitation-sweep","blocks_next_stage":false}]}' \
    > /dev/null
  if [[ ! -e .context/open-questions-3.jsonl ]] \
    && [[ "$(jq -r '.facts.open_questions | length' .context/state.json)" == "12" ]]; then
    printf 'T23b: a union that evicts nothing writes no spill line: ok\n'
  else
    printf 'T23b: spilled without an eviction: FAIL\n' >&2
    exit 1
  fi

  # ---- T23c: a spill whose append FAILS says so, and claims no success ----
  # Reachable without a test seam (QA-1's recipe): make the spill path unwritable. The INFO
  # line used to be unconditional, so the log recorded a spill that never reached the file
  # while the WARN two lines above said the opposite — and the WARN was log-only, so the call
  # site saw nothing at all.
  t21_seed 12 0
  : > .context/open-questions-3.jsonl
  chmod 0444 .context/open-questions-3.jsonl
  st23c_rc=0
  : > .context/t23c.log
  LOG_FILE=.context/t23c.log bash "$SELF" --log .context/t23c.log --task-id DV1 --facts \
    '{"open_questions":[{"id":"sw-DV1-1","class":"decision","ref":"development-1.md#elicitation-sweep","blocks_next_stage":false}]}' \
    > /dev/null 2> .context/t23c.err || st23c_rc=$?
  chmod 0644 .context/open-questions-3.jsonl
  if [[ "$st23c_rc" -eq 0 ]] \
    && [[ ! -s .context/open-questions-3.jsonl ]] \
    && grep -q 'spill append to .* failed' .context/t23c.err \
    && grep -q 'evicted item(s) unrecorded' .context/t23c.err \
    && jq -e '(.facts.open_questions | map(.id) | index("sw-DV1-1")) != null' \
      .context/state.json > /dev/null \
    && grep -q 'spill append failed for' .context/t23c.log \
    && ! grep -q 'spilled 1 evicted' .context/t23c.log; then
    printf 'T23c: a failed spill append warns on stderr and claims no success: ok\n'
  else
    printf 'T23c: failed spill append was silent or claimed success (rc=%s): FAIL\n' "$st23c_rc" >&2
    cat .context/t23c.err >&2
    exit 1
  fi

  # ---- T24: --facts rejects per item, persisting the valid remainder ----
  # One bad class value used to discard the whole write — decisions, changed files and
  # every valid sweep stub in the same object.
  make_state
  st24_rc=0
  bash "$SELF" --facts '{
      "decisions":[{"id":"d-good","summary":"kept"},{"summary":"no id"}],
      "files_modified":["a.sh", 42],
      "open_questions":[
        {"id":"sw-DV0-1","class":"decision","ref":"development-0.md#elicitation-sweep","blocks_next_stage":false},
        {"id":"sw-DV0-2","class":"risk","ref":"development-0.md#elicitation-sweep","blocks_next_stage":false}]
    }' > /dev/null 2> .context/t24.err || st24_rc=$?
  if [[ "$st24_rc" -eq 2 ]] \
    && jq -e '(.facts.decisions | map(.id)) == ["d-good"]
              and (.facts.files_modified) == ["a.sh"]
              and (.facts.open_questions | map(.id)) == ["sw-DV0-1"]' \
      .context/state.json > /dev/null \
    && grep -q 'sw-DV0-2' .context/t24.err; then
    printf 'T24: --facts persists the valid remainder and names each rejection (rc=2): ok\n'
  else
    printf 'T24: per-item rejection did not partition the payload (rc=%s): FAIL\n' "$st24_rc" >&2
    jq -c '.facts' .context/state.json >&2
    cat .context/t24.err >&2
    exit 1
  fi

  # ---- T24b: an unknown key is still a whole-payload refusal ----
  # Per-item rejection is about item shape; an unknown key means the caller is writing to a
  # slot that does not exist, and no part of that payload can be trusted to land where meant.
  cp .context/state.json .context/state.json.snap24b
  st24b_rc=0
  bash "$SELF" --facts '{"decisions":[{"id":"d-x"}],"nope":[]}' > /dev/null 2>&1 || st24b_rc=$?
  if [[ "$st24b_rc" -eq 2 ]] \
    && diff -q .context/state.json .context/state.json.snap24b > /dev/null; then
    printf 'T24b: an unknown key refuses the whole payload, state byte-unchanged: ok\n'
  else
    printf 'T24b: unknown-key guard (rc=%s): FAIL\n' "$st24b_rc" >&2
    exit 1
  fi

  # ---- T24c: a rejection diagnostic is not buried under the help text ----
  # The reproduction: the real message scrolled past behind a ~100-line usage dump.
  bash "$SELF" --facts '{"open_questions":[{"id":"sw-PL0-1"}]}' > /dev/null 2> .context/t24c.err || true
  if [[ "$(grep -c '^' .context/t24c.err)" -le 6 ]] \
    && ! grep -q 'state-patch.sh --stage' .context/t24c.err; then
    printf 'T24c: a rejection prints its diagnostic, not the usage block: ok\n'
  else
    printf 'T24c: rejection diagnostic buried under usage (%s lines): FAIL\n' \
      "$(grep -c '^' .context/t24c.err)" >&2
    exit 1
  fi

  # ---- T24d: an EMPTY payload is a no-op success, not a refusal ----
  # The sweep contract tells a stage with nothing to ask to emit `open_questions: []`. Refusing
  # that aborted the stage-completion merge the same call was paired with.
  make_state
  cp .context/state.json .context/state.json.snap24d
  st24d_rc=0
  bash "$SELF" --facts '{"open_questions":[]}' > /dev/null 2>&1 || st24d_rc=$?
  if [[ "$st24d_rc" -eq 0 ]] \
    && diff -q .context/state.json .context/state.json.snap24d > /dev/null; then
    printf 'T24d: an empty --facts payload is a no-op success, state byte-unchanged: ok\n'
  else
    printf 'T24d: empty payload refused (rc=%s): FAIL\n' "$st24d_rc" >&2
    exit 1
  fi
  # And it must not abort the stage merge it is paired with — the shape every agent emits.
  st24e_rc=0
  bash "$SELF" --stage DV --artifact .context/development-0.md --facts '{"open_questions":[]}' \
    > /dev/null 2>&1 || st24e_rc=$?
  if [[ "$st24e_rc" -eq 0 ]] \
    && [[ "$(jq -r '.tasks.DV0.status' .context/state.json)" == "completed" ]]; then
    printf 'T24e: --stage paired with an empty --facts still patches the ledger: ok\n'
  else
    printf 'T24e: empty --facts aborted the stage merge (rc=%s): FAIL\n' "$st24e_rc" >&2
    jq -c '.tasks.DV0' .context/state.json >&2
    exit 1
  fi

  # ---- T24f: a partial payload paired with --stage still exits 2 ----
  # The rejection must survive the fall-through, or a combined call hides it.
  make_state
  st24f_rc=0
  bash "$SELF" --stage DV --artifact .context/development-0.md --facts \
    '{"decisions":[{"id":"d-ok"},{"summary":"no id"}]}' > /dev/null 2>&1 || st24f_rc=$?
  if [[ "$st24f_rc" -eq 2 ]] \
    && [[ "$(jq -r '.tasks.DV0.status' .context/state.json)" == "completed" ]] \
    && jq -e '[.facts.decisions[].id] | index("d-ok")' .context/state.json > /dev/null; then
    printf 'T24f: a partial --facts beside --stage completes the merge and still exits 2: ok\n'
  else
    printf 'T24f: combined partial-facts exit wrong (rc=%s): FAIL\n' "$st24f_rc" >&2
    exit 1
  fi

  # ---- T27: the post-write assertion names ids a clamp evicted ----
  # facts.decisions[] clamps to the newest 8 and has no spill (gh#316), so an id can land and
  # be evicted by the same write. The detector is the only signal that happened.
  make_state
  bash "$SELF" --facts "$(jq -nc '{decisions: [range(1;9) | {id: ("old-" + (.|tostring))}]}')" \
    > /dev/null
  bash "$SELF" --facts "$(jq -nc '{decisions: [range(1;10) | {id: ("new-" + (.|tostring))}]}')" \
    > /dev/null 2> .context/t27.err || true
  if grep -q 'not in the ledger (clamp eviction)' .context/t27.err \
    && grep -q 'new-1' .context/t27.err; then
    printf 'T27: an id evicted by the clamp on its own write is named on stderr: ok\n'
  else
    printf 'T27: clamp eviction of a just-written id was silent: FAIL\n' >&2
    cat .context/t27.err >&2
    exit 1
  fi

  # ---- T25: a --facts write that lands nothing is loud ----
  # log_msg writes only to the log file, so an absent ledger exited 0 with nothing on stderr.
  rm -rf .context
  mkdir -p .context
  st25_rc=0
  bash "$SELF" --facts '{"decisions":[{"id":"d-1"}]}' > /dev/null 2> t25.err || st25_rc=$?
  if [[ "$st25_rc" -ne 0 ]] && grep -q 'no ledger' t25.err; then
    printf 'T25: a facts write with no ledger fails loudly on stderr: ok\n'
  else
    printf 'T25: absent-ledger facts write was silent (rc=%s): FAIL\n' "$st25_rc" >&2
    exit 1
  fi

  # ---- T26: metadata.description is capped on the two ledger write paths ----
  make_state
  T26_LONG=$(printf 'x%.0s' $(seq 1 400))
  bash "$SELF" --task-create DV9 --metadata "$(jq -nc --arg d "$T26_LONG" '{stage:"DV",description:$d}')" > /dev/null
  bash "$SELF" --task-meta DV9 --set "$(jq -nc --arg d "$T26_LONG" '{description:$d}')" > /dev/null
  if jq -e '(.tasks.DV9.metadata.description | length) == 240
            and (.tasks.DV9.metadata.description | endswith("…"))
            and .tasks.DV9.metadata.stage == "DV"' .context/state.json > /dev/null; then
    printf 'T26: an over-long description is truncated, not rejected, on create and meta: ok\n'
  else
    printf 'T26: description cap did not apply: FAIL\n' >&2
    jq -c '.tasks.DV9' .context/state.json >&2
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
  # Ambiguity is exit 4 here too: --resolve-code is what the orchestrator asks before it
  # patches, so answering with a guess would only move the mis-slot one call later.
  if ! _RESOLVED=$(resolve_task_id "$RESOLVE_CODE_ARG"); then
    exit 4
  fi
  printf '%s\n' "$_RESOLVED"
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
    printf >&2 'invalid --facts: %s item(s) rejected, the rest still persist:\n' "$FACTS_REJECT_N"
    printf '%s' "$FACTS_PART" \
      | jq -r '.rejects[] | "  - " + .key + " " + .label + ": " + .reason' >&2
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

  if [[ "$FACTS_EMPTY_NOOP" -eq 1 ]]; then
    : # no-op: nothing to write, and an absent ledger is not an error for an empty payload
  elif [[ ! -f "$STATE_PATH" ]]; then
    # log_msg writes only to $LOG_FILE, so this used to be an INFO line and exit 0 — a write
    # that landed nothing, indistinguishable at the call site from one that landed.
    printf >&2 'no ledger at %s — --facts landed nothing\n' "$STATE_PATH"
    log_msg ERROR "state.json absent at ${STATE_PATH}; --facts landed nothing"
    exit 1
  elif atomic_apply "$STATE_PATH" "$_FACTS_UNION_FILTER" \
    --argjson f "$FACTS_ARG" --arg sweep_stage "$SWEEP_STAGE_FALLBACK"; then
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
  # Every no-op return on the paired path still carries a --facts rejection out.
  exit $((FACTS_REJECTED == 1 ? 2 : 0))
fi

if [[ ! -f "$STATE_PATH" ]]; then
  log_msg INFO "state.json absent — nothing to merge (artifact=$ART)"
  exit $((FACTS_REJECTED == 1 ? 2 : 0))
fi

# ---------- Parse frontmatter ----------
parse_frontmatter "$ART"

if [[ -z "$PARSED_STAGE" ]]; then
  log_msg WARN "could not extract stage from $ART; aborting merge silently"
  exit $((FACTS_REJECTED == 1 ? 2 : 0))
fi

# ---------- Resolve the ledger key ----------
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
    CURRENT_HANDOFF=$(jq -r --arg k "${PREV_ARG}→${PARSED_STAGE}" '.handoffs[$k] // ""' \
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
# because the handoff edges it pairs with are bare codes; a split stage's last instance to
# complete owns the entry, which matches how the edge behaves. --prev additionally emits handoffs["<PREV>→<CODE>"] (maxLength 300, must
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
  + {facts: {verdicts: {($stage): $verdict}}}
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

exit $((FACTS_REJECTED == 1 ? 2 : 0))

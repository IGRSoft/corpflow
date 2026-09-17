#!/usr/bin/env bash
# @description land-artifacts.sh — copies a DV producer's staged artifact(s) into a
#   consumer's assigned tree, verified on git's own object id before sha256 is
#   trusted, so a corrupted read cannot vouch for itself.
#
#   Two callers, one script: the producer boundary (`--producer`, after the row is
#   patched completed) and the idempotent dispatch gate (`--consumer`, after any
#   re-pin). They differ only in the `blocked`-consumer skip and the ledger-row
#   cardinality; every path check is identical.
#
# @arg --producer <ID>    Boundary pass: land every consumer of this producer row.
# @arg --consumer <ID>    Dispatch gate: land every producer this row consumes from.
#                          At least one of --producer/--consumer is required.
# @arg --state <path>     state.json path (default: corpflow_context_dir()+/state.json).
# @arg --orch-root <path> Passed through to workspace-root-banner.sh unchanged.
# @arg --dry-run          Preflight only; writes nothing (no mkdir, no copy).
# @arg --list-landed [--state <path>]
#                          Print the union of every landed_paths entry across the
#                          ledger, one path per line. Empty output is exit 0.
# @arg --self-test        Exec the sibling land-artifacts-selftest.sh harness.
# @arg -h | --help        Show this header.
#
# @exitcode 0  Landed, same tree, already present, gate no-op, boundary-skipped
#              `blocked` consumer, or nothing selected.
# @exitcode 1  A consumer's landing failed: it is now `blocked`, a fail
#              `contract_landed` row was written.
# @exitcode 2  Usage, malformed id, unreadable/invalid ledger, missing
#              jq/git/hasher, or a failed state-patch.sh write (this run's own
#              files were rolled back first).
#
# Minimum shell: bash 3.2+ (macOS default).

set -euo pipefail
IFS=$'\n\t'

# The one landed-paths exclusion expression. Every other transport (hook, technical-lead.md,
# project-manager.md, state-ledger.md) carries this SAME string; a parity test
# diffs them, so a change here without the others is a test failure, not a typo.
readonly LANDED_UNION_JQ='[(.tasks // {})[] | .metadata.landed_paths // [] | arrays | .[] | strings] | unique | .[]'

# Sentinel carried through the collect_pairs TSV stream for a candidate whose
# `consumes` shape is invalid. Kept out of the producer-id column so it can
# never collide with a real `DV[0-9]+` id.
readonly BADDECL_MARK='__BADDECL__'

usage() {
  sed -n '2,32s/^# \{0,1\}//p' "$0" >&2
  exit 2
}

die() {
  local code="$1"
  shift
  printf >&2 'land-artifacts: %s\n' "$*"
  exit "$code"
}

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Physical-path normalisation for a directory that already exists.
# shellcheck disable=SC1007  # CDPATH= is an env-prefix on `cd`, not an assignment
phys_dir() { (CDPATH= cd -P -- "$1" 2> /dev/null && pwd -P); }

valid_task_id() {
  [[ "$1" =~ ^DV[0-9]+$ ]]
}

oid_valid() {
  [[ "$1" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]]
}

# ---------- hasher: stdin only, first field only ----------
HASHER_KIND=""
if command -v sha256sum > /dev/null 2>&1; then
  HASHER_KIND="sha256sum"
elif command -v shasum > /dev/null 2>&1; then
  HASHER_KIND="shasum"
fi
hash_stdin() {
  case "$HASHER_KIND" in
    sha256sum) sha256sum | awk '{print $1}' ;;
    shasum) shasum -a 256 | awk '{print $1}' ;;
    *) return 1 ;;
  esac
}

# ---------- lexical ladder, one reason each, strict order ----------
lexical_check() {
  local p="$1" len seg lc old_ifs
  len=${#p}
  if [ -z "$p" ] || [ "$len" -gt 1024 ]; then
    printf 'bad_path'
    return 0
  fi
  case "$p" in
    /*)
      printf 'absolute_path'
      return 0
      ;;
  esac
  case "$p" in
    */)
      printf 'dotdot'
      return 0
      ;;
  esac
  old_ifs="$IFS"
  IFS='/'
  set -f
  # shellcheck disable=SC2086  # deliberate word split: IFS='/' + set -f fields p on '/'
  set -- $p
  set +f
  IFS="$old_ifs"
  for seg in "$@"; do
    case "$seg" in
      '' | '.' | '..')
        printf 'dotdot'
        return 0
        ;;
    esac
  done
  for seg in "$@"; do
    lc="$(lower "$seg")"
    case "$lc" in
      .git | .context)
        printf 'reserved_segment'
        return 0
        ;;
    esac
  done
  if printf '%s' "$p" | LC_ALL=C grep -q '[[:cntrl:]]'; then
    printf 'control_char'
    return 0
  fi
  for seg in "$@"; do
    case "$seg" in
      -*)
        printf 'leading_dash'
        return 0
        ;;
    esac
  done
  case "$p" in
    *[!A-Za-z0-9._@+/-]*)
      printf 'unsafe_char'
      return 0
      ;;
  esac
  return 0
}

# ---------- git hygiene (called once, before any git call) ----------
git_hygiene() {
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR
  export GIT_LITERAL_PATHSPECS=1
}

# ---------- source: mode/oid at path p in tree root, or a REASON ----------
source_check() {
  local root="$1" p="$2"
  local n=0 line mode oid rest stage path found_mode="" found_oid=""
  while IFS= read -r -d '' line; do
    n=$((n + 1))
    mode="${line%% *}"
    rest="${line#* }"
    oid="${rest%% *}"
    rest="${rest#* }"
    stage="${rest%%$'\t'*}"
    path="${rest#*$'\t'}"
    if [ "$path" != "$p" ] || [ "$stage" != "0" ]; then
      printf 'REASON:conflicted'
      return 0
    fi
    found_mode="$mode"
    found_oid="$oid"
  done < <(git -C "$root" ls-files -s -z -- "$p" 2> /dev/null)
  if [ "$n" -eq 0 ]; then
    printf 'REASON:not_staged'
    return 0
  fi
  if [ "$n" -gt 1 ]; then
    printf 'REASON:conflicted'
    return 0
  fi
  case "$found_mode" in
    100644 | 100755) : ;;
    120000)
      printf 'REASON:symlink_source'
      return 0
      ;;
    160000)
      printf 'REASON:gitlink'
      return 0
      ;;
    *)
      printf 'REASON:not_staged'
      return 0
      ;;
  esac

  local filt=""
  filt=$(
    git -C "$root" check-attr -z filter -- "$p" 2> /dev/null \
      | { IFS= read -r -d '' _p || true
        IFS= read -r -d '' _a || true
        IFS= read -r -d '' _v || true
        printf '%s' "${_v:-}"; }
  )
  if [ -n "$filt" ] && [ "$filt" != "unspecified" ]; then
    printf 'REASON:filtered_path'
    return 0
  fi

  # Every prefix AND the final component of p, walked under root: a symlinked
  # intermediate directory can smuggle the read outside the producer worktree
  # even though the index entry itself is a clean blob.
  local accum="" seg old_ifs
  old_ifs="$IFS"
  IFS='/'
  set -f
  # shellcheck disable=SC2086  # deliberate word split: IFS='/' + set -f fields p on '/'
  set -- $p
  set +f
  IFS="$old_ifs"
  for seg in "$@"; do
    if [ -z "$accum" ]; then accum="$seg"; else accum="$accum/$seg"; fi
    if [ -L "$root/$accum" ]; then
      printf 'REASON:symlink_source'
      return 0
    fi
  done

  if git -C "$root" diff --quiet --no-ext-diff --no-textconv -- "$p" 2> /dev/null; then
    :
  else
    local rc=$?
    if [ "$rc" -eq 1 ]; then
      printf 'REASON:staged_then_modified'
      return 0
    fi
    printf 'REASON:git_error'
    return 0
  fi

  printf 'OK:%s:%s' "$found_mode" "$found_oid"
}

# ---------- membership test over a newline-joined set ----------
in_set() {
  local needle="$1" hay="$2" line
  while IFS= read -r line; do
    [ "$line" = "$needle" ] && return 0
  done <<< "$hay"
  return 1
}

# ---------- destination walk ----------
# Globals read: DRY_RUN. Globals written: CREATED_DIRS (append).
# Prints "OK:<phys_parent>" or "REASON:<reason>".
dest_walk() {
  local c_root="$1" p="$2"
  local parent base seg accum="" full old_ifs
  parent=$(dirname -- "$p")
  base=$(basename -- "$p")
  if [ "$parent" != "." ]; then
    old_ifs="$IFS"
    IFS='/'
    set -f
    # shellcheck disable=SC2086  # deliberate word split: IFS='/' + set -f fields parent on '/'
    set -- $parent
    set +f
    IFS="$old_ifs"
    for seg in "$@"; do
      if [ -z "$accum" ]; then full="$c_root/$seg"; else full="$c_root/$accum/$seg"; fi
      if [ -L "$full" ]; then
        printf 'REASON:symlink_segment'
        return 0
      fi
      if [ -e "$full" ]; then
        if [ ! -d "$full" ]; then
          printf 'REASON:not_dir'
          return 0
        fi
      elif [ "$DRY_RUN" -eq 0 ]; then
        mkdir -m 755 -- "$full" || {
          printf 'REASON:not_dir'
          return 0
        }
        CREATED_DIRS[${#CREATED_DIRS[@]}]="$full"
        if [ -L "$full" ]; then
          printf 'REASON:symlink_segment'
          return 0
        fi
      fi
      if [ -z "$accum" ]; then accum="$seg"; else accum="$accum/$seg"; fi
    done
  fi

  local phys_parent
  if [ "$parent" = "." ]; then
    phys_parent="$c_root"
  elif [ -d "$c_root/$parent" ] && [ ! -L "$c_root/$parent" ]; then
    phys_parent=$(phys_dir "$c_root/$parent") || {
      printf 'REASON:not_dir'
      return 0
    }
  else
    # --dry-run only: the parent chain was validated but not created above.
    # Best-effort physical anchor: the deepest existing ancestor, plus the
    # still-missing suffix appended as text (it cannot be a symlink yet).
    phys_parent="$(phys_resolve_partial "$c_root" "$parent")" || {
      printf 'REASON:not_dir'
      return 0
    }
  fi

  case "$phys_parent/" in
    "$c_root"/*) : ;;
    *)
      printf 'REASON:dest_escape'
      return 0
      ;;
  esac

  local dest="$c_root/$p"
  if [ -L "$dest" ]; then
    printf 'REASON:symlink_dest'
    return 0
  fi
  if [ -e "$dest" ] && [ ! -f "$dest" ]; then
    printf 'REASON:dest_not_regular'
    return 0
  fi
  printf 'OK:%s' "$phys_parent"
}

phys_resolve_partial() {
  local root="$1" rel="$2" seg old_ifs remaining="" phys
  local cur="$root"
  old_ifs="$IFS"
  IFS='/'
  set -f
  # shellcheck disable=SC2086  # deliberate word split: IFS='/' + set -f fields rel on '/'
  set -- $rel
  set +f
  IFS="$old_ifs"
  local found_all=1
  for seg in "$@"; do
    if [ "$found_all" -eq 1 ] && [ -d "$cur/$seg" ] && [ ! -L "$cur/$seg" ]; then
      cur="$cur/$seg"
    else
      found_all=0
      remaining="$remaining/$seg"
    fi
  done
  phys=$(phys_dir "$cur") || return 1
  printf '%s%s' "$phys" "$remaining"
}

# ---------- write, verify, rollback ----------
TMP_LIVE=""
CREATED_DIRS=()
WRITTEN_FILES=()

# shellcheck disable=SC2329 # invoked only through the EXIT/INT/TERM trap below
cleanup_trap() {
  if [ -n "$TMP_LIVE" ] && [ -e "$TMP_LIVE" ]; then
    rm -f -- "$TMP_LIVE"
  fi
}
trap cleanup_trap EXIT INT TERM

# write_blob <producer_root> <phys_parent> <base> <oid> <index_mode> <consumer_root>
# Prints "OK:<sha256>" or "REASON:<reason>".
write_blob() {
  local p_root="$1" parent="$2" base="$3" oid="$4" idxmode="$5" c_root="$6"
  local tmp
  tmp=$(mktemp "$parent/.land-artifacts.XXXXXX") || {
    printf 'REASON:git_error'
    return 0
  }
  TMP_LIVE="$tmp"

  if ! git -C "$p_root" cat-file blob "$oid" > "$tmp" 2> /dev/null; then
    rm -f -- "$tmp"
    TMP_LIVE=""
    printf 'REASON:git_error'
    return 0
  fi

  # Anchor on git's own object id before sha256 is trusted: both reads share
  # one failure source (a corrupt `cat-file`), so a second sha256 read alone
  # would let that same corruption verify itself.
  local check=""
  check=$(git -C "$p_root" hash-object --no-filters --stdin < "$tmp" 2> /dev/null) || check=""
  if [ "$check" != "$oid" ]; then
    rm -f -- "$tmp"
    TMP_LIVE=""
    printf 'REASON:sha256_mismatch'
    return 0
  fi

  local sha
  sha=$(hash_stdin < "$tmp")
  local perm=644
  [ "$idxmode" = "100755" ] && perm=755
  chmod "$perm" -- "$tmp"

  local dest="$parent/$base"
  if [ -L "$dest" ] || [ -d "$dest" ]; then
    rm -f -- "$tmp"
    TMP_LIVE=""
    printf 'REASON:dest_race'
    return 0
  fi
  if ! mv -f -- "$tmp" "$dest"; then
    rm -f -- "$tmp" 2> /dev/null || true
    TMP_LIVE=""
    printf 'REASON:git_error'
    return 0
  fi
  TMP_LIVE=""

  if [ -e "$tmp" ]; then
    printf 'REASON:dest_race'
    return 0
  fi
  if [ -d "$dest" ] && [ ! -L "$dest" ]; then
    # Same-uid race replaced our file with a directory; rmdir (never rm -rf)
    # cleans up the stray only when it is still ours to touch.
    case "$(phys_dir "$dest" 2> /dev/null)/" in
      "$c_root"/*) rmdir -- "$dest" 2> /dev/null || true ;;
    esac
    printf 'REASON:dest_race'
    return 0
  fi
  if [ ! -f "$dest" ] || [ -L "$dest" ]; then
    printf 'REASON:dest_race'
    return 0
  fi
  local reparent
  reparent=$(phys_dir "$parent") || reparent=""
  if [ "$reparent" != "$parent" ]; then
    printf 'REASON:dest_race'
    return 0
  fi
  local dest_sha
  dest_sha=$(hash_stdin < "$dest")
  if [ "$dest_sha" != "$sha" ]; then
    rm -f -- "$dest"
    printf 'REASON:sha256_mismatch'
    return 0
  fi

  WRITTEN_FILES[${#WRITTEN_FILES[@]}]="$dest:$sha"
  printf 'OK:%s' "$sha"
}

# Failure rollback: only files this run wrote whose sha is still ours, then
# rmdir (never rm -rf) the dirs this run created, in reverse order.
rollback_run() {
  local i entry f sha cursha
  i=${#WRITTEN_FILES[@]}
  while [ "$i" -gt 0 ]; do
    i=$((i - 1))
    entry="${WRITTEN_FILES[$i]}"
    f="${entry%:*}"
    sha="${entry##*:}"
    if [ -f "$f" ] && [ ! -L "$f" ]; then
      cursha=$(hash_stdin < "$f" 2> /dev/null || printf '')
      [ "$cursha" = "$sha" ] && rm -f -- "$f"
    fi
  done
  WRITTEN_FILES=()
  i=${#CREATED_DIRS[@]}
  while [ "$i" -gt 0 ]; do
    i=$((i - 1))
    rmdir -- "${CREATED_DIRS[$i]}" 2> /dev/null || true
  done
  CREATED_DIRS=()
}

# ---------- ledger resolution ----------
resolve_state() {
  local lib ctx
  lib="$(dirname "${BASH_SOURCE[0]}")/../../shared/lib/state-read-lib.sh"
  [ -r "$lib" ] || die 2 "state-read-lib.sh unreachable at $lib"
  # shellcheck source=../../shared/lib/state-read-lib.sh
  # shellcheck disable=SC1090
  . "$lib" || die 2 "failed to source $lib"
  ctx=$(corpflow_context_dir) || die 2 "no .context/state.json resolved; pass --state"
  [ -n "$ctx" ] || die 2 "no .context/state.json resolved; pass --state"
  printf '%s/state.json' "$ctx"
}

# resolve_tree <task-id> -> physical root, or dies (tree_invalid is a hard stop:
# a wrong tree writing files is worse than any other refusal in this script).
resolve_tree() {
  local id="$1" banner path root
  local self_dir
  self_dir="$(dirname "${BASH_SOURCE[0]}")"
  # IFS has no space (top of file), so an unquoted ${ORCH_ROOT:+--orch-root
  # "$ORCH_ROOT"} would never split into two argv words; use an array instead.
  local -a orch_flag=()
  [ -n "$ORCH_ROOT" ] && orch_flag=(--orch-root "$ORCH_ROOT")
  banner=$(bash "$self_dir/workspace-root-banner.sh" --state "$STATE_PATH" --task "$id" \
    "${orch_flag[@]+"${orch_flag[@]}"}" 2>&1) || die 2 "workspace-root-banner failed for $id: $banner"
  path="${banner#WORKSPACE_ROOT=}"
  [ -d "$path" ] || die 2 "tree_invalid: $id resolves to a non-existent path: $path"
  root=$(phys_dir "$path") || die 2 "tree_invalid: $id path does not physically resolve: $path"
  local toplevel
  toplevel=$(git -C "$root" rev-parse --show-toplevel 2> /dev/null) || \
    die 2 "tree_invalid: $id tree is not a git worktree: $root"
  toplevel=$(phys_dir "$toplevel") || die 2 "tree_invalid: $id toplevel does not resolve: $toplevel"
  [ "$toplevel" = "$root" ] || die 2 "tree_invalid: $id resolved root $root != its own toplevel $toplevel"
  printf '%s' "$root"
}

jqf() { jq -r "$@" "$STATE_PATH" 2> /dev/null; }

task_exists() {
  [ "$(jqf --arg id "$1" '(.tasks // {}) | has($id)')" = "true" ]
}

task_status() { jqf --arg id "$1" '.tasks[$id].status // "pending"'; }

landed_paths_of() {
  jqf --arg id "$1" '.tasks[$id].metadata.landed_paths // [] | arrays | .[]?'
}

produces_of() {
  jqf --arg id "$1" '.tasks[$id].metadata.produces // [] | arrays | .[]?'
}

blocked_by_has() {
  [ "$(jqf --arg id "$1" --arg on "$2" '[(.tasks[$id].blocked_by // [])[]?] | index($on) != null')" = "true" ]
}

# consumes_json <id> -> raw JSON value (string "null" if absent), for shape checks.
consumes_json() { jqf --arg id "$1" '.tasks[$id].metadata.consumes // null | tojson'; }

# ---------- audit + ledger writers (single writer per surface) ----------
audit_row() {
  local lib dir
  if ! command -v corpflow_audit_row > /dev/null 2>&1; then
    lib="$(dirname "${BASH_SOURCE[0]}")/../../shared/lib/audit-lib.sh"
    [ -r "$lib" ] || return 0
    # shellcheck source=../../shared/lib/audit-lib.sh
    # shellcheck disable=SC1090
    . "$lib" || return 0
  fi
  dir="$(dirname "$STATE_PATH")/logs"
  corpflow_audit_row --file "$dir/audit.jsonl" "$@"
  # Audit loss is evidence lost, never a gate: warn, never change the exit code.
  [ "${CORPFLOW_AUDIT_LAST_RC:-1}" -eq 0 ] || \
    printf >&2 'land-artifacts: WARNING: audit row not written (%s)\n' "$*"
}

state_patch() {
  local self_dir
  self_dir="$(dirname "${BASH_SOURCE[0]}")"
  bash "$self_dir/state-patch.sh" --state "$STATE_PATH" "$@"
}

# ---------- pair handling ----------
# fail_pair <C> <P> <reason> <path>
# Rolls back this run's writes for C, blocks C, writes one fail audit row.
fail_pair() {
  local c="$1" p="$2" reason="$3" path="$4"
  rollback_run
  if [ "$DRY_RUN" -eq 1 ]; then
    printf >&2 'land-artifacts: %s -> %s refused: %s (%s) [dry-run: no ledger write]\n' \
      "$p" "$c" "$reason" "$path"
    RUN_RC=1
    return 0
  fi
  local meta
  meta=$(jq -cn --arg reason "$reason" --arg path "$path" --arg producer "$p" \
    '{reason: $reason, path: $path, producer: $producer}')
  state_patch --task-meta "$c" --set "{\"landing_error\":$meta}" \
    || die 2 "state-patch.sh failed writing landing_error for $c"
  state_patch --task-status "$c" blocked \
    || die 2 "state-patch.sh failed blocking $c"
  audit_row --actor orchestrator --action contract_landed --result fail \
    --subject "$c" --task-id "$c" --meta "$meta"
  printf >&2 'land-artifacts: %s -> %s refused: %s (%s)\n' "$p" "$c" "$reason" "$path"
  RUN_RC=1
}

# ok_row <C> <P> <mode> <files_json>
# One audit row for one selected pair. Ledger landed_paths
# are committed separately, once per consumer, by commit_landed.
ok_row() {
  local c="$1" p="$2" mode="$3" files_json="$4"
  [ "$DRY_RUN" -eq 1 ] && return 0
  local meta
  meta=$(jq -cn --arg producer "$p" --arg consumer "$c" --arg mode "$mode" \
    --argjson files "$files_json" '{producer: $producer, consumer: $consumer, mode: $mode, files: $files}')
  audit_row --actor orchestrator --action contract_landed --result ok \
    --subject "$c" --task-id "$c" --meta "$meta"
}

# commit_landed <C> <new_landed_json>
# The single --task-meta write for the whole consumer: jq's "*" merge
# replaces arrays wholesale, so every pair's new paths must be folded into one
# union before the one write, not one write per pair.
commit_landed() {
  local c="$1" new_landed_json="$2" existing union
  existing=$(jqf --arg id "$c" '.tasks[$id].metadata.landed_paths // [] | arrays | .[]?')
  union=$(printf '%s\n%s\n' "$existing" "$(printf '%s' "$new_landed_json" | jq -r '.[]?')" \
    | grep -v '^[[:space:]]*$' | LC_ALL=C sort -u | jq -R -s -c 'split("\n") | map(select(length > 0))')
  state_patch --task-meta "$c" --set "{\"landed_paths\":$union,\"landing_error\":null}"
}

# first_of_csv <csv> -> first comma-separated field, for the single <path>
# a fail row records when the failure is not path-specific.
first_of_csv() { printf '%s' "${1%%,*}"; }

# process_consumer <C>
# Reads the ROW_P/ROW_PATHS globals (one entry per selected producer of C,
# grouped by the caller). Every path of every pair of C is preflighted
# before the first write, and C lands all-or-nothing, so nothing here is
# committed to the ledger until every pair has cleared preflight.
process_consumer() {
  local c="$1"
  local n="${#ROW_P[@]}"
  [ "$n" -gt 0 ] || return 0

  if [ "${ROW_PATHS[0]}" = "$BADDECL_MARK" ]; then
    fail_pair "$c" "${ROW_P[0]}" "bad_declaration" "-"
    return 0
  fi

  local cstat
  cstat=$(task_status "$c")
  if [ "$cstat" = "blocked" ] && [ "$BOUNDARY" -eq 1 ]; then
    # An earlier landing_error is kept; the gate re-lands after release.
    return 0
  fi
  if [ "$cstat" != "pending" ]; then
    fail_pair "$c" "${ROW_P[0]}" "consumer_already_dispatched" "$(first_of_csv "${ROW_PATHS[0]}")"
    return 0
  fi

  # Phase B: declaration preconditions, every pair, before any tree is touched.
  local i=0 p pathcsv pstat produces path
  local -a plist
  while [ "$i" -lt "$n" ]; do
    p="${ROW_P[$i]}"
    pathcsv="${ROW_PATHS[$i]}"
    if ! task_exists "$p"; then
      fail_pair "$c" "$p" "bad_declaration" "$(first_of_csv "$pathcsv")"
      return 0
    fi
    # Declaration-shape reasons (self_consume, not_blocked_on_producer,
    # not_produced) must be reachable, so they run before the status read
    # below ever gets a chance to shadow them with producer_not_completed.
    if [ "$p" = "$c" ]; then
      fail_pair "$c" "$p" "self_consume" "$(first_of_csv "$pathcsv")"
      return 0
    fi
    if ! blocked_by_has "$c" "$p"; then
      fail_pair "$c" "$p" "not_blocked_on_producer" "$(first_of_csv "$pathcsv")"
      return 0
    fi
    produces=$(produces_of "$p")
    IFS=',' read -r -a plist <<< "$pathcsv"
    for path in "${plist[@]+"${plist[@]}"}"; do
      if ! in_set "$path" "$produces"; then
        fail_pair "$c" "$p" "not_produced" "$path"
        return 0
      fi
    done
    pstat=$(task_status "$p")
    if [ "$pstat" != "completed" ]; then
      fail_pair "$c" "$p" "producer_not_completed" "$(first_of_csv "$pathcsv")"
      return 0
    fi
    i=$((i + 1))
  done

  local c_root
  c_root=$(resolve_tree "$c")
  local landed_snapshot
  landed_snapshot=$(landed_paths_of "$c")

  # Phase C: preflight every path of every pair. No blob is written here;
  # dest_walk may mkdir scaffolding, which rollback_run reverts if any later
  # pair of this same consumer fails.
  local -a row_start=() row_root=()
  local -a act_path=() act_kind=() act_mode=() act_oid=() act_parent=()
  local p_root reason mo mode oid dw parent dest tracked expect_sha dest_sha kind
  i=0
  while [ "$i" -lt "$n" ]; do
    p="${ROW_P[$i]}"
    pathcsv="${ROW_PATHS[$i]}"
    p_root=$(resolve_tree "$p")
    row_root[i]="$p_root"
    row_start[i]="${#act_path[@]}"
    IFS=',' read -r -a plist <<< "$pathcsv"

    if [ "$c_root" = "$p_root" ]; then
      for path in "${plist[@]+"${plist[@]}"}"; do
        reason=$(lexical_check "$path")
        if [ -n "$reason" ]; then
          fail_pair "$c" "$p" "$reason" "$path"
          return 0
        fi
        mo=$(source_check "$p_root" "$path")
        case "$mo" in
          REASON:*)
            fail_pair "$c" "$p" "${mo#REASON:}" "$path"
            return 0
            ;;
        esac
        oid="${mo##*:}"
        act_path[${#act_path[@]}]="$path"
        act_kind[${#act_kind[@]}]="same_tree"
        act_mode[${#act_mode[@]}]=""
        act_oid[${#act_oid[@]}]="$oid"
        act_parent[${#act_parent[@]}]=""
      done
      i=$((i + 1))
      continue
    fi

    for path in "${plist[@]+"${plist[@]}"}"; do
      reason=$(lexical_check "$path")
      if [ -n "$reason" ]; then
        fail_pair "$c" "$p" "$reason" "$path"
        return 0
      fi
      mo=$(source_check "$p_root" "$path")
      case "$mo" in
        REASON:*)
          fail_pair "$c" "$p" "${mo#REASON:}" "$path"
          return 0
          ;;
      esac
      mode="${mo#OK:}"
      mode="${mode%%:*}"
      oid="${mo##*:}"
      oid_valid "$oid" || {
        fail_pair "$c" "$p" "git_error" "$path"
        return 0
      }

      dw=$(dest_walk "$c_root" "$path")
      case "$dw" in
        REASON:*)
          fail_pair "$c" "$p" "${dw#REASON:}" "$path"
          return 0
          ;;
      esac
      parent="${dw#OK:}"
      dest="$c_root/$path"

      kind="copy"
      if [ -e "$dest" ]; then
        tracked=0
        git -C "$c_root" ls-files --error-unmatch -- "$path" > /dev/null 2>&1 && tracked=1
        expect_sha=$(git -C "$p_root" cat-file blob "$oid" 2> /dev/null | hash_stdin)
        dest_sha=$(hash_stdin < "$dest" 2> /dev/null || printf '')
        if [ "$tracked" -eq 1 ]; then
          if [ "$dest_sha" = "$expect_sha" ]; then
            kind="already_present"
          else
            fail_pair "$c" "$p" "dest_tracked" "$path"
            return 0
          fi
        else
          if [ "$dest_sha" = "$expect_sha" ]; then
            kind="idempotent"
          elif in_set "$path" "$landed_snapshot"; then
            kind="copy"
          else
            fail_pair "$c" "$p" "dest_exists" "$path"
            return 0
          fi
        fi
      fi

      act_path[${#act_path[@]}]="$path"
      act_kind[${#act_kind[@]}]="$kind"
      act_mode[${#act_mode[@]}]="$mode"
      act_oid[${#act_oid[@]}]="$oid"
      act_parent[${#act_parent[@]}]="$parent"
    done
    i=$((i + 1))
  done

  # Write pass: every pair cleared preflight; now write. A failure here rolls
  # back every file/dir this consumer created so far, across every pair.
  local total="${#act_path[@]}"
  local -a act_sha=() act_copy=() act_grew=()
  local j=0 base sha any_copy_c=0 grew_c=0 new_landed_total="[]"
  while [ "$j" -lt "$total" ]; do
    path="${act_path[$j]}"
    kind="${act_kind[$j]}"
    mode="${act_mode[$j]}"
    oid="${act_oid[$j]}"
    parent="${act_parent[$j]}"
    act_copy[j]=0
    act_grew[j]=0

    if [ "$kind" = "same_tree" ]; then
      # c_root == p_root for a same_tree pair (checked at preflight); hash
      # the blob the same way as every other kind, not git's own oid, so the
      # ok-row's sha256 field always means what its name says.
      sha=$(git -C "$c_root" cat-file blob "$oid" 2> /dev/null | hash_stdin)
    else
      # p_root for this entry: walk back to the owning row via row_start.
      local ri=0 owner=0
      while [ "$ri" -lt "$n" ]; do
        [ "${row_start[$ri]}" -le "$j" ] && owner="$ri"
        ri=$((ri + 1))
      done
      p_root="${row_root[$owner]}"
      base=$(basename -- "$path")
      if [ "$kind" = "copy" ] && [ "$DRY_RUN" -eq 0 ]; then
        mo=$(write_blob "$p_root" "$parent" "$base" "$oid" "$mode" "$c_root")
        case "$mo" in
          REASON:*)
            fail_pair "$c" "${ROW_P[$owner]}" "${mo#REASON:}" "$path"
            return 0
            ;;
        esac
        sha="${mo#OK:}"
        any_copy_c=1
        act_copy[j]=1
      elif [ "$kind" = "copy" ]; then
        sha=""
      else
        sha=$(git -C "$p_root" cat-file blob "$oid" 2> /dev/null | hash_stdin)
      fi
      if [ "$kind" != "already_present" ]; then
        if ! in_set "$path" "$landed_snapshot"; then
          grew_c=1
          act_grew[j]=1
        fi
        new_landed_total=$(printf '%s' "$new_landed_total" | jq -c --arg p "$path" '. + [$p]')
      fi
    fi
    act_sha[j]="$sha"
    j=$((j + 1))
  done

  # Ledger meta write: one write for the whole consumer. A same-tree-only
  # consumer never touches landed_paths.
  if [ "$DRY_RUN" -eq 0 ] && { [ "$any_copy_c" -eq 1 ] || [ "$grew_c" -eq 1 ]; }; then
    if ! commit_landed "$c" "$new_landed_total"; then
      rollback_run
      die 2 "state-patch.sh failed writing landed_paths for $c; files rolled back"
    fi
  fi
  # This consumer's writes are now durable (or never happened); a later
  # consumer's failure must never roll these back.
  WRITTEN_FILES=()
  CREATED_DIRS=()

  # Audit rows: exactly one ok row per selected pair.
  i=0
  while [ "$i" -lt "$n" ]; do
    local start="${row_start[$i]}" end row_files="[]" row_any_copy=0 row_grew=0 row_mode
    if [ "$((i + 1))" -lt "$n" ]; then end="${row_start[$((i + 1))]}"; else end="$total"; fi
    j="$start"
    while [ "$j" -lt "$end" ]; do
      row_files=$(printf '%s' "$row_files" \
        | jq -c --arg path "${act_path[$j]}" --arg sha "${act_sha[$j]}" '. + [{path: $path, sha256: $sha}]')
      [ "${act_copy[$j]}" -eq 1 ] && row_any_copy=1
      [ "${act_grew[$j]}" -eq 1 ] && row_grew=1
      j=$((j + 1))
    done
    row_mode="already_present"
    [ "${row_root[$i]}" = "$c_root" ] && row_mode="same_tree"
    [ "$row_any_copy" -eq 1 ] && row_mode="copied"
    if [ "$BOUNDARY" -eq 1 ] || [ "$row_any_copy" -eq 1 ] || [ "$row_grew" -eq 1 ]; then
      ok_row "$c" "${ROW_P[$i]}" "$row_mode" "$row_files"
    fi
    i=$((i + 1))
  done
}

# ---------- declaration parsing per candidate consumer ----------
# Emits pairs as "consumer<TAB>producer<TAB>path1,path2,...". A malformed
# `consumes` shape emits "consumer<TAB>producer-or-?<TAB>BADDECL_MARK" instead
# of calling fail_pair itself: this function is read through a `$(...)`
# command substitution, which runs in a subshell, so a side effect here (like
# fail_pair's RUN_RC=1) would never reach the parent shell's exit code.
collect_pairs() {
  local cid raw
  local -a candidates=()
  if [ -n "$CONSUMER_ARG" ]; then
    candidates[0]="$CONSUMER_ARG"
  else
    while IFS= read -r cid; do
      [ -n "$cid" ] && candidates[${#candidates[@]}]="$cid"
    done <<< "$(jqf '(.tasks // {}) | keys[]?')"
  fi

  for cid in "${candidates[@]+"${candidates[@]}"}"; do
    raw=$(consumes_json "$cid")
    [ "$raw" = "null" ] && continue
    local shape
    shape=$(printf '%s' "$raw" | jq -r '
      if type != "array" then "bad"
      elif any(.[]; (type != "object") or (has("from")|not) or (has("paths")|not)
                    or (.from|type != "string") or (.paths|type != "array")
                    or ((.paths|length) < 1) or any(.paths[]; type != "string")) then "bad"
      else "ok" end' 2> /dev/null || printf 'bad')
    if [ "$shape" != "ok" ]; then
      printf '%s\t%s\t%s\n' "$cid" "${PRODUCER_ARG:-?}" "$BADDECL_MARK"
      continue
    fi
    local from_ids
    from_ids=$(printf '%s' "$raw" | jq -r --arg p "$PRODUCER_ARG" \
      'map(.from) | unique | .[] | select($p == "" or . == $p)')
    [ -n "$from_ids" ] || continue
    local fid pathset
    while IFS= read -r fid; do
      [ -n "$fid" ] || continue
      pathset=$(printf '%s' "$raw" | jq -r --arg f "$fid" \
        '[.[] | select(.from == $f) | .paths[]] | unique | join(",")')
      printf '%s\t%s\t%s\n' "$cid" "$fid" "$pathset"
    done <<< "$from_ids"
  done
}

# ---------- main ----------
CONSUMER_ARG=""
PRODUCER_ARG=""
STATE_ARG=""
ORCH_ROOT=""
DRY_RUN=0
CMD="land"
RUN_RC=0
BOUNDARY=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --consumer)
      [ "$#" -ge 2 ] || usage
      CONSUMER_ARG="$2"
      shift 2
      ;;
    --producer)
      [ "$#" -ge 2 ] || usage
      PRODUCER_ARG="$2"
      shift 2
      ;;
    --state)
      [ "$#" -ge 2 ] || usage
      STATE_ARG="$2"
      shift 2
      ;;
    --orch-root)
      [ "$#" -ge 2 ] || usage
      ORCH_ROOT="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --list-landed)
      CMD="list-landed"
      shift
      ;;
    --self-test)
      CMD="self-test"
      shift
      ;;
    -h | --help) usage ;;
    *)
      printf >&2 'unknown argument: %s\n' "$1"
      usage
      ;;
  esac
done

if [ "$CMD" = "self-test" ]; then
  self="$(dirname "${BASH_SOURCE[0]}")/land-artifacts-selftest.sh"
  [ -x "$self" ] || die 2 "self-test harness unreachable at $self"
  exec bash "$self"
fi

command -v jq > /dev/null 2>&1 || die 2 "jq is required"
command -v git > /dev/null 2>&1 || die 2 "git is required"
[ -n "$HASHER_KIND" ] || die 2 "no sha256 hasher (sha256sum or shasum) found"

if [ -n "$STATE_ARG" ]; then
  STATE_PATH="$STATE_ARG"
else
  STATE_PATH="$(resolve_state)"
fi
[ -r "$STATE_PATH" ] || die 2 "ledger unreadable: $STATE_PATH"
jq -e . "$STATE_PATH" > /dev/null 2>&1 || die 2 "ledger is not valid JSON: $STATE_PATH"

if [ "$CMD" = "list-landed" ]; then
  jq -r "$LANDED_UNION_JQ" "$STATE_PATH" 2> /dev/null || true
  exit 0
fi

[ -n "$CONSUMER_ARG" ] || [ -n "$PRODUCER_ARG" ] || usage

if [ -n "$CONSUMER_ARG" ]; then
  valid_task_id "$CONSUMER_ARG" || die 2 "malformed --consumer id: $CONSUMER_ARG"
  task_exists "$CONSUMER_ARG" || die 2 "unknown --consumer id: $CONSUMER_ARG"
fi
if [ -n "$PRODUCER_ARG" ]; then
  valid_task_id "$PRODUCER_ARG" || die 2 "malformed --producer id: $PRODUCER_ARG"
  task_exists "$PRODUCER_ARG" || die 2 "unknown --producer id: $PRODUCER_ARG"
  BOUNDARY=1
fi

git_hygiene

# flush_consumer <C>: dispatches every row buffered for the just-finished
# consumer before moving to the next one (all its pairs, one decision).
flush_consumer() {
  local c="$1"
  [ -n "$c" ] || return 0
  [ "${#ROW_P[@]}" -gt 0 ] || return 0
  process_consumer "$c"
  ROW_P=()
  ROW_PATHS=()
}

# collect_pairs emits every candidate's rows contiguously (one outer loop per
# consumer id, never revisited), so grouping on "id changed" is exact.
CUR_C=""
ROW_P=()
ROW_PATHS=()
while IFS=$'\t' read -r cid pid pathcsv; do
  [ -n "$cid" ] || continue
  if [ "$cid" != "$CUR_C" ]; then
    flush_consumer "$CUR_C"
    CUR_C="$cid"
  fi
  ROW_P[${#ROW_P[@]}]="$pid"
  ROW_PATHS[${#ROW_PATHS[@]}]="$pathcsv"
done <<< "$(collect_pairs)"
flush_consumer "$CUR_C"

exit "$RUN_RC"

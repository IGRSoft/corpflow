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
# @arg --check-path <path>
#                          Sole mode: needs no ledger, makes no git call. Runs the
#                          same lexical ladder every landing does; safe prints
#                          nothing (exit 0), refused prints `reason=<token>` on
#                          stdout (exit 1). Combined with any other mode, or a
#                          missing value, exits 2.
# @arg --list-landed --tree <path> [--strict] [--state <path>]
#                          Print the landed set scoped to that tree, one path
#                          per line. Missing or unresolvable --tree exits 2.
#                          Empty output is exit 0. --strict (valid only here)
#                          re-checks every raw landed_paths entry of that tree's
#                          rows against the lexical ladder before printing; a
#                          non-string entry or one the ladder refuses prints
#                          nothing on stdout, one line on stderr, and exits 1.
# @arg --self-test        Exec the sibling land-artifacts-selftest.sh harness.
#                          Must be the only argument on the command line.
# @arg -h | --help        Show this header.
#
# @exitcode 0  Landed, same tree, already present, gate no-op, boundary-skipped
#              `blocked` consumer, boundary-skipped non-pending consumer (warn
#              row), nothing selected, a safe --check-path, or a clean --strict
#              --list-landed.
# @exitcode 1  A consumer's landing failed: it is now `blocked`, a fail
#              `contract_landed` row was written; or --check-path refused the
#              path; or --strict found an unsafe entry in the tree's landed set.
# @exitcode 2  Usage, malformed id, unreadable/invalid ledger, missing
#              jq/git/hasher, or a failed state-patch.sh write (this run's own
#              files were rolled back first).
#
# Minimum shell: bash 3.2+ (macOS default).

set -euo pipefail
IFS=$'\n\t'
# ASCII-only collation for every allow-list `case` below: a UTF-8 locale can
# admit non-ASCII letters into ranges like [A-Za-z...], which would break the
# "porcelain never quotes a landed path" premise this ladder depends on.
export LC_ALL=C

# The one landed-set exclusion expression, scoped to the tree that received
# the landing (`landed_roots`), never a global union. Every other transport
# (hook, technical-lead.md, project-manager.md, state-ledger.md) carries this
# SAME string, always evaluated with `--arg root <tree>`; a parity test diffs
# them, so a change here without the others is a test failure, not a typo.
readonly LANDED_SET_JQ='[(.tasks // {})[] | .metadata | select(any(.landed_roots // [] | arrays | .[]; . == $root)) | .landed_paths // [] | arrays | .[] | strings | select(test("\\A[A-Za-z0-9._@+/-]+\\z"))] | unique | .[]'

# Sentinel carried through the collect_pairs TSV stream for a candidate whose
# `consumes` shape is invalid. Kept out of the producer-id column so it can
# never collide with a real `DV[0-9]+` id.
readonly BADDECL_MARK='__BADDECL__'

usage() {
  sed -n '2,44s/^# \{0,1\}//p' "$0" >&2
  CONTRACT_EXIT=1
  exit 2
}

die() {
  local code="$1"
  shift
  printf >&2 'land-artifacts: %s\n' "$*"
  CONTRACT_EXIT=1
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
      .claude | .github | .mcp.json | .envrc | .gitattributes | .gitmodules)
        printf 'reserved_destination'
        return 0
        ;;
    esac
  done
  if printf '%s' "$p" | grep -q '[[:cntrl:]]'; then
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
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_CONFIG_PARAMETERS \
    GIT_CONFIG_COUNT GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_NOSYSTEM \
    GIT_ATTR_SOURCE GIT_REPLACE_REF_BASE GIT_NAMESPACE GIT_CEILING_DIRECTORIES
  # A numbered GIT_CONFIG_KEY_n/VALUE_n pair injects arbitrary config values;
  # the count above is unbounded, so every exported name matching the prefix
  # must go, not just a fixed range.
  local envname
  for envname in $(compgen -e 'GIT_CONFIG_KEY_' 2> /dev/null) $(compgen -e 'GIT_CONFIG_VALUE_' 2> /dev/null); do
    unset "$envname"
  done
  export GIT_LITERAL_PATHSPECS=1
}

# ---------- git wrapper: every call disables fsmonitor, none trust a hook ----------
git_run() {
  git -c core.fsmonitor=false "$@"
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
  done < <(git_run -C "$root" ls-files -s -z -- "$p" 2> /dev/null)
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
    git_run -C "$root" check-attr -z filter -- "$p" 2> /dev/null \
      | { IFS= read -r -d '' _p || true
        IFS= read -r -d '' _a || true
        IFS= read -r -d '' _v || true
        printf '%s' "${_v:-}"; }
  ) || filt=""
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

  if git_run -C "$root" diff --quiet --no-ext-diff --no-textconv -- "$p" 2> /dev/null; then
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
# Globals read: DRY_RUN. Globals written: CREATED_DIRS (append), DW_RESULT.
# Must be called directly, never through `$(...)`: a command substitution
# forks a subshell, so the CREATED_DIRS append below would never reach the
# caller and rollback_run would have nothing to undo. Sets
# DW_RESULT="OK:<phys_parent>" or "REASON:<reason>"; always returns 0.
DW_RESULT=""
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
        DW_RESULT='REASON:symlink_segment'
        return 0
      fi
      if [ -e "$full" ]; then
        if [ ! -d "$full" ]; then
          DW_RESULT='REASON:not_dir'
          return 0
        fi
      elif [ "$DRY_RUN" -eq 0 ]; then
        mkdir -m 755 -- "$full" || {
          DW_RESULT='REASON:not_dir'
          return 0
        }
        CREATED_DIRS[${#CREATED_DIRS[@]}]="$full"
        if [ -L "$full" ]; then
          DW_RESULT='REASON:symlink_segment'
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
      DW_RESULT='REASON:not_dir'
      return 0
    }
  else
    # --dry-run only: the parent chain was validated but not created above.
    # Best-effort physical anchor: the deepest existing ancestor, plus the
    # still-missing suffix appended as text (it cannot be a symlink yet).
    phys_parent="$(phys_resolve_partial "$c_root" "$parent")" || {
      DW_RESULT='REASON:not_dir'
      return 0
    }
  fi

  case "$phys_parent/" in
    "$c_root"/*) : ;;
    *)
      DW_RESULT='REASON:dest_escape'
      return 0
      ;;
  esac

  local dest="$c_root/$p"
  if [ -L "$dest" ]; then
    DW_RESULT='REASON:symlink_dest'
    return 0
  fi
  if [ -e "$dest" ] && [ ! -f "$dest" ]; then
    DW_RESULT='REASON:dest_not_regular'
    return 0
  fi
  DW_RESULT="OK:$phys_parent"
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

# Set to 1 immediately before every intentional exit (usage, die, --check-path,
# --list-landed, the `|| exit 2` sites, the final exit "$RUN_RC"); left "" for
# a signal or an errexit stop no site named. An unmarked exit can be read as
# neither "already blocked" (1) nor "already landed" (0), so cleanup_trap rolls
# back this run's writes and exits 2; a marked non-0/1 exit rolls back too.
CONTRACT_EXIT=""

# shellcheck disable=SC2329 # invoked only through the EXIT trap below
cleanup_trap() {
  local rc=$?
  # A second signal would re-enter the signal trap and cut rollback short.
  trap '' INT TERM HUP
  if [ -n "$TMP_LIVE" ] && [ -e "$TMP_LIVE" ]; then
    rm -f -- "$TMP_LIVE"
  fi
  if [ -z "$CONTRACT_EXIT" ]; then
    rollback_run
    rc=2
  elif [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
    rollback_run
    rc=2
  fi
  exit "$rc"
}
trap cleanup_trap EXIT
# A signal always reaches the EXIT trap unmarked, even if it lands between a
# CONTRACT_EXIT=1 assignment and the exit statement right after it.
trap 'CONTRACT_EXIT=""; exit 2' INT TERM HUP

# mv flavor that refuses to follow a symlink-to-dir destination: GNU has -T,
# BSD/macOS has -h. Detected once so a same-uid race during the move below
# cannot rename our tmp file inside a raced directory.
MV_NOFOLLOW=""
if { mv --version 2> /dev/null || true; } | grep -q GNU; then
  MV_NOFOLLOW="-T"
elif { mv 2>&1 || true; } | grep -q -- '-h'; then
  MV_NOFOLLOW="-h"
fi

# write_blob <producer_root> <phys_parent> <base> <oid> <index_mode> <consumer_root>
# Globals written: TMP_LIVE, WRITTEN_FILES (append), WB_RESULT. Must be called
# directly, never through `$(...)`: see dest_walk's contract note above; the
# same subshell defect here would make WRITTEN_FILES/TMP_LIVE invisible to
# rollback_run and to the EXIT trap. Sets WB_RESULT="OK:<sha256>",
# "REASON:<reason>", or "REASON:dest_race:<stray-path>" when a raced
# directory resolves outside consumer_root (left in place, named for the
# caller instead of removed). Always returns 0.
WB_RESULT=""
write_blob() {
  local p_root="$1" parent="$2" base="$3" oid="$4" idxmode="$5" c_root="$6"
  local tmp
  tmp=$(mktemp "$parent/.land-artifacts.XXXXXX") || {
    WB_RESULT='REASON:git_error'
    return 0
  }
  TMP_LIVE="$tmp"

  if ! git_run -C "$p_root" cat-file blob "$oid" > "$tmp" 2> /dev/null; then
    rm -f -- "$tmp"
    TMP_LIVE=""
    WB_RESULT='REASON:git_error'
    return 0
  fi

  # Anchor on git's own object id before sha256 is trusted: both reads share
  # one failure source (a corrupt `cat-file`), so a second sha256 read alone
  # would let that same corruption verify itself.
  local check=""
  check=$(git_run -C "$p_root" hash-object --no-filters --stdin < "$tmp" 2> /dev/null) || check=""
  if [ "$check" != "$oid" ]; then
    rm -f -- "$tmp"
    TMP_LIVE=""
    WB_RESULT='REASON:sha256_mismatch'
    return 0
  fi

  local sha=""
  sha=$(hash_stdin < "$tmp") || sha=""
  if [ -z "$sha" ]; then
    rm -f -- "$tmp"
    TMP_LIVE=""
    WB_RESULT='REASON:git_error'
    return 0
  fi
  local perm=644
  [ "$idxmode" = "100755" ] && perm=755
  chmod "$perm" -- "$tmp" || {
    rm -f -- "$tmp"
    TMP_LIVE=""
    WB_RESULT='REASON:git_error'
    return 0
  }

  local dest="$parent/$base"
  if [ -L "$dest" ] || [ -d "$dest" ]; then
    rm -f -- "$tmp"
    TMP_LIVE=""
    WB_RESULT='REASON:dest_race'
    return 0
  fi
  local -a mv_cmd=(mv -f)
  [ -n "$MV_NOFOLLOW" ] && mv_cmd+=("$MV_NOFOLLOW")
  mv_cmd+=(-- "$tmp" "$dest")
  if ! "${mv_cmd[@]}"; then
    rm -f -- "$tmp" 2> /dev/null || true
    TMP_LIVE=""
    WB_RESULT='REASON:git_error'
    return 0
  fi
  TMP_LIVE=""

  if [ -e "$tmp" ]; then
    WB_RESULT='REASON:dest_race'
    return 0
  fi
  if [ -d "$dest" ] && [ ! -L "$dest" ]; then
    local stray_phys
    stray_phys="$(phys_dir "$dest" 2> /dev/null)" || stray_phys=""
    case "$stray_phys/" in
      "$c_root"/*)
        # Same-uid race replaced our file with a directory; rmdir (never
        # rm -rf) cleans up the stray only when it is still ours to touch.
        rmdir -- "$dest" 2> /dev/null || true
        WB_RESULT='REASON:dest_race'
        ;;
      *)
        # Outside the consumer root: removing it would reach beyond our
        # write boundary, so it is left in place and named for the caller.
        WB_RESULT="REASON:dest_race:${stray_phys:-$dest}"
        ;;
    esac
    return 0
  fi
  if [ ! -f "$dest" ] || [ -L "$dest" ]; then
    WB_RESULT='REASON:dest_race'
    return 0
  fi
  local reparent
  reparent=$(phys_dir "$parent") || reparent=""
  if [ "$reparent" != "$parent" ]; then
    WB_RESULT='REASON:dest_race'
    return 0
  fi
  local dest_sha=""
  dest_sha=$(hash_stdin < "$dest") || dest_sha=""
  if [ "$dest_sha" != "$sha" ]; then
    rm -f -- "$dest"
    WB_RESULT='REASON:sha256_mismatch'
    return 0
  fi

  WRITTEN_FILES[${#WRITTEN_FILES[@]}]="$dest:$sha"
  WB_RESULT="OK:$sha"
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

# resolve_tree <task-id> -> "root<TAB>banner_path<TAB>raw_toplevel", or dies
# (tree_invalid is a hard stop: a wrong tree writing files is worse than any
# other refusal in this script). The three fields are every spelling this run
# saw of the same tree; a consumer caller unions them into landed_roots so a
# later re-pin under a different banner/orchestrator root still matches.
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
  local raw_toplevel toplevel
  raw_toplevel=$(git_run -C "$root" rev-parse --show-toplevel 2> /dev/null) || \
    die 2 "tree_invalid: $id tree is not a git worktree: $root"
  toplevel=$(phys_dir "$raw_toplevel") || die 2 "tree_invalid: $id toplevel does not resolve: $raw_toplevel"
  [ "$toplevel" = "$root" ] || die 2 "tree_invalid: $id resolved root $root != its own toplevel $toplevel"
  printf '%s\t%s\t%s' "$root" "$path" "$raw_toplevel"
}

# resolve_tree_root <task-id> -> just the physical root (producer-side calls
# never need the extra spellings; only the consumer row records landed_roots).
resolve_tree_root() {
  local out
  out=$(resolve_tree "$1") || { CONTRACT_EXIT=1; exit 2; }
  printf '%s' "${out%%$'\t'*}"
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
# fail_pair <C> <P> <reason> <path> [<stray>]
# Rolls back this run's writes for C, blocks C, writes one fail audit row.
# <stray> names a raced destination that was left in place rather than
# removed (dest_race outside the consumer root); optional, omitted when empty.
fail_pair() {
  local c="$1" p="$2" reason="$3" path="$4" stray="${5:-}"
  rollback_run
  if [ "$DRY_RUN" -eq 1 ]; then
    printf >&2 'land-artifacts: %s -> %s refused: %s (%s) [dry-run: no ledger write]\n' \
      "$p" "$c" "$reason" "$path"
    RUN_RC=1
    return 0
  fi
  local meta
  if [ -n "$stray" ]; then
    meta=$(jq -cn --arg reason "$reason" --arg path "$path" --arg producer "$p" --arg stray "$stray" \
      '{reason: $reason, path: $path, producer: $producer, stray: $stray}')
  else
    meta=$(jq -cn --arg reason "$reason" --arg path "$path" --arg producer "$p" \
      '{reason: $reason, path: $path, producer: $producer}')
  fi
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

# commit_landed <C> <new_landed_json> <new_roots_json>
# The single --task-meta write for the whole consumer: jq's "*" merge
# replaces arrays wholesale, so every pair's new paths/roots must be folded
# into one union before the one write, not one write per pair. Existing
# entries are unioned and re-validated inside jq, as JSON values end to end —
# never split on a text newline — so a stored entry holding one can neither
# smuggle a non-string nor get laundered into two separate entries.
#
# Called through `if !`, which suppresses errexit for everything below: a jq
# call that fails silently here would otherwise fall through with stale data
# and still read as success, so every step needs its own explicit `|| return 1`.
commit_landed() {
  local c="$1" new_landed_json="$2" new_roots_json="$3"
  local existing_paths_json existing_roots_json union_paths union_roots set_body
  existing_paths_json=$(jq -c --arg id "$c" \
    '(.tasks[$id].metadata.landed_paths // []) | if type == "array" then . else [] end' \
    "$STATE_PATH" 2> /dev/null) || return 1
  existing_roots_json=$(jq -c --arg id "$c" \
    '(.tasks[$id].metadata.landed_roots // []) | if type == "array" then . else [] end' \
    "$STATE_PATH" 2> /dev/null) || return 1
  union_paths=$(jq -cn --argjson ex "$existing_paths_json" --argjson new "$new_landed_json" \
    '($ex + $new) | map(strings | select(test("\\A[A-Za-z0-9._@+/-]+\\z"))) | unique' \
    2> /dev/null) || return 1
  union_roots=$(jq -cn --argjson ex "$existing_roots_json" --argjson new "$new_roots_json" \
    '($ex + $new) | map(strings | select(length > 0 and startswith("/")
       and (explode | all(.[]; . >= 32 and . != 127)))) | unique' \
    2> /dev/null) || return 1
  set_body=$(jq -cn --argjson paths "$union_paths" --argjson roots "$union_roots" \
    '{landed_paths: $paths, landed_roots: $roots, landing_error: null}') || return 1
  state_patch --task-meta "$c" --set "$set_body"
}

# roots_would_grow <C> <root> <banner_path> <raw_toplevel> -> "true"/"false"
# Whether unioning these three spellings into C's existing landed_roots would
# add anything new; used to decide if a same-file re-pin still needs the
# meta write (a re-pinned tree with identical files still records its root).
roots_would_grow() {
  jqf --arg id "$1" --arg a "$2" --arg b "$3" --arg c "$4" \
    '(.tasks[$id].metadata.landed_roots // [] | arrays | map(select(type=="string"))) as $ex
     | (([$a, $b, $c] - $ex) | length) > 0'
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

  # Status is read before the declaration is ever inspected: a consumer this
  # pass has no business touching (already dispatched, or a producer rework
  # racing an in-flight/finished stream) must never be refused bad_declaration
  # for a shape it was never going to act on.
  local cstat
  cstat=$(task_status "$c")

  if [ "$BOUNDARY" -eq 1 ]; then
    case "$cstat" in
      blocked)
        # An earlier landing_error is kept; the gate re-lands after release.
        return 0
        ;;
      pending) : ;;
      *)
        # A producer rework must not flip an already-dispatched consumer to
        # blocked; Step 4.8's gate stays the sole authority over readiness.
        # Record why this pass took no action, without touching the row.
        if [ "$DRY_RUN" -eq 0 ]; then
          local paths_json="[]" meta
          if [ "${ROW_PATHS[0]}" != "$BADDECL_MARK" ]; then
            paths_json=$(printf '%s' "${ROW_PATHS[0]}" | tr ',' '\n' \
              | jq -R -s -c 'split("\n") | map(select(length > 0))')
          fi
          meta=$(jq -cn --arg producer "${ROW_P[0]}" --arg consumer "$c" --arg status "$cstat" \
            --argjson paths "$paths_json" \
            '{producer: $producer, consumer: $consumer, reason: "consumer_not_pending", status: $status, paths: $paths}')
          audit_row --actor orchestrator --action contract_landed --result warn \
            --subject "$c" --task-id "$c" --meta "$meta"
        fi
        return 0
        ;;
    esac
  elif [ "$cstat" != "pending" ]; then
    local badpath
    if [ "${ROW_PATHS[0]}" = "$BADDECL_MARK" ]; then
      badpath="-"
    else
      badpath="$(first_of_csv "${ROW_PATHS[0]}")"
    fi
    fail_pair "$c" "${ROW_P[0]}" "consumer_already_dispatched" "$badpath"
    return 0
  fi

  # Reached only for a pending consumer (boundary or gate): now the
  # declaration shape itself can be judged.
  if [ "${ROW_PATHS[0]}" = "$BADDECL_MARK" ]; then
    fail_pair "$c" "${ROW_P[0]}" "bad_declaration" "-"
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
    if [ "${#plist[@]}" -eq 0 ]; then
      fail_pair "$c" "$p" "bad_declaration" "-"
      return 0
    fi
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

  # Every spelling this run saw of C's own tree: the writer unions them into
  # landed_roots on success, so a later re-pin under a different
  # banner/orchestrator root still matches the exclusion at read time.
  # resolve_tree's die runs inside a command substitution, which bash does not
  # propagate through `read <<<`; an unchecked empty root would turn every
  # destination below into an absolute path, so its status is checked here.
  local c_root c_banner_path c_toplevel_raw tree_line
  tree_line=$(resolve_tree "$c") || { CONTRACT_EXIT=1; exit 2; }
  IFS=$'\t' read -r c_root c_banner_path c_toplevel_raw <<< "$tree_line"
  [ -n "$c_root" ] || die 2 "tree_invalid: $c resolved to an empty root"
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
    p_root=$(resolve_tree_root "$p") || { CONTRACT_EXIT=1; exit 2; }
    [ -n "$p_root" ] || die 2 "tree_invalid: $p resolved to an empty root"
    row_root[i]="$p_root"
    row_start[i]="${#act_path[@]}"
    IFS=',' read -r -a plist <<< "$pathcsv"
    if [ "${#plist[@]}" -eq 0 ]; then
      fail_pair "$c" "$p" "bad_declaration" "-"
      return 0
    fi

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
        oid_valid "$oid" || {
          fail_pair "$c" "$p" "git_error" "$path"
          return 0
        }
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

      dest_walk "$c_root" "$path"
      dw="$DW_RESULT"
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
        git_run -C "$c_root" ls-files --error-unmatch -- "$path" > /dev/null 2>&1 && tracked=1
        expect_sha=$(git_run -C "$p_root" cat-file blob "$oid" 2> /dev/null | hash_stdin) || expect_sha=""
        if [ -z "$expect_sha" ]; then
          fail_pair "$c" "$p" "git_error" "$path"
          return 0
        fi
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
  local j=0 base sha any_copy_c=0 grew_c=0 saw_cross_tree_c=0 new_landed_total="[]" ri owner
  while [ "$j" -lt "$total" ]; do
    path="${act_path[$j]}"
    kind="${act_kind[$j]}"
    mode="${act_mode[$j]}"
    oid="${act_oid[$j]}"
    parent="${act_parent[$j]}"
    act_copy[j]=0
    act_grew[j]=0

    # p_root for this entry: walk back to the owning row via row_start. Needed
    # for both branches below (a same_tree row's p_root equals c_root too),
    # so this runs once per entry rather than duplicated per branch.
    ri=0
    owner=0
    while [ "$ri" -lt "$n" ]; do
      [ "${row_start[$ri]}" -le "$j" ] && owner="$ri"
      ri=$((ri + 1))
    done
    p_root="${row_root[$owner]}"

    if [ "$kind" = "same_tree" ]; then
      # c_root == p_root for a same_tree pair (checked at preflight); hash
      # the blob the same way as every other kind, not git's own oid, so the
      # ok-row's sha256 field always means what its name says.
      sha=$(git_run -C "$c_root" cat-file blob "$oid" 2> /dev/null | hash_stdin) || sha=""
      if [ -z "$sha" ]; then
        fail_pair "$c" "${ROW_P[$owner]}" "git_error" "$path"
        return 0
      fi
    else
      saw_cross_tree_c=1
      base=$(basename -- "$path")
      if [ "$kind" = "copy" ] && [ "$DRY_RUN" -eq 0 ]; then
        write_blob "$p_root" "$parent" "$base" "$oid" "$mode" "$c_root"
        mo="$WB_RESULT"
        case "$mo" in
          REASON:dest_race:*)
            fail_pair "$c" "${ROW_P[$owner]}" "dest_race" "$path" "${mo#REASON:dest_race:}"
            return 0
            ;;
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
        sha=$(git_run -C "$p_root" cat-file blob "$oid" 2> /dev/null | hash_stdin) || sha=""
        if [ -z "$sha" ]; then
          fail_pair "$c" "${ROW_P[$owner]}" "git_error" "$path"
          return 0
        fi
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

  # landed_roots grows only when this consumer actually crossed trees this
  # run (a same-tree-only consumer records neither); a re-pin that
  # lands identical files still needs its root recorded even without a copy.
  local new_roots_json roots_grew_c=0
  new_roots_json=$(jq -cn --arg a "$c_root" --arg b "$c_banner_path" --arg c "$c_toplevel_raw" \
    '[$a, $b, $c] | unique')
  if [ "$saw_cross_tree_c" -eq 1 ] \
    && [ "$(roots_would_grow "$c" "$c_root" "$c_banner_path" "$c_toplevel_raw")" = "true" ]; then
    roots_grew_c=1
  fi

  # Ledger meta write: one write for the whole consumer. A same-tree-only
  # consumer never touches landed_paths or landed_roots.
  if [ "$DRY_RUN" -eq 0 ] && { [ "$any_copy_c" -eq 1 ] || [ "$grew_c" -eq 1 ] || [ "$roots_grew_c" -eq 1 ]; }; then
    if ! commit_landed "$c" "$new_landed_total" "$new_roots_json"; then
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
    if [ "$BOUNDARY" -eq 1 ] || [ "$row_any_copy" -eq 1 ] || [ "$row_grew" -eq 1 ] \
      || { [ "$roots_grew_c" -eq 1 ] && [ "${row_root[$i]}" != "$c_root" ]; }; then
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
  local cid raw keys
  local -a candidates=()
  if [ -n "$CONSUMER_ARG" ]; then
    candidates[0]="$CONSUMER_ARG"
  else
    # A `done <<< "$(...)"` would discard jq's status and read a failed query
    # as "no candidates", exiting 0 with nothing landed.
    keys=$(jqf '(.tasks // {}) | keys[]?') || exit 2
    while IFS= read -r cid; do
      valid_task_id "$cid" || continue
      candidates[${#candidates[@]}]="$cid"
    done <<< "$keys"
  fi

  for cid in "${candidates[@]+"${candidates[@]}"}"; do
    raw=$(consumes_json "$cid") || exit 2
    [ "$raw" = "null" ] && continue
    local shape
    shape=$(printf '%s' "$raw" | jq -r '
      if type != "array" then "bad"
      elif any(.[]; (type != "object") or (has("from")|not) or (has("paths")|not)
                    or (.from|type != "string") or (.paths|type != "array")
                    or ((.paths|length) < 1) or any(.paths[]; type != "string")
                    or (.from|test("\\ADV[0-9]+\\z")|not)
                    or any(.paths[]; test("[\t\n\r,]"))
                    or any(.paths[]; length == 0)) then "bad"
      else "ok" end' 2> /dev/null || printf 'bad')
    if [ "$shape" != "ok" ]; then
      # At the boundary, a malformed declaration is only this producer's
      # business if it names this producer somewhere in the raw shape; a row
      # that never mentions $p is silently not this pass's concern.
      if [ -n "$PRODUCER_ARG" ]; then
        # jq -e: 1 is a real "does not name $p", anything above is a failure.
        local named=0
        printf '%s' "$raw" | jq -e --arg p "$PRODUCER_ARG" \
          '(type == "array") and any(.[]?; (type == "object") and (.from == $p))' \
          > /dev/null 2>&1 || named=$?
        [ "$named" -le 1 ] || exit 2
        [ "$named" -eq 0 ] || continue
        printf '%s\t%s\t%s\n' "$cid" "$PRODUCER_ARG" "$BADDECL_MARK"
      else
        printf '%s\t%s\t%s\n' "$cid" "?" "$BADDECL_MARK"
      fi
      continue
    fi
    local from_ids
    from_ids=$(printf '%s' "$raw" | jq -r --arg p "$PRODUCER_ARG" \
      'map(.from) | unique | .[] | select($p == "" or . == $p)') || exit 2
    [ -n "$from_ids" ] || continue
    local fid pathset
    while IFS= read -r fid; do
      [ -n "$fid" ] || continue
      pathset=$(printf '%s' "$raw" | jq -r --arg f "$fid" \
        '[.[] | select(.from == $f) | .paths[]] | unique | join(",")') || exit 2
      printf '%s\t%s\t%s\n' "$cid" "$fid" "$pathset"
    done <<< "$from_ids"
  done
}

# ---------- main ----------
CONSUMER_ARG=""
PRODUCER_ARG=""
STATE_ARG=""
ORCH_ROOT=""
TREE_ARG=""
DRY_RUN=0
CMD="land"
RUN_RC=0
BOUNDARY=0
CHECKPATH_ARG=""
CHECKPATH_GIVEN=0
STRICT=0

# Captured once, before any shift: --self-test's "sole argument" rule needs
# the original argc, since by the time --self-test is reached mid-loop the
# preceding args are already consumed and $# alone would look like 1.
ARGC=$#

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
    --tree)
      [ "$#" -ge 2 ] || usage
      TREE_ARG="$2"
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
    --check-path)
      [ "$#" -ge 2 ] || usage
      CHECKPATH_ARG="$2"
      CHECKPATH_GIVEN=1
      shift 2
      ;;
    --strict)
      STRICT=1
      shift
      ;;
    --self-test)
      [ "$ARGC" -eq 1 ] || die 2 "--self-test takes no other arguments"
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

# --check-path is the sole mode: no ledger is resolved and no git call is made,
# so a caller can validate a path before a ledger even exists.
if [ "$CHECKPATH_GIVEN" -eq 1 ]; then
  if [ -n "$CONSUMER_ARG" ] || [ -n "$PRODUCER_ARG" ] || [ "$CMD" = "list-landed" ] \
    || [ -n "$TREE_ARG" ] || [ "$DRY_RUN" -eq 1 ] || [ "$STRICT" -eq 1 ]; then
    die 2 "--check-path is the sole mode"
  fi
  checkpath_reason=$(lexical_check "$CHECKPATH_ARG")
  if [ -n "$checkpath_reason" ]; then
    printf 'reason=%s\n' "$checkpath_reason"
    CONTRACT_EXIT=1
    exit 1
  fi
  CONTRACT_EXIT=1
  exit 0
fi

[ "$STRICT" -eq 0 ] || [ "$CMD" = "list-landed" ] || die 2 "--strict is only valid with --list-landed --tree <path>"

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
  [ -n "$TREE_ARG" ] || die 2 "--list-landed requires --tree <path>"
  root=$(phys_dir "$TREE_ARG") || die 2 "--tree does not resolve: $TREE_ARG"
  if [ "$STRICT" -eq 1 ]; then
    # jq classifies before bash sees the value: a control character (a newline
    # above all) would split one entry across lines or be trimmed by $( ).
    while IFS= read -r raw_entry; do
      case "$raw_entry" in
        N) strict_reason="bad_path" ;;
        C) strict_reason="control_char" ;;
        S*) strict_reason=$(lexical_check "${raw_entry#S}") ;;
        *) strict_reason="bad_path" ;;
      esac
      if [ -n "$strict_reason" ]; then
        printf >&2 'land-artifacts: landed set for --tree holds an unsafe entry (reason=%s)\n' "$strict_reason"
        CONTRACT_EXIT=1
        exit 1
      fi
    done < <(jq -r --arg root "$root" \
      '[(.tasks // {})[] | .metadata | select(any(.landed_roots // [] | arrays | .[]; . == $root)) | .landed_paths // [] | arrays | .[]] | .[]
       | if type != "string" then "N" elif (explode | any(.[]; . < 32 or . == 127)) then "C" else "S" + . end' \
      "$STATE_PATH" 2> /dev/null || printf 'N\n')
  fi
  jq -r --arg root "$root" "$LANDED_SET_JQ" "$STATE_PATH" 2> /dev/null || true
  CONTRACT_EXIT=1
  exit 0
fi

[ -z "$TREE_ARG" ] || die 2 "--tree is only valid with --list-landed"

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
# consumer id, never revisited), so grouping on "id changed" is exact. Its
# subshell status is checked here, before any consumer is processed, so a
# failed ledger read exits 2 with nothing dispatched.
PAIRS=$(collect_pairs) || die 2 "ledger read failed while collecting consumes declarations"
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
done <<< "$PAIRS"
flush_consumer "$CUR_C"

CONTRACT_EXIT=1
exit "$RUN_RC"

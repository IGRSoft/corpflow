#!/usr/bin/env bash
# @description Resolve membershipExceptions conflicts in an Xcode project file by sorted union.
#
#   Narrow by design. It resolves exactly one conflict class: a merge conflict
#   whose every line, on both sides, is an entry of a synchronized-build-file
#   `membershipExceptions = ( ... );` list. Both sides are kept, deduplicated and
#   emitted in LC_ALL=C sort order. Dropping either side silently unregisters
#   test files: the build stays green and those tests never run again.
#
#   Anything else REFUSES the whole file — a conflict elsewhere in the project,
#   a comment or blank line inside a side, nested or unterminated markers, or a
#   diff3 base section. Partial resolution would leave some markers gone and
#   some present, inviting a `git add` of a half-resolved project file.
#
#   Usage:
#     bash resolve-pbxproj-membership.sh --file App.xcodeproj/project.pbxproj
#     bash resolve-pbxproj-membership.sh --file <path> --dry-run
#     bash resolve-pbxproj-membership.sh --self-test
#
# @arg --file <path>   Project file to resolve in place (required).
# @arg --dry-run       Print the resolved result to stdout; write nothing.
# @arg --self-test     Run built-in tests against temp fixtures; exit non-zero on fail.
# @arg -h, --help      Show usage.
#
# @exitcode 0  Union written; or no conflict present (no-op); or --dry-run; or --self-test passed.
# @exitcode 1  Refusal (out-of-class input, message prefixed "refusing:") or usage error.
# @exitcode 2  awk not found.
#
# Minimum Bash: 3.2. Tested on macOS + Linux.
set -Eeuo pipefail
shopt -s inherit_errexit 2> /dev/null || true
IFS=$'\n\t'
trap 'printf >&2 "error: %s:%d (exit %d)\n" "${BASH_SOURCE[0]}" "$LINENO" "$?"' ERR

# Cleanup rides EXIT, not RETURN: refuse() and die() terminate with `exit`,
# which never fires a RETURN trap, and every refusal path allocates temp files.
TMPFILES=()
cleanup_tmp() {
  [[ "${#TMPFILES[@]}" -gt 0 ]] && rm -f -- "${TMPFILES[@]}"
  return 0
}
trap cleanup_tmp EXIT

die() {
  printf >&2 'resolve-pbxproj-membership: %s\n' "$*"
  exit 1
}

# Refusal shares exit 1 with usage error, so the prefix is what distinguishes
# them for a caller (and for the contract tests).
refuse() {
  printf >&2 'resolve-pbxproj-membership: refusing: %s\n' "$*"
  exit 1
}

require_tools() {
  command -v awk > /dev/null 2>&1 || {
    printf >&2 'resolve-pbxproj-membership: awk is required but not found\n'
    exit 2
  }
}

# ---------------------------------------------------------------------------
# AWK_PARSER — linear state machine over the file.
#
# Two independent states: whether the cursor sits inside a membershipExceptions
# list, and conflict-marker state (0 outside, 1 ours, 2 theirs). A side is
# accepted only when every one of its lines matches the entry grammar, so a
# comment line — the shape that caused the original mis-join — refuses.
# ---------------------------------------------------------------------------
read -r -d '' AWK_PARSER << 'AWK' || true
# awk's exit runs END, so the first reason must win: a mid-file refusal would
# otherwise be relabelled "unterminated conflict" by the END guard below.
function refuse(msg) { refused = 1; printf "%s\n", msg > reasonfile; close(reasonfile); exit 1 }
function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
function is_entry(l) { return l ~ /^[[:space:]]*[^=(){};[:space:]][^=(){};]*,$/ }
function emit_union(   i, j, k) {
  for (i = 2; i <= n; i++) {          # insertion sort: entry lists are tens of items
    k = keys[i]
    for (j = i - 1; j >= 1 && keys[j] > k; j--) keys[j + 1] = keys[j]
    keys[j + 1] = k
  }
  for (i = 1; i <= n; i++) printf "%s%s\n", indent, keys[i]
}
BEGIN { state = 0; in_list = 0; n = 0; nconf = 0; indent = "" }
/^<<<<<<</ {
  if (state != 0) refuse("nested conflict start")
  if (!in_list) refuse("conflict outside membershipExceptions")
  state = 1; nconf++; n = 0; indent = ""; split("", seen)
  next
}
/^\|\|\|\|\|\|\|/ {
  # A base section means an entry may have been deliberately deleted on one
  # side; a union would silently resurrect it.
  refuse("diff3 base section present")
}
/^=======[[:space:]]*$/ {
  if (state != 1) refuse("unexpected conflict separator")
  state = 2
  next
}
/^>>>>>>>/ {
  if (state != 2) refuse("unexpected conflict end")
  state = 0
  emit_union()
  next
}
state != 0 {
  if ($0 ~ /^[[:space:]]*\);/) refuse("list close inside conflict")
  if (!is_entry($0)) refuse("non-entry line in conflict side")
  key = trim($0)
  if (!(key in seen)) { seen[key] = 1; keys[++n] = key }
  if (indent == "") { match($0, /^[[:space:]]*/); indent = substr($0, 1, RLENGTH) }
  next
}
{
  if ($0 ~ /membershipExceptions[[:space:]]*=[[:space:]]*\(/) in_list = 1
  # Unconditional, so a single-line `membershipExceptions = ( );` closes again:
  # a latched in_list would let a later conflict in some other ( ) list — files,
  # children — pass as in-class, and those entries satisfy the entry grammar.
  if (in_list && $0 ~ /\);/) in_list = 0
  print
}
END {
  if (refused) exit 1
  if (state != 0) refuse("unterminated conflict")
  printf "%d\n", nconf > countfile
  close(countfile)
}
AWK

# ---------------------------------------------------------------------------
# run_resolve <file> <dry_run>
# Parses into a mktemp buffer and mv -f's over the target only on accept, so a
# refusal cannot touch the file even on an unhandled error.
# ---------------------------------------------------------------------------
run_resolve() {
  local file="$1" dry_run="$2"

  [[ -f "$file" ]] || die "--file not found: $file"

  # Explicit template dir, not `mktemp -t`: macOS ignores TMPDIR for -t, and the
  # self-test needs its buffers inside a directory it can delete wholesale —
  # a $( ) subshell resets the EXIT trap, so cleanup_tmp cannot reach them.
  local tdir buf reasonfile countfile
  tdir="${RESOLVE_TMPDIR:-${TMPDIR:-/tmp}}"
  buf=$(mktemp "${tdir%/}/resolve-pbxproj-buf.XXXXXX")
  reasonfile=$(mktemp "${tdir%/}/resolve-pbxproj-reason.XXXXXX")
  countfile=$(mktemp "${tdir%/}/resolve-pbxproj-count.XXXXXX")
  TMPFILES+=("$buf" "$reasonfile" "$countfile")

  if ! LC_ALL=C awk -v reasonfile="$reasonfile" -v countfile="$countfile" \
    -- "$AWK_PARSER" "$file" > "$buf" 2> /dev/null; then
    local reason
    reason=$(cat -- "$reasonfile" 2> /dev/null || true)
    refuse "${reason:-parse failed} (${file})"
  fi

  local nconf
  nconf=$(cat -- "$countfile" 2> /dev/null || printf '0')

  if [[ "$nconf" -eq 0 ]]; then
    printf 'resolve-pbxproj-membership: no conflict found, nothing to do: %s\n' "$file"
    return 0
  fi

  if [[ "$dry_run" -eq 1 ]]; then
    printf '[dry-run] %s conflict(s) resolvable by sorted union in %s; file unchanged\n' \
      "$nconf" "$file" >&2
    cat -- "$buf"
    return 0
  fi

  # mktemp is 0600 and mv transfers the mode, so the target would silently lose
  # its permissions — invisible in a diff, since git tracks only the exec bit.
  # The format MUST stay attached to the flag: GNU's `-f` is --file-system and
  # takes no argument, so the separated form prints a filesystem block on stdout
  # while exiting 1, and `||` would concatenate that with the fallback.
  local mode
  mode=$(stat -f%Lp "$file" 2> /dev/null || stat -c%a "$file" 2> /dev/null || printf '644')
  [[ "$mode" =~ ^[0-7]+$ ]] || die "unusable mode from stat: ${mode}"
  chmod "$mode" "$buf"

  mv -f -- "$buf" "$file"
  printf 'resolve-pbxproj-membership: resolved %s conflict(s) by sorted union: %s\n' \
    "$nconf" "$file"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
OPT_FILE=""
OPT_DRY_RUN=0
SELF_TEST_MODE=0

usage() {
  cat >&2 << 'USAGE'
Usage: resolve-pbxproj-membership.sh --file <path> [OPTIONS]

Required:
  --file <path>            Xcode project file with a conflicted
                           membershipExceptions list

Optional:
  --dry-run                Print the resolved result; write nothing
  --self-test              Run built-in tests; exit non-zero on failure
  -h, --help               Show this help
USAGE
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)
      OPT_FILE="$2"
      shift 2
      ;;
    --file=*)
      OPT_FILE="${1#--file=}"
      shift
      ;;
    --dry-run)
      OPT_DRY_RUN=1
      shift
      ;;
    --self-test | self-test)
      SELF_TEST_MODE=1
      shift
      ;;
    -h | --help | help)
      usage
      ;;
    *)
      printf >&2 'resolve-pbxproj-membership: unknown option: %s\n' "$1"
      usage
      ;;
  esac
done

require_tools

if [[ "$SELF_TEST_MODE" -eq 1 ]]; then
  # Sourced HERE, not at the top: the harness is test code the production path
  # never runs. `[ -r ]` first, not a bare `.`: sourcing a missing file with the
  # `.` builtin is a special-builtin error that exits the shell immediately,
  # bypassing an `if ! . …` guard entirely.
  SELFTEST_LIB_PATH="$(dirname "${BASH_SOURCE[0]}")/resolve-pbxproj-membership-selftest.sh"
  if [ -r "$SELFTEST_LIB_PATH" ]; then
    # shellcheck source=resolve-pbxproj-membership-selftest.sh
    # shellcheck disable=SC1090
    . "$SELFTEST_LIB_PATH"
  else
    printf >&2 'resolve-pbxproj-membership: self-test harness unreachable at %s — plugin install broken\n' \
      "$SELFTEST_LIB_PATH"
    exit 2
  fi
  self_test
  exit $?
fi

[[ -n "$OPT_FILE" ]] || die "--file <path> is required"

run_resolve "$OPT_FILE" "$OPT_DRY_RUN"

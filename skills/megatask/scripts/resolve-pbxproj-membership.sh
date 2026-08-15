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
# Self-test
# ---------------------------------------------------------------------------
self_test() {
  require_tools

  local failures=0 pass_count=0 td
  td=$(mktemp -d -t resolve-pbxproj-selftest.XXXXXX)
  # shellcheck disable=SC2064
  trap "rm -rf '$td'; cleanup_tmp" EXIT
  local RESOLVE_TMPDIR="$td"
  export RESOLVE_TMPDIR

  st_pass() {
    pass_count=$((pass_count + 1))
    printf 'PASS: %s\n' "$1"
  }
  st_fail() {
    failures=$((failures + 1))
    printf 'FAIL: %s\n' "$1"
  }
  st_check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then st_pass "$desc"; else
      st_fail "$desc -- expected $(printf '%q' "$expected") got $(printf '%q' "$actual")"
    fi
  }

  # Fixture writers. Heredocs, not printf, so the conflict markers are literal.
  local clean="${td}/clean.pbxproj"
  cat > "$clean" << 'EOF'
		membershipExceptions = (
			Alpha.swift,
			Beta.swift,
		);
EOF

  local conflicted="${td}/conflicted.pbxproj"
  cat > "$conflicted" << 'EOF'
		membershipExceptions = (
<<<<<<< HEAD
			Beta.swift,
			Shared.swift,
=======
			Alpha.swift,
			Shared.swift,
>>>>>>> feature/x
		);
EOF

  # --- accept: sorted, deduplicated union -------------------------------
  local out rc
  out=$(run_resolve "$conflicted" 0 2>&1) && rc=0 || rc=$?
  st_check "accept: exit 0" "0" "$rc"
  if ! grep -q '<<<<<<<\|=======\|>>>>>>>' "$conflicted"; then
    st_pass "accept: no conflict markers remain"
  else
    st_fail "accept: markers still present"
  fi
  st_check "accept: sorted union body" \
    "$(printf '\t\t\tAlpha.swift,\n\t\t\tBeta.swift,\n\t\t\tShared.swift,')" \
    "$(sed -n '2,4p' "$conflicted")"
  st_check "accept: shared entry appears once" "1" \
    "$(grep -c 'Shared.swift' "$conflicted")"
  st_check "accept: list structure preserved" "		);" "$(sed -n '5p' "$conflicted")"

  # --- the target's mode survives the write -------------------------------
  local moded="${td}/moded.pbxproj"
  cat > "$moded" << 'EOF'
		membershipExceptions = (
<<<<<<< HEAD
			Beta.swift,
=======
			Alpha.swift,
>>>>>>> feature/x
		);
EOF
  chmod 640 "$moded"

  # Platform guard: a stat probe that prints to stdout while failing (GNU `-f`
  # given a format) yields a multi-line or non-numeric token, which chmod then
  # rejects. Assert the token's shape so that break is local, not Linux-only.
  local probe
  probe=$(stat -f%Lp "$moded" 2> /dev/null || stat -c%a "$moded" 2> /dev/null || printf '644')
  if [[ "$probe" =~ ^[0-7]+$ ]] && [[ "$(printf '%s' "$probe" | wc -l | tr -d ' ')" == "0" ]]; then
    st_pass "mode probe yields a single numeric token"
  else
    st_fail "mode probe yields an unusable token: $(printf '%q' "$probe")"
  fi

  run_resolve "$moded" 0 > /dev/null
  st_check "accept: file mode preserved" "640" \
    "$(stat -f%Lp "$moded" 2> /dev/null || stat -c%a "$moded" 2> /dev/null || printf '?')"

  # --- no-conflict input is a no-op --------------------------------------
  local before after
  before=$(cksum < "$clean")
  out=$(run_resolve "$clean" 0)
  after=$(cksum < "$clean")
  st_check "no-op: file byte-identical" "$before" "$after"
  case "$out" in
    *"no conflict found"*) st_pass "no-op: reports nothing to do" ;;
    *) st_fail "no-op: unexpected output: $out" ;;
  esac

  # --- dry-run writes nothing --------------------------------------------
  local dryfix="${td}/dry.pbxproj"
  cat > "$dryfix" << 'EOF'
		membershipExceptions = (
<<<<<<< HEAD
			Beta.swift,
=======
			Alpha.swift,
>>>>>>> feature/x
		);
EOF
  before=$(cksum < "$dryfix")
  out=$(run_resolve "$dryfix" 1 2> /dev/null)
  after=$(cksum < "$dryfix")
  st_check "dry-run: file untouched" "$before" "$after"
  case "$out" in
    *Alpha.swift*Beta.swift*) st_pass "dry-run: prints the resolved result" ;;
    *) st_fail "dry-run: result not printed" ;;
  esac

  # --- refusals: each leaves the file byte-identical ----------------------
  st_refuse() {
    local desc="$1" fixture="$2" want="$3" b a rc msg
    b=$(cksum < "$fixture")
    # `&& … || …` keeps the ERR trap quiet: a refusal here is the expected
    # outcome, and the trap's diagnostic would read like a self-test failure.
    msg=$(run_resolve "$fixture" 0 2>&1) && rc=0 || rc=$?
    a=$(cksum < "$fixture")
    if [[ "$rc" -eq 1 ]]; then st_pass "$desc: exit 1"; else st_fail "$desc: exit $rc"; fi
    case "$msg" in
      *"refusing: ${want}"*) st_pass "$desc: reason '$want'" ;;
      *) st_fail "$desc: wrong reason: $msg" ;;
    esac
    st_check "$desc: file byte-identical" "$b" "$a"
  }

  local outside="${td}/outside.pbxproj"
  cat > "$outside" << 'EOF'
		buildSettings = {
<<<<<<< HEAD
			SWIFT_VERSION = 6.0;
=======
			SWIFT_VERSION = 5.9;
>>>>>>> feature/x
		};
EOF
  st_refuse "outside" "$outside" "conflict outside membershipExceptions"

  local diff3="${td}/diff3.pbxproj"
  cat > "$diff3" << 'EOF'
		membershipExceptions = (
<<<<<<< HEAD
			Beta.swift,
||||||| base
			Gamma.swift,
=======
			Alpha.swift,
>>>>>>> feature/x
		);
EOF
  st_refuse "diff3" "$diff3" "diff3 base section present"

  local commented="${td}/commented.pbxproj"
  cat > "$commented" << 'EOF'
		membershipExceptions = (
<<<<<<< HEAD
			/* added by #12 */
			Beta.swift,
=======
			Alpha.swift,
>>>>>>> feature/x
		);
EOF
  st_refuse "comment" "$commented" "non-entry line in conflict side"

  # A single-line `membershipExceptions = ( );` must not latch in_list on, or a
  # later conflict in an unrelated ( ) list would be accepted as in-class.
  local latch="${td}/latch.pbxproj"
  cat > "$latch" << 'EOF'
		membershipExceptions = ( );
		children = (
<<<<<<< HEAD
			Beta.swift,
=======
			Alpha.swift,
>>>>>>> feature/x
		);
EOF
  st_refuse "single-line list" "$latch" "conflict outside membershipExceptions"

  local nested="${td}/nested.pbxproj"
  cat > "$nested" << 'EOF'
		membershipExceptions = (
<<<<<<< HEAD
			Beta.swift,
<<<<<<< HEAD
			Gamma.swift,
=======
			Alpha.swift,
>>>>>>> feature/x
		);
EOF
  st_refuse "nested" "$nested" "nested conflict start"

  local unterminated="${td}/unterminated.pbxproj"
  cat > "$unterminated" << 'EOF'
		membershipExceptions = (
<<<<<<< HEAD
			Beta.swift,
=======
			Alpha.swift,
EOF
  st_refuse "unterminated" "$unterminated" "unterminated conflict"

  local spanning="${td}/spanning.pbxproj"
  cat > "$spanning" << 'EOF'
		membershipExceptions = (
<<<<<<< HEAD
			Beta.swift,
		);
=======
			Alpha.swift,
		);
>>>>>>> feature/x
EOF
  st_refuse "spanning" "$spanning" "list close inside conflict"

  # All-or-nothing: one in-class conflict plus one out-of-class refuses both.
  local mixed="${td}/mixed.pbxproj"
  cat > "$mixed" << 'EOF'
		membershipExceptions = (
<<<<<<< HEAD
			Beta.swift,
=======
			Alpha.swift,
>>>>>>> feature/x
		);
		buildSettings = {
<<<<<<< HEAD
			SWIFT_VERSION = 6.0;
=======
			SWIFT_VERSION = 5.9;
>>>>>>> feature/x
		};
EOF
  st_refuse "all-or-nothing" "$mixed" "conflict outside membershipExceptions"

  trap - EXIT
  rm -rf "$td"

  if [[ "$failures" -eq 0 ]]; then
    printf 'resolve-pbxproj-membership: self-test OK (%d checks passed)\n' "$pass_count"
    return 0
  else
    printf 'resolve-pbxproj-membership: self-test FAILED (%d/%d checks failed)\n' \
      "$failures" "$((failures + pass_count))"
    return 1
  fi
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
  self_test
  exit $?
fi

[[ -n "$OPT_FILE" ]] || die "--file <path> is required"

run_resolve "$OPT_FILE" "$OPT_DRY_RUN"

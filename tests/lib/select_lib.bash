#!/usr/bin/env bash
# select_lib.bash — pure selection library for the change→test dependency matrix.
#
# No `set`/`IFS`/`export` at file scope: bats `load` is `source` and does not reset
# shell options, so arming errexit here would arm it inside every @test body.
# The library never invokes git and never reads the environment — that is what lets
# guards aim the real entry point at a synthetic tree.
# Empty stdout + exit 0 is the only "nothing found" signal; non-zero means a fault.

[ -n "${SEL_LIB_SOURCED:-}" ] && return 0
SEL_LIB_SOURCED=1

SEL_ROOT=""
SEL_TESTS_DIR=""
SEL_MATRIX=""
SEL_INDEX_FILE=""

# Script basename -> .bats basename, where the test file legitimately does not echo
# the script name. An unlisted mismatch is a coverage gap, which is the point.
# Keep in lockstep with sel_alias_keys: coverage-proxy C6 iterates the keys and
# re-resolves each here, so a key with no arm fails loudly.
sel_alias_for() {
  [ "$#" -eq 1 ] || return 2
  local _owner _alias
  case "$1" in
    dv-comment-density-gate.sh) echo "comment-density-gate.bats" ;;
    audit-dedup.sh) echo "agent-coordination__audit-dedup.bats" ;;
    # A self-test body under hooks/lib/ is exercised by its OWNING hook's .bats.
    # Resolved through this table rather than by stripping the suffix, because
    # the owner may itself be aliased — dv-comment-density-gate-selftest.sh has
    # to reach comment-density-gate.bats, and a plain strip would leave it
    # unmapped and fail the whole selection closed to FULL.
    *-selftest.sh)
      _owner="${1%-selftest.sh}.sh"
      _alias="$(sel_alias_for "$_owner")"
      if [ -n "$_alias" ]; then echo "$_alias"; else echo "${_owner%.sh}.bats"; fi
      ;;
    *) echo "" ;;
  esac
}

sel_alias_keys() {
  printf '%s\n' \
    dv-comment-density-gate.sh \
    audit-dedup.sh | LC_ALL=C sort
}

# Candidate scripts under an arbitrary root, so callers can be pointed at a
# synthetic tree and proven to fail. Empty output when the root is absent.
sel_all_scripts() {
  local root="$1"
  (
    cd "$root" 2>/dev/null || exit 0
    ls hooks/*.sh 2>/dev/null
    find .claude/hooks -name '*.sh' -type f 2>/dev/null
    find skills -path '*/scripts/*.sh' -type f 2>/dev/null
  ) | sort -u
}

# Resolve a script basename to its dedicated .bats under $2, or print nothing.
# `LC_ALL=C sort` makes a multi-match stable; `find` alone is filesystem order.
sel_resolve_bats() {
  [ "$#" -eq 2 ] || return 2
  local base="$1" troot="$2" want f
  want="$(sel_alias_for "$base")"
  [ -z "$want" ] && want="${base%.sh}.bats"
  f="$(find "$troot" -name "$want" -type f 2>/dev/null | LC_ALL=C sort | head -1)"
  # Some tests retain the .sh in their name (branch-name.sh -> branch-name.sh.bats).
  [ -z "$f" ] && f="$(find "$troot" -name "${base}.bats" -type f 2>/dev/null | LC_ALL=C sort | head -1)"
  echo "$f"
}

# --- context -----------------------------------------------------------------

sel_context_init() {
  [ "$#" -ge 1 ] || return 1
  sel_context_free
  [ -d "$1" ] || return 1
  SEL_ROOT="${1%/}"
  SEL_TESTS_DIR="${2:-$SEL_ROOT/tests/shell}"
  SEL_MATRIX="${3:-$SEL_ROOT/tests/selection/matrix.tsv}"
  SEL_INDEX_FILE=""
  return 0
}

sel_context_free() {
  [ -n "${SEL_INDEX_FILE:-}" ] && [ -f "$SEL_INDEX_FILE" ] && rm -f "$SEL_INDEX_FILE"
  SEL_ROOT=""; SEL_TESTS_DIR=""; SEL_MATRIX=""; SEL_INDEX_FILE=""
  return 0
}

# --- glob dialect ------------------------------------------------------------
# bash 3.2 `case` globs: `*` crosses `/`, there is no globstar and no brace
# expansion. `**` is a readability synonym collapsed to `*`. Alternation cannot be
# delegated to `case` — `|` is syntax, parsed before the pattern variable expands,
# so an alternation arriving in a variable is a literal character. Split it here.
sel_glob_match() {
  local glob="$1" path="$2" alt
  while :; do
    case "$glob" in
      *'**'*) glob="${glob%%'**'*}*${glob#*'**'}" ;;
      *) break ;;
    esac
  done
  while [ -n "$glob" ]; do
    case "$glob" in
      *'|'*) alt="${glob%%|*}"; glob="${glob#*|}" ;;
      *)     alt="$glob";       glob="" ;;
    esac
    [ -n "$alt" ] || continue
    case "$path" in $alt) return 0 ;; esac
  done
  return 1
}

# --- matrix ------------------------------------------------------------------
# Emits `<glob>\t<targets>\t<rule>\t<rationale>` per data row, or a single
# `FULL\tF7\t<detail>` record when the file is unreadable or malformed.
# The `|| [ -n "$line" ]` guard is mandatory: without it a file with no trailing
# newline silently drops its last row. The tab count is taken from the RAW line
# because `set -- $line` under IFS=tab collapses empty middle fields and folds a
# 5th field into the 4th — both fail open, and an empty rationale must be F7.
sel_matrix_rows() {
  local line lineno=0 tabs old_ifs
  if [ -z "${SEL_MATRIX:-}" ] || [ ! -r "$SEL_MATRIX" ]; then
    printf 'FULL\tF7\tmatrix missing or unreadable: %s\n' "${SEL_MATRIX:-<unset>}"
    return 0
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    case "$line" in ''|'#'*) continue ;; esac
    tabs="${line//[!$'\t']/}"
    if [ "${#tabs}" -ne 3 ]; then
      printf 'FULL\tF7\tmatrix.tsv:%s: %s tabs, want 3\n' "$lineno" "${#tabs}"
      return 0
    fi
    old_ifs=$IFS; IFS=$'\t'; set -f
    set -- $line
    set +f; IFS=$old_ifs
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
      printf 'FULL\tF7\tmatrix.tsv:%s: empty field\n' "$lineno"
      return 0
    fi
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"
  done < "$SEL_MATRIX"
  return 0
}

# --- discovery ---------------------------------------------------------------

sel_all_bats() {
  [ -n "${SEL_TESTS_DIR:-}" ] || return 1
  [ -d "$SEL_TESTS_DIR" ] || return 0
  find "$SEL_TESTS_DIR" -type f -name '*.bats' 2>/dev/null \
    | sed "s#^$SEL_ROOT/##" | LC_ALL=C sort
}

# The floor of every scoped run. A constant, not matrix rows: ALWAYS is not
# glob-driven and a matrix edit must not be able to delete it.
sel_always_set() {
  local b
  for b in tests/shell/lib/test-helper.bats \
           tests/shell/meta/coverage-proxy.bats \
           tests/shell/skills/plugin-root-refs.bats \
           tests/shell/worktask/manifest-parity.bats; do
    [ -f "$SEL_ROOT/$b" ] || continue
    printf 'BATS\t%s\tL3\tALWAYS\n' "$b"
  done
}

# --- L1 ----------------------------------------------------------------------
# Demand-driven: one `grep -l -F -f <changed paths>` pass over the .bats set.
# Materialising the forward inverse index costs ~200x for a map queried for 1-5
# paths. `grep -F` is substring, not path-anchored, so `hooks/agent-stop.sh` also
# matches a mention of `.claude/hooks/agent-stop.sh` — over-selection, the safe
# direction. Do not "fix" that into an anchored match; anchoring fails open.
sel_l1_consumers() {
  [ "$#" -ge 1 ] || return 0
  local pat rc=0 p bats=()
  while IFS= read -r p; do [ -n "$p" ] && bats+=("$SEL_ROOT/$p"); done <<< "$(sel_all_bats)"
  [ "${#bats[@]}" -gt 0 ] || return 0
  pat="$(sel_tmpfile)" || return 1
  for p in "$@"; do
    [ -n "$p" ] && printf '%s\n' "$p"
  done | grep -v '^[[:space:]]*$' > "$pat"
  # An empty or blank-bearing pattern file is the fail-open trap: GNU grep -f
  # matches nothing on empty, everything on a blank line. Both are silent.
  if [ ! -s "$pat" ]; then rm -f "$pat"; return 0; fi
  grep -l -F -f "$pat" -- "${bats[@]}" 2>/dev/null | sed "s#^$SEL_ROOT/##" | LC_ALL=C sort || rc=0
  rm -f "$pat"
  return 0
}

# Full inverse index `<referenced-path>\t<bats-rel-path>`. Guard suite only —
# O(repo) per call, which M4/M7 pay once at test time and the hot path never does.
sel_build_index() {
  [ -n "${SEL_ROOT:-}" ] || return 1
  local pat srcs b rel
  pat="$(sel_tmpfile)" || return 1
  find "$SEL_ROOT" \( -name .git -o -name vendor -o -name .build -o -name node_modules \) -prune \
    -o -type f -print 2>/dev/null \
    | sed "s#^$SEL_ROOT/##" | grep -v '^tests/vendor/' | grep -v '^[[:space:]]*$' \
    | LC_ALL=C sort -u > "$pat"
  if [ ! -s "$pat" ]; then rm -f "$pat"; return 0; fi
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    b="$SEL_ROOT/$rel"
    grep -o -F -f "$pat" -- "$b" 2>/dev/null | LC_ALL=C sort -u \
      | while IFS= read -r srcs; do
          [ -n "$srcs" ] && printf '%s\t%s\n' "$srcs" "$rel"
        done
  done <<< "$(sel_all_bats)"
  rm -f "$pat"
  return 0
}

sel_tmpfile() {
  local t
  t="$(mktemp "${TMPDIR:-/tmp}/sel.XXXXXX" 2>/dev/null)" || return 1
  printf '%s\n' "$t"
}

# --- fail-closed scopes ------------------------------------------------------
# F5 foundation: shared plumbing whose change invalidates every scoped answer.
# The selector is on its own list — when it changes, its output is not evidence.
sel_is_foundation() {
  case "$1" in
    tests/lib/test_helper.bash|tests/lib/select_lib.bash|tests/bin/select-tests.sh) return 0 ;;
    tests/selection/matrix.tsv|run-tests.sh|Makefile) return 0 ;;
    tests/vendor/*) return 0 ;;
  esac
  return 1
}

# F4 is deliberately narrow: a delete under these roots can silently drop coverage
# (a renamed .bats is invisible to any content glob). Deletes of agent, command and
# skill docs resolve normally — under --no-renames they surface as an A+D pair that
# the same L2 glob matches, so nothing is lost.
sel_is_failclosed_delete_scope() {
  case "$1" in
    tests/*|hooks/*|.claude/hooks/*) return 0 ;;
    skills/*/scripts/*|skills/*/*/scripts/*) return 0 ;;
  esac
  return 1
}

# --- the engine --------------------------------------------------------------
# Emits `BATS\t<rel>\t<layer>\t<rule>` and/or `FULL\t<Fn>\t<detail>`. Never emits
# L3: ALWAYS is a run-level floor, which is what lets M10 assert "delete a row ->
# this target is no longer selected" without ALWAYS noise.
#
# Two deliberate inversions of skills/self-improvement/scripts/map-and-filter.sh,
# whose numbered glob->target `case` this mirrors:
#   1. Its `*)` arm DISCARDS on no-match. Here no-match is FULL/F3. Discarding is
#      correct when filtering proposals and catastrophic when selecting tests.
#   2. It is first-match. Here every matching row contributes — agents/developer.md
#      must fire R01 AND R04, and a first-match engine drops R01 and looks correct.
sel_select_for_path() {
  [ "$#" -ge 1 ] || return 1
  local path="$1" status="${2:-M}" matched=0 row glob targets rule t consumer base resolved

  if sel_is_foundation "$path"; then
    printf 'FULL\tF5\t%s is shared foundation\n' "$path"
    return 0
  fi
  if [ "$status" = "D" ] && sel_is_failclosed_delete_scope "$path"; then
    printf 'FULL\tF4\t%s deleted under a fail-closed root\n' "$path"
    return 0
  fi

  # A changed .bats selects itself. Not a matrix row: no test names its own path,
  # so L1 cannot see this edge and a static target column cannot express "self".
  case "$path" in
    tests/shell/*.bats)
      if [ -f "$SEL_ROOT/$path" ]; then
        printf 'BATS\t%s\tL1\tSELF\n' "$path"
        matched=1
      fi
      ;;
  esac

  while IFS= read -r consumer; do
    [ -n "$consumer" ] || continue
    printf 'BATS\t%s\tL1\tPATHREF\n' "$consumer"
    matched=1
  done <<< "$(sel_l1_consumers "$path")"

  case "$path" in
    *.sh)
      base="${path##*/}"
      resolved="$(sel_resolve_bats "$base" "$SEL_TESTS_DIR")"
      if [ -n "$resolved" ]; then
        printf 'BATS\t%s\tL1\tCONV\n' "${resolved#$SEL_ROOT/}"
        matched=1
      fi
      ;;
  esac

  while IFS= read -r row; do
    [ -n "$row" ] || continue
    case "$row" in
      "FULL	"*) printf '%s\n' "$row"; return 0 ;;
    esac
    glob="${row%%	*}"; row="${row#*	}"
    targets="${row%%	*}"; row="${row#*	}"
    rule="${row%%	*}"
    sel_glob_match "$glob" "$path" || continue
    matched=1
    [ "$targets" = "NONE" ] && continue
    if [ "$targets" = "FULL" ]; then
      printf 'FULL\t%s\tglob %s forces the full suite\n' "$rule" "$glob"
      return 0
    fi
    local old_ifs=$IFS
    IFS=','; set -f; set -- $targets; set +f; IFS=$old_ifs
    for t in "$@"; do
      [ -n "$t" ] || continue
      printf 'BATS\ttests/shell/%s.bats\tL2\t%s\n' "$t" "$rule"
    done
  done <<< "$(sel_matrix_rows)"

  [ "$matched" -eq 1 ] || printf 'FULL\tF3\t%s matches no L1 edge and no matrix row\n' "$path"
  return 0
}

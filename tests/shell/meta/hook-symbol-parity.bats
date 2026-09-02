#!/usr/bin/env bats
# tests/shell/meta/hook-symbol-parity.bats
# Target: the shared hook library's symbol surface versus what hooks/ calls.
#
# A renamed or deleted library symbol is the failure most likely to actually
# happen, and it is silent at runtime: every consumer degrades to a fail-open
# allow rather than erroring, which is correct behaviour and therefore invisible.
# This is the check that makes the rename loud, at CI, in one place.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

LIB="${BATS_TEST_DIRNAME}/../../../hooks/model-switch-lib.sh"
HOOKDIR="${BATS_TEST_DIRNAME}/../../../hooks"

# Every corpflow_* token any hook mentions, library included.
_referenced() {
  grep -rhoE 'corpflow_[a-z_]+' "$HOOKDIR" | sort -u
}

# Every corpflow_* the library defines, by definition syntax alone.
_defined() {
  grep -oE '^corpflow_[a-z_]+\(\)' "$LIB" | sed 's/()//' | sort -u
}

# Every corpflow_* the library freezes with readonly -f.
_frozen() {
  sed -n '/^readonly -f/,/[^\\]$/p' "$LIB" | grep -oE 'corpflow_[a-z_]+' | sort -u
}

@test "P1: every corpflow_* referenced under hooks/ is defined by the library" {
  local missing
  missing="$(comm -23 <(_referenced) <(_defined))"
  [ -z "$missing" ] || fail "referenced but not defined in $LIB: $missing"
}

@test "P2: every defined symbol is readonly -f'd" {
  # readonly -f is what makes self-test isolation un-violable rather than merely
  # checkable: a body that tried to redefine a symbol is refused outright.
  local unfrozen
  unfrozen="$(comm -23 <(_defined) <(_frozen))"
  [ -z "$unfrozen" ] || fail "defined but not readonly -f'd: $unfrozen"
}

@test "P3: readonly -f names nothing the library does not define" {
  local phantom
  phantom="$(comm -13 <(_defined) <(_frozen))"
  [ -z "$phantom" ] || fail "readonly -f names an undefined symbol: $phantom"
}

@test "P4: ANTI-VACUITY — a planted reference to a nonexistent symbol is caught" {
  # Without this the whole file passes trivially the day the greps stop matching.
  local wd="$(mk_tmpworkdir)"
  cp -R "$HOOKDIR" "$wd/hooks"
  printf '\ncorpflow_no_such_symbol "$CTX"\n' >> "$wd/hooks/model-switch-gate.sh"
  local missing
  missing="$(comm -23 \
    <(grep -rhoE 'corpflow_[a-z_]+' "$wd/hooks" | sort -u) \
    <(_defined))"
  [ "$missing" = "corpflow_no_such_symbol" ]
}

@test "P5: every consumer sources the library under the guarded idiom" {
  # `[ -f ]` alone does not cover a TRUNCATED library: a syntax error in a sourced
  # file is fatal under set -e and `||` cannot rescue it. The $- save/restore is
  # what keeps that from turning a fail-open hook into a hard block.
  local f
  for f in model-switch-gate model-switch-audit test-execution-gate state-merge; do
    grep -q 'set +e' "$HOOKDIR/$f.sh" \
      || fail "$f.sh sources the library without dropping -e first"
    grep -qE 'case "\$_[cC][fF]_[oO][pP][tT][sS]" in \*e\*\) set -e' "$HOOKDIR/$f.sh" \
      || fail "$f.sh does not restore -e from a captured \$-"
    grep -q 'command -v corpflow_audit_row' "$HOOKDIR/$f.sh" \
      || fail "$f.sh has no symbol probe after the source"
  done
}

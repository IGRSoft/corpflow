#!/usr/bin/env bats
# tests/shell/meta/coverage-proxy.bats
# Target: the test suite itself.
#
# Every executable script under hooks/, .claude/hooks/ and skills/**/scripts/
# must have a dedicated .bats driving it. This is the standing guard against the
# class of gap that motivated this worktask: dv-comment-density-gate.sh,
# comment-standard-context.sh and the three capture adapters all shipped wired
# into plugin.json with zero tests, and nothing in the suite noticed.
#
# It is a PROXY, not a coverage measurement: it proves a dedicated test file
# exists and is non-trivial, not that the script's branches are exercised.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"
load "${BATS_TEST_DIRNAME}/../../lib/select_lib.bash"

# A file below this many @tests is a placeholder, not coverage.
MIN_TESTS=3

# The resolver lives in select_lib.bash so this checker and the change→test
# selector cannot drift apart: a third alias added there is seen by both.
_alias_for() { sel_alias_for "$@"; }

# Exemptions: scripts allowed to ship without a dedicated .bats.
# EMPTY BY DESIGN — every script in the tree is covered as of Phase 3. Adding an
# entry here is a visible decision that must carry its justification inline, so
# that dropping coverage costs a reviewed diff rather than a silent omission.
_is_exempt() {
  case "$1" in
    *) return 1 ;;
  esac
}

_all_scripts() { sel_all_scripts "$@"; }

_resolve_bats() { sel_resolve_bats "$@"; }

# Prints one "<script><TAB><reason>" line per uncovered script; silent when clean.
_scan_gaps() {
  local root="$1" troot="$2" s base f n
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    base="$(basename "$s")"
    _is_exempt "$base" && continue
    f="$(_resolve_bats "$base" "$troot")"
    if [ -z "$f" ]; then
      printf '%s\tno-dedicated-bats\n' "$s"
      continue
    fi
    n="$(grep -c '^@test' "$f" 2>/dev/null || true)"
    n="${n:-0}"
    [ "$n" -lt "$MIN_TESTS" ] && printf '%s\tonly-%s-tests\n' "$s" "$n"
  done < <(_all_scripts "$root")
  return 0
}

# --- the gate ---------------------------------------------------------------

@test "C1: the script inventory is non-empty and plausible" {
  # Without this, a broken enumeration would make every assertion below pass
  # vacuously — the exact failure mode this file exists to prevent.
  run _all_scripts "$PLUGIN_ROOT"
  assert_success
  [ "${#lines[@]}" -ge 40 ] || fail "only ${#lines[@]} scripts discovered; expected >= 40"
}

@test "C2: every hook and skill script has a dedicated .bats with >= MIN_TESTS" {
  run _scan_gaps "$PLUGIN_ROOT" "$PLUGIN_ROOT/tests/shell"
  assert_success
  assert_output ""
}

@test "C3: each hooks/*.sh resolves individually and is named in the failure message" {
  local s base f n
  while IFS= read -r s; do
    base="$(basename "$s")"
    f="$(_resolve_bats "$base" "$PLUGIN_ROOT/tests/shell")"
    [ -n "$f" ] || fail "hooks/$base has no dedicated .bats"
    n="$(grep -c '^@test' "$f" || true)"
    [ "${n:-0}" -ge "$MIN_TESTS" ] || fail "$base -> $(basename "$f") has only ${n:-0} @test"
  done < <(ls "$PLUGIN_ROOT"/hooks/*.sh)
}

# --- falsification: the gate must be able to go red -------------------------

@test "C4: a synthetic tree with an untested and an under-tested script is reported" {
  local wd; wd="$(mk_tmpworkdir)"
  mkdir -p "$wd/hooks" "$wd/t"

  printf '#!/bin/bash\n' > "$wd/hooks/covered.sh"
  printf '#!/bin/bash\n' > "$wd/hooks/thin.sh"
  printf '#!/bin/bash\n' > "$wd/hooks/absent.sh"

  printf '@test "a" {\n :\n}\n@test "b" {\n :\n}\n@test "c" {\n :\n}\n' > "$wd/t/covered.bats"
  printf '@test "a" {\n :\n}\n@test "b" {\n :\n}\n' > "$wd/t/thin.bats"

  run _scan_gaps "$wd" "$wd/t"
  assert_success
  refute_output --partial "covered.sh"
  assert_output --partial "hooks/thin.sh	only-2-tests"
  assert_output --partial "hooks/absent.sh	no-dedicated-bats"
  [ "${#lines[@]}" -eq 2 ] || fail "expected exactly 2 gaps, got ${#lines[@]}: $output"
}

@test "C5: a script whose .bats is renamed away is reported as a gap" {
  # Mirrors the manual acceptance check (rename a real .bats, watch this go red)
  # so the regression is executable rather than a one-off demonstration.
  local wd; wd="$(mk_tmpworkdir)"
  mkdir -p "$wd/skills/demo/scripts" "$wd/t"
  printf '#!/bin/bash\n' > "$wd/skills/demo/scripts/widget.sh"
  printf '@test "a" {\n :\n}\n@test "b" {\n :\n}\n@test "c" {\n :\n}\n' > "$wd/t/widget.bats"

  run _scan_gaps "$wd" "$wd/t"
  assert_success
  assert_output ""

  mv "$wd/t/widget.bats" "$wd/t/widget-renamed.bats"
  run _scan_gaps "$wd" "$wd/t"
  assert_success
  assert_output "skills/demo/scripts/widget.sh	no-dedicated-bats"
}

# --- hygiene: the alias and exemption tables must not rot -------------------

@test "C6: every alias names a script and a .bats that both still exist" {
  local base keys key_count=0
  keys="$(sel_alias_keys)"
  # Without the count guard this test passes vacuously on an empty key list —
  # the same failure mode C1 exists to prevent.
  while IFS= read -r base; do
    [ -n "$base" ] || continue
    key_count=$((key_count + 1))
    local want; want="$(_alias_for "$base")"
    [ -n "$want" ] || fail "alias table lost its entry for $base"
    run find "$PLUGIN_ROOT" -name "$base" -not -path '*/.git/*' -type f
    assert_success
    [ -n "$output" ] || fail "alias entry $base names a script that no longer exists"
    run find "$PLUGIN_ROOT/tests/shell" -name "$want" -type f
    assert_success
    [ -n "$output" ] || fail "alias entry $base -> $want names a .bats that no longer exists"
  done <<< "$keys"
  [ "$key_count" -ge 1 ] || fail "sel_alias_keys returned no keys; C6 would pass vacuously"
}

@test "C7: no exemption is stale — an exempt script must still exist" {
  # Vacuous while the table is empty; it is the guard that keeps a future
  # exemption from outliving the script that justified it.
  local s exempt_count=0
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    _is_exempt "$(basename "$s")" && exempt_count=$((exempt_count + 1))
  done < <(_all_scripts "$PLUGIN_ROOT")
  [ "$exempt_count" -eq 0 ] || fail "exemptions in use ($exempt_count); confirm each is still justified"
}

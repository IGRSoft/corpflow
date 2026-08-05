#!/usr/bin/env bats
# Contract tests for skills/csv-export-templates/scripts/validate-export.sh
# Contracts: exit 0 all-pass, exit 1 on violations, exit 2 usage/missing-dir.
# Writes a semicolon-delimited report (check;status;detail) with ;FAIL; rows on
# failure; --self-test runs internal pass+fail fixtures and exits 0.
#
# The report is asserted by check ID, not by counting rows. `grep -c ';PASS;'`
# + `refute_output "0"` passed as long as any single row of either kind existed:
# a validator that silently stopped emitting 16 of its 17 checks, or that moved a
# violation from one check to another, satisfied it.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/csv-export-templates/scripts/validate-export.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  PASS_FIX="${FIXTURES}/skills/csv-pass"
  FAIL_FIX="${FIXTURES}/skills/csv-fail"
}

# Prints "<check>;<status>" for every report row, header excluded.
report_ids() {
  tail -n +2 "$1" | cut -d';' -f1,2
}

@test "happy: a consistent 4-file export set passes (exit 0)" {
  cp "$PASS_FIX"/*.csv "$WD/"
  run_script "$SCRIPT" --dir "$WD" --out "$WD/report.csv"
  assert_success
  assert_output --partial "All checks PASSED"
  run head -1 "$WD/report.csv"
  assert_output "check;status;detail"
}

@test "happy: the clean run emits the exact expected check set, all PASS" {
  cp "$PASS_FIX"/*.csv "$WD/"
  run_script "$SCRIPT" --dir "$WD" --out "$WD/report.csv"
  assert_success
  run report_ids "$WD/report.csv"
  assert_output "format/file-01;PASS
format/file-04;PASS
format/file-07;PASS
format/file-13;PASS
sum/04-vs-13/SP-Min;PASS
sum/04-vs-13/SP-Max;PASS
sum/07-vs-13/Hours-Min;PASS
sum/07-vs-13/Hours-Max;PASS
sum/01-vs-13/Hours-Min;PASS
sum/01-vs-13/Hours-Max;PASS
range/04/SP-Min-le-Max;PASS
range/04/Hours-Min-le-Max;PASS
range/13/SP-Min-le-Max;PASS
range/13/Hours-Min-le-Max;PASS
phase-cap/13/Hours-Max-le-160;PASS
range/07/Hours-Min-le-Max;PASS
phase-cap/07/Hours-Max-le-160;PASS"
}

@test "failure: the broken set fails (exit 1) on exactly the expected checks" {
  cp "$FAIL_FIX"/*.csv "$WD/"
  run_script "$SCRIPT" --dir "$WD" --out "$WD/report.csv"
  assert_failure 1
  # Which checks failed is the contract; a different set is a different defect.
  run bash -c "grep ';FAIL;' \"\$1\" | cut -d';' -f1" _ "$WD/report.csv"
  assert_output "sum/04-vs-13/SP-Min
sum/04-vs-13/SP-Max
sum/07-vs-13/Hours-Max
sum/01-vs-13/Hours-Min
sum/01-vs-13/Hours-Max
range/04/SP-Min-le-Max
phase-cap/07/Hours-Max-le-160"
}

@test "failure: the failing report still carries its PASS rows and their details" {
  cp "$FAIL_FIX"/*.csv "$WD/"
  run_script "$SCRIPT" --dir "$WD" --out "$WD/report.csv"
  assert_failure 1
  # A validator that bailed at the first violation would drop these.
  run bash -c "grep ';PASS;' \"\$1\" | cut -d';' -f1" _ "$WD/report.csv"
  assert_output "format/file-01
format/file-04
format/file-07
format/file-13
sum/07-vs-13/Hours-Min
range/04/Hours-Min-le-Max
range/13/SP-Min-le-Max
range/13/Hours-Min-le-Max
phase-cap/13/Hours-Max-le-160
range/07/Hours-Min-le-Max"
  # The detail column must carry the offending values, not just a verdict.
  run grep '^sum/01-vs-13/Hours-Min;FAIL;' "$WD/report.csv"
  assert_output "sum/01-vs-13/Hours-Min;FAIL;01=99 13=24"
  run grep '^range/04/SP-Min-le-Max;FAIL;' "$WD/report.csv"
  assert_output "range/04/SP-Min-le-Max;FAIL;row=Auth|5|3"
}

@test "failure: the reported failure count equals the number of FAIL rows" {
  cp "$FAIL_FIX"/*.csv "$WD/"
  run_script "$SCRIPT" --dir "$WD" --out "$WD/report.csv"
  assert_failure 1
  assert_output --partial "7 check(s) FAILED"
  run bash -c "grep -c ';FAIL;' \"\$1\"" _ "$WD/report.csv"
  assert_output "7"
}

@test "failure: missing directory is a usage error (exit 2)" {
  run_script "$SCRIPT" --dir "$WD/does-not-exist"
  assert_failure 2
}

@test "failure: unknown argument exits 2" {
  run_script "$SCRIPT" --bogus
  assert_failure 2
}

@test "contract: --self-test passes (smoke)" {
  run_script "$SCRIPT" --self-test
  assert_success
}

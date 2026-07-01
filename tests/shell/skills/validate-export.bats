#!/usr/bin/env bats
# Contract tests for skills/csv-export-templates/scripts/validate-export.sh
# Contracts: exit 0 all-pass, exit 1 on violations, exit 2 usage/missing-dir.
# Writes a semicolon-delimited report (check;status;detail) with ;FAIL; rows on
# failure; --self-test runs internal pass+fail fixtures and exits 0.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/csv-export-templates/scripts/validate-export.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  PASS_FIX="${FIXTURES}/skills/csv-pass"
  FAIL_FIX="${FIXTURES}/skills/csv-fail"
}

@test "happy: a consistent 4-file export set passes (exit 0)" {
  cp "$PASS_FIX"/*.csv "$WD/"
  run_script "$SCRIPT" --dir "$WD" --out "$WD/report.csv"
  assert_success
  run head -1 "$WD/report.csv"
  assert_output "check;status;detail"
}

@test "edge: report header + PASS rows are written even on success" {
  cp "$PASS_FIX"/*.csv "$WD/"
  run_script "$SCRIPT" --dir "$WD" --out "$WD/report.csv"
  assert_success
  run grep -c ';PASS;' "$WD/report.csv"
  refute_output "0"
}

@test "failure: mismatched/out-of-range set fails (exit 1) and writes FAIL rows" {
  cp "$FAIL_FIX"/*.csv "$WD/"
  run_script "$SCRIPT" --dir "$WD" --out "$WD/report.csv"
  assert_failure 1
  run grep -c ';FAIL;' "$WD/report.csv"
  refute_output "0"
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

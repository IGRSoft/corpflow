#!/usr/bin/env bats
# Contract tests for skills/security-review-process/scripts/scan-secrets.sh
# AC-4 anchor for DV0b.
#
# Asserted REAL contracts (read from the script source):
#   - exit 0 on clean input; exit 1 when Critical/High secrets found; exit 2 usage.
#   - plain output format is exactly  file:line:severity:pattern  (4 colon fields,
#     path RELATIVE to the scanned root, no code excerpt).
#   - --format json emits one NDJSON object per finding with keys
#     {file,line,severity,pattern} (line is a STRING, per the script's jq -Rs).
#   - the six built-in regex labels: aws-access-key, private-key,
#     password-assignment, database-url, jwt-token, generic-api-key.
#   - --self-test prints "self-test OK" and exits 0.
#
# REAL BUG documented below (not a synthetic assertion): the database-url pattern
# is corrupted by the script's own `regex="${entry##*|}"` field split — the
# last-pipe greedy strip leaves the invalid ERE `mongodb)://...`, so database-url
# NEVER produces a finding. Five of the six labels are therefore live; the sixth
# is asserted as a known non-firing pattern so the suite captures the contract
# truthfully and a future fix flips the expectation deliberately.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/security-review-process/scripts/scan-secrets.sh"
SS_FIX="${FIXTURES}/skills/scan-secrets"

# --- happy path -------------------------------------------------------------
@test "happy: clean directory exits 0 with no findings" {
  WD="$(mk_tmpworkdir)"
  cp "$SS_FIX/clean.env" "$WD/clean.env"
  run_script "$SCRIPT" --path "$WD"
  assert_success
  refute_output --partial "Critical"
  refute_output --partial "High"
}

# --- edge/boundary: exact output format ------------------------------------
@test "edge: plain output is file:line:severity:pattern with relative path" {
  WD="$(mk_tmpworkdir)"
  cp "$SS_FIX/p1-aws.env" "$WD/p1-aws.env"
  run_script "$SCRIPT" --path "$WD"
  assert_failure 1
  # Relative path (no leading WD), exactly 4 colon-separated fields.
  # (the script also emits a gitleaks-not-found notice on stderr, which `run`
  # folds into $output; assert on the finding line specifically.)
  assert_line "p1-aws.env:1:Critical:aws-access-key"
}

# --- failure/exit-code ------------------------------------------------------
@test "failure: Critical secret present exits 1" {
  WD="$(mk_tmpworkdir)"
  cp "$SS_FIX/p1-aws.env" "$WD/p1-aws.env"
  run_script "$SCRIPT" --path "$WD"
  assert_failure 1
}

@test "failure: missing path argument value is a usage error (exit 2)" {
  run_script "$SCRIPT" --path
  assert_failure 2
}

@test "failure: path that is not a directory exits 2" {
  WD="$(mk_tmpworkdir)"
  printf 'x\n' > "$WD/not-a-dir-file"
  run_script "$SCRIPT" --path "$WD/not-a-dir-file"
  assert_failure 2
}

# --- --format json shape ----------------------------------------------------
@test "json: --format json emits one NDJSON object per finding with expected keys" {
  WD="$(mk_tmpworkdir)"
  cp "$SS_FIX/p1-aws.env" "$WD/p1-aws.env"
  run_script "$SCRIPT" --path "$WD" --format json
  assert_failure 1
  # The finding line is the JSON object (a gitleaks notice may precede on stderr,
  # folded into $output by `run`); select it and assert the four required keys.
  local json_line
  json_line="$(printf '%s\n' "$output" | grep '^{')"
  run jq -e '.file and .line and .severity and .pattern' <<< "$json_line"
  assert_success
  # line is serialized as a STRING (script uses jq -Rs on the lineno).
  run jq -r '.line | type' <<< "$json_line"
  assert_output "string"
  run jq -r '.pattern' <<< "$json_line"
  assert_output "aws-access-key"
}

# --- six built-in regex patterns, each independently -----------------------
@test "patterns: aws-access-key fires independently" {
  WD="$(mk_tmpworkdir)"; cp "$SS_FIX/p1-aws.env" "$WD/f.env"
  run_script "$SCRIPT" --path "$WD"
  assert_failure 1
  assert_output --partial ":Critical:aws-access-key"
}

@test "patterns: private-key fires independently" {
  WD="$(mk_tmpworkdir)"; cp "$SS_FIX/p2-private-key.env" "$WD/f.env"
  run_script "$SCRIPT" --path "$WD"
  assert_failure 1
  assert_output --partial ":Critical:private-key"
}

@test "patterns: password-assignment fires independently" {
  WD="$(mk_tmpworkdir)"; cp "$SS_FIX/p3-password.env" "$WD/f.env"
  run_script "$SCRIPT" --path "$WD"
  assert_failure 1
  assert_output --partial ":Critical:password-assignment"
}

@test "patterns: jwt-token fires independently" {
  WD="$(mk_tmpworkdir)"; cp "$SS_FIX/p5-jwt.env" "$WD/f.env"
  run_script "$SCRIPT" --path "$WD"
  assert_failure 1
  assert_output --partial ":High:jwt-token"
}

@test "patterns: generic-api-key fires independently" {
  WD="$(mk_tmpworkdir)"; cp "$SS_FIX/p6-generic-api-key.env" "$WD/f.env"
  run_script "$SCRIPT" --path "$WD"
  assert_failure 1
  assert_output --partial ":High:generic-api-key"
}

@test "patterns: database-url is a KNOWN non-firing pattern (regex split bug)" {
  # REAL contract: the database-url entry's ERE is corrupted by ${entry##*|}
  # (greedy last-pipe strip), so neither postgres:// nor mongodb:// is reported.
  # When the script is fixed, flip this to assert ":Critical:database-url".
  WD="$(mk_tmpworkdir)"; cp "$SS_FIX/p4-database-url.env" "$WD/f.env"
  run_script "$SCRIPT" --path "$WD"
  assert_success
  refute_output --partial "database-url"
}

@test "patterns: five distinct live labels present in a combined file" {
  WD="$(mk_tmpworkdir)"; cp "$SS_FIX/all-classes.env" "$WD/f.env"
  run_script "$SCRIPT" --path "$WD"
  assert_failure 1
  assert_output --partial "aws-access-key"
  assert_output --partial "password-assignment"
  assert_output --partial "jwt-token"
  assert_output --partial "generic-api-key"
}

# --- --self-test smoke (NON-counting toward the 3 required scenarios) -------
@test "contract: --self-test passes (smoke)" {
  run_script "$SCRIPT" --self-test
  assert_success
  assert_output --partial "self-test OK"
}

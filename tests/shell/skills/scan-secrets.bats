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
# R4.1 (FIXED): database-url was dead. `regex="${entry##*|}"` stripped through the
# LAST `|`, truncating the alternation `(mysql|postgres|mongodb)://…` to the
# malformed `mongodb)://…`, so DB-URL credentials were never reported. All six
# labels are live now and each is asserted independently.
#
# How the truncated ERE failed is grep-dependent, which is why no stderr noise ever
# appeared: BSD /usr/bin/grep (what this script resolves) treats the unmatched `)`
# as a LITERAL and just returns "no match", while GNU grep and ugrep reject it as a
# parse error. Either way fallback_scan's `2>/dev/null` on the grep call swallowed
# it; that suppression is now gone and a startup compile check rejects patterns the
# local grep refuses. Neither catches a pattern that compiles but matches the wrong
# thing (BSD's reading of the original bug) — the per-pattern specimen tests do.
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
  # RK5 (stderr honesty): the gitleaks-not-found notice belongs on stderr. Under
  # a plain `run` it was folded into $output and this test worked around it by
  # matching a single line; splitting the streams asserts the routing instead of
  # tolerating it, so a finding accidentally emitted on stderr now fails.
  run_script_env --separate-stderr -- "$SCRIPT" --path "$WD"
  assert_failure 1
  # stdout carries findings only: relative path, exactly 4 colon-separated fields.
  assert_output "p1-aws.env:1:Critical:aws-access-key"
  # The tool notice is a diagnostic and must not pollute the finding stream.
  refute_output --partial "gitleaks"
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
  run_script_env --separate-stderr -- "$SCRIPT" --path "$WD" --format json
  assert_failure 1
  # With the streams split, stdout is NDJSON and nothing else — no grep-for-{
  # workaround, and a diagnostic leaking into the machine-readable stream fails.
  local json_line
  json_line="$output"
  run jq -e . <<< "$json_line"
  assert_success
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

@test "patterns: database-url fires on all three schemes in one file" {
  # Fixture lines: 1 postgres, 2 mongodb, 3 mysql. Asserting per line proves three
  # distinct matches rather than one pattern firing repeatedly.
  WD="$(mk_tmpworkdir)"; cp "$SS_FIX/p4-database-url.env" "$WD/f.env"
  # Split streams: the gitleaks-fallback notice is a stderr diagnostic and must not
  # be counted as a finding.
  run_script_env --separate-stderr -- "$SCRIPT" --path "$WD"
  assert_failure 1
  assert_output --partial "f.env:1:Critical:database-url"
  assert_output --partial "f.env:2:Critical:database-url"
  assert_output --partial "f.env:3:Critical:database-url"
}

@test "patterns: each database-url scheme fires on its own" {
  # The truncated ERE kept only the last alternation branch, so a combined-file
  # assertion alone could pass on one scheme. Each is driven in isolation here.
  local scheme
  for scheme in mysql postgres mongodb; do
    WD="$(mk_tmpworkdir)"
    printf 'DB_URL=%s://fakeuser:fakepass@host.example.invalid:5432/appdb\n' "$scheme" > "$WD/f.env"
    run_script_env --separate-stderr -- "$SCRIPT" --path "$WD"
    assert_failure 1
    # Exact match: exactly one finding, and no other pattern claims the line.
    assert_output "f.env:1:Critical:database-url"
  done
}

@test "streams: a database-url scan emits no regex diagnostic on stderr" {
  WD="$(mk_tmpworkdir)"; cp "$SS_FIX/p4-database-url.env" "$WD/f.env"
  run_script_env --separate-stderr -- "$SCRIPT" --path "$WD"
  assert_failure 1
  # stderr carries the gitleaks-fallback notice and nothing else — a clean scan is
  # quiet even though grep's stderr now reaches it. A pattern the local grep rejects
  # is caught one step earlier, at startup (see the broken-pattern test below), so
  # this pins hygiene rather than serving as the malformed-pattern canary itself.
  assert_equal "$stderr" "scan-secrets: gitleaks not found — using built-in regex fallback"
  refute_output --partial "gitleaks"
}

@test "patterns: exactly the six built-in labels fire in a combined file" {
  WD="$(mk_tmpworkdir)"; cp "$SS_FIX/all-classes.env" "$WD/f.env"
  run_script_env --separate-stderr -- "$SCRIPT" --path "$WD"
  assert_failure 1
  # The distinct label SET, asserted whole: a pattern mangled by field-splitting
  # drops its label, and a split that over-captured could introduce a spurious one.
  # Both directions fail here, unlike a list of --partial checks.
  local labels
  labels="$(printf '%s\n' "$output" | cut -d: -f4 | sort -u | paste -sd, -)"
  assert_equal "$labels" \
    "aws-access-key,database-url,generic-api-key,jwt-token,password-assignment,private-key"
}

@test "patterns: an ERE the local grep rejects aborts at startup, loudly" {
  WD="$(mk_tmpworkdir)"; cp "$SS_FIX/all-classes.env" "$WD/f.env"

  # The pattern array is a hardcoded literal, so the only way to drive the invalid-
  # pattern path is a mutated copy of the SUT. `(unclosed[0-9]{3,}` is an unbalanced
  # OPENING paren — rejected by BSD, GNU and ugrep alike, unlike the unmatched
  # CLOSING paren of the original database-url bug, which BSD accepts as a literal.
  # Rewritten line-by-line rather than with ${var/…/…}: bash 3.2 leaks the quote
  # characters of a quoted replacement into the result.
  local mutant="$WD/mutant.sh" line mutated=0
  : > "$mutant"
  while IFS= read -r line; do
    if [[ $line == *"aws-access-key|AKIA"* ]]; then
      line="  'Critical|broken-canary|(unclosed[0-9]{3,}'"
      mutated=1
    fi
    printf '%s\n' "$line" >> "$mutant"
  done < "$PLUGIN_ROOT/$SCRIPT"
  # A silently-failed mutation would make this test vacuously green.
  [ "$mutated" = 1 ] || fail "mutation did not apply — PATTERNS literal changed?"

  run_script_env --separate-stderr -- "$mutant" --path "$WD"
  assert_failure 2
  [[ "$stderr" == *"built-in pattern broken-canary is invalid"* ]] \
    || fail "no compile diagnostic on stderr: $stderr"
  # The scan must not run at all on an unvalidated pattern set.
  assert_output ""
}

# --- --self-test smoke (NON-counting toward the 3 required scenarios) -------
@test "contract: --self-test passes (smoke)" {
  run_script "$SCRIPT" --self-test
  assert_success
  assert_output --partial "self-test OK"
}

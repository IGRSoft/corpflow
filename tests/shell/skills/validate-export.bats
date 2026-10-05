#!/usr/bin/env bats
# Contract tests for skills/csv-export-templates/scripts/validate-export.sh
# Contracts: exit 0 all-pass, exit 1 on violations, exit 2 usage/missing-dir/bad
# --delimiter.
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

# Rewrites every fixture CSV in $1 into $2 with delimiter $3, quoting as needed.
redelimit() {
  local f
  for f in "$1"/*.csv; do
    python3 -c 'import csv, sys
w = csv.writer(sys.stdout, delimiter=sys.argv[2], lineterminator="\n")
w.writerows(csv.reader(open(sys.argv[1], encoding="utf-8", newline=""), delimiter=";"))' \
      "$f" "$3" > "$2/${f##*/}"
  done
}

@test "happy: a consistent export set passes (exit 0)" {
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
format/file-05;PASS
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
phase-cap/07/Hours-Max-le-160;PASS
phase/13/Weeks-continuous;PASS
phase/13/Dependencies-valid;PASS
phase/05/Weeks-continuous;PASS
phase/05/Dependencies-valid;PASS"
}

@test "happy: 01 Total Hours is checked against 13 phases plus its Buffer row" {
  # 01 Total Hours is base + buffer (69/138); 13's phase rows alone sum to 60/120.
  cp "$PASS_FIX"/*.csv "$WD/"
  run_script "$SCRIPT" --dir "$WD" --out "$WD/report.csv"
  assert_success
  run grep '^sum/01-vs-13/' "$WD/report.csv"
  assert_output "sum/01-vs-13/Hours-Min;PASS;both=69
sum/01-vs-13/Hours-Max;PASS;both=138"
  # The base-hour sums still leave the buffer out.
  run grep '^sum/07-vs-13/Hours-Min;' "$WD/report.csv"
  assert_output "sum/07-vs-13/Hours-Min;PASS;both=60"
}

@test "failure: 01 without a Total Hours row fails the 01-vs-13 checks" {
  cp "$PASS_FIX"/*.csv "$WD/"
  grep -v '^Total Hours;' "$PASS_FIX/01_project_overview.csv" > "$WD/01_project_overview.csv"
  run_script "$SCRIPT" --dir "$WD" --out "$WD/report.csv"
  assert_failure 1
  run grep ';FAIL;' "$WD/report.csv"
  assert_output "sum/01-vs-13/Hours-Min;FAIL;01 has no Total Hours row
sum/01-vs-13/Hours-Max;FAIL;01 has no Total Hours row"
}

@test "happy: a comma-delimited set passes with --delimiter ," {
  redelimit "$PASS_FIX" "$WD" ","
  run_script "$SCRIPT" --dir "$WD" --delimiter , --out "$WD/report.csv"
  assert_success
  # The report keeps its own semicolon format whatever the export uses.
  run bash -c "tail -n +2 \"\$1\" | grep -vc ';PASS;'" _ "$WD/report.csv"
  assert_output "0"
}

@test "failure: a comma-delimited set without --delimiter fails format only (exit 1)" {
  redelimit "$PASS_FIX" "$WD" ","
  run_script "$SCRIPT" --dir "$WD" --out "$WD/report.csv"
  assert_failure 1
  # Content checks are skipped rather than run against unsplit rows.
  run report_ids "$WD/report.csv"
  assert_output "format/file-01;FAIL
format/file-04;FAIL
format/file-05;FAIL
format/file-07;FAIL
format/file-13;FAIL"
  run grep '^format/file-01;' "$WD/report.csv"
  assert_output "format/file-01;FAIL;DELIMITER|first line has no semicolon (looks comma-delimited)"
}

@test "failure: --delimiter must be a single character (exit 2)" {
  run_script "$SCRIPT" --dir "$WD" --delimiter ';;'
  assert_failure 2
  run_script "$SCRIPT" --dir "$WD" --delimiter '"'
  assert_failure 2
}

@test "failure: the broken set fails (exit 1) on exactly the expected checks" {
  cp "$FAIL_FIX"/*.csv "$WD/"
  run_script "$SCRIPT" --dir "$WD" --out "$WD/report.csv"
  assert_failure 1
  # Which checks failed is the contract; a different set is a different defect.
  run bash -c "grep ';FAIL;' \"\$1\" | cut -d';' -f1" _ "$WD/report.csv"
  assert_output "format/file-05
format/file-07
sum/04-vs-13/SP-Min
sum/04-vs-13/SP-Max
sum/07-vs-13/Hours-Max
sum/01-vs-13/Hours-Min
sum/01-vs-13/Hours-Max
range/04/SP-Min-le-Max
phase-cap/07/Hours-Max-le-160
phase/13/Weeks-continuous
phase/13/Dependencies-valid"
}

@test "failure: the failing report still carries its PASS rows and their details" {
  cp "$FAIL_FIX"/*.csv "$WD/"
  run_script "$SCRIPT" --dir "$WD" --out "$WD/report.csv"
  assert_failure 1
  # A validator that bailed at the first violation would drop these.
  run bash -c "grep ';PASS;' \"\$1\" | cut -d';' -f1" _ "$WD/report.csv"
  assert_output "format/file-01
format/file-04
format/file-13
sum/07-vs-13/Hours-Min
range/04/Hours-Min-le-Max
range/13/SP-Min-le-Max
range/13/Hours-Min-le-Max
phase-cap/13/Hours-Max-le-160
range/07/Hours-Min-le-Max
phase/05/Weeks-continuous
phase/05/Dependencies-valid"
  # The detail column must carry the offending values, not just a verdict.
  run grep '^sum/01-vs-13/Hours-Min;FAIL;' "$WD/report.csv"
  assert_output "sum/01-vs-13/Hours-Min;FAIL;01=99 13=28"
  run grep '^range/04/SP-Min-le-Max;FAIL;' "$WD/report.csv"
  assert_output "range/04/SP-Min-le-Max;FAIL;row=Auth|5|3"
  run grep '^phase/13/' "$WD/report.csv"
  assert_output "phase/13/Weeks-continuous;FAIL;row=Buffer|week range 4 leaves a gap after week 2
phase/13/Dependencies-valid;FAIL;row=1|depends on phase 2, which does not exist"
}

# Copies the pass set into $1, then rewrites 13 and 05 with phases 1-3 on week
# cells $2-$4 and Buffer on $5. Phase 3 carries zero SP/hours so every sum and
# cap check stays as in the pass set; no phase depends on another.
phase_weeks() {
  cp "$PASS_FIX"/*.csv "$1/"
  cat > "$1/13_phase_summary.csv" << EOF
Phase;Name;Duration;Weeks;SP Min;SP Max;Hours Min;Hours Max;Cost Min;Cost Max;Key Deliverables;Dependencies
1;Core;2 weeks;$2;6;12;36;72;\$3600;\$7200;Auth;-
2;Profile;2 weeks;$3;4;8;24;48;\$2400;\$4800;Profile form;-
3;Extra;2 weeks;$4;0;0;0;0;\$0;\$0;Extra;-
Buffer;Contingency;1 weeks;$5;;;9;18;\$900;\$1800;Risk mitigation;All
TOTAL;;5 weeks;;10;20;69;138;\$6900;\$13800;;
EOF
  cat > "$1/05_roadmap_milestones.csv" << EOF
Phase;Week;Milestone;Deliverables;SP Min;SP Max;Hours Min;Hours Max;Dependencies
1;$2;Core;Auth;6;12;36;72;-
2;$3;Profile;Profile form;4;8;24;48;-
3;$4;Extra;Extra;0;0;0;0;-
Buffer;$5;Contingency;"Risk mitigation, feedback";;;9;18;All phases
TOTAL;;;;10;20;69;138;
EOF
}

@test "happy: week ranges out of start order that cover every week pass" {
  phase_weeks "$WD" 1-2 5-6 3-4 7
  run_script "$SCRIPT" --dir "$WD" --out "$WD/report.csv"
  assert_success
  run grep 'Weeks-continuous;' "$WD/report.csv"
  assert_output "phase/13/Weeks-continuous;PASS;all rows OK
phase/05/Weeks-continuous;PASS;all rows OK"
}

@test "failure: a real gap between unsorted week ranges still fails" {
  # Week 5 is uncovered; the gap is reported once, at the first range past it.
  phase_weeks "$WD" 1-2 6-7 3-4 8
  run_script "$SCRIPT" --dir "$WD" --out "$WD/report.csv"
  assert_failure 1
  run grep ';FAIL;' "$WD/report.csv"
  assert_output "phase/13/Weeks-continuous;FAIL;row=2|week range 6-7 leaves a gap after week 4
phase/05/Weeks-continuous;FAIL;row=2|week range 6-7 leaves a gap after week 4"
}

@test "failure: a malformed week range fails continuity" {
  phase_weeks "$WD" 1-2 soon 3-4 5
  run_script "$SCRIPT" --dir "$WD" --out "$WD/report.csv"
  assert_failure 1
  run grep ';FAIL;' "$WD/report.csv"
  assert_output "phase/13/Weeks-continuous;FAIL;row=2|week range 'soon' is not N or N-M
phase/05/Weeks-continuous;FAIL;row=2|week range 'soon' is not N or N-M"
}

@test "failure: a reversed week range fails continuity" {
  # 3-5 covers the weeks 4-3 names, so only the reversal itself is reported.
  phase_weeks "$WD" 1-2 4-3 3-5 6
  run_script "$SCRIPT" --dir "$WD" --out "$WD/report.csv"
  assert_failure 1
  run grep ';FAIL;' "$WD/report.csv"
  assert_output "phase/13/Weeks-continuous;FAIL;row=2|week range 4-3 ends before it starts
phase/05/Weeks-continuous;FAIL;row=2|week range 4-3 ends before it starts"
}

@test "failure: a TOTAL row one field short of its header fails format" {
  # The 05 and 07 fixtures carry TOTAL rows in the shape that put every total
  # one column left of its header.
  cp "$FAIL_FIX"/*.csv "$WD/"
  run_script "$SCRIPT" --dir "$WD" --out "$WD/report.csv"
  assert_failure 1
  run grep -E '^format/file-0[57];' "$WD/report.csv"
  assert_output "format/file-05;FAIL;WIDTH|line 3 (TOTAL): 8 fields, header has 9
format/file-07;FAIL;WIDTH|line 3 (TOTAL): 10 fields, header has 11"
}

@test "contract: every row of every template in references/templates.md matches its header width" {
  run python3 - "${PLUGIN_ROOT}/skills/csv-export-templates/references/templates.md" << 'PY'
import csv, re, sys
text = open(sys.argv[1], encoding="utf-8").read()
blocks = re.findall(r"## Template: (\S+)\n\n```csv\n(.*?)```", text, re.S)
assert len(blocks) == 13, f"expected 13 templates, found {len(blocks)}"
for name, block in blocks:
    rows = list(csv.reader(block.strip().split("\n"), delimiter=";"))
    for row in rows[1:]:
        if len(row) != len(rows[0]):
            print(f"{name}: {row[0]} has {len(row)} fields, header has {len(rows[0])}")
PY
  assert_success
  assert_output ""
}

@test "failure: the reported failure count equals the number of FAIL rows" {
  cp "$FAIL_FIX"/*.csv "$WD/"
  run_script "$SCRIPT" --dir "$WD" --out "$WD/report.csv"
  assert_failure 1
  assert_output --partial "11 check(s) FAILED"
  run bash -c "grep -c ';FAIL;' \"\$1\"" _ "$WD/report.csv"
  assert_output "11"
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

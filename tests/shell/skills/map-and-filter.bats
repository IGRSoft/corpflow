#!/usr/bin/env bats
# Contract tests for skills/self-improvement/scripts/map-and-filter.sh
# Contracts (from source + self-test):
#   Requires --context-set=<file> and LOG_OUT env var.
#   Reads changes TSV (path\tadded\tremoved) from --changes=<file> or stdin.
#   Emits kept rows: path\trule_num\ttarget\tadded\tremoved.
#   Missing --context-set or missing LOG_OUT -> exit 1.
#   Rule 1: agents/*.md -> target=itself (if in context).
#   Rule 13: src/* -> target=dv_agent (default agents/developer.md).
#   Rule 17: unmatched path -> discard (no output).
#   Early filter: .context/logs/* and skills/self-improvement/* -> discard.
#   --self-test -> exit 0, prints "passed".
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/self-improvement/scripts/map-and-filter.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  export LOG_OUT="$WD/run.log"
  touch "$LOG_OUT"
}

_mk_ctx() {
  # Write a context-set file with given lines; prints path.
  local ctx="$WD/ctx-$RANDOM.txt"
  printf '%s\n' "$@" > "$ctx"
  printf '%s' "$ctx"
}

_mk_changes() {
  # Write a changes TSV file; prints path.
  local chg="$WD/chg-$RANDOM.tsv"
  printf '%s\n' "$@" > "$chg"
  printf '%s' "$chg"
}

# --- happy path -------------------------------------------------------------
@test "happy: src/* maps to dv_agent and is kept when agent is in context" {
  local ctx; ctx="$(_mk_ctx "agents/developer.md")"
  local chg; chg="$(_mk_changes "src/main.go	10	0")"
  run_script "$SCRIPT" --changes="$chg" --context-set="$ctx"
  assert_success
  assert_output "src/main.go	13	agents/developer.md	10	0"
}

@test "happy: agents/*.md edit direct (rule 1) kept when in context" {
  local ctx; ctx="$(_mk_ctx "agents/developer.md")"
  local chg; chg="$(_mk_changes "agents/developer.md	5	2")"
  run_script "$SCRIPT" --changes="$chg" --context-set="$ctx"
  assert_success
  assert_output "agents/developer.md	1	agents/developer.md	5	2"
}

# --- edge/boundary ----------------------------------------------------------
@test "edge: rule 17 (no match) path is discarded — no output" {
  local ctx; ctx="$(_mk_ctx "agents/developer.md")"
  local chg; chg="$(_mk_changes "some/unknown/path.xyz	1	1")"
  run_script "$SCRIPT" --changes="$chg" --context-set="$ctx"
  assert_success
  assert_output ""
}

@test "edge: early-filter discards .context/logs/* even when target is in context" {
  local ctx; ctx="$(_mk_ctx "agents/developer.md")"
  local chg; chg="$(_mk_changes ".context/logs/run.log	2	0")"
  run_script "$SCRIPT" --changes="$chg" --context-set="$ctx"
  assert_success
  assert_output ""
}

@test "edge: skills/self-improvement/* is discarded (anti-recursion)" {
  local ctx; ctx="$(_mk_ctx "skills/self-improvement/SKILL.md")"
  local chg; chg="$(_mk_changes "skills/self-improvement/SKILL.md	4	1")"
  run_script "$SCRIPT" --changes="$chg" --context-set="$ctx"
  assert_success
  assert_output ""
}

@test "edge: rule 16 plugin.json maps to workflow-engineer when in context" {
  local ctx; ctx="$(_mk_ctx "agents/workflow-engineer.md")"
  local chg; chg="$(_mk_changes "plugin.json	3	0")"
  run_script "$SCRIPT" --changes="$chg" --context-set="$ctx"
  assert_success
  assert_output "plugin.json	16	agents/workflow-engineer.md	3	0"
}

# --- failure / exit-code ----------------------------------------------------
@test "failure: missing --context-set exits 1" {
  local chg; chg="$(_mk_changes "src/main.go	1	0")"
  run bash "$PLUGIN_ROOT/$SCRIPT" --changes="$chg"
  assert_failure 1
}

@test "failure: LOG_OUT unset (or empty) causes exit 1" {
  local ctx; ctx="$(_mk_ctx "agents/developer.md")"
  local chg; chg="$(_mk_changes "src/main.go	1	0")"
  unset LOG_OUT
  run bash "$PLUGIN_ROOT/$SCRIPT" --changes="$chg" --context-set="$ctx"
  # The script uses `: "${LOG_OUT:?...}"` which causes exit 1 when unset.
  assert_failure
  export LOG_OUT="$WD/run.log"
}

# --- self-test smoke (NON-counting) ----------------------------------------
@test "contract: --self-test passes (smoke)" {
  run_script "$SCRIPT" --self-test
  assert_success
  assert_output --partial "passed"
}

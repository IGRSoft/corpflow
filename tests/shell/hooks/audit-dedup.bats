#!/usr/bin/env bats
# Tests for hooks/audit-dedup.sh (DV0c) — dedupe-key MODE selector for
# audit.jsonl. Prints "base" or "extended" per the auto-detection rule.
#
# Partition note: this is the HOOK variant under tests/shell/hooks/. DV0b owns
# the skill variant at tests/shell/skills/agent-coordination__audit-dedup.bats.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="hooks/audit-dedup.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context/logs"
}

@test "happy: missing/empty audit.jsonl -> base via --check-mode" {
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" --check-mode
  assert_success
  assert_output "base"
}

@test "happy: a non-none parent_agent_id in tail-100 -> extended" {
  cp "${FIXTURES}/hooks/audit-has-parent.jsonl" "$WD/.context/logs/audit.jsonl"
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" --check-mode
  assert_success
  assert_output "extended"
}

@test "edge: all-none parents (but ext key present) -> base" {
  cp "${FIXTURES}/hooks/audit-all-none.jsonl" "$WD/.context/logs/audit.jsonl"
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" --check-mode
  assert_success
  assert_output "base"
}

@test "edge: pre-v3.10.6 first row lacks dedupe_key_extended -> base (compat)" {
  cp "${FIXTURES}/hooks/audit-pre-v3106.jsonl" "$WD/.context/logs/audit.jsonl"
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" --check-mode
  assert_success
  assert_output "base"
}

@test "failure: no mode flag prints usage to stderr and still exits 0" {
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_output --partial "Usage: audit-dedup.sh"
}

@test "contract: --self-test passes (smoke, NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "self-test OK"
}

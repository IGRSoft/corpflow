#!/usr/bin/env bats
# Contract tests for skills/self-improvement/scripts/label-stats.sh
# Contracts (from source + self-test):
#   Reads evals/failure-labels.jsonl (or --dataset=<file>).
#   Absent or empty dataset -> "no labels yet", exit 0 (never an error).
#   --format=json emits total/worktasks/by_target/by_category/by_confidence.
#   --format=table (default) renders per-target and per-category counts.
#   Unknown flag -> exit 1.
#   --self-test -> exit 0.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/self-improvement/scripts/label-stats.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  DS="$WD/labels.jsonl"
  printf '%s\n' \
    '{"target":"agents/developer.md","category":"completeness","confidence":"high","worktask_id":"a"}' \
    '{"target":"agents/developer.md","category":"accuracy","confidence":"high","worktask_id":"a"}' \
    '{"target":"skills/worktask/SKILL.md","category":"completeness","confidence":"low","worktask_id":"b"}' \
    > "$DS"
}

@test "self-test passes" {
  run bash "$SCRIPT" --self-test
  [ "$status" -eq 0 ]
}

@test "absent dataset reports no labels and exits 0" {
  run bash "$SCRIPT" --dataset="$WD/missing.jsonl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no labels yet"* ]]
}

@test "json format counts labels and worktasks" {
  run bash "$SCRIPT" --dataset="$DS" --format=json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.total')" = "3" ]
  [ "$(printf '%s' "$output" | jq -r '.worktasks')" = "2" ]
}

@test "json format groups by target and category" {
  run bash "$SCRIPT" --dataset="$DS" --format=json
  [ "$(printf '%s' "$output" | jq -r '.by_target["agents/developer.md"]')" = "2" ]
  [ "$(printf '%s' "$output" | jq -r '.by_category["completeness"]')" = "2" ]
}

@test "table format renders both groupings" {
  run bash "$SCRIPT" --dataset="$DS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"by target:"* ]]
  [[ "$output" == *"by category:"* ]]
}

@test "unknown flag exits 1" {
  run bash "$SCRIPT" --nope
  [ "$status" -eq 1 ]
}

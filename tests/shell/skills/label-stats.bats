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

# --- recurrence threshold ----------------------------------------------------
# The fixture has agents/developer.md and completeness at 2 each, everything
# else at 1, so min=2 and min=3 straddle the same data.

@test "min-count flags targets and categories at or above the threshold" {
  run bash "$SCRIPT" --dataset="$DS" --format=json --min-count=2
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.recurrence_threshold')" = "2" ]
  [ "$(printf '%s' "$output" | jq -r '.recurring.targets["agents/developer.md"]')" = "2" ]
  [ "$(printf '%s' "$output" | jq -r '.recurring.categories["completeness"]')" = "2" ]
}

@test "a target below the threshold is not flagged" {
  run bash "$SCRIPT" --dataset="$DS" --format=json --min-count=2
  [ "$(printf '%s' "$output" | jq -r '.recurring.targets["skills/worktask/SKILL.md"] // "absent"')" = "absent" ]
}

@test "raising the threshold past every count empties the recurring set" {
  run bash "$SCRIPT" --dataset="$DS" --format=json --min-count=3
  [ "$(printf '%s' "$output" | jq -r '.recurring.targets | length')" = "0" ]
  [ "$(printf '%s' "$output" | jq -r '.recurring.categories | length')" = "0" ]
}

@test "min-count 0 disables the section in both formats" {
  run bash "$SCRIPT" --dataset="$DS" --format=json --min-count=0
  [ "$(printf '%s' "$output" | jq -r '.recurring.targets | length')" = "0" ]
  run bash "$SCRIPT" --dataset="$DS" --min-count=0
  [[ "$output" != *"recurring"* ]]
}

@test "table renders recurring rows, and 'none' when nothing crosses" {
  run bash "$SCRIPT" --dataset="$DS" --min-count=2
  [ "$status" -eq 0 ]
  [[ "$output" == *"recurring (>=2):"* ]]
  [[ "$output" == *"agents/developer.md"* ]]
  run bash "$SCRIPT" --dataset="$DS" --min-count=3
  [[ "$output" == *"recurring (>=3):"* ]]
  [[ "$output" == *"none"* ]]
}

@test "non-numeric min-count exits 1" {
  run bash "$SCRIPT" --dataset="$DS" --min-count=abc
  [ "$status" -eq 1 ]
}

# --- taxonomy trigger --------------------------------------------------------
# evals/README.md blocks failure-taxonomy.md on ~100 rows; the gate has to
# announce itself here rather than be counted by hand.

@test "taxonomy trigger reports progress toward the 100-row gate" {
  run bash "$SCRIPT" --dataset="$DS" --format=json
  [ "$(printf '%s' "$output" | jq -r '.taxonomy.threshold')" = "100" ]
  [ "$(printf '%s' "$output" | jq -r '.taxonomy.rows')" = "3" ]
  [ "$(printf '%s' "$output" | jq -r '.taxonomy.ready')" = "false" ]
  run bash "$SCRIPT" --dataset="$DS"
  [[ "$output" == *"taxonomy trigger: 3/100 rows"* ]]
  [[ "$output" == *"not yet"* ]]
}

@test "taxonomy trigger flips to READY at the threshold" {
  local big="$WD/big.jsonl"
  : > "$big"
  for i in $(seq 1 100); do
    printf '{"target":"agents/developer.md","category":"completeness","confidence":"high","worktask_id":"w%s"}\n' \
      "$i" >> "$big"
  done
  run bash "$SCRIPT" --dataset="$big"
  [ "$status" -eq 0 ]
  [[ "$output" == *"taxonomy trigger: 100/100 rows"* ]]
  [[ "$output" == *"READY"* ]]
}

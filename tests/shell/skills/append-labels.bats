#!/usr/bin/env bats
# Contract tests for skills/self-improvement/scripts/append-labels.sh
# Contracts (from source + self-test):
#   Requires --worktask-id=<id>; missing -> exit 1 (usage).
#   Reads TSV (path\ttarget\tcategory\tconfidence\tadded\tremoved\tsummary)
#     from --changes=<file> or stdin; appends one JSONL row per new observation.
#   Idempotent on a content hash of (path, added, removed, summary).
#   SELF_IMPROVE_LABELS=0 -> no-op, exit 0, dataset untouched.
#   Never writes diff bodies — counts + summary only.
#   --self-test -> exit 0.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/self-improvement/scripts/append-labels.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  DS="$WD/labels.jsonl"
  ROW=$'agents/developer.md\tagents/developer.md\tcompleteness\thigh\t4\t1\tadded Sendable constraint'
}

@test "self-test passes" {
  run bash "$SCRIPT" --self-test
  [ "$status" -eq 0 ]
}

@test "missing --worktask-id exits 1" {
  run bash -c "printf '%s\n' '$ROW' | bash '$SCRIPT' --dataset='$DS'"
  [ "$status" -eq 1 ]
}

@test "appends one JSONL row per observation" {
  printf '%s\n' "$ROW" | bash "$SCRIPT" --worktask-id=wt-1 --dataset="$DS"
  [ "$(wc -l < "$DS" | tr -d ' ')" -eq 1 ]
  run jq -r '.category' "$DS"
  [ "$output" = "completeness" ]
}

@test "re-running the same observation does not duplicate" {
  printf '%s\n' "$ROW" | bash "$SCRIPT" --worktask-id=wt-1 --dataset="$DS"
  printf '%s\n' "$ROW" | bash "$SCRIPT" --worktask-id=wt-1 --dataset="$DS"
  [ "$(wc -l < "$DS" | tr -d ' ')" -eq 1 ]
}

@test "a different observation appends a second row" {
  printf '%s\n' "$ROW" | bash "$SCRIPT" --worktask-id=wt-1 --dataset="$DS"
  printf '%s\n' $'skills/worktask/SKILL.md\tskills/worktask/SKILL.md\tstructure\tmedium\t2\t0\treordered' \
    | bash "$SCRIPT" --worktask-id=wt-1 --dataset="$DS"
  [ "$(wc -l < "$DS" | tr -d ' ')" -eq 2 ]
}

@test "SELF_IMPROVE_LABELS=0 writes nothing" {
  printf '%s\n' "$ROW" | SELF_IMPROVE_LABELS=0 bash "$SCRIPT" --worktask-id=wt-1 --dataset="$DS"
  [ ! -s "$DS" ]
}

@test "row carries counts and summary but no diff body" {
  printf '%s\n' "$ROW" | bash "$SCRIPT" --worktask-id=wt-1 --dataset="$DS"
  run jq -r '[.lines_added, .lines_removed, .summary] | @tsv' "$DS"
  [ "$output" = $'4\t1\tadded Sendable constraint' ]
  run bash -c "grep -c '^+++\\|^@@\\|^--- ' '$DS' || true"
  [ "$output" = "0" ]
}

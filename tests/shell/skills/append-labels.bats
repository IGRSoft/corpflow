#!/usr/bin/env bats
# Contract tests for skills/self-improvement/scripts/append-labels.sh
# Contracts (from source + self-test):
#   Requires --worktask-id=<id>; missing -> exit 1 (usage).
#   Reads TSV (path\ttarget\tcategory\tconfidence\tadded\tremoved\tsummary)
#     from --changes=<file> or stdin; appends one JSONL row per new observation.
#   Idempotent on a content hash of (worktask_id, run_index, path, added,
#     removed, summary) — same run never duplicates; a later worktask appends.
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

@test "the same observation in a different worktask appends" {
  printf '%s\n' "$ROW" | bash "$SCRIPT" --worktask-id=wt-1 --dataset="$DS"
  printf '%s\n' "$ROW" | bash "$SCRIPT" --worktask-id=wt-2 --dataset="$DS"
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

@test "a newly created labels file is 0600" {
  printf '%s\n' "$ROW" | bash "$SCRIPT" --worktask-id=wt-1 --dataset="$DS"
  run bash -c "ls -l -- '$DS' | awk '{print \$1}'"
  [ "$status" -eq 0 ]
  [ "$output" = "-rw-------" ]
}

# --- dataset resolution (plugin-data-lib.sh) --------------------------
# Every case below runs against a throwaway git repo / $BATS_TEST_TMPDIR data
# dir, never the real plugin root, so a resolver bug cannot touch the tracked
# evals/failure-labels.jsonl. The final test in this file asserts that directly.

@test "--plugin-data lands the dataset under <dir>/self-improvement/, untracked repo stays clean" {
  local data="$BATS_TEST_TMPDIR/data"
  local repo; repo="$(mk_git_fixture)"
  run_script_env --cwd "$repo" --env "CLAUDE_PROJECT_DIR=$repo" --unset CLAUDE_PLUGIN_DATA \
    --stdin-string "$ROW" "$SCRIPT" --worktask-id=wt-1 --plugin-data="$data"
  [ "$status" -eq 0 ]
  [ -f "$data/self-improvement/failure-labels.jsonl" ]
  run bash -c "git -C '$repo' status --porcelain --untracked-files=all"
  [ -z "$output" ]
  [ ! -d "$repo/evals" ]
}

@test "flag beats env: --plugin-data wins over CLAUDE_PLUGIN_DATA" {
  local flag_dir="$BATS_TEST_TMPDIR/flag-data"
  local env_dir="$BATS_TEST_TMPDIR/env-data"
  run_script_env --env "CLAUDE_PLUGIN_DATA=$env_dir" \
    --stdin-string "$ROW" "$SCRIPT" --worktask-id=wt-1 --plugin-data="$flag_dir"
  [ "$status" -eq 0 ]
  [ -f "$flag_dir/self-improvement/failure-labels.jsonl" ]
  [ ! -e "$env_dir" ]
}

@test "relative --plugin-data exits 1" {
  run_script_env --stdin-string "$ROW" "$SCRIPT" --worktask-id=wt-1 --plugin-data="relative/dir"
  [ "$status" -eq 1 ]
}

@test "unset CLAUDE_PLUGIN_DATA falls back to the fixture repo's evals/ with a stderr notice" {
  local repo; repo="$(mk_git_fixture)"
  run_script_env --cwd "$repo" --env "CLAUDE_PROJECT_DIR=$repo" --unset CLAUDE_PLUGIN_DATA \
    --separate-stderr --stdin-string "$ROW" "$SCRIPT" --worktask-id=wt-1
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"plugin data dir unavailable"* ]]
  [ -f "$repo/evals/failure-labels.jsonl" ]
}

@test "empty CLAUDE_PLUGIN_DATA falls back the same way" {
  local repo; repo="$(mk_git_fixture)"
  run_script_env --cwd "$repo" --env "CLAUDE_PROJECT_DIR=$repo" --env "CLAUDE_PLUGIN_DATA=" \
    --separate-stderr --stdin-string "$ROW" "$SCRIPT" --worktask-id=wt-1
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"plugin data dir unavailable"* ]]
}

@test "the unsubstituted literal token falls back the same way" {
  local repo; repo="$(mk_git_fixture)"
  run_script_env --cwd "$repo" --env "CLAUDE_PROJECT_DIR=$repo" \
    --env 'CLAUDE_PLUGIN_DATA=${CLAUDE_PLUGIN_DATA}' \
    --separate-stderr --stdin-string "$ROW" "$SCRIPT" --worktask-id=wt-1
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"plugin data dir unavailable"* ]]
}

# --- --count-out ---------------------------------------------------------

@test "--count-out receives the appended row count" {
  local cnt="$WD/count.txt"
  printf '%s\n' "$ROW" | bash "$SCRIPT" --worktask-id=wt-1 --dataset="$DS" --count-out="$cnt"
  [ "$(cat "$cnt")" = "1" ]
}

@test "--count-out is written as 0 under SELF_IMPROVE_LABELS=0" {
  local cnt="$WD/count.txt"
  printf '%s\n' "$ROW" | SELF_IMPROVE_LABELS=0 bash "$SCRIPT" --worktask-id=wt-1 --dataset="$DS" --count-out="$cnt"
  [ "$(cat "$cnt")" = "0" ]
}

# --- repo hygiene --------------------------------------------------------------

@test "the real repo's evals/failure-labels.jsonl is unchanged by this suite" {
  run bash -c "git -C '$PLUGIN_ROOT' diff --quiet -- evals/failure-labels.jsonl"
  [ "$status" -eq 0 ]
}

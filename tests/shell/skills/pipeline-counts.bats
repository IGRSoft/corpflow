#!/usr/bin/env bats
# Contract tests for skills/self-improvement/scripts/pipeline-counts.sh
# Contracts (from source and skills/self-improvement/SKILL.md § Step 5b):
#   Requires --worktask-id, --run-index, --context-set, --changes, --mapped,
#     --appended; any missing -> exit 1 (usage).
#   --worktask-id rejects '"' and '\'; --run-index must be a non-negative
#     integer; both violations -> exit 1.
#   Counts (absent input file = 0): context_paths = NF>=1 lines in
#     --context-set; changed_paths = 3-field TSV rows in --changes; mapped_rows
#     = 5-field TSV rows with a numeric $2 in --mapped; appended_rows = line 1
#     of --appended, must be an integer (non-integer -> 0 + stderr warn).
#   Stderr always carries one "self-improve-counts: ..." line, on every path.
#   Appends one JSONL row to <dataset dir>/pipeline-counts.jsonl UNLESS the
#     dataset resolved to the fallback rung or --dry-run was passed.
#   Dataset resolves via plugin-data-lib.sh: --dataset > --plugin-data > env >
#     fallback (${CLAUDE_PROJECT_DIR:-.}/evals/failure-labels.jsonl) — same
#     checks as append-labels.sh / label-stats.sh.
#   SELF_IMPROVE_LABELS=0 -> labels_enabled:false in the row; the row still
#     writes (only append-labels.sh's own capture is gated on this var).
#   --self-test -> exit 0.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/self-improvement/scripts/pipeline-counts.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  CTX="$WD/ctx"
  CH="$WD/changes"
  MAP="$WD/mapped"
  APP="$WD/appended"
  # 2 in-context paths.
  printf 'agents/developer.md\nskills/worktask/SKILL.md\n' >"$CTX"
  # 1 row: path\tlines_added\tlines_removed (3 fields, detect-user-changes.sh shape).
  printf 'agents/developer.md\t4\t1\n' >"$CH"
  # 1 row: path\trule_num\ttarget\tadded\tremoved (5 fields, map-and-filter.sh shape).
  printf 'agents/developer.md\t1\tagents/developer.md\t4\t1\n' >"$MAP"
  # append-labels.sh's --count-out shape: one integer line.
  printf '2\n' >"$APP"
}

# --- usage / validation -------------------------------------------------------

@test "missing --worktask-id exits 1 (usage)" {
  run_script_env -- "$SCRIPT" --run-index=0 \
    --context-set="$CTX" --changes="$CH" --mapped="$MAP" --appended="$APP"
  assert_failure
}

@test "missing --run-index exits 1 (usage)" {
  run_script_env -- "$SCRIPT" --worktask-id=wt-1 \
    --context-set="$CTX" --changes="$CH" --mapped="$MAP" --appended="$APP"
  assert_failure
}

@test "missing a required stage-output flag exits 1 (usage)" {
  run_script_env -- "$SCRIPT" --worktask-id=wt-1 --run-index=0 \
    --changes="$CH" --mapped="$MAP" --appended="$APP"
  assert_failure
}

@test "non-numeric --run-index exits 1" {
  run_script_env -- "$SCRIPT" --worktask-id=wt-1 --run-index=abc \
    --context-set="$CTX" --changes="$CH" --mapped="$MAP" --appended="$APP"
  assert_failure
}

@test "a double-quote in --worktask-id is rejected" {
  run_script_env -- "$SCRIPT" --worktask-id='wt"1' --run-index=0 \
    --context-set="$CTX" --changes="$CH" --mapped="$MAP" --appended="$APP"
  assert_failure
}

@test "a backslash in --worktask-id is rejected" {
  run_script_env -- "$SCRIPT" --worktask-id='wt\1' --run-index=0 \
    --context-set="$CTX" --changes="$CH" --mapped="$MAP" --appended="$APP"
  assert_failure
}

@test "a lowercase --stage is rejected (no counts row)" {
  local ds="$WD/data/self-improvement/failure-labels.jsonl"
  run_script_env -- "$SCRIPT" --worktask-id=wt-1 --run-index=0 --stage=st \
    --context-set="$CTX" --changes="$CH" --mapped="$MAP" --appended="$APP" --dataset="$ds"
  assert_failure
  [ ! -f "$WD/data/self-improvement/pipeline-counts.jsonl" ]
}

@test "a --stage value with JSON-breaking characters is rejected (no counts row)" {
  local ds="$WD/data/self-improvement/failure-labels.jsonl"
  run_script_env -- "$SCRIPT" --worktask-id=wt-1 --run-index=0 --stage='ST","x":"y' \
    --context-set="$CTX" --changes="$CH" --mapped="$MAP" --appended="$APP" --dataset="$ds"
  assert_failure
  [ ! -f "$WD/data/self-improvement/pipeline-counts.jsonl" ]
}

@test "a tab in --worktask-id is rejected (no counts row)" {
  local ds="$WD/data/self-improvement/failure-labels.jsonl"
  run_script_env -- "$SCRIPT" --worktask-id=$'wt\t1' --run-index=0 \
    --context-set="$CTX" --changes="$CH" --mapped="$MAP" --appended="$APP" --dataset="$ds"
  assert_failure
  [ ! -f "$WD/data/self-improvement/pipeline-counts.jsonl" ]
}

@test "a newline in --worktask-id is rejected (no counts row)" {
  local ds="$WD/data/self-improvement/failure-labels.jsonl"
  run_script_env -- "$SCRIPT" --worktask-id=$'wt\n1' --run-index=0 \
    --context-set="$CTX" --changes="$CH" --mapped="$MAP" --appended="$APP" --dataset="$ds"
  assert_failure
  [ ! -f "$WD/data/self-improvement/pipeline-counts.jsonl" ]
}

@test "a tab in --stage is rejected (no counts row)" {
  local ds="$WD/data/self-improvement/failure-labels.jsonl"
  run_script_env -- "$SCRIPT" --worktask-id=wt-1 --run-index=0 --stage=$'S\tT' \
    --context-set="$CTX" --changes="$CH" --mapped="$MAP" --appended="$APP" --dataset="$ds"
  assert_failure
  [ ! -f "$WD/data/self-improvement/pipeline-counts.jsonl" ]
}

@test "a newline in --stage is rejected (no counts row)" {
  local ds="$WD/data/self-improvement/failure-labels.jsonl"
  run_script_env -- "$SCRIPT" --worktask-id=wt-1 --run-index=0 --stage=$'S\nT' \
    --context-set="$CTX" --changes="$CH" --mapped="$MAP" --appended="$APP" --dataset="$ds"
  assert_failure
  [ ! -f "$WD/data/self-improvement/pipeline-counts.jsonl" ]
}

@test "self-test passes" {
  run bash "$SCRIPT" --self-test
  assert_success
}

# --- counts --------------------------------------------------------------------

@test "counts absent input files as zero; row and stderr line both reflect it" {
  local ds="$WD/data/self-improvement/failure-labels.jsonl"
  run_script_env --separate-stderr -- "$SCRIPT" --worktask-id=wt-1 --run-index=0 \
    --context-set="$WD/nope-ctx" --changes="$WD/nope-ch" --mapped="$WD/nope-map" \
    --appended="$WD/nope-app" --dataset="$ds"
  assert_success
  [[ "$stderr" == *"context_paths=0 changed_paths=0 mapped_rows=0 appended_rows=0"* ]]
  local counts="$WD/data/self-improvement/pipeline-counts.jsonl"
  [ -f "$counts" ]
  run jq -e '.context_paths==0 and .changed_paths==0 and .mapped_rows==0 and .appended_rows==0' "$counts"
  assert_success
}

@test "a leading-zero --run-index and appended count normalise to canonical integers" {
  local ds="$WD/data/self-improvement/failure-labels.jsonl"
  local app0="$WD/appended-zero"
  printf '007\n' >"$app0"
  run_script_env -- "$SCRIPT" --worktask-id=wt-1 --run-index=01 \
    --context-set="$CTX" --changes="$CH" --mapped="$MAP" --appended="$app0" --dataset="$ds"
  assert_success
  local counts="$WD/data/self-improvement/pipeline-counts.jsonl"
  run jq -e '.run_index==1 and .appended_rows==7' "$counts"
  assert_success
}

@test "a newly created counts file is 0600" {
  local ds="$WD/data/self-improvement/failure-labels.jsonl"
  run_script_env -- "$SCRIPT" --worktask-id=wt-1 --run-index=0 \
    --context-set="$CTX" --changes="$CH" --mapped="$MAP" --appended="$APP" --dataset="$ds"
  assert_success
  local counts="$WD/data/self-improvement/pipeline-counts.jsonl"
  [ -f "$counts" ]
  run bash -c "ls -l -- '$counts' | awk '{print \$1}'"
  assert_success
  [ "$output" = "-rw-------" ]
}

@test "a non-integer --appended first line counts 0 and warns" {
  local bad="$WD/bad-appended"
  printf 'oops\n' >"$bad"
  run_script_env --separate-stderr -- "$SCRIPT" --worktask-id=wt-1 --run-index=0 \
    --context-set="$CTX" --changes="$CH" --mapped="$MAP" --appended="$bad" \
    --dataset="$WD/data/self-improvement/failure-labels.jsonl"
  assert_success
  [[ "$stderr" == *"is not an integer"* ]]
  [[ "$stderr" == *"appended_rows=0"* ]]
}

# --- dataset resolution (plugin-data-lib.sh) --------------------------

@test "a real run appends one row with the right counts, under --plugin-data" {
  local data="$BATS_TEST_TMPDIR/data"
  local repo
  repo="$(mk_git_fixture)"
  run_script_env --cwd "$repo" --env "CLAUDE_PROJECT_DIR=$repo" --unset CLAUDE_PLUGIN_DATA \
    -- "$SCRIPT" --worktask-id=wt-1 --run-index=2 --stage=ST \
    --context-set="$CTX" --changes="$CH" --mapped="$MAP" --appended="$APP" --plugin-data="$data"
  assert_success
  local counts="$data/self-improvement/pipeline-counts.jsonl"
  [ -f "$counts" ]
  run jq -e '.context_paths==2 and .changed_paths==1 and .mapped_rows==1 and .appended_rows==2
             and .worktask_id=="wt-1" and .run_index==2 and .stage=="ST"
             and .dataset_source=="plugin-data" and .labels_enabled==true' "$counts"
  assert_success
  run bash -c "git -C '$repo' status --porcelain --untracked-files=all"
  [ -z "$output" ]
  [ ! -d "$repo/evals" ]
}

@test "--dry-run writes no row" {
  local data="$BATS_TEST_TMPDIR/dry-data"
  run_script_env -- "$SCRIPT" --worktask-id=wt-1 --run-index=0 \
    --context-set="$CTX" --changes="$CH" --mapped="$MAP" --appended="$APP" \
    --plugin-data="$data" --dry-run
  assert_success
  [ ! -f "$data/self-improvement/pipeline-counts.jsonl" ]
}

@test "flag beats env: --plugin-data wins over CLAUDE_PLUGIN_DATA" {
  local flag_dir="$BATS_TEST_TMPDIR/flag-data"
  local env_dir="$BATS_TEST_TMPDIR/env-data"
  run_script_env --env "CLAUDE_PLUGIN_DATA=$env_dir" \
    -- "$SCRIPT" --worktask-id=wt-1 --run-index=0 \
    --context-set="$CTX" --changes="$CH" --mapped="$MAP" --appended="$APP" --plugin-data="$flag_dir"
  assert_success
  [ -f "$flag_dir/self-improvement/pipeline-counts.jsonl" ]
  [ ! -e "$env_dir" ]
}

@test "relative --plugin-data exits 1" {
  run_script_env -- "$SCRIPT" --worktask-id=wt-1 --run-index=0 \
    --context-set="$CTX" --changes="$CH" --mapped="$MAP" --appended="$APP" \
    --plugin-data="relative/dir"
  assert_failure
}

@test "unset CLAUDE_PLUGIN_DATA falls back with a stderr notice and no counts row" {
  local repo
  repo="$(mk_git_fixture)"
  run_script_env --cwd "$repo" --env "CLAUDE_PROJECT_DIR=$repo" --unset CLAUDE_PLUGIN_DATA \
    --separate-stderr -- "$SCRIPT" --worktask-id=wt-1 --run-index=0 \
    --context-set="$CTX" --changes="$CH" --mapped="$MAP" --appended="$APP"
  assert_success
  [[ "$stderr" == *"plugin data dir unavailable"* ]]
  [ ! -f "$repo/evals/pipeline-counts.jsonl" ]
}

@test "empty CLAUDE_PLUGIN_DATA falls back the same way" {
  local repo
  repo="$(mk_git_fixture)"
  run_script_env --cwd "$repo" --env "CLAUDE_PROJECT_DIR=$repo" --env "CLAUDE_PLUGIN_DATA=" \
    --separate-stderr -- "$SCRIPT" --worktask-id=wt-1 --run-index=0 \
    --context-set="$CTX" --changes="$CH" --mapped="$MAP" --appended="$APP"
  assert_success
  [[ "$stderr" == *"plugin data dir unavailable"* ]]
}

@test "the unsubstituted literal token falls back the same way" {
  local repo
  repo="$(mk_git_fixture)"
  run_script_env --cwd "$repo" --env "CLAUDE_PROJECT_DIR=$repo" \
    --env 'CLAUDE_PLUGIN_DATA=${CLAUDE_PLUGIN_DATA}' \
    --separate-stderr -- "$SCRIPT" --worktask-id=wt-1 --run-index=0 \
    --context-set="$CTX" --changes="$CH" --mapped="$MAP" --appended="$APP"
  assert_success
  [[ "$stderr" == *"plugin data dir unavailable"* ]]
}

@test "SELF_IMPROVE_LABELS=0 flips labels_enabled but the row still writes" {
  local data="$BATS_TEST_TMPDIR/opt-out-data"
  run_script_env --env "SELF_IMPROVE_LABELS=0" \
    -- "$SCRIPT" --worktask-id=wt-1 --run-index=0 \
    --context-set="$CTX" --changes="$CH" --mapped="$MAP" --appended="$APP" --plugin-data="$data"
  assert_success
  local counts="$data/self-improvement/pipeline-counts.jsonl"
  run grep -q '"labels_enabled":false' "$counts"
  assert_success
}

# --- repo hygiene --------------------------------------------------------------

@test "the real repo's evals/failure-labels.jsonl is unchanged by this suite" {
  run bash -c "git -C '$PLUGIN_ROOT' diff --quiet -- evals/failure-labels.jsonl"
  assert_success
}

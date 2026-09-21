#!/usr/bin/env bats
# Contract tests for skills/worktask/scripts/seed-state.sh.
# Contracts (from the header):
#   - exit 0 seeds the exact v2 shape; stdout is result/state/run_index/plan_file only
#   - run_index is the next free planning-<N>.md index
#   - exit 3 refuses an existing ledger byte-identical, with no temp or lock left
#   - the goal is sanitized and capped in jq, never evaluated
#   - the context ladder never leaves the invoking worktree (exit 4 instead)
#   - the seeded ledger round-trips through skills/worktask/scripts/state-patch.sh
#     --task-create: a full-key non-PL row lands, a row missing base_ref exits 2
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/seed-state.sh"
PATCH="skills/worktask/scripts/state-patch.sh"
FULL_META='{"agent":"x","effort":"high","isolation":"worktree","base_ref":"origin/develop","requires_screenshots":false,"workspace_path":"/abs"}'
NO_BASE_META='{"agent":"x","effort":"high","isolation":"worktree","requires_screenshots":false,"workspace_path":"/abs"}'

setup() {
  WD="$(mk_tmpworkdir)"
  # Physical: macOS temp dirs sit behind a /var -> /private/var symlink and state= is physical.
  WD="$(cd "$WD" && pwd -P)"
  unset CDPATH GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR STATE_LOCK_TIMEOUT_S
  export HOME="$WD" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$WD"
}

# _repo <dir> [--context] — a git repo with one commit, optionally with .context/.
_repo() {
  mkdir -p "$1"
  git -c init.defaultBranch=main -C "$1" init -q
  git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty --no-verify -m i
  if [ "${2:-}" = "--context" ]; then mkdir -p "$1/.context"; fi
}

@test "shape: exit 0 seeds the exact v2 ledger and none of the unseeded keys" {
  _repo "$WD/r" --context
  run_script_env --separate-stderr --cwd "$WD/r" "$SCRIPT" \
    --worktask-id wt-1 --goal hello --platform systems
  assert_success
  run jq -e --arg ws "$WD/r" '
    (keys_unsorted == ["version","worktask_id","plan_file","platform","run_index",
                       "metadata","tasks","facts","handoffs"])
    and .version == 2 and .worktask_id == "wt-1" and .platform == "systems"
    and .plan_file == ".context/planning-0.md" and .run_index == 0
    and .metadata == {workspace_path: $ws}
    and .tasks == {PL0: {status: "in_progress"}}
    and .facts == {goal: "hello", files_modified: [], tests_added: [], decisions: [],
                   open_questions: [], verdicts: {}, dispatched_agents: []}
    and .handoffs == {}
    and ([paths | .[] | strings
          | select(. == "completed_via" or . == "last_error"
                   or . == "worktree" or . == "capabilities")] | length == 0)' \
    "$WD/r/.context/state.json"
  assert_success
}

@test "stdout: exit 0 prints exactly the four key=value lines" {
  _repo "$WD/r" --context
  run_script_env --separate-stderr --cwd "$WD/r" "$SCRIPT" --worktask-id wt-1 --goal g
  assert_success
  assert_equal "${#lines[@]}" 4
  assert_line --index 0 "result=seeded"
  assert_line --index 1 "state=$WD/r/.context/state.json"
  assert_line --index 2 "run_index=0"
  assert_line --index 3 "plan_file=.context/planning-0.md"
  assert_equal "$stderr" ""
}

@test "index: planning-0 and planning-2 give run_index 3; malformed names are ignored" {
  _repo "$WD/r" --context
  : > "$WD/r/.context/planning-0.md"
  : > "$WD/r/.context/planning-2.md"
  : > "$WD/r/.context/planning-1a.md"
  : > "$WD/r/.context/planning-.md"
  run_script_env --separate-stderr --cwd "$WD/r" "$SCRIPT" --worktask-id wt-3 --goal g
  assert_success
  assert_line "run_index=3"
  assert_line "plan_file=.context/planning-3.md"
  run jq -e '.run_index == 3 and .plan_file == ".context/planning-3.md" and .platform == "all"' \
    "$WD/r/.context/state.json"
  assert_success
}

@test "atomic: a seed leaves no temp file and no lock dir behind" {
  _repo "$WD/r" --context
  run_script_env --separate-stderr --cwd "$WD/r" "$SCRIPT" --worktask-id wt-4 --goal g
  assert_success
  run ls -A "$WD/r/.context"
  assert_output "state.json"
}

@test "exists: a second seed exits 3 with the ledger byte-identical" {
  _repo "$WD/r" --context
  run_script_env --separate-stderr --cwd "$WD/r" "$SCRIPT" --worktask-id wt-5 --goal first
  assert_success
  cp "$WD/r/.context/state.json" "$WD/before.json"
  run_script_env --separate-stderr --cwd "$WD/r" "$SCRIPT" --worktask-id other --goal second
  assert_failure 3
  assert_equal "${#lines[@]}" 2
  assert_line --index 0 "result=exists"
  assert_line --index 1 "state=$WD/r/.context/state.json"
  [[ "$stderr" == *"refused"* ]] || fail "stderr lacks the refusal line: $stderr"
  cmp "$WD/before.json" "$WD/r/.context/state.json"
  run ls -A "$WD/r/.context"
  assert_output "state.json"
}

@test "goal: quotes, backslashes and control codepoints are sanitized, nothing evaluated" {
  _repo "$WD/r" --context
  local mid goal want
  mid="$(jq -nr '[97,1,10,133,98] | implode')"
  goal="  \"q\\ \$(touch $WD/sentinel) $mid  "
  want="\"q\\ \$(touch $WD/sentinel) a b"
  run_script_env --separate-stderr --cwd "$WD/r" "$SCRIPT" --worktask-id wt-6 --goal "$goal"
  assert_success
  [ ! -e "$WD/sentinel" ] || fail "the goal was evaluated"
  run jq -e --arg want "$want" '.facts.goal == $want' "$WD/r/.context/state.json"
  assert_success
}

@test "goal: longer than 240 codepoints is cut to 239 plus an ellipsis; 240 is kept" {
  _repo "$WD/r"
  mkdir -p "$WD/r/a" "$WD/r/b" "$WD/r/c"
  run_script_env --separate-stderr --cwd "$WD/r" "$SCRIPT" --worktask-id wt-7 \
    --goal "$(jq -nr '[range(300) | 120] | implode')" --context-dir "$WD/r/a"
  assert_success
  run jq -e '(.facts.goal | length) == 240
    and (.facts.goal | endswith([8230] | implode))
    and (.facts.goal[0:239] == ([range(239) | 120] | implode))' "$WD/r/a/state.json"
  assert_success
  run_script_env --separate-stderr --cwd "$WD/r" "$SCRIPT" --worktask-id wt-7 \
    --goal "$(jq -nr '[range(240) | 120] | implode')" --context-dir "$WD/r/b"
  assert_success
  run jq -e '.facts.goal == ([range(240) | 120] | implode)' "$WD/r/b/state.json"
  assert_success
  run_script_env --separate-stderr --cwd "$WD/r" "$SCRIPT" --worktask-id wt-7 \
    --goal "$(jq -nr '[range(241) | 128512] | implode')" --context-dir "$WD/r/c"
  assert_success
  run jq -e '(.facts.goal | length) == 240
    and (.facts.goal[0:239] == ([range(239) | 128512] | implode))' "$WD/r/c/state.json"
  assert_success
}

@test "goal: word boundary — spaced goal over 240 ends on whole word plus ellipsis" {
  _repo "$WD/r"
  mkdir -p "$WD/r/a"
  run_script_env --separate-stderr --cwd "$WD/r" "$SCRIPT" --worktask-id wt-7b \
    --goal "$(jq -nr '[range(30) | "abcdefghi "] | add')" --context-dir "$WD/r/a"
  assert_success
  run jq -e '(.facts.goal | length) == 240
    and (.facts.goal | endswith([8230] | implode))
    and (.facts.goal == (([range(24) | "abcdefghi"] | join(" ")) + ([8230] | implode)))' \
    "$WD/r/a/state.json"
  assert_success
}

@test "ladder: a linked worktree seeds its own ledger, not CLAUDE_PROJECT_DIR's" {
  _repo "$WD/main" --context
  git -C "$WD/main" worktree add -q --detach "$WD/wt"
  mkdir "$WD/wt/.context"
  run_script_env --separate-stderr --cwd "$WD/wt" --env "CLAUDE_PROJECT_DIR=$WD/main" \
    "$SCRIPT" --worktask-id wt-8 --goal g
  assert_success
  assert_line "state=$WD/wt/.context/state.json"
  [ ! -e "$WD/main/.context/state.json" ] || fail "the parent checkout's ledger was written"
}

@test "ladder: a worktree without .context exits 4 and the parent stays untouched" {
  _repo "$WD/main" --context
  git -C "$WD/main" worktree add -q --detach "$WD/wt"
  run_script_env --separate-stderr --cwd "$WD/wt" --env "CLAUDE_PROJECT_DIR=$WD/main" \
    "$SCRIPT" --worktask-id wt-9 --goal g
  assert_failure 4
  assert_output ""
  [ ! -e "$WD/main/.context/state.json" ] || fail "the parent checkout's ledger was written"
  [ ! -e "$WD/wt/.context" ] || fail "a context dir was created in the worktree"
}

@test "ladder: --context-dir outranks CONTEXT_DIR; a missing --context-dir exits 4" {
  _repo "$WD/r"
  mkdir -p "$WD/r/flag" "$WD/r/env"
  run_script_env --separate-stderr --cwd "$WD/r" --env "CONTEXT_DIR=$WD/r/env" \
    "$SCRIPT" --worktask-id wt-10 --goal g --context-dir "$WD/r/flag"
  assert_success
  assert_line "state=$WD/r/flag/state.json"
  [ ! -e "$WD/r/env/state.json" ] || fail "CONTEXT_DIR won over --context-dir"
  run_script_env --separate-stderr --cwd "$WD/r" "$SCRIPT" \
    --worktask-id wt-10 --goal g --context-dir "$WD/r/missing"
  assert_failure 4
  assert_output ""
  [ ! -e "$WD/r/missing" ] || fail "--context-dir was created"
}

@test "round trip: state-patch.sh --task-create DV0 with every mandatory key lands" {
  _repo "$WD/r" --context
  run_script_env --separate-stderr --cwd "$WD/r" "$SCRIPT" --worktask-id wt-11 --goal g
  assert_success
  run bash "$PLUGIN_ROOT/$PATCH" --state "$WD/r/.context/state.json" --log "$WD/patch.log" \
    --task-create DV0 --metadata "$FULL_META"
  assert_success
  run jq -e '.tasks.DV0.status == "pending" and .tasks.DV0.metadata.base_ref == "origin/develop"
    and .tasks.PL0.status == "in_progress"' "$WD/r/.context/state.json"
  assert_success
}

@test "round trip: --task-create without base_ref exits 2 with the ledger byte-identical" {
  _repo "$WD/r" --context
  run_script_env --separate-stderr --cwd "$WD/r" "$SCRIPT" --worktask-id wt-12 --goal g
  assert_success
  cp "$WD/r/.context/state.json" "$WD/before.json"
  run --separate-stderr bash "$PLUGIN_ROOT/$PATCH" --state "$WD/r/.context/state.json" \
    --log "$WD/patch.log" --task-create DV0 --metadata "$NO_BASE_META"
  assert_failure 2
  [[ "$stderr" == *"base_ref"* ]] || fail "stderr does not name base_ref: $stderr"
  cmp "$WD/before.json" "$WD/r/.context/state.json"
}

@test "usage: malformed invocations exit 2 with empty stdout and nothing written" {
  _repo "$WD/r" --context
  local -a cases=(
    "--worktask-id|wt-13"
    "--worktask-id|wt-13|--goal|g|--bogus|x"
    "--worktask-id|wt-13|--goal|g|--workspace-path|rel/path"
    "--worktask-id=wt-13|--goal|g"
    "--worktask-id|wt-13|--goal|g|--goal|h"
    "--worktask-id|wt-13|--goal"
    "--worktask-id|bad id|--goal|g"
    "--worktask-id|wt-13|--goal|g|--platform|iOS"
    "--worktask-id|wt-13|--goal|g|stray"
  )
  local c
  local -a argv
  for c in "${cases[@]}"; do
    IFS='|' read -r -a argv <<< "$c"
    run_script_env --separate-stderr --cwd "$WD/r" "$SCRIPT" "${argv[@]}"
    [ "$status" -eq 2 ] || fail "expected exit 2 for [$c], got $status"
    [ -z "$output" ] || fail "expected empty stdout for [$c], got: $output"
  done
  run ls -A "$WD/r/.context"
  assert_output ""
}

@test "help: --help documents the bash invocation and every exit code" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --help
  assert_success
  # shellcheck disable=SC2016 # the usage text is matched literally
  assert_output --partial 'bash "$PLUGIN_ROOT/skills/worktask/scripts/seed-state.sh" --worktask-id'
  assert_output --partial "--self-test"
  assert_output --partial "@exitcode 3"
  assert_output --partial "@exitcode 4"
}

@test "self-test: --self-test exits 0 and reports ALL PASS" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "ALL PASS"
}

#!/usr/bin/env bats
# Contract tests for the /megatask per-issue run environment (commands/megatask.md § Step 3 —
# run environment in the per-issue prompt; commands/worktask.md § Per-issue run under
# /megatask):
#   - both files state one Bash prefix, `cd "<wt>" && export WORKSPACE_ROOT="<wt>" MILESTONE_MODE=1 &&`;
#   - run literally from megatask's root, as a subagent's shell starts, that prefix makes
#     seed-state.sh and state-patch.sh write the worktree's ledger and leave megatask's alone,
#     and the scan, preflight and branch scripts see a per-issue run;
#   - without the export, state-patch.sh resolves megatask's ledger (why the prefix exports);
#   - Step 2a never asks, Phase 3 is skipped, and nothing calls EnterWorktree.
#
# Nothing here launches a subagent: the prefix is executed by bash exactly as the prompt
# states it, which is the part of the run a test can reach.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

MEGATASK_DOC="commands/megatask.md"
WORKTASK_DOC="commands/worktask.md"
SKILL_DOC="skills/worktask/SKILL.md"
ENV_HEAD="#### Step 3 — run environment in the per-issue prompt"
PER_ISSUE_HEAD='### Per-issue run under `/megatask`'
SCRIPTS="skills/worktask/scripts"

section() {
  awk -v h="$2" '$0 == h {f=1; print; next} f && /^#/ {exit} f {print}' "$PLUGIN_ROOT/$1"
}

# The prefix as megatask Step 3 states it, `<wt>` still in place.
doc_prefix() {
  section "$MEGATASK_DOC" "$ENV_HEAD" \
    | sed -n 's/^- Begin every Bash call with `\(cd "<wt>" && [^`]*&&\)`\.$/\1/p' | head -1
}

setup() {
  ROOT="$(mk_tmpworkdir)"
  WT="$ROOT/.worktrees/milestone-9/41"
  mkdir -p "$ROOT/.context/logs" "$WT/.context"
  printf '{"version":2,"run_index":0,"tasks":{"PL0":{"status":"completed","metadata":{}}}}\n' \
    > "$ROOT/.context/state.json"
  cp "$ROOT/.context/state.json" "$ROOT/state.before"
  printf '{"version":"2.0","isolation":"worktree","execution":{"status":"in_progress"}}\n' \
    > "$WT/workspace.json"
  WT_PHYS="$(cd "$WT" && pwd -P)"
}

# in_run <command…> — one Bash call of the per-issue subagent: cwd and CLAUDE_PROJECT_DIR are
# megatask's root, and the documented prefix opens the call.
in_run() {
  local prefix
  prefix="$(doc_prefix)"
  prefix="${prefix//<wt>/$WT}"
  cd "$ROOT"
  run env -u WORKSPACE_ROOT -u MILESTONE_MODE -u CONTEXT_DIR CLAUDE_PROJECT_DIR="$ROOT" \
    bash -c "$prefix $*"
}

@test "prefix: megatask Step 3 and worktask's per-issue section state the same one" {
  local p
  p="$(doc_prefix)"
  [ "$p" = 'cd "<wt>" && export WORKSPACE_ROOT="<wt>" MILESTONE_MODE=1 &&' ] \
    || fail "megatask Step 3 prefix changed or missing: [$p]"
  section "$WORKTASK_DOC" "$PER_ISSUE_HEAD" | grep -qF "\`$p\`" \
    || fail "$WORKTASK_DOC § Per-issue run under /megatask does not state the same prefix"
}

@test "prefix: seed-state.sh and state-patch.sh write the worktree's ledger, not megatask's" {
  in_run "bash '$PLUGIN_ROOT/$SCRIPTS/seed-state.sh' --worktask-id issue-41 --goal 'Add login'"
  assert_success
  assert_line "result=seeded"
  in_run "bash '$PLUGIN_ROOT/$SCRIPTS/state-patch.sh' --task-meta PL0 --set '{\"megatask_group\":\"milestone-9\",\"workspace_path\":\"$WT_PHYS\"}'"
  assert_success
  run jq -r '"\(.metadata.workspace_path) \(.tasks.PL0.metadata.megatask_group)"' "$WT/.context/state.json"
  assert_output "$WT_PHYS milestone-9"
  cmp -s "$ROOT/.context/state.json" "$ROOT/state.before" || fail "megatask's ledger changed"
}

@test "why the export: with only the cd, state-patch.sh resolves megatask's ledger" {
  printf '{"version":2,"run_index":0,"tasks":{"PL0":{"status":"in_progress","metadata":{}}}}\n' \
    > "$WT/.context/state.json"
  cd "$ROOT"
  run env -u WORKSPACE_ROOT -u CONTEXT_DIR CLAUDE_PROJECT_DIR="$ROOT" \
    bash -c "cd '$WT' && bash '$PLUGIN_ROOT/$SCRIPTS/state-patch.sh' --task-meta PL0 --set '{\"probe\":1}'"
  assert_success
  run jq -r '.tasks.PL0.metadata.probe' "$ROOT/.context/state.json"
  assert_output "1"
  run jq -r '.tasks.PL0.metadata.probe' "$WT/.context/state.json"
  assert_output "null"
}

@test "prefix: the scan, the autonomy preflight and the branch rename all see a per-issue run" {
  printf '{"version":2,"run_index":0,"tasks":{"PL0":{"status":"in_progress","metadata":{}}}}\n' \
    > "$WT/.context/state.json"
  in_run "bash '$PLUGIN_ROOT/$SCRIPTS/preflight-issue-scan.sh' --goal 'Add login'"
  assert_success
  assert_line "result=skipped"
  assert_line "reason=milestone_mode"
  in_run "bash '$PLUGIN_ROOT/$SCRIPTS/autonomy-preflight.sh' --auto plan,decision,finalization --platform none"
  assert_success
  assert_line "reason=milestone_mode"
  in_run "BRANCH_NAME_PRINT=1 bash '$PLUGIN_ROOT/$SCRIPTS/branch-name.sh' --goal 'Add login'"
  assert_success
  assert_output --partial "milestone_mode_env"
}

@test "Step 2a: a per-issue run never reaches the duplicate-issue question" {
  section "$WORKTASK_DOC" "#### Step 2a — the gate" | tr '\n' ' ' \
    | grep -qF 'A `/megatask` per-issue run never asks' \
    || fail "Step 2a's gate no longer rules out the question under /megatask"
  section "$WORKTASK_DOC" "#### Per-issue run — what changes" \
    | grep -E '^\| 2a-pre, 2a \|' | grep -qF 'no `AskUserQuestion` runs' \
    || fail "the per-issue table no longer says Step 2a asks nothing"
}

@test "Phase 3: skipped under /megatask in the command and the skill" {
  section "$WORKTASK_DOC" "## Phase 3: Post-Worktask Self-Improvement" | tr '\n' ' ' \
    | grep -qF 'A `/megatask` per-issue run skips this phase' \
    || fail "$WORKTASK_DOC § Phase 3 does not skip under /megatask"
  section "$SKILL_DOC" "## Post-Worktask Self-Improvement" \
    | grep -qF 'except in a `/megatask` per-issue run' \
    || fail "$SKILL_DOC § Post-Worktask Self-Improvement does not skip under /megatask"
}

@test "EnterWorktree: never called by the per-issue run or its DV stage" {
  section "$MEGATASK_DOC" "$ENV_HEAD" | grep -qF 'Never call `EnterWorktree`' \
    || fail "megatask's run environment no longer forbids EnterWorktree"
  section "$WORKTASK_DOC" "#### Per-issue run — what changes" \
    | grep -E '^\| `EnterWorktree` \|' | grep -qF 'Never called' \
    || fail "the per-issue table no longer forbids EnterWorktree"
  section "$SKILL_DOC" "##### Step 4.8 — isolation banner" | tr '\n' ' ' \
    | grep -qE 'megatask_group[^:]*\? *`WORKTREE ISOLATION: WORKSPACE_ROOT is already an isolated worktree\. Never call ` *\+ *`EnterWorktree' \
    || fail "the DV isolation banner has no /megatask arm forbidding EnterWorktree"
}

#!/usr/bin/env bats
# Tests for hooks/megatask-monitor.sh (DV0c) — SubagentStop/Stop reconciliation
# sweep over .worktrees/*/orchestrator.json. Settles completed issues, unblocks
# dependents, frees tracks, and writes a megatask_progress audit row.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="hooks/megatask-monitor.sh"

# Seed a milestone-9 group: issue 41 (in_progress, completed in workspace.json)
# blocks issue 42 (blocked).
_seed_group() {
  local root="$1"
  mkdir -p "$root/.worktrees/milestone-9/41" \
           "$root/.worktrees/milestone-9/42" "$root/.context/logs"
  cat > "$root/.worktrees/milestone-9/orchestrator.json" <<'EOF'
{ "version":"3.1","group":"milestone-9","milestone":{"number":9,"title":"T"},
  "configuration":{"parallel_tracks":2,"isolation":"worktree"},
  "topological_order":[41,42],
  "issues":[
    {"number":41,"priority":"P0","status":"in_progress","track":1,"level":0,"blocked_by":[],"blocks":[42]},
    {"number":42,"priority":"P1","status":"blocked","track":null,"level":1,"blocked_by":[41],"blocks":[]}],
  "tracks":{"1":{"issue_number":41,"task_prefix":"t1"},"2":{"issue_number":null,"status":"available"}},
  "progress":{"total":2,"completed":0,"in_progress":1,"ready":0,"blocked":1,"failed":0} }
EOF
}

setup() {
  WD="$(mk_tmpworkdir)"
}

@test "happy: completed issue settles, dependent unblocks, track frees" {
  _seed_group "$WD"
  cat > "$WD/.worktrees/milestone-9/41/workspace.json" <<'EOF'
{ "version":"2.0","isolation":"worktree","execution":{"status":"completed","pr":"https://x/pull/1"} }
EOF
  cat > "$WD/.worktrees/milestone-9/42/workspace.json" <<'EOF'
{ "version":"2.0","isolation":"worktree","execution":{"status":"in_progress"} }
EOF
  run env WORKSPACE_ROOT="$WD" CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" < /dev/null
  assert_success
  local orch="$WD/.worktrees/milestone-9/orchestrator.json"
  run jq -e '
       (.issues[] | select(.number==41) | .status=="completed" and .pr=="https://x/pull/1" and .track==null)
    and (.issues[] | select(.number==42) | .status=="ready" and ((.blocked_by|length)==0))
    and (.tracks["1"].issue_number==null)
    and (.progress.completed==1 and .progress.ready==1 and .progress.blocked==0)
  ' "$orch"
  assert_success
  run grep -q megatask_progress "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "edge: a still-in_progress issue is left untouched (idempotent sweep)" {
  _seed_group "$WD"
  cat > "$WD/.worktrees/milestone-9/41/workspace.json" <<'EOF'
{ "version":"2.0","isolation":"worktree","execution":{"status":"in_progress"} }
EOF
  run env WORKSPACE_ROOT="$WD" CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" < /dev/null
  assert_success
  local orch="$WD/.worktrees/milestone-9/orchestrator.json"
  run jq -e '(.issues[] | select(.number==41) | .status=="in_progress")
             and (.issues[] | select(.number==42) | .status=="blocked")' "$orch"
  assert_success
}

@test "edge: failed issue settles but does NOT unblock its dependent" {
  _seed_group "$WD"
  cat > "$WD/.worktrees/milestone-9/41/workspace.json" <<'EOF'
{ "version":"2.0","isolation":"worktree","execution":{"status":"failed"} }
EOF
  run env WORKSPACE_ROOT="$WD" CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" < /dev/null
  assert_success
  local orch="$WD/.worktrees/milestone-9/orchestrator.json"
  run jq -e '(.issues[] | select(.number==41) | .status=="failed")
             and (.issues[] | select(.number==42) | .status=="blocked" and ((.blocked_by|length)==1))
             and (.progress.failed==1)' "$orch"
  assert_success
}

@test "failure: no .worktrees groups present -> self-skip, no crash" {
  mkdir -p "$WD/.context/logs"
  run env WORKSPACE_ROOT="$WD" CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" < /dev/null
  assert_success
  [ ! -f "$WD/.context/logs/audit.jsonl" ]
}

@test "contract: --self-test passes (smoke, NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "self-test OK"
}

#!/usr/bin/env bats
# Contract tests for skills/worktask/scripts/workspace-root-banner.sh (S4, AC4).
# Contracts (from the header + handoff-protocol.md § DV fan-out — ledger tasks):
#   - a row with metadata.workspace_path renders that path
#   - a row without one renders the orchestrator root (--orch-root, else git toplevel)
#   - unknown or malformed task id => exit 2, no banner line
#   - a workspace_path that is neither a string nor absent/null => exit 2, no fallback
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/workspace-root-banner.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/orch/.context"
  cat > "$WD/orch/.context/state.json" << 'EOF'
{"tasks":{
  "DV0":{"status":"pending","metadata":{"stage":"DV","stream":"service"}},
  "DV1":{"status":"pending","metadata":{"stage":"DV","stream":"web","workspace_path":"/x"}},
  "DV2":{"status":"pending","metadata":{"stage":"DV","workspace_path":null}},
  "DV3":{"status":"pending","metadata":{"stage":"DV","workspace_path":42}},
  "DV4":{"status":"pending","metadata":{"stage":"DV","workspace_path":{"path":"/x"}}}
}}
EOF
  (cd "$WD/orch" && git init -q . && git config user.email t@t.t && git config user.name t)
  ORCH_REAL="$(cd "$WD/orch" && git rev-parse --show-toplevel)"
}

@test "AC4: a task with metadata.workspace_path renders that path" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --state "$WD/orch/.context/state.json" --task DV1 --orch-root /orch
  assert_success
  assert_output "WORKSPACE_ROOT=/x"
}

@test "AC4: a task without metadata.workspace_path renders --orch-root" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --state "$WD/orch/.context/state.json" --task DV0 --orch-root /orch
  assert_success
  assert_output "WORKSPACE_ROOT=/orch"
}

@test "AC4: no --orch-root falls back to the git toplevel, and a null path counts as unset" {
  cd "$WD/orch"
  run bash "$PLUGIN_ROOT/$SCRIPT" --state "$WD/orch/.context/state.json" --task DV2
  assert_success
  assert_output "WORKSPACE_ROOT=$ORCH_REAL"
}

@test "default --state resolves the ledger through the context-dir ladder" {
  cd "$WD/orch"
  run env -u CONTEXT_DIR -u CLAUDE_PROJECT_DIR WORKSPACE_ROOT="$WD/orch" \
    bash "$PLUGIN_ROOT/$SCRIPT" --task DV1
  assert_success
  assert_output "WORKSPACE_ROOT=/x"
}

@test "failure: an unknown task id exits 2 and prints no banner" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --state "$WD/orch/.context/state.json" --task DV7 --orch-root /orch
  assert_failure 2
  assert_output --partial "unknown task id: DV7"
  refute_output --partial "WORKSPACE_ROOT="
}

@test "failure: a malformed task id exits 2 before the ledger is read" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --state "$WD/absent.json" --task '.tasks'
  assert_failure 2
  assert_output --partial "malformed task id"
}

@test "failure: a newline-bearing task id is malformed, not matched line by line" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --state "$WD/orch/.context/state.json" --task $'DV1\nx' --orch-root /orch
  assert_failure 2
  assert_output --partial "malformed task id"
  refute_output --partial "WORKSPACE_ROOT="
}

@test "failure: a non-string workspace_path exits 2 instead of falling back to the orchestrator root" {
  local id
  for id in DV3 DV4; do
    run bash "$PLUGIN_ROOT/$SCRIPT" --state "$WD/orch/.context/state.json" --task "$id" --orch-root /orch
    assert_failure 2
    assert_output --partial "tasks.$id.metadata.workspace_path is a"
    refute_output --partial "WORKSPACE_ROOT="
  done
}

@test "failure: missing --task and unknown flags are usage errors (exit 2)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --state "$WD/orch/.context/state.json"
  assert_failure 2
  run bash "$PLUGIN_ROOT/$SCRIPT" --bogus
  assert_failure 2
}

@test "contract: --self-test passes" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "self-test OK"
}

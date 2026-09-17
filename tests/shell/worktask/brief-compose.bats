#!/usr/bin/env bats
# Contract tests for skills/worktask/scripts/brief-compose.sh.
# Contracts (from the script header):
#   - --self-test runs the built-in harness (ref, guard and fan-out fixtures) and exits 0
#   - an absolute path outside every allowed root fails closed: exit 1, empty stdout,
#     one "brief-compose: <reason>: <token>" stderr line
#   - an unknown or malformed task id is a usage-class failure: exit 2, no stdout
#   - the orchestrator loop wires brief-compose.sh into SKILL.md and commands/worktask.md
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/brief-compose.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context"
  cat > "$WD/.context/planning-0.md" << 'EOF'
## requirements

Fixture requirement text.

## acceptance-criteria

Fixture acceptance text.
EOF
}

@test "contract: --self-test passes" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "self-test OK"
}

@test "guard: an off-root absolute path in the ledger fails closed" {
  cat > "$WD/.context/state.json" << EOF
{
  "worktask_id": "brief-compose-bats",
  "plan_file": ".context/planning-0.md",
  "run_index": 0,
  "tasks": {
    "DV0": {
      "metadata": {
        "stage": "DV",
        "model": "opus",
        "run_index": 0,
        "workspace_path": "$WD",
        "description": "touches /opt/elsewhere/x.md outside every allowed root"
      }
    }
  }
}
EOF
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" DV0 --state "$WD/.context/state.json" --orch-root "$WD"
  assert_failure 1
  assert_output ""
  [[ "$stderr" == *"brief-compose: "* ]]
}

@test "usage: an unknown or malformed task id exits 2 with no stdout" {
  cat > "$WD/.context/state.json" << EOF
{
  "worktask_id": "brief-compose-bats",
  "plan_file": ".context/planning-0.md",
  "run_index": 0,
  "tasks": {
    "DV0": {
      "metadata": {"stage": "DV", "model": "opus", "run_index": 0, "workspace_path": "$WD"}
    }
  }
}
EOF
  run bash "$PLUGIN_ROOT/$SCRIPT" ZZ9 --state "$WD/.context/state.json" --orch-root "$WD"
  assert_failure 2
  assert_output ""

  run bash "$PLUGIN_ROOT/$SCRIPT" 'not-an-id' --state "$WD/.context/state.json" --orch-root "$WD"
  assert_failure 2
  assert_output ""
}

@test "wiring: the orchestrator loop wires brief-compose.sh into SKILL.md and commands/worktask.md" {
  cd "$PLUGIN_ROOT"
  run grep -q 'brief-compose\.sh' skills/worktask/SKILL.md
  assert_success
  run grep -q 'brief-compose\.sh' commands/worktask.md
  assert_success
}

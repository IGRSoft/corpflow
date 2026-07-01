#!/usr/bin/env bats
# Contract tests for skills/worktask/references/hook-install.sh.
# Contracts (from header + body):
#   - default (install): copies state-merge.sh -> .claude/hooks/, chmod +x; idempotent
#   - --check: exit 0 when installed + registered, exit 1 when hook missing
#   - CLAUDE_PLUGIN_ROOT overrides plugin-root discovery
#   - --self-test => "ALL PASS", exit 0
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/references/hook-install.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  # synthetic plugin root with a source hook + registering plugin.json
  PLUG="$WD/plugin"
  mkdir -p "$PLUG/.claude/hooks" "$PLUG/.claude-plugin"
  printf '#!/usr/bin/env bash\necho stub\n' > "$PLUG/.claude/hooks/state-merge.sh"
  chmod +x "$PLUG/.claude/hooks/state-merge.sh"
  printf '%s\n' '{"name":"t","hooks":{"SubagentStop":[{"hooks":[{"type":"command","command":"state-merge.sh"}]}]}}' \
    > "$PLUG/.claude-plugin/plugin.json"
  PROJ="$WD/project"
  mkdir -p "$PROJ"
}

@test "happy: default install copies an executable state-merge.sh hook (exit 0)" {
  cd "$PROJ"
  run env CLAUDE_PLUGIN_ROOT="$PLUG" bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_output --partial "copied"
  [ -x "$PROJ/.claude/hooks/state-merge.sh" ]
}

@test "edge: a second install run is idempotent (no-op message, exit 0)" {
  cd "$PROJ"
  env CLAUDE_PLUGIN_ROOT="$PLUG" bash "$PLUGIN_ROOT/$SCRIPT" >/dev/null
  run env CLAUDE_PLUGIN_ROOT="$PLUG" bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_output --partial "idempotent"
}

@test "happy: --check succeeds once the hook is installed (exit 0)" {
  cd "$PROJ"
  env CLAUDE_PLUGIN_ROOT="$PLUG" bash "$PLUGIN_ROOT/$SCRIPT" >/dev/null
  run env CLAUDE_PLUGIN_ROOT="$PLUG" bash "$PLUGIN_ROOT/$SCRIPT" --check
  assert_success
  assert_output --partial "exists and is executable"
}

@test "failure: --check exits 1 when the hook is not installed" {
  cd "$PROJ"
  run env CLAUDE_PLUGIN_ROOT="$PLUG" bash "$PLUGIN_ROOT/$SCRIPT" --check
  assert_failure 1
}

@test "contract: --self-test passes (smoke, NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "ALL PASS"
}

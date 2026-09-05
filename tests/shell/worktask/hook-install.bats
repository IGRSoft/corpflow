#!/usr/bin/env bats
# Contract tests for skills/worktask/scripts/hook-install.sh.
# Contracts (from header + body):
#   - default (install): copies state-merge.sh -> .claude/hooks/, chmod +x; idempotent
#   - --check: exit 0 when installed + registered, exit 1 when hook missing
#   - CLAUDE_PLUGIN_ROOT overrides plugin-root discovery
#   - --self-test => "ALL PASS", exit 0
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/hook-install.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  # synthetic plugin root with a source hook + registering plugin.json
  PLUG="$WD/plugin"
  mkdir -p "$PLUG/hooks" "$PLUG/.claude-plugin"
  printf '#!/usr/bin/env bash\necho stub\n' > "$PLUG/hooks/state-merge.sh"
  chmod +x "$PLUG/hooks/state-merge.sh"
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

@test "edge: an existing non-executable hook is backed up to .bak before being overwritten" {
  cd "$PROJ"
  mkdir -p .claude/hooks
  printf 'CUSTOMIZED\n' > .claude/hooks/state-merge.sh
  chmod -x .claude/hooks/state-merge.sh
  run env CLAUDE_PLUGIN_ROOT="$PLUG" bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_output --partial "backed up"
  [ "$(cat .claude/hooks/state-merge.sh.bak)" = "CUSTOMIZED" ]
  [ -x .claude/hooks/state-merge.sh ]
}

@test "edge: a fresh install leaves no stray .bak behind" {
  cd "$PROJ"
  run env CLAUDE_PLUGIN_ROOT="$PLUG" bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  [ ! -e .claude/hooks/state-merge.sh.bak ]
}

@test "contract: --self-test passes (smoke, NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "ALL PASS"
}

# --- drift between hooks/state-merge.sh and its installed copy -----------------
#
# DR0 P2-4: this run shipped a symlink-refusal security fix into
# hooks/state-merge.sh. Nothing compared the installed copy to it, and the
# documented remedy (re-run the installer) no-opped on an existing file, so a
# stale hook kept running the pre-fix code with no signal anywhere.

@test "drift: --check fails when the installed hook differs from the plugin's" {
  cd "$PROJ"
  env CLAUDE_PLUGIN_ROOT="$PLUG" bash "$PLUGIN_ROOT/$SCRIPT" >/dev/null
  printf '#!/usr/bin/env bash\necho STALE\n' > .claude/hooks/state-merge.sh
  run env CLAUDE_PLUGIN_ROOT="$PLUG" bash "$PLUGIN_ROOT/$SCRIPT" --check
  assert_failure 1
  assert_output --partial "DIFFERS"
}

@test "drift: --check reports parity when the copies agree" {
  cd "$PROJ"
  env CLAUDE_PLUGIN_ROOT="$PLUG" bash "$PLUGIN_ROOT/$SCRIPT" >/dev/null
  run env CLAUDE_PLUGIN_ROOT="$PLUG" bash "$PLUGIN_ROOT/$SCRIPT" --check
  assert_success
  assert_output --partial "matches"
}

@test "drift: re-running the installer refreshes a stale copy and keeps a .bak" {
  cd "$PROJ"
  env CLAUDE_PLUGIN_ROOT="$PLUG" bash "$PLUGIN_ROOT/$SCRIPT" >/dev/null
  printf '#!/usr/bin/env bash\necho STALE\n' > .claude/hooks/state-merge.sh
  chmod +x .claude/hooks/state-merge.sh
  run env CLAUDE_PLUGIN_ROOT="$PLUG" bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_output --partial "refreshed stale"
  run cmp -s "$PLUG/hooks/state-merge.sh" .claude/hooks/state-merge.sh
  assert_success
  # The displaced copy is recoverable, and .bak stays out of the live-hook glob.
  run grep -q STALE .claude/hooks/state-merge.sh.bak
  assert_success
}

@test "drift: an up-to-date copy is still a no-op (idempotence is preserved)" {
  cd "$PROJ"
  env CLAUDE_PLUGIN_ROOT="$PLUG" bash "$PLUGIN_ROOT/$SCRIPT" >/dev/null
  run env CLAUDE_PLUGIN_ROOT="$PLUG" bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_output --partial "idempotent"
  [ ! -e .claude/hooks/state-merge.sh.bak ]
}

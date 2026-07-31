#!/usr/bin/env bats
# Guard for the v3.28.1 failure class: manifest/filesystem drift that silently
# breaks command/skill registration (AC-3), and version-triple drift across
# plugin.json / marketplace.json / README.md (AC-4).
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

@test "AC-3: marketplace.json commands[] matches commands/*.md filesystem set exactly" {
  local manifest_list fs_list
  manifest_list="$(jq -r '.plugins[0].commands[]' "$PLUGIN_ROOT/.claude-plugin/marketplace.json" \
    | sed 's#^\./##' | sort)"
  fs_list="$(cd "$PLUGIN_ROOT" && ls commands/*.md | sort)"
  diff <(printf '%s\n' "$manifest_list") <(printf '%s\n' "$fs_list")
}

@test "AC-4: plugin.json / marketplace.json / README.md agree on version" {
  local plugin_ver market_meta_ver market_plugin_ver
  plugin_ver="$(jq -r '.version' "$PLUGIN_ROOT/.claude-plugin/plugin.json")"
  market_meta_ver="$(jq -r '.metadata.version' "$PLUGIN_ROOT/.claude-plugin/marketplace.json")"
  market_plugin_ver="$(jq -r '.plugins[0].version' "$PLUGIN_ROOT/.claude-plugin/marketplace.json")"

  [ -n "$plugin_ver" ]
  [ "$plugin_ver" = "$market_meta_ver" ]
  [ "$plugin_ver" = "$market_plugin_ver" ]

  run grep -F -- "$plugin_ver" "$PLUGIN_ROOT/README.md"
  assert_success
}

@test "AC-9: test-execution-gate.sh is registered under PreToolUse and is executable on disk" {
  [ -x "$PLUGIN_ROOT/hooks/test-execution-gate.sh" ]
  run jq -r '.hooks.PreToolUse[].hooks[].command' "$PLUGIN_ROOT/.claude-plugin/plugin.json"
  assert_success
  assert_output --partial 'hooks/test-execution-gate.sh'
}

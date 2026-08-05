#!/usr/bin/env bats
# Contract test for skills/shared/plugin-root-resolution.md — freezes the
# CLAUDE_PLUGIN_ROOT reference grammar so provider-agnostic paths cannot
# silently regress:
#   - markdown may carry the token only in its exact bare form; composing a
#     path after the closing brace is reserved for CC-native config surfaces
#     (agent frontmatter hooks) and their verbatim documentation
#     (handoff-protocol.md);
#   - the shell default-value form (colon-dash) is script-only;
#   - scripts reading the env var must be the known env-first fallbacks.
# Scope: tracked files only (git ls-files) — .context/ runtime artifacts and
# untracked scratch are exempt; plugin.json is JSON, outside the .md glob.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

@test "contract: composed token in markdown only in whitelisted CC-config files" {
  run bash -c 'cd "$PLUGIN_ROOT" && git ls-files -z -- "*.md" \
    | xargs -0 grep -l "{CLAUDE_PLUGIN_ROOT}/" 2>/dev/null | LC_ALL=C sort; true'
  assert_output "agents/product-manager.md
agents/project-manager.md
agents/stakeholder.md
skills/worktask/references/handoff-protocol.md"
}

@test "contract: composed-token markdown line count frozen at 5" {
  # 3 agent frontmatter Stop hooks + handoff-protocol.md prose/JSON quote (2).
  run bash -c 'cd "$PLUGIN_ROOT" && git ls-files -z -- "*.md" \
    | xargs -0 grep -h "{CLAUDE_PLUGIN_ROOT}/" 2>/dev/null | wc -l'
  assert_equal "$(printf "%s" "$output" | tr -d "[:space:]")" "5"
}

@test "contract: default-value (colon-dash) token form never appears in markdown" {
  run bash -c 'cd "$PLUGIN_ROOT" && git ls-files -z -- "*.md" \
    | xargs -0 grep -n "CLAUDE_PLUGIN_ROOT:-" 2>/dev/null; true'
  assert_output ""
}

@test "contract: scripts reading the env var are the 4 known env-first fallbacks" {
  run bash -c 'cd "$PLUGIN_ROOT" && git ls-files -z -- "*.sh" \
    | xargs -0 grep -l "CLAUDE_PLUGIN_ROOT" 2>/dev/null | LC_ALL=C sort; true'
  assert_output ".claude/hooks/state-merge.sh
hooks/anchor-preflight.sh
skills/dv-screenshot-capture/scripts/apple-canvas.sh
skills/worktask/scripts/hook-install.sh"
}

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

# agents[] and skills[] were unguarded while commands[] was pinned, so a new agent
# or skill registered correctly on disk and silently missing from the listing broke
# nothing until a user installed from the marketplace.
@test "AC-3: marketplace.json agents[] matches agents/*.md filesystem set exactly" {
  local manifest_list fs_list
  manifest_list="$(jq -r '.plugins[0].agents[]' "$PLUGIN_ROOT/.claude-plugin/marketplace.json" \
    | sed 's#^\./##' | sort)"
  fs_list="$(cd "$PLUGIN_ROOT" && ls agents/*.md | sort)"
  diff <(printf '%s\n' "$manifest_list") <(printf '%s\n' "$fs_list")
}

@test "AC-3: marketplace.json skills[] matches the SKILL.md-bearing directory set exactly" {
  local manifest_list fs_list
  manifest_list="$(jq -r '.plugins[0].skills[]' "$PLUGIN_ROOT/.claude-plugin/marketplace.json" \
    | sed 's#^\./##' | sort)"
  # Carrying a SKILL.md is what makes a directory a skill, so discovery is by that
  # file rather than by depth: it admits skills/shared/milestone-helpers and excludes
  # skills/shared and skills/shared/lib, which are reference material and libraries.
  fs_list="$(cd "$PLUGIN_ROOT" && find skills -name SKILL.md | sed 's#/SKILL\.md$##' | sort)"
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

# The two manifests are read by different consumers — plugin.json by the runtime,
# marketplace.json by the marketplace listing — so a description or keyword edit
# applied to one drifts silently from the other. Nothing else compares them.
@test "AC-13: plugin.json and marketplace.json agree on description" {
  local plugin_desc market_desc market_meta_desc
  plugin_desc="$(jq -r '.description' "$PLUGIN_ROOT/.claude-plugin/plugin.json")"
  market_desc="$(jq -r '.plugins[0].description' "$PLUGIN_ROOT/.claude-plugin/marketplace.json")"
  market_meta_desc="$(jq -r '.metadata.description' "$PLUGIN_ROOT/.claude-plugin/marketplace.json")"

  [ -n "$plugin_desc" ]
  [ "$plugin_desc" = "$market_desc" ]
  [ "$plugin_desc" = "$market_meta_desc" ]
}

@test "AC-13: plugin.json and marketplace.json agree on keywords, capped at 15" {
  local plugin_kw market_kw count
  plugin_kw="$(jq -c '.keywords' "$PLUGIN_ROOT/.claude-plugin/plugin.json")"
  market_kw="$(jq -c '.plugins[0].keywords' "$PLUGIN_ROOT/.claude-plugin/marketplace.json")"
  [ "$plugin_kw" = "$market_kw" ] || fail "keyword drift: plugin=$plugin_kw marketplace=$market_kw"

  # The cap is what keeps the list a description of the plugin rather than a
  # changelog: the array reached 120 entries, most of them release-note tokens.
  count="$(jq -r '.keywords | length' "$PLUGIN_ROOT/.claude-plugin/plugin.json")"
  [ "$count" -ge 1 ]
  [ "$count" -le 15 ] || fail "keywords: $count entries, cap is 15"
}

@test "AC-13: no keyword is version- or release-note-shaped" {
  # CHANGELOG.md already carries per-release detail; a keyword naming a model
  # generation or a removed feature is stale the day the next version ships.
  run bash -c "jq -r '.keywords[]' '$PLUGIN_ROOT/.claude-plugin/plugin.json' \
    | grep -nE 'opus|sonnet|haiku|fable|[0-9]+\\.[0-9]+|removed|cleanup|default\$|deprecat'"
  assert_failure
}

@test "AC-9: test-execution-gate.sh is registered under PreToolUse and is executable on disk" {
  [ -x "$PLUGIN_ROOT/hooks/test-execution-gate.sh" ]
  run jq -r '.hooks.PreToolUse[].hooks[].command' "$PLUGIN_ROOT/.claude-plugin/plugin.json"
  assert_success
  assert_output --partial 'hooks/test-execution-gate.sh'
}

@test "AC-14: model-switch-gate.sh is registered under PreModelSwitch and is executable on disk" {
  [ -x "$PLUGIN_ROOT/hooks/model-switch-gate.sh" ]
  run jq -r '.hooks.PreModelSwitch[].hooks[].command' "$PLUGIN_ROOT/.claude-plugin/plugin.json"
  assert_success
  assert_output --partial 'hooks/model-switch-gate.sh'
}

@test "AC-14: model-switch-audit.sh is registered under PostModelSwitch and is executable on disk" {
  [ -x "$PLUGIN_ROOT/hooks/model-switch-audit.sh" ]
  run jq -r '.hooks.PostModelSwitch[].hooks[].command' "$PLUGIN_ROOT/.claude-plugin/plugin.json"
  assert_success
  assert_output --partial 'hooks/model-switch-audit.sh'
}

@test "AC-14: the shared model-switch library is sourced-only, never registered as a hook" {
  # A library wired as a hook command would be exec'd, hit its anti-execution
  # guard and exit 2 on every model switch.
  [ ! -x "$PLUGIN_ROOT/hooks/model-switch-lib.sh" ]
  run jq -r '[.. | .command? // empty] | .[]' "$PLUGIN_ROOT/.claude-plugin/plugin.json"
  assert_success
  refute_output --partial 'model-switch-lib.sh'
}

# Hooks reach the runtime by two independent routes: plugin.json (repo-wide firing) and
# agent frontmatter (fires only for that agent). The frontmatter route has no manifest to
# drift against, so a renamed or deleted script fails silently at dispatch time instead.
# These three tests are that missing check.

# Prints "<agent-file>:<hook-relpath>" for every ${CLAUDE_PLUGIN_ROOT}-composed hook
# command declared in an agent's YAML frontmatter (everything above the second `---`).
_frontmatter_hook_refs() {
  local f
  for f in "$PLUGIN_ROOT"/agents/*.md; do
    awk -v name="${f##*/}" '
      /^---[[:space:]]*$/ { fences++; if (fences >= 2) exit; next }
      fences == 1 && match($0, /\$\{CLAUDE_PLUGIN_ROOT\}\/[^"'"'"'[:space:]]+\.sh/) {
        ref = substr($0, RSTART, RLENGTH)
        sub(/^\$\{CLAUDE_PLUGIN_ROOT\}\//, "", ref)
        print name ":" ref
      }
    ' "$f"
  done
}

@test "frontmatter-wired hooks: every agent-declared hook script exists and is executable" {
  local refs count=0 entry script
  refs="$(_frontmatter_hook_refs)"

  # Non-vacuity: at least one agent must wire a hook, or this test asserts nothing.
  [ -n "$refs" ]

  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    script="${entry#*:}"
    [ -f "$PLUGIN_ROOT/$script" ] || fail "frontmatter hook missing on disk: $entry"
    [ -x "$PLUGIN_ROOT/$script" ] || fail "frontmatter hook not executable: $entry"
    count=$((count + 1))
  done <<< "$refs"

  [ "$count" -ge 3 ]
}

@test "frontmatter-wired hooks: agent-stop.sh is wired ONLY via frontmatter, never in plugin.json" {
  # Deliberate contract, not an oversight. agent-stop.sh runs for the three agents that
  # declare it; registering it in plugin.json would widen its firing scope to every
  # subagent in the repo. Kept executable as an assertion so a "fix" must argue with it.
  local wired
  wired="$(_frontmatter_hook_refs | grep -c 'hooks/agent-stop\.sh$' || true)"
  [ "$wired" -ge 3 ]

  run jq -r '[.. | .command? // empty] | join("\n")' "$PLUGIN_ROOT/.claude-plugin/plugin.json"
  assert_success
  refute_output --partial 'hooks/agent-stop.sh'
}

@test "plugin.json hooks: every registered command resolves to an executable script" {
  local cmd script count=0
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    script="${cmd#\$\{CLAUDE_PLUGIN_ROOT\}/}"
    [ -f "$PLUGIN_ROOT/$script" ] || fail "plugin.json hook missing on disk: $script"
    # `hooks/*` are exec'd directly and are +x (see AC-9).
    case "$script" in
      hooks/*) [ -x "$PLUGIN_ROOT/$script" ] || fail "plugin.json hook not executable: $script" ;;
    esac
    count=$((count + 1))
  done < <(jq -r '[.. | .command? // empty] | .[]' "$PLUGIN_ROOT/.claude-plugin/plugin.json")

  [ "$count" -ge 8 ]
}

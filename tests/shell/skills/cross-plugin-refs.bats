#!/usr/bin/env bats
# Contract test for cross-plugin references — every `/<plugin>:<command>` and
# `Task(<plugin>:<agent>)` this plugin names must resolve to a real file in that
# sibling plugin. A dangling reference is invisible until a worktask actually
# routes to it, at which point the stage has no build gate (or no agent) and the
# failure surfaces far from its cause.
#
# Caught in practice: the DV/DR/QA build-delegation table promised
# `/ai-engineer:build-test` while ai-engineer shipped no such command, and an
# android agent rename left three `Task(android-developer:*)` grants pointing at
# files that no longer existed. Both passed every other check in the suite.
#
# Scope: sibling plugins are separate git repos checked out next to this one.
# When they are absent (CI clone of this repo alone), the test SKIPS rather than
# fails — absence of a sibling is not a defect in this plugin.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

# Space-separated so this stays bash-3.2 portable (no associative arrays).
SIBLINGS="apple-developer system-developer android-developer frontend-developer backend-developer ai-engineer"

siblings_root() { cd "$PLUGIN_ROOT/.." && pwd; }

# Every sibling present? Partial checkouts would yield misleading passes.
all_siblings_present() {
  local root; root="$(siblings_root)" || return 1
  local p
  for p in $SIBLINGS; do
    [ -d "$root/$p/.claude-plugin" ] || return 1
  done
  return 0
}

# Emit "<plugin>:<name>" for each distinct reference of the given shape.
collect_refs() {
  local pattern="$1"
  cd "$PLUGIN_ROOT" || return 1
  git ls-files -z -- 'agents/*.md' 'commands/*.md' 'skills/*.md' 'skills/**/*.md' \
    | xargs -0 grep -hoE "$pattern" 2>/dev/null \
    | sed -E 's/^\///; s/^Task\(//; s/\)$//' \
    | LC_ALL=C sort -u
}

@test "contract: every /<plugin>:<command> reference resolves to a real command" {
  all_siblings_present || skip "sibling plugin repos not checked out beside this one"
  local root; root="$(siblings_root)"
  local missing=""
  local ref plug name
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    plug="${ref%%:*}"; name="${ref##*:}"
    # A reference may legitimately name an agent rather than a command.
    if [ ! -f "$root/$plug/commands/$name.md" ] && [ ! -f "$root/$plug/agents/$name.md" ]; then
      missing="${missing}${ref}"$'\n'
    fi
  done <<< "$(collect_refs '/(apple|system|android|frontend|backend)-developer:[a-z][a-z0-9-]*|/ai-engineer:[a-z][a-z0-9-]*')"
  [ -z "$missing" ] || {
    printf 'unresolved cross-plugin command references:\n%s' "$missing" >&2
    return 1
  }
}

@test "contract: every Task(<plugin>:<agent>) grant resolves to a real agent" {
  all_siblings_present || skip "sibling plugin repos not checked out beside this one"
  local root; root="$(siblings_root)"
  local missing=""
  local ref plug name
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    plug="${ref%%:*}"; name="${ref##*:}"
    [ -f "$root/$plug/agents/$name.md" ] || missing="${missing}${ref}"$'\n'
  done <<< "$(collect_refs 'Task\((apple|system|android|frontend|backend)-developer:[a-z][a-z0-9-]*\)|Task\(ai-engineer:[a-z][a-z0-9-]*\)')"
  [ -z "$missing" ] || {
    printf 'unresolved Task() agent grants:\n%s' "$missing" >&2
    return 1
  }
}

@test "contract: registry plugin list matches the publish-pl-issue prefix regex" {
  # skills/shared/compatible-plugins.md states these must stay in lockstep; a
  # prefix missing from the regex leaks that plugin's agent identifiers into
  # published GitHub issues, and nothing else in the suite checks it.
  local p
  for p in $SIBLINGS; do
    run bash -c "grep -c '$p' '$PLUGIN_ROOT/skills/worktask/scripts/publish-pl-issue.sh'"
    [ "$output" -ge 1 ] || {
      echo "registry plugin '$p' is absent from publish-pl-issue.sh prefix handling" >&2
      return 1
    }
  done
}

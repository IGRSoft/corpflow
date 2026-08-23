#!/usr/bin/env bats
# Contract tests for skills/request-plan/scripts/capability-registry.sh
# Contracts (from source):
#   Enumerates commands/*.md, agents/*.md and skills/*/SKILL.md, one line each.
#   Line shape: "<path> — <description>", em-dash separated.
#   Description comes from frontmatter `description:` ONLY; a body heading or a
#     later frontmatter key must never leak in.
#   A multi-line folded description collapses to one line.
#   An asset with no description is omitted rather than emitted half-formed.
#   Runs from any cwd: it resolves the plugin root from BASH_SOURCE.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/request-plan/scripts/capability-registry.sh"

# --- inventory ---------------------------------------------------------------

@test "inventory: emits every asset class, one line each" {
  run_script "$SCRIPT"
  assert_success
  # All three globs must contribute. A single class silently dropping out is the
  # failure that matters here: the skill reads this list INSTEAD of searching, so
  # a missing class is a capability the planner can no longer find at all.
  assert_output --partial "commands/"
  assert_output --partial "agents/"
  assert_output --partial "/SKILL.md"
  [ "${#lines[@]}" -ge 40 ] || fail "only ${#lines[@]} capabilities listed; expected >= 40"
}

@test "inventory: every line carries a path and an em-dash separated description" {
  run_script "$SCRIPT"
  assert_success
  local bad=0
  for l in "${lines[@]}"; do
    [ -z "$l" ] && continue
    case "$l" in
      *.md\ —\ ?*) ;;
      *) bad=$((bad + 1)); echo "malformed: $l" >&2 ;;
    esac
  done
  [ "$bad" -eq 0 ] || fail "$bad line(s) not in '<path> — <description>' shape"
}

@test "inventory: every listed path resolves in the tree" {
  run_script "$SCRIPT"
  assert_success
  local missing=0 p
  for l in "${lines[@]}"; do
    [ -z "$l" ] && continue
    p="${l%% — *}"
    [ -f "${PLUGIN_ROOT}/${p}" ] || { missing=$((missing + 1)); echo "unresolved: $p" >&2; }
  done
  [ "$missing" -eq 0 ] || fail "$missing listed path(s) do not exist"
}

# --- description extraction --------------------------------------------------

@test "description: stops at the next frontmatter key, never folding one in" {
  # The awk collects until the next `key:` or the closing fence. Without that
  # guard a description absorbs `model:`/`tools:` and the registry reads as noise.
  run_script "$SCRIPT"
  assert_success
  local leaked=0 l
  for l in "${lines[@]}"; do
    [ -z "$l" ] && continue
    # Inspect only the description half; a PATH may legitimately contain a colon.
    case "${l#* — }" in
      *allowed-tools:*|*argument-hint:*|*"model:"*|*"version:"*|*"effort:"*|*"tools:"*)
        leaked=$((leaked + 1)); echo "leaked key: $l" >&2 ;;
    esac
  done
  [ "$leaked" -eq 0 ] || fail "$leaked description(s) absorbed a later frontmatter key"
}

@test "description: no body heading leaks past the frontmatter fence" {
  run_script "$SCRIPT"
  assert_success
  # A leaked body would drag a markdown heading onto the line; frontmatter has none.
  refute_output --regexp '— .*#{1,6} '
}

@test "description: a multi-line folded description collapses to one line" {
  run_script "$SCRIPT"
  assert_success
  # One line per asset: the count of emitted lines must equal the count of paths.
  local paths
  paths="$(printf '%s\n' "${lines[@]}" | grep -c '\.md — ' || true)"
  [ "$paths" -eq "${#lines[@]}" ] \
    || fail "${#lines[@]} lines but only $paths carry a path — a description wrapped"
}

# --- robustness ---------------------------------------------------------------

@test "cwd: resolves the plugin root regardless of the working directory" {
  # It cd's to a root derived from BASH_SOURCE. Invoked from elsewhere it must
  # still enumerate, or every caller has to know where the plugin lives.
  run_script_env --cwd "$BATS_TEST_TMPDIR" "$SCRIPT"
  assert_success
  assert_output --partial "/SKILL.md"
}

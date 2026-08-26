#!/usr/bin/env bats
# Contract tests for skills/request-plan/scripts/capability-registry.sh
# Contracts (from source):
#   Enumerates commands/*.md, agents/*.md, skills/*/SKILL.md, hooks/*.sh,
#     skills/*/scripts/*.{sh,py} and benchmark/harness/**/*.py (tests excluded),
#     one line each.
#   Line shape: "<path> — <description>", em-dash separated.
#   Description source per class: markdown = frontmatter `description:` ONLY;
#     shell = `@description` when present, else the first comment block after the
#     shebang; python = the module docstring's summary paragraph.
#   A multi-line folded description collapses to one line.
#   An asset with no description is omitted rather than emitted half-formed.
#   tests/, evals/, skills/*/references/ and skills/shared/ are never enumerated —
#     the eval corpus grounds its remaining search cases there.
#   Runs from any cwd: it resolves the plugin root from BASH_SOURCE.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/request-plan/scripts/capability-registry.sh"

# --- inventory ---------------------------------------------------------------

@test "inventory: emits every asset class, one line each" {
  run_script "$SCRIPT"
  assert_success
  # Every class must contribute. A single class silently dropping out is the failure
  # that matters here: the skill reads this list INSTEAD of searching, so a missing
  # class is a capability the planner can no longer find at all. A line count alone
  # passes while a whole class emits nothing, so each is asserted separately.
  local class
  for class in 'commands/[^/]+\.md' 'agents/[^/]+\.md' 'skills/[^/]+/SKILL\.md' \
               'hooks/[^/]+\.sh' 'skills/[^/]+/scripts/[^/]+\.sh' \
               'benchmark/harness/.+\.py'; do
    printf '%s\n' "${lines[@]}" | grep -qE "^${class} — ." \
      || fail "no line for class ${class}"
  done
  # Floor sits below the live count with room for churn, and far enough above the
  # markdown-only count that dropping a whole class cannot pass.
  [ "${#lines[@]}" -ge 120 ] || fail "only ${#lines[@]} capabilities listed; expected >= 120"
}

@test "inventory: every line carries a path and an em-dash separated description" {
  run_script "$SCRIPT"
  assert_success
  local bad=0
  for l in "${lines[@]}"; do
    [ -z "$l" ] && continue
    case "$l" in
      *.md\ —\ ?*|*.sh\ —\ ?*|*.py\ —\ ?*) ;;
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

@test "inventory: a skill that nests its scripts one level deeper is still listed" {
  # skills/*/scripts/ is a flat glob and skills/shared/milestone-helpers/ is not flat,
  # so this class was silently absent. It is shared CODE, which the shared-canon
  # exclusion below does not cover.
  run_script "$SCRIPT"
  assert_success
  printf '%s\n' "${lines[@]}" | grep -qE '^skills/[^/]+/[^/]+/scripts/[^/]+\.sh — .' \
    || fail "no nested skills/*/*/scripts/*.sh line"
}

@test "inventory: the deliberately-unlisted directories stay unlisted" {
  # Not tidiness. The eval corpus grounds its replacement `buried` cases on exactly
  # these directories, so an over-broad glob here destroys the search signal the
  # registry extension already spent most of. Note the exclusion is skills/shared/*.md
  # — shared CANON — and not shared code, which is a capability like any other.
  run_script "$SCRIPT"
  assert_success
  local leaked=0 p
  for l in "${lines[@]}"; do
    [ -z "$l" ] && continue
    p="${l%% — *}"
    case "$p" in
      tests/*|evals/*|skills/*/references/*|skills/shared/*.md|*/tests/*)
        leaked=$((leaked + 1)); echo "should not be listed: $p" >&2 ;;
    esac
  done
  [ "$leaked" -eq 0 ] || fail "$leaked path(s) from a deliberately-unlisted directory"
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
  paths="$(printf '%s\n' "${lines[@]}" | grep -cE '\.(md|sh|py) — ' || true)"
  [ "$paths" -eq "${#lines[@]}" ] \
    || fail "${#lines[@]} lines but only $paths carry a path — a description wrapped"
}

@test "description: shell takes the first comment block after the shebang" {
  local wd; wd="$(mk_tmpworkdir)"
  printf '%s\n' '#!/usr/bin/env bash' \
                '# First line of the block.' \
                '# Second line of the same block.' \
                '#' \
                '# A later paragraph that must not be folded in.' \
                'echo hi' > "$wd/plain.sh"
  run_script_env --cwd "$wd" --source "$SCRIPT" desc_shell "$wd/plain.sh"
  assert_success
  assert_output --partial "First line of the block."
  assert_output --partial "Second line of the same block."
  refute_output --partial "later paragraph"
}

@test "description: shell prefers an explicit @description over its neighbours" {
  # append-labels.sh opens with `@file`, so a naive first-block reader emits the
  # filename as the description. The tag is what the file declared; take it.
  local wd; wd="$(mk_tmpworkdir)"
  printf '%s\n' '#!/usr/bin/env bash' \
                '# @file        thing.sh' \
                '# @description What the thing is for,' \
                '#              continued on a hanging indent.' \
                '#' \
                '# Not part of the description.' \
                'echo hi' > "$wd/tagged.sh"
  run_script_env --cwd "$wd" --source "$SCRIPT" desc_shell "$wd/tagged.sh"
  assert_success
  assert_output --partial "What the thing is for, continued on a hanging indent."
  refute_output --partial "thing.sh"
  refute_output --partial "Not part of the description"
}

@test "description: python takes the module docstring's summary paragraph" {
  local wd; wd="$(mk_tmpworkdir)"
  printf '%s\n' '"""Summary that wraps' \
                'onto a second physical line.' \
                '' \
                'Body paragraph that must not be folded in.' \
                '"""' \
                'X = 1' > "$wd/mod.py"
  run_script_env --cwd "$wd" --source "$SCRIPT" desc_python "$wd/mod.py"
  assert_success
  assert_output --partial "Summary that wraps"
  assert_output --partial "onto a second physical line."
  refute_output --partial "Body paragraph"
}

@test "description: no description means no line at all, not a half-formed one" {
  # The emit() contract for markdown; the executable classes must not diverge from
  # it, or the registry starts listing paths with nothing said about them.
  local wd; wd="$(mk_tmpworkdir)"
  printf '%s\n' '#!/usr/bin/env bash' 'echo hi' > "$wd/silent.sh"
  printf '%s\n' 'X = 1' > "$wd/silent.py"

  run_script_env --cwd "$wd" --source "$SCRIPT" desc_shell "$wd/silent.sh"
  assert_success
  assert_output ""

  run_script_env --cwd "$wd" --source "$SCRIPT" desc_python "$wd/silent.py"
  assert_success
  assert_output ""

  # …and an empty description must produce no line, not a bare path with a dangling dash.
  run_script_env --cwd "$wd" --source "$SCRIPT" emit_line "silent.sh" ""
  assert_success
  assert_output ""
  # Non-vacuity: the same call with a description does emit, so "" above means the
  # guard fired rather than the harness swallowing everything.
  run_script_env --cwd "$wd" --source "$SCRIPT" emit_line "silent.sh" "something"
  assert_success
  assert_output "silent.sh — something"
}

# --- robustness ---------------------------------------------------------------

@test "cwd: resolves the plugin root regardless of the working directory" {
  # It cd's to a root derived from BASH_SOURCE. Invoked from elsewhere it must
  # still enumerate, or every caller has to know where the plugin lives.
  run_script_env --cwd "$BATS_TEST_TMPDIR" "$SCRIPT"
  assert_success
  assert_output --partial "/SKILL.md"
}

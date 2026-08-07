#!/usr/bin/env bats
# Contract test for skill references in agents/ and commands/ — the sibling of
# cross-plugin-refs.bats, for references that stay inside this plugin.
#
# Caught in practice, from the first paired live run's stage transcripts:
#   - agents/developer.md ordered `Skill("dv-screenshot-capture")` while its
#     `tools:` omitted Skill. The DV stage made zero Skill calls and hand-wrote
#     its own capture script three times, reimplementing the adapter chain
#     skills/dv-screenshot-capture already ships.
#   - agents/stakeholder.md ordered `Skill("self-improvement")` with the same
#     omission, so the mandatory ST retrospective silently never ran.
#   - agents/technical-lead.md called `Skill("dev-code-review")`, which names a
#     command; skills/dev-code-review/ does not exist and never did.
# Every one of these passed the whole suite. Nothing read a `tools:` line
# against the body that depended on it.
#
# The predicates are expressed over each occurrence rather than as a frozen file
# list, for the reason plugin-root-refs.bats states: a list goes red on any doc
# edit without the protected property regressing. Each is driven here against a
# synthetic tree that plants the violation, so the checker itself is falsifiable.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

# A `Skill(` inside a markdown table cell is reference documentation — the
# worktask entry-point row in agents/workflow-engineer.md is the standing case.
# Outside a table it is an instruction the agent must be able to carry out.
_imperative_skill_lines() {
  grep -n 'Skill(' "$1" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*\|' || true
}

_grants_skill() {
  awk '/^tools:/{print; exit}' "$1" | grep -qE '(^|[ ,:])Skill([ ,]|$)'
}

# ungranted_skill_calls <plugin-root>
# One line per agent that orders a Skill call its `tools:` cannot serve.
ungranted_skill_calls() {
  local root="$1" f
  ( cd "$root" || return 1
    for f in $(git ls-files -- 'agents/*.md'); do
      [ -n "$(_imperative_skill_lines "$f")" ] || continue
      _grants_skill "$f" || printf '%s\n' "$f"
    done
    return 0 )
}

# Emit every skill name named by a `Skill(...)` call, plugin prefix stripped.
# Template metavariables (`<command>`) are placeholders, not targets.
collect_skill_targets() {
  ( cd "$1" || return 1
    git ls-files -z -- 'agents/*.md' 'commands/*.md' \
      | xargs -0 grep -hoE 'Skill\(\{?[^)]*' 2>/dev/null \
      | grep -oE '"[^"]+"' | tr -d '"' \
      | sed -E 's/^[a-z][a-z0-9-]*://' \
      | grep -v '[<>]' \
      | LC_ALL=C sort -u )
}

# dangling_skill_targets <plugin-root> — targets with no skills/<name>/ directory.
dangling_skill_targets() {
  local root="$1" s
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    [ -d "$root/skills/$s" ] || printf '%s\n' "$s"
  done <<< "$(collect_skill_targets "$root")"
  return 0
}

# Emit every `skills/<name>/…` path cited in agents/ or commands/, trailing
# sentence punctuation stripped.
collect_skill_paths() {
  ( cd "$1" || return 1
    git ls-files -z -- 'agents/*.md' 'commands/*.md' \
      | xargs -0 grep -hoE 'skills/[a-z0-9-]+/[A-Za-z0-9._/-]+' 2>/dev/null \
      | sed -E 's/[.,;:]+$//' \
      | LC_ALL=C sort -u )
}

# dangling_skill_paths <plugin-root> — cited paths that are neither file nor dir.
dangling_skill_paths() {
  local root="$1" p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ -e "$root/$p" ] || printf '%s\n' "$p"
  done <<< "$(collect_skill_paths "$root")"
  return 0
}

# missing_paths_block <plugin-root>
# An agent citing a plugin-root-relative path without saying what that path is
# relative to sends the model hunting: PL spent 14 of its 17 Bash calls in the
# live run locating plugin files, one of them a `find /`.
missing_paths_block() {
  local root="$1" f
  ( cd "$root" || return 1
    for f in $(git ls-files -- 'agents/*.md'); do
      grep -qE 'skills/[a-z0-9-]+/' "$f" || continue
      grep -qx '## Plugin paths' "$f" || printf '%s\n' "$f"
    done
    return 0 )
}

# A plugin tree that satisfies every predicate; prints its root.
mk_skill_layout() {
  local root
  root="$(mk_tmpworkdir)"
  mk_git_fixture --dir "$root" \
    --file 'agents/developer.md:---\ntools: Read, Skill, Bash\n---\n\n## Plugin paths\n\nPaths are plugin-root-relative.\n\n## Body\n\nRun `Skill({skill: "company-workflow:capture"})`; canon in `skills/capture/SKILL.md`.\n' \
    --file 'agents/router.md:---\ntools: Read\n---\n\n| Entry | `Skill({skill:"company-workflow:capture"})` |\n' \
    --file 'skills/capture/SKILL.md:x\n' >/dev/null
  printf '%s\n' "$root"
}

# --- predicate behaviour (always runs) ---------------------------------------

@test "resolver: a well-formed tree trips no predicate" {
  local root
  root="$(mk_skill_layout)"
  run ungranted_skill_calls "$root"; assert_output ""
  run dangling_skill_targets "$root"; assert_output ""
  run dangling_skill_paths "$root"; assert_output ""
  run missing_paths_block "$root"; assert_output ""
}

@test "resolver: an ordered Skill call without the grant is named" {
  local root
  root="$(mk_skill_layout)"
  # Drop the grant, leaving the body's instruction in place.
  printf -- '---\ntools: Read, Bash\n---\n\n## Plugin paths\n\nx\n\n`Skill({skill: "company-workflow:capture"})`\n' \
    > "$root/agents/developer.md"
  run ungranted_skill_calls "$root"
  assert_output --partial "agents/developer.md"
}

@test "resolver: a documentation-only Skill mention in a table needs no grant" {
  local root
  root="$(mk_skill_layout)"
  run ungranted_skill_calls "$root"
  refute_output --partial "agents/router.md"
}

@test "resolver: a Skill target with no skills/<name>/ directory is named" {
  local root
  root="$(mk_skill_layout)"
  rm -rf "$root/skills/capture"
  run dangling_skill_targets "$root"
  assert_output --partial "capture"
}

@test "resolver: a Skill target naming a command, not a skill, is named" {
  # The live defect: `Skill("dev-code-review")` against commands/dev-code-review.md.
  local root
  root="$(mk_skill_layout)"
  mkdir -p "$root/commands"; : > "$root/commands/code-review.md"
  printf -- '---\ntools: Read, Skill\n---\n\n## Plugin paths\n\nx\n\n`Skill("code-review")`\n' \
    > "$root/agents/developer.md"
  run dangling_skill_targets "$root"
  assert_output --partial "code-review"
}

@test "resolver: a dangling skills/<name>/… path citation is named" {
  local root
  root="$(mk_skill_layout)"
  rm -f "$root/skills/capture/SKILL.md"
  run dangling_skill_paths "$root"
  assert_output --partial "skills/capture/SKILL.md"
}

@test "resolver: an agent citing plugin paths without the block is named" {
  local root
  root="$(mk_skill_layout)"
  printf -- '---\ntools: Read, Skill\n---\n\n## Body\n\nCanon in `skills/capture/SKILL.md`.\n' \
    > "$root/agents/developer.md"
  run missing_paths_block "$root"
  assert_output --partial "agents/developer.md"
}

# --- this repo (always runs) -------------------------------------------------

@test "contract: every ordered Skill call in this repo has its grant" {
  run ungranted_skill_calls "$PLUGIN_ROOT"
  assert_output ""
}

@test "contract: every Skill target in this repo names a real skill" {
  local targets
  # Guard the collector: this plugin genuinely invokes skills, so an empty set
  # means the pattern regressed rather than that the repo became clean.
  targets="$(collect_skill_targets "$PLUGIN_ROOT")"
  [ -n "$targets" ]
  run dangling_skill_targets "$PLUGIN_ROOT"
  assert_output ""
}

@test "contract: every skills/<name>/… citation in this repo resolves" {
  local paths
  paths="$(collect_skill_paths "$PLUGIN_ROOT")"
  [ -n "$paths" ]
  run dangling_skill_paths "$PLUGIN_ROOT"
  assert_output ""
}

@test "contract: every agent citing plugin paths carries the resolution block" {
  run missing_paths_block "$PLUGIN_ROOT"
  assert_output ""
}

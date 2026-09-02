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
#     command; skills/dev-code-review/ does not exist and never did. Historical:
#     both that call and the command are gone — the command is now
#     commands/tech-code-review.md and the callers name the file, not a skill.
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
# Only the FIRST quoted argument is the target -- later ones are call arguments
# (`platform="apple"`), and reading them as targets is a false positive. Template
# metavariables (`<command>`, `${embedded_cmd}`) are placeholders, not targets.
# skills/ is in the glob because the defect that motivated this file lived there:
# skills/worktask/SKILL.md ordered a skill that does not exist, and a collector
# scoped to agents/ + commands/ silently no-opped on it.
collect_skill_targets() {
  ( cd "$1" || return 1
    git ls-files -z -- 'agents/*.md' 'commands/*.md' 'skills/**/*.md' \
      | xargs -0 grep -hoE 'Skill\(\{?[^)]*' 2>/dev/null \
      | sed -nE 's/[^"]*"([^"]+)".*/\1/p' \
      | sed -E 's/^[a-z][a-z0-9-]*://' \
      | grep -v '[<>${}]' \
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

# --- state-patch executability ------------------------------------------------
# The same defect class as the ungranted Skill calls above, found the same way: ten
# agents were told to run `state-patch.sh` while holding no `bash` grant, so every
# one of them silently skipped its ledger patch. An agent satisfies this predicate
# by holding a grant that can execute the tool OR by documenting the Edit-direct
# fallback it *can* execute -- an instruction it cannot carry out either way is the
# violation.

_orders_state_patch() {
  grep -qE '^Run `state-patch\.sh' "$1" 2>/dev/null
}

_grants_state_patch() {
  local tools
  tools="$(awk '/^tools:/{print; exit}' "$1")"
  printf '%s' "$tools" | grep -qE '(^|[ ,:])Bash([ ,]|$)' && return 0
  printf '%s' "$tools" | grep -qF 'Bash(bash skills/worktask/scripts/state-patch.sh:'
}

_documents_state_patch_fallback() {
  # The fallback is only real if the agent can also execute IT.
  grep -qF 'patch `.context/state.json` yourself with `Edit`' "$1" 2>/dev/null \
    && awk '/^tools:/{print; exit}' "$1" | grep -qE '(^|[ ,:])Edit([ ,]|$)'
}

# unexecutable_state_patch_orders <plugin-root>
# One line per agent ordered to run the patch tool with neither a usable grant nor
# an executable documented alternative.
unexecutable_state_patch_orders() {
  local root="$1" f
  ( cd "$root" || return 1
    for f in $(git ls-files -- 'agents/*.md'); do
      _orders_state_patch "$f" || continue
      _grants_state_patch "$f" && continue
      _documents_state_patch_fallback "$f" && continue
      printf '%s\n' "$f"
    done
    return 0 )
}

# --- path-scoped Bash grants --------------------------------------------------
# A grant like `Bash(bash skills/foo/scripts/bar.sh:*)` names a file by path. When
# that file moves or is deleted the grant does not error -- it simply never matches,
# so the agent silently loses the capability. Nothing else in the suite reads these
# paths against the filesystem.

# Emit every plugin-root-relative script path named inside a `Bash(...)` grant on a
# `tools:` or `allowed-tools:` line.
collect_bash_grant_paths() {
  ( cd "$1" || return 1
    git ls-files -z -- 'agents/*.md' 'commands/*.md' \
      | xargs -0 grep -hE '^(tools|allowed-tools):' 2>/dev/null \
      | grep -oE 'Bash\([^)]*\)' \
      | grep -oE '(agents|commands|hooks|skills|tests)/[A-Za-z0-9._/-]+\.(sh|py)' \
      | LC_ALL=C sort -u )
}

# dangling_bash_grant_paths <plugin-root> — granted paths with no file behind them.
dangling_bash_grant_paths() {
  local root="$1" p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ -f "$root/$p" ] || printf '%s\n' "$p"
  done <<< "$(collect_bash_grant_paths "$root")"
  return 0
}

# A plugin tree that satisfies every predicate; prints its root.
mk_skill_layout() {
  local root
  root="$(mk_tmpworkdir)"
  mk_git_fixture --dir "$root" \
    --file 'agents/developer.md:---\ntools: Read, Skill, Bash\n---\n\n## Plugin paths\n\nPaths are plugin-root-relative.\n\n## Body\n\nRun `Skill({skill: "corpflow:capture"})`; canon in `skills/capture/SKILL.md`.\n' \
    --file 'agents/router.md:---\ntools: Read\n---\n\n| Entry | `Skill({skill:"corpflow:capture"})` |\n' \
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
  printf -- '---\ntools: Read, Bash\n---\n\n## Plugin paths\n\nx\n\n`Skill({skill: "corpflow:capture"})`\n' \
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
  # The live defect, since fixed: `Skill("dev-code-review")` against a file that
  # was only ever commands/dev-code-review.md. Driven against a synthetic tree,
  # so the name below describes the fixture, not anything at HEAD.
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

@test "contract: no agent in this repo is ordered to run state-patch.sh it cannot execute" {
  # Guard the collector before asserting emptiness: 13 agents order this tool, so a
  # zero-sized candidate set means the matcher regressed, not that the repo is clean.
  local ordering
  ordering="$(cd "$PLUGIN_ROOT" && for f in $(git ls-files -- 'agents/*.md'); do
    grep -qE '^Run `state-patch\.sh' "$f" && printf '%s\n' "$f"; done || true)"
  [ "$(printf '%s\n' "$ordering" | grep -c .)" -ge 13 ]
  run unexecutable_state_patch_orders "$PLUGIN_ROOT"
  assert_output ""
}

@test "contract: every path-scoped Bash grant in this repo names a real file" {
  # Guard the collector first: this plugin genuinely ships path-scoped grants, so an
  # empty candidate set means the matcher regressed, not that the repo went clean.
  local granted
  granted="$(collect_bash_grant_paths "$PLUGIN_ROOT")"
  [ -n "$granted" ]
  run dangling_bash_grant_paths "$PLUGIN_ROOT"
  assert_output ""
}

@test "resolver: a path-scoped Bash grant naming a missing file is named" {
  local root
  root="$(mk_tmpworkdir)"
  mk_git_fixture --dir "$root" \
    --file 'agents/live.md:---\ntools: Read, Bash(bash skills/worktask/scripts/state-patch.sh:*)\n---\n\nx\n' \
    --file 'commands/moved.md:---\nallowed-tools: Read, Bash(skills/gone/scripts/vanished.sh)\n---\n\nx\n' \
    --file 'skills/worktask/scripts/state-patch.sh:#!/usr/bin/env bash\n' \
    >/dev/null
  run dangling_bash_grant_paths "$root"
  assert_output --partial "skills/gone/scripts/vanished.sh"
  refute_output --partial "state-patch.sh"
}

@test "resolver: an agent ordered to patch state with neither grant nor fallback is named" {
  local root
  root="$(mk_tmpworkdir)"
  mk_git_fixture --dir "$root" \
    --file 'agents/blocked.md:---\ntools: Read, Write\n---\n\nRun `state-patch.sh --stage AR --prev PL` (`skills/worktask/scripts/`).\n' \
    --file 'agents/granted.md:---\ntools: Read, Bash(bash skills/worktask/scripts/state-patch.sh:*)\n---\n\nRun `state-patch.sh --stage DC --prev QA` (`skills/worktask/scripts/`).\n' \
    --file 'agents/fallback.md:---\ntools: Read, Edit\n---\n\nRun `state-patch.sh --stage ST --prev FN`; if it cannot run, patch `.context/state.json` yourself with `Edit`.\n' \
    >/dev/null
  run unexecutable_state_patch_orders "$root"
  assert_output --partial "agents/blocked.md"
  refute_output --partial "agents/granted.md"
  refute_output --partial "agents/fallback.md"
}

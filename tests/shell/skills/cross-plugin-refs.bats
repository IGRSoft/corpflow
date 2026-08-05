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
# Sibling plugins are separate git repos checked out next to this one. Previously
# both resolution tests `skip`ped unless ALL of them were present, which is never
# the case in CI or in a worktree checkout — the contract never actually ran. The
# resolver now takes its roots as arguments and is exercised against a synthetic
# sibling layout that is built here, so the logic is verified everywhere; the
# real tree is then checked against whatever siblings do exist, per plugin,
# without an all-or-nothing skip.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

# Space-separated so this stays bash-3.2 portable (no associative arrays).
SIBLINGS="apple-developer system-developer android-developer frontend-developer backend-developer ai-engineer"

CMD_PATTERN='/(apple|system|android|frontend|backend)-developer:[a-z][a-z0-9-]*|/ai-engineer:[a-z][a-z0-9-]*'
TASK_PATTERN='Task\((apple|system|android|frontend|backend)-developer:[a-z][a-z0-9-]*\)|Task\(ai-engineer:[a-z][a-z0-9-]*\)'

# Emit "<plugin>:<name>" for each distinct reference of the given shape in $1.
collect_refs() {
  local root="$1" pattern="$2"
  ( cd "$root" || return 1
    git ls-files -z -- 'agents/*.md' 'commands/*.md' 'skills/*.md' 'skills/**/*.md' \
      | xargs -0 grep -hoE "$pattern" 2>/dev/null \
      | sed -E 's/^\///; s/^Task\(//; s/\)$//' \
      | LC_ALL=C sort -u )
}

# unresolved_refs <plugin-root> <siblings-root> command|agent
# Prints one line per reference that names a PRESENT sibling but no file in it.
# References into an absent sibling are not resolvable here and are not reported;
# `checked_siblings` below is what keeps that from silently emptying the check.
unresolved_refs() {
  local root="$1" sibroot="$2" kind="$3" pattern ref plug name
  if [ "$kind" = "command" ]; then pattern="$CMD_PATTERN"; else pattern="$TASK_PATTERN"; fi
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    plug="${ref%%:*}"; name="${ref##*:}"
    [ -d "$sibroot/$plug" ] || continue
    if [ "$kind" = "command" ]; then
      # A reference may legitimately name an agent rather than a command.
      [ -f "$sibroot/$plug/commands/$name.md" ] || [ -f "$sibroot/$plug/agents/$name.md" ] \
        || printf '%s\n' "$ref"
    else
      [ -f "$sibroot/$plug/agents/$name.md" ] || printf '%s\n' "$ref"
    fi
  done <<< "$(collect_refs "$root" "$pattern")"
}

# Names of the sibling plugins actually checked out beside $1.
checked_siblings() {
  local sibroot="$1" p
  for p in $SIBLINGS; do
    [ -d "$sibroot/$p/.claude-plugin" ] && printf '%s\n' "$p"
  done
  return 0
}

# Builds a self-plugin git repo plus sibling dirs under one root; prints the root.
mk_plugin_layout() {
  local root self
  root="$(mk_tmpworkdir)"
  self="$root/company-workflow"
  mk_git_fixture --dir "$self" \
    --file 'agents/developer.md:Build via /apple-developer:build-test.\nGrant: Task(system-developer:python-developer)\n' \
    --file 'commands/worktask.md:Routes to Task(apple-developer:ios-developer).\n' >/dev/null
  mkdir -p "$root/apple-developer/commands" "$root/apple-developer/agents" \
           "$root/system-developer/agents"
  : > "$root/apple-developer/commands/build-test.md"
  : > "$root/apple-developer/agents/ios-developer.md"
  : > "$root/system-developer/agents/python-developer.md"
  printf '%s\n' "$root"
}

# --- resolver behaviour (always runs) ----------------------------------------

@test "resolver: a fully populated sibling layout yields no unresolved refs" {
  local root
  root="$(mk_plugin_layout)"
  run unresolved_refs "$root/company-workflow" "$root" command
  assert_output ""
  run unresolved_refs "$root/company-workflow" "$root" agent
  assert_output ""
}

@test "resolver: a dangling /<plugin>:<command> reference is named" {
  local root
  root="$(mk_plugin_layout)"
  rm -f "$root/apple-developer/commands/build-test.md"
  run unresolved_refs "$root/company-workflow" "$root" command
  assert_output --partial "apple-developer:build-test"
}

@test "resolver: a dangling Task(<plugin>:<agent>) grant is named" {
  local root
  root="$(mk_plugin_layout)"
  rm -f "$root/system-developer/agents/python-developer.md"
  run unresolved_refs "$root/company-workflow" "$root" agent
  assert_output --partial "system-developer:python-developer"
}

@test "resolver: a command reference satisfied by an agent file resolves" {
  # `/apple-developer:ios-developer` names an agent, not a command — legal.
  local root
  root="$(mk_plugin_layout)"
  mk_git_fixture --dir "$root/company-workflow" \
    --file 'agents/router.md:Delegates to /apple-developer:ios-developer.\n' >/dev/null
  rm -f "$root/apple-developer/commands/build-test.md"
  run unresolved_refs "$root/company-workflow" "$root" command
  refute_output --partial "apple-developer:ios-developer"
}

# --- this repo (always runs) -------------------------------------------------

@test "contract: this repo's cross-plugin references are collected and resolve" {
  local sibroot refs
  sibroot="$(cd "$PLUGIN_ROOT/.." && pwd)"
  # Guard against the collector silently breaking: this plugin genuinely names
  # sibling commands and agents, so an empty set means the glob or the pattern
  # regressed, not that the repo became clean.
  refs="$(collect_refs "$PLUGIN_ROOT" "$CMD_PATTERN")"
  [ -n "$refs" ]
  refs="$(collect_refs "$PLUGIN_ROOT" "$TASK_PATTERN")"
  [ -n "$refs" ]
  run unresolved_refs "$PLUGIN_ROOT" "$sibroot" command
  assert_output ""
  run unresolved_refs "$PLUGIN_ROOT" "$sibroot" agent
  assert_output ""
  # Report coverage so a checkout with no siblings is visible rather than silent.
  echo "siblings checked: $(checked_siblings "$sibroot" | tr '\n' ' ')" >&3
}

# --- registry / sanitiser lockstep -------------------------------------------

@test "contract: every registry plugin appears in each publish-pl-issue prefix regex" {
  # skills/shared/compatible-plugins.md states these must stay in lockstep; a
  # prefix missing from the alternation leaks that plugin's agent identifiers
  # into published GitHub issues. Asserted against the alternation groups
  # themselves — a `grep -c <plugin>` over the whole file was satisfied by any
  # comment that happened to mention the name.
  local script="$PLUGIN_ROOT/skills/worktask/scripts/publish-pl-issue.sh"
  local alts n p
  alts="$(grep -n '(company-workflow|' "$script")"
  n="$(printf '%s\n' "$alts" | grep -c '(company-workflow|')"
  # L348 (line-drop predicate) and L394 (token predicate); both must survive.
  [ "$n" -ge 2 ]
  local line
  for p in $SIBLINGS; do
    while IFS= read -r line; do
      case "$line" in
        *"|$p|"*|*"|$p)"*) ;;
        *) printf 'registry plugin %s missing from prefix alternation: %s\n' "$p" "$line" >&2
           return 1 ;;
      esac
    done <<< "$alts"
  done
}

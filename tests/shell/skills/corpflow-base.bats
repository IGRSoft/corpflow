#!/usr/bin/env bats
# Target: skills/shared/lib/corpflow-base.sh and its hooks/lib/ mirror.
#
# The two files are byte-identical by contract and nothing but this file enforces it.
# Hooks cannot source across into skills/shared/lib/ without first resolving a plugin
# root — the very thing the library supplies — so the boundary is mirrored, and a mirror
# with no parity gate is how the two halves of one contract drift apart in silence.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SKILLS_LIB="skills/shared/lib/corpflow-base.sh"
HOOKS_LIB="hooks/lib/corpflow-base.sh"

# --- parity -------------------------------------------------------------------

@test "parity: the skills and hooks mirrors are byte-identical" {
  run cmp "$PLUGIN_ROOT/$SKILLS_LIB" "$PLUGIN_ROOT/$HOOKS_LIB"
  assert_success
}

@test "parity: both mirrors resolve the same plugin root from their different depths" {
  run bash -c ". '$PLUGIN_ROOT/$SKILLS_LIB'; corpflow_plugin_root"
  assert_success
  local from_skills="$output"
  run bash -c ". '$PLUGIN_ROOT/$HOOKS_LIB'; corpflow_plugin_root"
  assert_success
  assert_output "$from_skills"
  assert_output "$PLUGIN_ROOT"
}

# --- library header contract ---------------------------------------------------

@test "contract: host-specific root variables are consumed only by the base resolver" {
  local f
  for f in "$SKILLS_LIB" "$HOOKS_LIB"; do
    run grep -c 'set --.*CLAUDE_PLUGIN_ROOT' "$PLUGIN_ROOT/$f"
    assert_output "1"
    run grep -c 'CODEX_PLUGIN_ROOT' "$PLUGIN_ROOT/$f"
    assert_output "0"
  done
}

@test "contract: neither mirror uses readonly" {
  # Consumer suites source the library twice per process; a second readonly assignment
  # is rc 1, which kills a `set -e` caller.
  local f
  for f in "$SKILLS_LIB" "$HOOKS_LIB"; do
    run grep -cE '^[[:space:]]*(readonly|declare -r)' "$PLUGIN_ROOT/$f"
    assert_output "0"
  done
}

@test "contract: executing a mirror directly is refused with exit 2" {
  local f
  for f in "$SKILLS_LIB" "$HOOKS_LIB"; do
    run bash "$PLUGIN_ROOT/$f"
    assert_failure 2
    assert_output --partial "source it, do not execute it directly"
  done
}

@test "contract: the anti-execution guard is the first executable statement" {
  # A guard placed after any other statement lets that statement run in the very
  # invocation the guard exists to refuse.
  local first
  first="$(grep -nvE '^[[:space:]]*(#|$)' "$PLUGIN_ROOT/$SKILLS_LIB" | head -1)"
  [[ "$first" == *'if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then'* ]] \
    || fail "first statement is not the anti-execution guard: $first"
}

@test "contract: a double source is a no-op and the load does no work" {
  # No side effects at load: sourcing twice under `set -e` must stay silent and rc 0.
  run bash -euc ". '$PLUGIN_ROOT/$SKILLS_LIB'; . '$PLUGIN_ROOT/$SKILLS_LIB'; printf 'quiet'"
  assert_success
  assert_output "quiet"
}

@test "contract: sourcing defines exactly the documented symbols" {
  run bash -c ". '$PLUGIN_ROOT/$SKILLS_LIB'; declare -F | awk '{print \$3}' | grep '^corpflow_' | sort"
  assert_success
  assert_output "corpflow_init_base_paths
corpflow_is_plugin_root
corpflow_plugin_path
corpflow_plugin_root
corpflow_script_dir
corpflow_workspace_root"
}

# --- corpflow_script_dir --------------------------------------------------------

@test "script_dir: resolves a plain path to its physical directory" {
  run_script_env --source "$SKILLS_LIB" corpflow_script_dir \
    "$PLUGIN_ROOT/skills/worktask/scripts/hook-install.sh"
  assert_success
  assert_output "$PLUGIN_ROOT/skills/worktask/scripts"
}

@test "script_dir: follows an absolute symlink to the target's real directory" {
  # The security property: sibling resolution must not be redirectable onto a file
  # planted beside the symlink.
  local wd; wd="$(mk_tmpworkdir)"
  mkdir -p "$wd/real" "$wd/link"
  printf '#!/usr/bin/env bash\n' > "$wd/real/tool.sh"
  ln -s "$wd/real/tool.sh" "$wd/link/tool.sh"
  run_script_env --source "$SKILLS_LIB" corpflow_script_dir "$wd/link/tool.sh"
  assert_success
  assert_output "$(cd "$wd/real" && pwd -P)"
}

@test "script_dir: follows a RELATIVE symlink, resolved against the link's own directory" {
  local wd; wd="$(mk_tmpworkdir)"
  mkdir -p "$wd/real" "$wd/link"
  printf '#!/usr/bin/env bash\n' > "$wd/real/tool.sh"
  ln -s "../real/tool.sh" "$wd/link/tool.sh"
  run_script_env --source "$SKILLS_LIB" corpflow_script_dir "$wd/link/tool.sh"
  assert_success
  assert_output "$(cd "$wd/real" && pwd -P)"
}

@test "script_dir: a set CDPATH does not leak an extra line into the answer" {
  # A CDPATH hit makes `cd` echo the resolved path, which lands in the capture and
  # silently corrupts every path derived from it.
  local wd; wd="$(mk_tmpworkdir)"
  mkdir -p "$wd/scripts"
  printf '#!/usr/bin/env bash\n' > "$wd/scripts/tool.sh"
  run bash -c ". '$PLUGIN_ROOT/$SKILLS_LIB'; export CDPATH='$wd'; corpflow_script_dir '$wd/scripts/tool.sh'"
  assert_success
  [ "${#lines[@]}" -eq 1 ] || fail "expected one line, got ${#lines[@]}: $output"
}

# --- corpflow_plugin_root -------------------------------------------------------

@test "plugin_root: a candidate holding the marker wins over the self-location walk" {
  local wd; wd="$(mk_tmpworkdir)"
  mkdir -p "$wd/.claude-plugin"
  printf '{}' > "$wd/.claude-plugin/plugin.json"
  run_script_env --source "$SKILLS_LIB" corpflow_plugin_root "$wd"
  assert_success
  assert_output "$wd"
}

@test "plugin_root: a candidate WITHOUT the marker is skipped, not returned" {
  # The single rule the reference document already states and only 4 of 69 scripts
  # honoured: a candidate is a plugin root only if it carries the marker.
  local wd; wd="$(mk_tmpworkdir)"
  run_script_env --source "$SKILLS_LIB" corpflow_plugin_root "$wd"
  assert_success
  assert_output "$PLUGIN_ROOT"
}

@test "plugin_root: an empty candidate is skipped so callers can pass an unset variable" {
  local wd; wd="$(mk_tmpworkdir)"
  mkdir -p "$wd/.claude-plugin"
  printf '{}' > "$wd/.claude-plugin/plugin.json"
  run_script_env --source "$SKILLS_LIB" corpflow_plugin_root "" "$wd"
  assert_success
  assert_output "$wd"
}

@test "plugin_root: candidates are tried in order" {
  local wd; wd="$(mk_tmpworkdir)"
  mkdir -p "$wd/a/.claude-plugin" "$wd/b/.claude-plugin"
  printf '{}' > "$wd/a/.claude-plugin/plugin.json"
  printf '{}' > "$wd/b/.claude-plugin/plugin.json"
  run_script_env --source "$SKILLS_LIB" corpflow_plugin_root "$wd/a" "$wd/b"
  assert_success
  assert_output "$wd/a"
}

@test "plugin_root: portable and Codex compatibility markers are accepted" {
  local wd; wd="$(mk_tmpworkdir)"
  mkdir -p "$wd/portable" "$wd/codex/.codex-plugin"
  printf '{}' > "$wd/portable/plugin.json"
  printf '{}' > "$wd/codex/.codex-plugin/plugin.json"
  run_script_env --source "$SKILLS_LIB" corpflow_plugin_root "$wd/portable"
  assert_success
  assert_output "$wd/portable"
  run_script_env --source "$SKILLS_LIB" corpflow_plugin_root "$wd/codex"
  assert_success
  assert_output "$wd/codex"
}

@test "plugin_root: BASE then Codex then Claude environment precedence" {
  local wd; wd="$(mk_tmpworkdir)"
  mkdir -p "$wd/base/.claude-plugin" "$wd/codex/.codex-plugin" "$wd/claude/.claude-plugin"
  printf '{}' > "$wd/base/.claude-plugin/plugin.json"
  printf '{}' > "$wd/codex/.codex-plugin/plugin.json"
  printf '{}' > "$wd/claude/.claude-plugin/plugin.json"
  run env BASE_PLUGIN_ROOT="$wd/base" PLUGIN_ROOT="$wd/codex" CLAUDE_PLUGIN_ROOT="$wd/claude" \
    bash -c ". '$PLUGIN_ROOT/$SKILLS_LIB'; corpflow_plugin_root"
  assert_success
  assert_output "$wd/base"
  run env -u BASE_PLUGIN_ROOT PLUGIN_ROOT="$wd/codex" CLAUDE_PLUGIN_ROOT="$wd/claude" \
    bash -c ". '$PLUGIN_ROOT/$SKILLS_LIB'; corpflow_plugin_root"
  assert_success
  assert_output "$wd/codex"
}

@test "plugin_root: with no candidate it walks up from the library's own directory" {
  # Not the caller's: a library's depth below the root is fixed, a caller's is not.
  local wd; wd="$(mk_tmpworkdir)"
  run bash -c "cd '$wd' && . '$PLUGIN_ROOT/$SKILLS_LIB' && corpflow_plugin_root"
  assert_success
  assert_output "$PLUGIN_ROOT"
}

@test "plugin_root: refuses with rc 1 when no candidate and no ancestor holds the marker" {
  local wd; wd="$(mk_tmpworkdir)"
  mkdir -p "$wd/deep/lib"
  cp "$PLUGIN_ROOT/$SKILLS_LIB" "$wd/deep/lib/corpflow-base.sh"
  run env -u BASE_PLUGIN_ROOT -u PLUGIN_ROOT -u CLAUDE_PLUGIN_ROOT \
    bash -c ". '$wd/deep/lib/corpflow-base.sh'; corpflow_plugin_root"
  assert_failure 1
  assert_output ""
}

# --- canonical path initialization --------------------------------------------

@test "init_base_paths: exports canonical root, data and workspace paths" {
  local wd data project; wd="$(mk_tmpworkdir)"; data="$wd/plugin data"; project="$wd/project"
  mkdir -p "$wd/plugin/.codex-plugin" "$data" "$project"
  printf '{}' > "$wd/plugin/.codex-plugin/plugin.json"
  run env -u BASE_PLUGIN_ROOT -u BASE_PLUGIN_DATA -u WORKSPACE_ROOT \
    PLUGIN_ROOT="$wd/plugin" PLUGIN_DATA="$data" \
    bash -c ". '$PLUGIN_ROOT/$SKILLS_LIB'; corpflow_init_base_paths '$project'; printf '%s\n%s\n%s' \"\$BASE_PLUGIN_ROOT\" \"\$BASE_PLUGIN_DATA\" \"\$WORKSPACE_ROOT\""
  assert_success
  local physical_project; physical_project="$(cd "$project" && pwd -P)"
  assert_output "$wd/plugin
$data
$physical_project"
}

@test "init_base_paths: BASE data wins, then Codex data, then Claude data" {
  local wd; wd="$(mk_tmpworkdir)"
  mkdir -p "$wd/plugin/.claude-plugin"
  printf '{}' > "$wd/plugin/.claude-plugin/plugin.json"
  run env BASE_PLUGIN_ROOT="$wd/plugin" BASE_PLUGIN_DATA="$wd/base" \
    PLUGIN_DATA="$wd/codex" CLAUDE_PLUGIN_DATA="$wd/claude" \
    bash -c ". '$PLUGIN_ROOT/$SKILLS_LIB'; corpflow_init_base_paths; printf '%s' \"\$BASE_PLUGIN_DATA\""
  assert_success
  assert_output "$wd/base"
  run env -u BASE_PLUGIN_DATA BASE_PLUGIN_ROOT="$wd/plugin" \
    PLUGIN_DATA="$wd/codex" CLAUDE_PLUGIN_DATA="$wd/claude" \
    bash -c ". '$PLUGIN_ROOT/$SKILLS_LIB'; corpflow_init_base_paths; printf '%s' \"\$BASE_PLUGIN_DATA\""
  assert_success
  assert_output "$wd/codex"
  run env -u BASE_PLUGIN_DATA -u PLUGIN_DATA BASE_PLUGIN_ROOT="$wd/plugin" \
    CLAUDE_PLUGIN_DATA="$wd/claude" \
    bash -c ". '$PLUGIN_ROOT/$SKILLS_LIB'; corpflow_init_base_paths; printf '%s' \"\$BASE_PLUGIN_DATA\""
  assert_success
  assert_output "$wd/claude"
}

@test "plugin_root: a symlinked installation remains a valid explicit root" {
  local wd; wd="$(mk_tmpworkdir)"
  mkdir -p "$wd/real/.codex-plugin"
  printf '{}' > "$wd/real/.codex-plugin/plugin.json"
  ln -s "$wd/real" "$wd/link"
  run_script_env --source "$SKILLS_LIB" corpflow_plugin_root "$wd/link"
  assert_success
  assert_output "$wd/link"
}

@test "plugin_root: a relative root with spaces is returned as an absolute path" {
  local wd; wd="$(mk_tmpworkdir)"
  mkdir -p "$wd/install space/.codex-plugin"
  printf '{}' > "$wd/install space/.codex-plugin/plugin.json"
  run bash -c "cd '$wd' && . '$PLUGIN_ROOT/$SKILLS_LIB' && corpflow_plugin_root './install space'"
  assert_success
  assert_output "$wd/install space"
}

@test "plugin_path: joins safe relative paths and rejects escape attempts" {
  run env BASE_PLUGIN_ROOT="$PLUGIN_ROOT" bash -c ". '$PLUGIN_ROOT/$SKILLS_LIB'; corpflow_plugin_path 'skills/worktask/SKILL.md'"
  assert_success
  assert_output "$PLUGIN_ROOT/skills/worktask/SKILL.md"
  run env BASE_PLUGIN_ROOT="$PLUGIN_ROOT" bash -c ". '$PLUGIN_ROOT/$SKILLS_LIB'; corpflow_plugin_path '../secret'"
  assert_failure 2
  run env BASE_PLUGIN_ROOT="$PLUGIN_ROOT" bash -c ". '$PLUGIN_ROOT/$SKILLS_LIB'; corpflow_plugin_path '/tmp/secret'"
  assert_failure 2
}

@test "workspace_root: explicit neutral root wins over payload and Claude fallback" {
  local wd; wd="$(mk_tmpworkdir)"
  mkdir -p "$wd/neutral" "$wd/payload" "$wd/claude"
  run env WORKSPACE_ROOT="$wd/neutral" CLAUDE_PROJECT_DIR="$wd/claude" \
    bash -c ". '$PLUGIN_ROOT/$SKILLS_LIB'; corpflow_workspace_root '$wd/payload'"
  assert_success
  assert_output "$(cd "$wd/neutral" && pwd -P)"
}

@test "workspace_root: preserves an absolute host path before its checkout exists" {
  local wd; wd="$(mk_tmpworkdir)"
  run env -u WORKSPACE_ROOT CLAUDE_PROJECT_DIR="$wd/future checkout" \
    bash -c ". '$PLUGIN_ROOT/$SKILLS_LIB'; corpflow_workspace_root"
  assert_success
  assert_output "$wd/future checkout"
}

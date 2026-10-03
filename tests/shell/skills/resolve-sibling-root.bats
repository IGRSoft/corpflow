#!/usr/bin/env bats
# Contract tests for skills/cross-plugin-handoff/scripts/resolve-sibling-root.sh.
#   - exit 0: exactly one stdout line, the verified root; stderr empty
#   - exit 1: stdout empty, one "resolve-sibling-root: <reason>" stderr line
#   - exit 2: usage error
# Every case runs from a fixture cwd with HOME sandboxed and CLAUDE_CONFIG_DIR set or unset
# explicitly, so the operator's real ~/.claude registry is never read.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/cross-plugin-handoff/scripts/resolve-sibling-root.sh"

setup() {
  WD="$(cd "$(mk_tmpworkdir)" && pwd -P)"
  HOME_DIR="$WD/home"
  CFG="$WD/cfg"
  PROJ="$WD/proj"
  mkdir -p "$HOME_DIR/.claude/plugins" "$CFG/plugins" "$PROJ/sub"
}

# <dir> [marker] — a plugin install carrying plugin.json (default) or CORPFLOW.md.
_mk_install() {
  if [ "${2:-manifest}" = corpflow ]; then
    mkdir -p "$1"
    : > "$1/CORPFLOW.md"
  else
    mkdir -p "$1/.claude-plugin"
    printf '{"name":"x"}\n' > "$1/.claude-plugin/plugin.json"
  fi
}

# <config-dir> <plugins-object-json> — installed_plugins.json in the version-2 shape.
_registry() {
  printf '{"version":2,"plugins":%s}\n' "$2" > "$1/plugins/installed_plugins.json"
}

# [cwd] — runs the resolver for apple-developer under the sandboxed HOME and CFG.
_resolve_cfg() {
  run_script_env --separate-stderr --cwd "${1:-$PROJ}" --env "HOME=$HOME_DIR" \
    --env "CLAUDE_CONFIG_DIR=$CFG" "$SCRIPT" apple-developer
}

_assert_root() {
  assert_success
  assert_output "$1"
  [ -z "$stderr" ] || fail "unexpected stderr: $stderr"
}

# <reason-fragment> — exit 1, empty stdout, one prefixed stderr line.
_assert_unresolved() {
  assert_failure 1
  assert_output ""
  [ "${#stderr_lines[@]}" -eq 1 ] || fail "expected one stderr line, got: $stderr"
  [[ "$stderr" == "resolve-sibling-root: "*"$1"* ]] || fail "unexpected stderr: $stderr"
}

@test "installed: a user-scope installed_plugins.json entry resolves to its installPath" {
  _mk_install "$CFG/plugins/cache/apple-developer/apple-developer/1.31.0"
  _registry "$CFG" "{\"apple-developer@apple-developer\":[{\"scope\":\"user\",\"projectPath\":null,
    \"installPath\":\"$CFG/plugins/cache/apple-developer/apple-developer/1.31.0\",\"version\":\"1.31.0\"}]}"
  _resolve_cfg
  _assert_root "$CFG/plugins/cache/apple-developer/apple-developer/1.31.0"
}

@test "installed: a local entry for this project, or an ancestor of it, beats the user entry" {
  _mk_install "$WD/v-user"
  _mk_install "$WD/v-local"
  _mk_install "$WD/v-other"
  _registry "$CFG" "{\"apple-developer@apple-developer\":[
    {\"scope\":\"user\",\"installPath\":\"$WD/v-user\"},
    {\"scope\":\"local\",\"projectPath\":\"$PROJ\",\"installPath\":\"$WD/v-local\"},
    {\"scope\":\"local\",\"projectPath\":\"$WD/elsewhere\",\"installPath\":\"$WD/v-other\"}]}"
  _resolve_cfg "$PROJ/sub"
  _assert_root "$WD/v-local"
}

@test "installed: a projectPath that only shares a name prefix with the project is not a match" {
  _mk_install "$WD/v-user"
  _mk_install "$WD/v-prefix"
  _registry "$CFG" "{\"apple-developer@apple-developer\":[
    {\"scope\":\"local\",\"projectPath\":\"$WD/pro\",\"installPath\":\"$WD/v-prefix\"},
    {\"scope\":\"user\",\"installPath\":\"$WD/v-user\"}]}"
  _resolve_cfg
  _assert_root "$WD/v-user"
}

@test "installed: CLAUDE_PROJECT_DIR, not the cwd, picks the project entry when set" {
  _mk_install "$WD/v-user"
  _mk_install "$WD/v-local"
  _registry "$CFG" "{\"apple-developer@apple-developer\":[
    {\"scope\":\"user\",\"installPath\":\"$WD/v-user\"},
    {\"scope\":\"local\",\"projectPath\":\"$PROJ\",\"installPath\":\"$WD/v-local\"}]}"
  run_script_env --separate-stderr --cwd "$WD" --env "HOME=$HOME_DIR" --env "CLAUDE_CONFIG_DIR=$CFG" \
    --env "CLAUDE_PROJECT_DIR=$PROJ" "$SCRIPT" apple-developer
  _assert_root "$WD/v-local"
}

@test "local-marketplace: a directory-source marketplace resolves to the plugin in place" {
  # The eval shape: installPath is a cache copy, but the session loads the directory source.
  _mk_install "$CFG/plugins/cache/apple-developer/apple-developer/1.31.0"
  mkdir -p "$CFG/local-marketplace/apple-developer/.claude-plugin"
  : > "$CFG/local-marketplace/apple-developer/CORPFLOW.md"
  printf '{"name":"apple-developer","plugins":[{"name":"apple-developer","source":"./"}]}\n' \
    > "$CFG/local-marketplace/apple-developer/.claude-plugin/marketplace.json"
  printf '{"apple-developer":{"source":{"source":"directory","path":"%s"},"installLocation":"%s"}}\n' \
    "$CFG/local-marketplace/apple-developer" "$CFG/local-marketplace/apple-developer" \
    > "$CFG/plugins/known_marketplaces.json"
  _registry "$CFG" "{\"apple-developer@apple-developer\":[{\"scope\":\"local\",\"projectPath\":\"$PROJ\",
    \"installPath\":\"$CFG/plugins/cache/apple-developer/apple-developer/1.31.0\"}]}"
  _resolve_cfg
  _assert_root "$CFG/local-marketplace/apple-developer"
}

@test "local-marketplace: a bare source name resolves under metadata.pluginRoot" {
  _mk_install "$WD/cache-copy"
  _mk_install "$WD/mkt/plugins/apple-developer" corpflow
  mkdir -p "$WD/mkt/.claude-plugin"
  printf '{"metadata":{"pluginRoot":"./plugins"},"plugins":[{"name":"apple-developer","source":"apple-developer"}]}\n' \
    > "$WD/mkt/.claude-plugin/marketplace.json"
  printf '{"m":{"source":{"source":"directory","path":"%s"}}}\n' "$WD/mkt" \
    > "$CFG/plugins/known_marketplaces.json"
  _registry "$CFG" "{\"apple-developer@m\":[{\"scope\":\"user\",\"installPath\":\"$WD/cache-copy\"}]}"
  _resolve_cfg
  _assert_root "$WD/mkt/plugins/apple-developer"
}

@test "local-marketplace: a directory plugin with no marker falls back to installPath" {
  _mk_install "$WD/cache-copy"
  mkdir -p "$WD/mkt/.claude-plugin"
  printf '{"plugins":[{"name":"apple-developer","source":"./"}]}\n' \
    > "$WD/mkt/.claude-plugin/marketplace.json"
  printf '{"m":{"source":{"source":"directory","path":"%s"},"installLocation":"%s"}}\n' \
    "$WD/mkt" "$WD/mkt" > "$CFG/plugins/known_marketplaces.json"
  _registry "$CFG" "{\"apple-developer@m\":[{\"scope\":\"user\",\"installPath\":\"$WD/cache-copy\"}]}"
  _resolve_cfg
  _assert_root "$WD/cache-copy"
}

@test "local-marketplace: a github-source marketplace keeps the cache installPath" {
  _mk_install "$WD/cache-copy"
  _mk_install "$WD/clone" corpflow
  printf '{"m":{"source":{"source":"github","repo":"o/r"},"installLocation":"%s"}}\n' \
    "$WD/clone" > "$CFG/plugins/known_marketplaces.json"
  _registry "$CFG" "{\"apple-developer@m\":[{\"scope\":\"user\",\"installPath\":\"$WD/cache-copy\"}]}"
  _resolve_cfg
  _assert_root "$WD/cache-copy"
}

@test "not installed: no entry for the plugin is exit 1 with one reason line" {
  _mk_install "$WD/v-user"
  _registry "$CFG" "{\"system-developer@system-developer\":[{\"scope\":\"user\",\"installPath\":\"$WD/v-user\"}]}"
  _resolve_cfg
  _assert_unresolved "apple-developer is not installed for this session"
}

@test "not installed: an entry bound only to another project is exit 1" {
  _mk_install "$WD/v-other"
  _registry "$CFG" "{\"apple-developer@apple-developer\":[
    {\"scope\":\"local\",\"projectPath\":\"$WD/elsewhere\",\"installPath\":\"$WD/v-other\"}]}"
  _resolve_cfg
  _assert_unresolved "is not installed for this session"
}

@test "not installed: no installed_plugins.json is exit 1" {
  _resolve_cfg
  _assert_unresolved "no installed_plugins.json at $CFG/plugins/installed_plugins.json"
}

@test "not installed: an installPath with neither marker is exit 1" {
  mkdir -p "$WD/empty-install"
  _registry "$CFG" "{\"apple-developer@apple-developer\":[{\"scope\":\"user\",\"installPath\":\"$WD/empty-install\"}]}"
  _resolve_cfg
  _assert_unresolved "holds neither CORPFLOW.md nor .claude-plugin/plugin.json"
}

@test "not installed: an unparseable registry is exit 1, not a crash" {
  printf '{not json\n' > "$CFG/plugins/installed_plugins.json"
  _resolve_cfg
  _assert_unresolved "cannot parse"
}

@test "config dir: CLAUDE_CONFIG_DIR beats \$HOME/.claude" {
  _mk_install "$WD/from-home"
  _mk_install "$WD/from-cfg"
  _registry "$HOME_DIR/.claude" "{\"apple-developer@apple-developer\":[{\"scope\":\"user\",\"installPath\":\"$WD/from-home\"}]}"
  _registry "$CFG" "{\"apple-developer@apple-developer\":[{\"scope\":\"user\",\"installPath\":\"$WD/from-cfg\"}]}"
  _resolve_cfg
  _assert_root "$WD/from-cfg"
}

@test "config dir: CLAUDE_CONFIG_DIR with no entry never falls back to \$HOME/.claude" {
  # The benchmark leak: an isolated config must not resolve into the operator's real cache.
  _mk_install "$WD/from-home"
  _registry "$HOME_DIR/.claude" "{\"apple-developer@apple-developer\":[{\"scope\":\"user\",\"installPath\":\"$WD/from-home\"}]}"
  _registry "$CFG" '{}'
  _resolve_cfg
  _assert_unresolved "is not installed for this session"
}

@test "config dir: with CLAUDE_CONFIG_DIR unset, the sandboxed \$HOME/.claude is read" {
  _mk_install "$WD/from-home"
  _registry "$HOME_DIR/.claude" "{\"apple-developer@apple-developer\":[{\"scope\":\"user\",\"installPath\":\"$WD/from-home\"}]}"
  run_script_env --separate-stderr --cwd "$PROJ" --env "HOME=$HOME_DIR" --unset CLAUDE_CONFIG_DIR \
    "$SCRIPT" apple-developer
  _assert_root "$WD/from-home"
}

@test "usage: no argument, two arguments, an unknown option or a path-shaped name is exit 2" {
  run_script_env --separate-stderr --env "HOME=$HOME_DIR" "$SCRIPT"
  assert_failure 2
  run_script_env --separate-stderr --env "HOME=$HOME_DIR" "$SCRIPT" a b
  assert_failure 2
  run_script_env --separate-stderr --env "HOME=$HOME_DIR" "$SCRIPT" --bogus
  assert_failure 2
  run_script_env --separate-stderr --env "HOME=$HOME_DIR" "$SCRIPT" ../apple-developer
  assert_failure 2
  assert_output ""
}

@test "help and self-test: --help prints usage, --self-test passes" {
  run_script_env --env "HOME=$HOME_DIR" "$SCRIPT" --help
  assert_success
  assert_output --partial "Usage: resolve-sibling-root.sh <plugin-name>"
  run_script_env --env "HOME=$HOME_DIR" --unset CLAUDE_CONFIG_DIR "$SCRIPT" --self-test
  assert_success
  assert_output "self-test OK"
}

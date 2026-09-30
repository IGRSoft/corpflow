#!/usr/bin/env bats
# Root ladder of state-patch.sh when --state is absent:
#   CONTEXT_DIR, WORKSPACE_ROOT/.context, CLAUDE_PROJECT_DIR/.context,
#   <git toplevel of $PWD>/.context, $PWD/.context
# and the refusal (exit 4) of an INFERRED result (git toplevel from a nested subdirectory, or
# $PWD/.context) that lies inside the plugin root. Explicit signals (--state, CONTEXT_DIR,
# WORKSPACE_ROOT, CLAUDE_PROJECT_DIR) and a cwd that is the plugin's own git toplevel are
# trusted, because the plugin is developed with itself.
#
# Every case runs from a fixture-owned cwd with HOME sandboxed and git contained by
# GIT_CEILING_DIRECTORIES: an uncontained cwd would resolve to THIS checkout's live ledger.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/state-patch.sh"

setup() {
  WD="$(cd "$(mk_tmpworkdir)" && pwd -P)"
  mkdir -p "$WD/home"
  META='{"agent":"corpflow:developer","stage":"DV","effort":"high","isolation":"worktree","base_ref":"origin/develop","requires_screenshots":false,"workspace_path":"/tmp/wt"}'
}

# _seed <context-dir> — a valid ledger, so a --task-create can land.
_seed() {
  mkdir -p "$1"
  cp "$FIXTURES/worktask/state.sample.json" "$1/state.json"
}

# _sp <cwd> <script> [args...] — run the script from <cwd> under a scrubbed environment.
# Roots the caller wants declared are exported before the call.
_sp() {
  local cwd="$1" script="$2"
  shift 2
  run env HOME="$WD/home" GIT_CEILING_DIRECTORIES="$WD" GIT_CONFIG_GLOBAL=/dev/null \
    GIT_CONFIG_NOSYSTEM=1 bash -c 'cd "$1" && shift && exec bash "$@"' _ "$cwd" "$script" "$@"
}

# _has_row <context-dir> <id> — the row landed in that ledger.
_has_row() {
  jq -e --arg id "$2" '.tasks | has($id)' "$1/state.json" > /dev/null
}

# _fake_plugin — a copy of the plugin's script tree at $WD/plug, so a regression that writes
# into "the plugin root" writes into a fixture rather than this checkout.
_fake_plugin() {
  mkdir -p "$WD/plug/skills"
  cp -R "$PLUGIN_ROOT/skills/shared" "$PLUGIN_ROOT/skills/worktask" "$WD/plug/skills/"
  FAKE_SCRIPT="$WD/plug/$SCRIPT"
}

@test "ladder: a non-git cwd resolves to \$PWD/.context" {
  mkdir -p "$WD/plain"
  _seed "$WD/plain/.context"
  _sp "$WD/plain" "$PLUGIN_ROOT/$SCRIPT" --task-create DV7 --metadata "$META"
  assert_success
  _has_row "$WD/plain/.context" DV7
}

@test "ladder: a non-git cwd never reaches for the plugin checkout" {
  mkdir -p "$WD/plain"
  before="$(find "$PLUGIN_ROOT/.context" -type f 2> /dev/null | LC_ALL=C sort | xargs -I{} shasum {} 2> /dev/null || true)"
  _sp "$WD/plain" "$PLUGIN_ROOT/$SCRIPT" --task-create DV7 --metadata "$META"
  # No ledger exists in the cwd, so the create cannot land; what matters is where it looked.
  assert_failure
  [[ "$output" != *"$PLUGIN_ROOT/.context"* ]] || fail "$output"
  after="$(find "$PLUGIN_ROOT/.context" -type f 2> /dev/null | LC_ALL=C sort | xargs -I{} shasum {} 2> /dev/null || true)"
  [ "$before" = "$after" ]
}

@test "ladder: the git toplevel outranks \$PWD when cwd is a subdirectory" {
  repo="$(mk_git_fixture --dir "$WD/repo" --file 'a.txt:hi' --commit init)"
  mkdir -p "$repo/sub/deep"
  _seed "$repo/.context"
  _sp "$repo/sub/deep" "$PLUGIN_ROOT/$SCRIPT" --task-create DV7 --metadata "$META"
  assert_success
  _has_row "$repo/.context" DV7
  [ ! -e "$repo/sub/deep/.context" ]
}

@test "ladder: a linked worktree resolves to its own toplevel, not the main worktree" {
  repo="$(mk_git_fixture --dir "$WD/repo" --file 'a.txt:hi' --commit init)"
  git -C "$repo" -c user.name=t -c user.email=t@t worktree add -q "$WD/wt" -b wtb 2> /dev/null \
    || skip "git worktree unavailable"
  _seed "$repo/.context"
  _seed "$WD/wt/.context"
  _sp "$WD/wt" "$PLUGIN_ROOT/$SCRIPT" --task-create DV7 --metadata "$META"
  assert_success
  _has_row "$WD/wt/.context" DV7
  run jq -e '.tasks | has("DV7")' "$repo/.context/state.json"
  assert_failure
}

@test "ladder: CLAUDE_PROJECT_DIR/.context outranks the git toplevel" {
  repo="$(mk_git_fixture --dir "$WD/repo" --file 'a.txt:hi' --commit init)"
  _seed "$repo/.context"
  _seed "$WD/proj/.context"
  export CLAUDE_PROJECT_DIR="$WD/proj"
  _sp "$repo" "$PLUGIN_ROOT/$SCRIPT" --task-create DV7 --metadata "$META"
  assert_success
  _has_row "$WD/proj/.context" DV7
  run jq -e '.tasks | has("DV7")' "$repo/.context/state.json"
  assert_failure
}

@test "ladder: CONTEXT_DIR outranks CLAUDE_PROJECT_DIR" {
  _seed "$WD/ctx"
  _seed "$WD/proj/.context"
  export CONTEXT_DIR="$WD/ctx" CLAUDE_PROJECT_DIR="$WD/proj"
  mkdir -p "$WD/plain"
  _sp "$WD/plain" "$PLUGIN_ROOT/$SCRIPT" --task-create DV7 --metadata "$META"
  assert_success
  _has_row "$WD/ctx" DV7
  run jq -e '.tasks | has("DV7")' "$WD/proj/.context/state.json"
  assert_failure
}

@test "ladder: an explicit --state wins over every declared root" {
  _seed "$WD/ctx"
  _seed "$WD/proj/.context"
  _seed "$WD/explicit"
  mkdir -p "$WD/plain"
  _seed "$WD/plain/.context"
  export CONTEXT_DIR="$WD/ctx" CLAUDE_PROJECT_DIR="$WD/proj"
  _sp "$WD/plain" "$PLUGIN_ROOT/$SCRIPT" --state "$WD/explicit/state.json" \
    --task-create DV7 --metadata "$META"
  assert_success
  _has_row "$WD/explicit" DV7
  for d in "$WD/ctx" "$WD/proj/.context" "$WD/plain/.context"; do
    run jq -e '.tasks | has("DV7")' "$d/state.json"
    assert_failure
  done
}

@test "refuse: a cwd inside the script's own plugin root is exit 4 with nothing written" {
  _fake_plugin
  mkdir -p "$WD/plug/benchmark/workdirs/arm"
  _sp "$WD/plug/benchmark/workdirs/arm" "$FAKE_SCRIPT" --task-create DV7 --metadata "$META"
  assert_failure 4
  [[ "$output" == *"inside the plugin root"* ]] || fail "$output"
  [ ! -e "$WD/plug/benchmark/workdirs/arm/.context" ]
  [ ! -e "$WD/plug/.context" ]
}

@test "refuse: a nested workdir in a plugin git checkout no longer reaches that checkout's ledger" {
  # The reported layout: the plugin repo's own live .context exists, the caller's cwd is a
  # subdirectory of the same repo that is not itself a repo root.
  _fake_plugin
  git -C "$WD/plug" init -q .
  _seed "$WD/plug/.context"
  mkdir -p "$WD/plug/benchmark/workdirs/arm/with"
  snap="$(shasum "$WD/plug/.context/state.json")"
  _sp "$WD/plug/benchmark/workdirs/arm/with" "$FAKE_SCRIPT" --task-create DV7 --metadata "$META"
  assert_failure 4
  [ "$snap" = "$(shasum "$WD/plug/.context/state.json")" ]
  [ ! -e "$WD/plug/.context/logs" ]
}

@test "trust: CONTEXT_DIR pointing inside the plugin root is honoured" {
  _fake_plugin
  _seed "$WD/plug/.context"
  export CONTEXT_DIR="$WD/plug/.context"
  mkdir -p "$WD/plain"
  _sp "$WD/plain" "$FAKE_SCRIPT" --task-create DV7 --metadata "$META"
  assert_success
  _has_row "$WD/plug/.context" DV7
}

@test "trust: CLAUDE_PROJECT_DIR equal to the plugin root is honoured (self-hosted session)" {
  _fake_plugin
  _seed "$WD/plug/.context"
  export CLAUDE_PROJECT_DIR="$WD/plug"
  mkdir -p "$WD/plug/benchmark/workdirs/arm"
  _sp "$WD/plug/benchmark/workdirs/arm" "$FAKE_SCRIPT" --task-create DV7 --metadata "$META"
  assert_success
  _has_row "$WD/plug/.context" DV7
}

@test "trust: WORKSPACE_ROOT inside the plugin root is honoured" {
  _fake_plugin
  _seed "$WD/plug/.context"
  export WORKSPACE_ROOT="$WD/plug"
  mkdir -p "$WD/plain"
  _sp "$WD/plain" "$FAKE_SCRIPT" --task-create DV7 --metadata "$META"
  assert_success
  _has_row "$WD/plug/.context" DV7
}

@test "trust: an explicit --state inside the plugin root is honoured" {
  _fake_plugin
  _seed "$WD/plug/.context"
  mkdir -p "$WD/plain"
  _sp "$WD/plain" "$FAKE_SCRIPT" --state "$WD/plug/.context/state.json" \
    --task-create DV7 --metadata "$META"
  assert_success
  _has_row "$WD/plug/.context" DV7
}

@test "trust: a cwd that IS the plugin's git toplevel resolves to its own .context" {
  _fake_plugin
  git -C "$WD/plug" init -q .
  _seed "$WD/plug/.context"
  _sp "$WD/plug" "$FAKE_SCRIPT" --task-create DV7 --metadata "$META"
  assert_success
  _has_row "$WD/plug/.context" DV7
}

@test "refuse: CLAUDE_PLUGIN_ROOT counts as the plugin root even for another copy of the script" {
  # The manifest makes it a root corpflow_plugin_root accepts; a bare directory is not one.
  mkdir -p "$WD/installed/sub" "$WD/installed/.claude-plugin"
  : > "$WD/installed/.claude-plugin/plugin.json"
  export CLAUDE_PLUGIN_ROOT="$WD/installed"
  # The helper's exported PLUGIN_ROOT is also Codex's host variable, which the resolver ranks
  # above CLAUDE_PLUGIN_ROOT; the child must see only the Claude one.
  export -n PLUGIN_ROOT
  _sp "$WD/installed/sub" "$PLUGIN_ROOT/$SCRIPT" --task-create DV7 --metadata "$META"
  assert_failure 4
  [[ "$output" == *"inside the plugin root"* ]] || fail "$output"
}

@test "refuse: a symlinked route into the plugin root is caught by the physical comparison" {
  _fake_plugin
  ln -s "$WD/plug" "$WD/alias"
  mkdir -p "$WD/plug/sub"
  _sp "$WD/alias/sub" "$FAKE_SCRIPT" --task-create DV7 --metadata "$META"
  assert_failure 4
}

@test "refuse: an unrelated sibling that merely shares the plugin root's name prefix is allowed" {
  _fake_plugin
  mkdir -p "$WD/plug-work"
  _seed "$WD/plug-work/.context"
  _sp "$WD/plug-work" "$FAKE_SCRIPT" --task-create DV7 --metadata "$META"
  assert_success
  _has_row "$WD/plug-work/.context" DV7
}

#!/usr/bin/env bats
# Tests for the reader-ladder nesting guard (corpflow_inferred_ctx_ok in
# skills/shared/lib/state-read-lib.sh): a cwd nested inside the plugin's own checkout, but not at
# its git toplevel, must not borrow that checkout's live ledger, while a linked worktree at its
# toplevel still reaches the main ledger. The fixture checkout stands in for the plugin root via
# CLAUDE_PLUGIN_ROOT plus a manifest, so the repo under test is never touched.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

# PLUGIN_ROOT is the host-root env the guard reads; keep the repo path under another name.
REPO="$PLUGIN_ROOT"
SRL="skills/shared/lib/state-read-lib.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  WD="$(cd "$WD" && pwd -P)"
  ROOT="$WD/root"
  mkdir -p "$ROOT"
  git -C "$ROOT" init -q
  git -C "$ROOT" -c user.name=t -c user.email=t@t -c commit.gpgsign=false \
    -c core.hooksPath=/dev/null commit -q --allow-empty -m init
  mkdir -p "$ROOT/.claude-plugin" "$ROOT/.context" "$ROOT/sub/deep"
  printf '{}' > "$ROOT/.claude-plugin/plugin.json"
  printf '%s' '{"version":2,"worktask_id":"wt-1","run_index":0,"tasks":{}}' > "$ROOT/.context/state.json"
  export CLAUDE_PLUGIN_ROOT="$ROOT"
  export GIT_CEILING_DIRECTORIES="$WD"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  unset CONTEXT_DIR WORKSPACE_ROOT CLAUDE_PROJECT_DIR BASE_PLUGIN_ROOT PLUGIN_ROOT
}

teardown() {
  export PLUGIN_ROOT="$REPO"
  _test_helper_cleanup
}

# <cwd> <snippet> — runs the snippet with the library sourced, from <cwd>.
inlib() {
  local cwd="$1"; shift
  run bash -c "set -uo pipefail; cd '$cwd' && . '$REPO/$SRL' && $1"
}

mk_worktree() {
  git -C "$ROOT" -c user.name=t -c user.email=t@t -c commit.gpgsign=false \
    -c core.hooksPath=/dev/null worktree add -q "$ROOT/.claude/worktrees/wt" -b wt
  mkdir -p "$ROOT/.claude/worktrees/wt/sub"
}

# --- the nested cwd ---------------------------------------------------------------

@test "N1: a plain subdirectory of the checkout resolves nothing, silently" {
  inlib "$ROOT/sub/deep" 'corpflow_context_dir; echo "rc=$?"'
  assert_success
  assert_output 'rc=1'
}

@test "N2: a symlinked route into the root is refused the same way" {
  ln -s "$ROOT/sub" "$WD/link"
  inlib "$WD/link" 'corpflow_context_dir; echo "rc=$?"'
  assert_output 'rc=1'
}

@test "N3: a sibling sharing the root's name prefix still resolves" {
  mkdir -p "$WD/root-x/sub"
  git -C "$WD/root-x" init -q
  mkdir -p "$WD/root-x/.context"
  printf '{}' > "$WD/root-x/.context/state.json"
  inlib "$WD/root-x/sub" 'corpflow_context_dir; echo " rc=$?"'
  assert_output "$WD/root-x/.context rc=0"
}

# --- the legitimate shapes ----------------------------------------------------------

@test "A1: cwd at the checkout toplevel resolves its own .context" {
  inlib "$ROOT" 'corpflow_context_dir; echo " rc=$?"'
  assert_output "$ROOT/.context rc=0"
}

@test "A2: CONTEXT_DIR inside the root is honoured from the nested cwd" {
  inlib "$ROOT/sub" "CONTEXT_DIR='$ROOT/.context' corpflow_context_dir; echo ' rc='\$?"
  assert_output "$ROOT/.context rc=0"
}

@test "A3: WORKSPACE_ROOT and CLAUDE_PROJECT_DIR inside the root are honoured" {
  inlib "$ROOT/sub" "WORKSPACE_ROOT='$ROOT' corpflow_context_dir; echo ' rc='\$?"
  assert_output "$ROOT/.context rc=0"
  inlib "$ROOT/sub" "CLAUDE_PROJECT_DIR='$ROOT' corpflow_context_dir; echo ' rc='\$?"
  assert_output "$ROOT/.context rc=0"
}

@test "A4: a linked worktree at its toplevel resolves the main worktree's .context (R12b)" {
  mk_worktree
  inlib "$ROOT/.claude/worktrees/wt" 'corpflow_context_dir; echo " rc=$?"'
  assert_output "$ROOT/.context rc=0"
}

@test "A5: a subdirectory of the linked worktree is refused, as the writer refuses it" {
  mk_worktree
  inlib "$ROOT/.claude/worktrees/wt/sub" 'corpflow_context_dir; echo "rc=$?"'
  assert_output 'rc=1'
}

@test "A6: a refused rank 5 ends the ladder instead of falling through to rank 6" {
  mk_worktree
  mkdir -p "$ROOT/.claude/worktrees/wt/.context"
  printf '{}' > "$ROOT/.claude/worktrees/wt/.context/state.json"
  inlib "$ROOT/.claude/worktrees/wt/sub" 'corpflow_context_dir; echo "rc=$?"'
  assert_output 'rc=1'
}

@test "A7: the predicate takes the 1-arg and 2-arg forms and rejects an unreadable dir" {
  inlib "$ROOT/sub" "corpflow_inferred_ctx_ok '$ROOT/.context'; echo \"1arg=\$?\"; corpflow_inferred_ctx_ok '$ROOT/.context' '$ROOT'; echo \"2arg=\$?\"; corpflow_inferred_ctx_ok '$WD/none'; echo \"none=\$?\""
  assert_output $'1arg=1\n2arg=1\nnone=1'
  inlib "$ROOT" "corpflow_inferred_ctx_ok '$ROOT/.context' '$ROOT'; echo \"top=\$?\""
  assert_output 'top=0'
}

# --- reader/writer parity (state-patch.sh exit 4 <=> reader rc 1) ----------------

@test "P1: the writer refuses exactly where the reader does, and not where it resolves" {
  local cwd rc_w rc_r
  for cwd in "$ROOT/sub/deep" "$ROOT"; do
    rc_w=0
    (cd "$cwd" && bash "$REPO/skills/worktask/scripts/state-patch.sh" --task-status PL0 pending > /dev/null 2>&1) || rc_w=$?
    rc_r=0
    (cd "$cwd" && . "$REPO/$SRL" && corpflow_context_dir > /dev/null) || rc_r=$?
    if [ "$cwd" = "$ROOT/sub/deep" ]; then
      [ "$rc_w" -eq 4 ] && [ "$rc_r" -eq 1 ]
    else
      [ "$rc_w" -ne 4 ] && [ "$rc_r" -eq 0 ]
    fi
  done
}

# --- the four direct callers and two lib-caller families --------------------------

@test "C1: model-switch-lib returns an empty root from the nested cwd, the toplevel root at the top" {
  run bash -c "cd '$ROOT/sub' && . '$REPO/hooks/model-switch-lib.sh' && corpflow_workspace_root"
  assert_success
  assert_output ''
  run bash -c "set -euf -o pipefail; cd '$ROOT' && . '$REPO/hooks/model-switch-lib.sh' && corpflow_workspace_root"
  assert_output "$ROOT"
}

@test "C2: model-switch-lib keeps -e across the lazy source and resolves a worktree toplevel" {
  mk_worktree
  # rank 6 also needs the main ledger to own the worktree (a registered workspace_path)
  jq --arg w "$ROOT/.claude/worktrees/wt" '.tasks.DV0={"metadata":{"workspace_path":$w}}' \
    "$ROOT/.context/state.json" > "$WD/s.json"
  mv "$WD/s.json" "$ROOT/.context/state.json"
  run bash -c "set -euf -o pipefail; cd '$ROOT/.claude/worktrees/wt' && . '$REPO/hooks/model-switch-lib.sh' && corpflow_workspace_root; case \$- in *e*) echo ' e-kept' ;; esac"
  assert_output "$ROOT e-kept"
  run bash -c "cd '$ROOT/.claude/worktrees/wt/sub' && . '$REPO/hooks/model-switch-lib.sh' && corpflow_workspace_root"
  assert_output ''
}

@test "C3: mailbox-lib mb_dir returns 1 from the nested cwd and creates no mailbox" {
  run bash -c "cd '$ROOT/sub' && . '$REPO/skills/worktask/scripts/mailbox-lib.sh' && mb_dir"
  assert_failure 1
  assert_output ''
  [ ! -e "$ROOT/.context/mailbox" ]
  run bash -c "cd '$ROOT' && . '$REPO/skills/worktask/scripts/mailbox-lib.sh' && mb_dir"
  assert_success
  assert_output "$ROOT/.context/mailbox"
}

@test "C4: brief-compose without --state dies 'pass --state' from the nested cwd" {
  run bash -c "cd '$ROOT/sub' && bash '$REPO/skills/worktask/scripts/brief-compose.sh' DV0"
  assert_failure 2
  assert_output --partial 'pass --state'
}

@test "C5: model-matrix ignores a seeded state.models row from the nested cwd" {
  jq '.models={"developer":{"model":"haiku","effort":"low"}}' "$ROOT/.context/state.json" > "$WD/s.json"
  mv "$WD/s.json" "$ROOT/.context/state.json"
  run bash -c "cd '$ROOT' && bash '$REPO/skills/worktask/scripts/model-matrix.sh' --resolve developer"
  assert_success
  assert_output --partial 'haiku'
  run bash -c "cd '$ROOT/sub' && bash '$REPO/skills/worktask/scripts/model-matrix.sh' --resolve developer"
  refute_output --partial 'haiku'
}

@test "C6: resolve-worktask (dv-screenshot family) exits 4 from the nested cwd, resolves at the top" {
  run bash -c "cd '$ROOT/sub' && bash '$REPO/skills/dv-screenshot-capture/scripts/resolve-worktask.sh'"
  assert_failure 4
  assert_output ''
  run bash -c "cd '$ROOT' && bash '$REPO/skills/dv-screenshot-capture/scripts/resolve-worktask.sh'"
  assert_success
  assert_output --partial 'worktask_id=wt-1'
}

@test "C7: state-patch (worktask family) leaves the root's ledger untouched from the nested cwd" {
  local before after
  before=$(cksum < "$ROOT/.context/state.json")
  run bash -c "cd '$ROOT/sub' && bash '$REPO/skills/worktask/scripts/state-patch.sh' --task-status PL0 in_progress"
  assert_failure 4
  after=$(cksum < "$ROOT/.context/state.json")
  [ "$before" = "$after" ]
}

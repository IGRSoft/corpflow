#!/usr/bin/env bats
# Tests for hooks/lib/dedupe-lib.sh — the one definition of the dedupe key and
# its sentinel store, shared by the PreToolUse gate and its PostToolUse
# companion. Exercised directly here; the two hooks' suites cover the wiring.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context"
  # shellcheck source=hooks/lib/dedupe-lib.sh
  . "$PLUGIN_ROOT/hooks/lib/dedupe-lib.sh"
}

mk_repo() {
  git -C "$1" init -q
  git -C "$1" config user.email t@example.com
  git -C "$1" config user.name t
  git -C "$1" config commit.gpgsign false
  echo seed > "$1/src.txt"
  git -C "$1" add -A
  git -C "$1" commit -qm init
}

@test "dedupe_key is a pure function of its four components" {
  local a b
  a="$(dedupe_key full_test_run './run-tests.sh' fp0 0)"
  b="$(dedupe_key full_test_run './run-tests.sh' fp0 0)"
  [ -n "$a" ]
  [ "$a" = "$b" ]
  [ "$a" != "$(dedupe_key scoped_test_run './run-tests.sh' fp0 0)" ]
  [ "$a" != "$(dedupe_key full_test_run './run-tests.sh --changed' fp0 0)" ]
  [ "$a" != "$(dedupe_key full_test_run './run-tests.sh' fp1 0)" ]
  [ "$a" != "$(dedupe_key full_test_run './run-tests.sh' fp0 1)" ]
}

@test "dedupe_key never stores the invocation — only its digest reaches the filesystem" {
  local k
  k="$(dedupe_key full_test_run 'pytest --token sk-secret-abc' fp0 0)"
  [[ "$k" != *"sk-secret"* ]]
  [[ "$k" =~ ^[0-9a-f]{40}$ ]]
}

@test "dedupe_root resolution order: payload cwd, WORKSPACE_ROOT, CLAUDE_PROJECT_DIR, cwd" {
  mkdir -p "$WD/a" "$WD/b" "$WD/c"
  local payload
  # Hook payloads carry the working directory as a TOP-LEVEL `cwd`; Bash's
  # tool_input has no such field, so reading it alone resolved nothing.
  payload="$(jq -cn --arg d "$WD/a" '{cwd:$d, tool_input:{command:"./run-tests.sh"}}')"
  WORKSPACE_ROOT="$WD/b" CLAUDE_PROJECT_DIR="$WD/c" run dedupe_root "$payload"
  [ "$output" = "$WD/a" ]

  WORKSPACE_ROOT="$WD/b" CLAUDE_PROJECT_DIR="$WD/c" run dedupe_root '{"tool_input":{}}'
  [ "$output" = "$WD/b" ]

  CLAUDE_PROJECT_DIR="$WD/c" run dedupe_root '{"tool_input":{}}'
  [ "$output" = "$WD/c" ]

  run dedupe_root '{}'
  [ "$output" = "." ]
}

@test "dedupe_root prefers the top-level cwd over a tool_input.cwd" {
  mkdir -p "$WD/top" "$WD/nested"
  local payload
  payload="$(jq -cn --arg t "$WD/top" --arg n "$WD/nested" '{cwd:$t, tool_input:{cwd:$n}}')"
  run dedupe_root "$payload"
  [ "$output" = "$WD/top" ]
}

@test "dedupe_root ignores a payload cwd that does not exist (a wrong root is an allow, never a deny)" {
  mkdir -p "$WD/c"
  local payload
  payload="$(jq -cn '{cwd:"/no/such/dir"}')"
  CLAUDE_PROJECT_DIR="$WD/c" run dedupe_root "$payload"
  [ "$output" = "$WD/c" ]
}

@test "tree_fingerprint tracks the tree at its ROOT argument, not the process cwd" {
  mkdir -p "$WD/main"
  mk_repo "$WD/main"
  git -C "$WD/main" worktree add -q -b feat "$WD/wt"

  local main_before wt_before
  main_before="$(tree_fingerprint "$WD/main")"
  wt_before="$(tree_fingerprint "$WD/wt")"
  [ -n "$main_before" ]
  [ -n "$wt_before" ]

  # A staged edit inside the linked worktree. The worktree keeps its own index,
  # so the main checkout reports nothing — the exact condition that made the
  # deny's stated remedy unreachable from a worktree-isolated stage.
  echo 'fix' >> "$WD/wt/src.txt"
  git -C "$WD/wt" add -A
  [ "$(tree_fingerprint "$WD/wt")" != "$wt_before" ]
  [ "$(tree_fingerprint "$WD/main")" = "$main_before" ]
}

@test "tree_fingerprint is empty outside a repo (fail-open: no key, no suppression)" {
  run tree_fingerprint "$WD"
  [ -z "$output" ]
}

@test "run_index_of reads a numeric run_index and rejects every other shape" {
  printf '{"run_index":3,"tasks":{}}' > "$WD/.context/state.json"
  run run_index_of "$WD/.context"
  [ "$output" = "3" ]

  printf '{"run_index":"3","tasks":{}}' > "$WD/.context/state.json"
  run run_index_of "$WD/.context"
  [ -z "$output" ]

  printf 'not json' > "$WD/.context/state.json"
  run run_index_of "$WD/.context"
  [ -z "$output" ]
}

@test "dedupe_pending_key is fingerprint-free, so both hooks name the marker identically" {
  local a b
  a="$(dedupe_pending_key full_test_run './run-tests.sh' 0)"
  b="$(dedupe_pending_key full_test_run './run-tests.sh' 0)"
  [ "$a" = "$b" ]
  [[ "$a" =~ ^[0-9a-f]{40}$ ]]
  [ "$a" != "$(dedupe_pending_key scoped_test_run './run-tests.sh' 0)" ]
  [ "$a" != "$(dedupe_pending_key full_test_run './run-tests.sh --changed' 0)" ]
  [ "$a" != "$(dedupe_pending_key full_test_run './run-tests.sh' 1)" ]
  # Never the same name as a sentinel, whatever the fingerprint component is.
  [ "$a" != "$(dedupe_key full_test_run './run-tests.sh' '' 0)" ]
}

@test "dedupe_lookup reads the sentinel and NEVER the pending marker" {
  dedupe_mark_pending "$WD/.context" pend01 abc123 QA
  [ -f "$WD/.context/logs/.test-runs/pend01.pending" ]
  run dedupe_lookup "$WD/.context" abc123
  [ -z "$output" ]

  dedupe_promote "$WD/.context" pend01
  run dedupe_lookup "$WD/.context" abc123
  [[ "$output" == QA\ * ]]
}

@test "dedupe_promote renames the marker to the FULL key it recorded before the run" {
  dedupe_mark_pending "$WD/.context" pend01 abc123 QA
  dedupe_promote "$WD/.context" pend01
  local d="$WD/.context/logs/.test-runs"
  [ ! -e "$d/pend01.pending" ]
  [ -f "$d/abc123" ]
  # dedupe_lookup's `head -c 200` contract: exactly "<stage> <ts>", no key.
  run dedupe_lookup "$WD/.context" abc123
  [ "$(printf '%s\n' "$output" | wc -w | tr -d ' ')" = "2" ]
  [[ "$output" != *abc123* ]]
}

@test "dedupe_discard removes the marker and leaves no sentinel" {
  dedupe_mark_pending "$WD/.context" pend01 abc123 QA
  dedupe_discard "$WD/.context" pend01
  [ ! -f "$WD/.context/logs/.test-runs/pend01.pending" ]
  run dedupe_lookup "$WD/.context" abc123
  [ -z "$output" ]
}

@test "a symlinked sentinel is refused on read, on write and on promotion" {
  local d="$WD/.context/logs/.test-runs"
  mkdir -p "$d"
  ln -s /etc/hosts "$d/sym"
  run dedupe_lookup "$WD/.context" sym
  [ -z "$output" ]

  dedupe_mark_pending "$WD/.context" sym2 target2 QA
  rm -f "$d/sym2.pending"
  ln -s /etc/hosts "$d/sym2.pending"
  dedupe_promote "$WD/.context" sym2
  [ -L "$d/sym2.pending" ]
  [ ! -e "$d/target2" ]

  # A symlink planted at the DESTINATION between marking and promoting.
  dedupe_mark_pending "$WD/.context" sym3 target3 QA
  ln -s /etc/hosts "$d/target3"
  dedupe_promote "$WD/.context" sym3
  [ -L "$d/target3" ]
  [ -f "$d/sym3.pending" ]
}

@test "pruning bounds the directory without touching a fresh marker or any sentinel" {
  local d="$WD/.context/logs/.test-runs"
  mkdir -p "$d"
  printf 'QA old\n' > "$d/stale.pending"
  printf 'QA kept\n' > "$d/durable"
  touch -t 200001010000 "$d/stale.pending" "$d/durable"
  dedupe_mark_pending "$WD/.context" fresh abc123 QA

  [ ! -f "$d/stale.pending" ]
  [ -f "$d/fresh.pending" ]
  [ -f "$d/durable" ]
}

#!/usr/bin/env bats
# status-view.sh — read-only status table over the worktask ledgers.
#
# The load-bearing assertions are that nothing is DROPPED and nothing is WRITTEN.
# A row silently missing from a status board reads as "that task does not exist",
# which is worse than no board at all; and a viewer that mutates a ledger it was
# only asked to display corrupts the very state the operator is inspecting.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/status-view.sh"

# mk_ledger <dir> [jq filters...] — v2 ledger with an empty tasks{}.
mk_ledger() {
  local dir="$1"; shift
  mkdir -p "$dir/.context"
  printf '%s\n' '{"version":2,"worktask_id":"wt-status","plan_file":".context/planning-0.md","platform":"all","run_index":0,"tasks":{},"facts":{},"handoffs":{}}' \
    > "$dir/.context/state.json"
  local f tmp="$dir/.context/state.json.tmp"
  for f in "$@"; do
    jq "$f" "$dir/.context/state.json" > "$tmp" || fail "mk_ledger: jq filter failed: $f"
    mv -f "$tmp" "$dir/.context/state.json"
  done
}

# task <ID> <STAGE> <STATUS> [AGENT] — jq filter seeding one ledger task.
task() {
  if [ -n "${4:-}" ]; then
    printf '.tasks["%s"] = {"status":"%s","metadata":{"stage":"%s","agent":"%s"}}' "$1" "$3" "$2" "$4"
  else
    printf '.tasks["%s"] = {"status":"%s","metadata":{"stage":"%s"}}' "$1" "$3" "$2"
  fi
}

# mk_group <dir> <group> <orchestrator-json> — a megatask group with no nested ledgers.
mk_group() {
  local dir="$1" group="$2" json="$3"
  mkdir -p "$dir/.worktrees/$group"
  printf '%s\n' "$json" > "$dir/.worktrees/$group/orchestrator.json"
}

# mk_nested_ledger <dir> <group> <issue#> [jq filters...] — the per-issue worktask ledger.
mk_nested_ledger() {
  local dir="$1" group="$2" num="$3"; shift 3
  mk_ledger "$dir/.worktrees/$group/$num" "$@"
}

# checksum_ledgers <dir> — stable digest of every ledger under a work dir.
checksum_ledgers() {
  find "$1" -name 'state.json' -o -name 'orchestrator.json' | sort | xargs shasum
}

# --- the empty board ---------------------------------------------------------

@test "no ledger and no worktrees: says so plainly and exits 0" {
  local w; w="$(mk_tmpworkdir)"

  run_script_env --cwd "$w" "$SCRIPT"
  assert_success
  assert_output --partial "no active worktask here"
}

@test "a seeded ledger with an empty tasks{} is not mistaken for an absent one" {
  local w; w="$(mk_tmpworkdir)"
  mk_ledger "$w"

  run_script_env --cwd "$w" "$SCRIPT"
  assert_success
  assert_output --partial "no tasks recorded yet"
  refute_output --partial "no active worktask here"
}

# --- completeness: nothing may be dropped ------------------------------------

@test "every task in tasks{} gets a row, whatever fields it carries" {
  local w; w="$(mk_tmpworkdir)"
  mk_ledger "$w" \
    "$(task PL0 PL completed corpflow:product-manager)" \
    "$(task AR0 AR completed corpflow:software-architector)" \
    "$(task DV0 DV in_progress corpflow:developer)" \
    "$(task QA0 QA pending)" \
    '.tasks["DC0"] = {"status":"skipped"}'

  run_script_env --cwd "$w" "$SCRIPT"
  assert_success
  local id
  for id in PL0 AR0 DV0 QA0 DC0; do
    assert_output --partial "$id"
  done
}

@test "a task with no agent and no blocked_by renders rather than disappearing" {
  local w; w="$(mk_tmpworkdir)"
  # Explicit nulls, not merely absent keys: a jq filter that assumes a present
  # field drops these two shapes in different ways.
  mk_ledger "$w" \
    '.tasks["QA0"] = {"status":"pending","agent":null,"blocked_by":null,"metadata":{"stage":"QA"}}' \
    '.tasks["DC0"] = {"status":"pending"}'

  run_script_env --cwd "$w" "$SCRIPT"
  assert_success
  assert_output --partial "QA0"
  assert_output --partial "DC0"
}

@test "a non-object task entry is surfaced as malformed, not skipped" {
  local w; w="$(mk_tmpworkdir)"
  mk_ledger "$w" "$(task DV0 DV in_progress corpflow:developer)" '.tasks["QA0"] = "wat"'

  run_script_env --cwd "$w" "$SCRIPT"
  assert_success
  assert_output --partial "QA0"
  assert_output --partial "(malformed)"
}

@test "blocked_by is rendered for the task it blocks" {
  local w; w="$(mk_tmpworkdir)"
  mk_ledger "$w" \
    "$(task DV0 DV in_progress corpflow:developer)" \
    '.tasks["QA0"] = {"status":"pending","blocked_by":["DV0"],"metadata":{"stage":"QA"}}'

  run_script_env --cwd "$w" "$SCRIPT"
  assert_success
  assert_line --regexp 'QA0.*DV0'
}

# --- degradation under a concurrent writer -----------------------------------

@test "a truncated ledger degrades to a notice instead of crashing" {
  local w; w="$(mk_tmpworkdir)"
  mkdir -p "$w/.context"
  # state-patch.sh renames into place, so a poll can catch a partial file.
  printf '%s' '{"version":2,"tasks":{"DV0":' > "$w/.context/state.json"

  run_script_env --cwd "$w" "$SCRIPT"
  assert_success
  assert_output --partial "not readable right now"
}

@test "an unreadable local ledger does not suppress the megatask rows" {
  local w; w="$(mk_tmpworkdir)"
  mkdir -p "$w/.context"
  printf '%s' '{"version":2,"tasks":{"DV0":' > "$w/.context/state.json"
  mk_group "$w" g '{"group":"g","issues":[{"number":7,"status":"in_progress","blocked_by":[]}]}'

  run_script_env --cwd "$w" "$SCRIPT"
  assert_success
  assert_output --partial "not readable right now"
  assert_output --partial "#7"
}

@test "an orchestrator with no usable issues[] is a notice, not a crash" {
  local w; w="$(mk_tmpworkdir)"
  mk_ledger "$w" "$(task DV0 DV in_progress corpflow:developer)"
  mk_group "$w" g '{"group":"g","issues":"nope"}'

  run_script_env --cwd "$w" "$SCRIPT"
  assert_success
  assert_output --partial "no usable issues[] array"
  assert_output --partial "DV0"
}

# --- the megatask merge (P1) -------------------------------------------------

@test "with no .worktrees present the merge is a clean no-op" {
  local w; w="$(mk_tmpworkdir)"
  mk_ledger "$w" "$(task DV0 DV in_progress corpflow:developer)"

  run_script_env --cwd "$w" "$SCRIPT"
  assert_success
  assert_output --partial "DV0"
  refute_output --partial "megatask groups"
}

@test "megatask issues join the same table, staged from their own nested ledger" {
  local w; w="$(mk_tmpworkdir)"
  mk_ledger "$w" "$(task PL0 PL completed corpflow:product-manager)"
  mk_group "$w" milestone-9 \
    '{"group":"milestone-9","issues":[{"number":41,"status":"in_progress","blocked_by":[]},{"number":42,"status":"blocked","blocked_by":[41]}]}'
  mk_nested_ledger "$w" milestone-9 41 "$(task DV0 DV in_progress corpflow:developer)"

  run_script_env --cwd "$w" "$SCRIPT"
  assert_success
  assert_output --partial "megatask groups: 1"
  assert_output --partial "PL0"
  # #41's stage comes from its nested ledger; #42 has none and must still appear.
  assert_line --regexp '#41 +DV +in_progress +developer'
  assert_line --regexp '#42 .*blocked.*#41'
}

@test "an issue with no nested ledger yet still gets a row" {
  local w; w="$(mk_tmpworkdir)"
  mk_ledger "$w"
  mk_group "$w" g '{"group":"g","issues":[{"number":5,"status":"ready","blocked_by":[]}]}'

  run_script_env --cwd "$w" "$SCRIPT"
  assert_success
  assert_output --partial "#5"
  assert_output --partial "ready"
}

@test "--no-worktrees drops the group rows and keeps the local ones" {
  local w; w="$(mk_tmpworkdir)"
  mk_ledger "$w" "$(task DV0 DV in_progress corpflow:developer)"
  mk_group "$w" g '{"group":"g","issues":[{"number":7,"status":"ready","blocked_by":[]}]}'

  run_script_env --cwd "$w" "$SCRIPT" --no-worktrees
  assert_success
  assert_output --partial "DV0"
  refute_output --partial "#7"
}

# --- read-only invariant -----------------------------------------------------

@test "a run mutates neither ledger" {
  local w; w="$(mk_tmpworkdir)"
  mk_ledger "$w" "$(task DV0 DV in_progress corpflow:developer)"
  mk_group "$w" g '{"group":"g","issues":[{"number":7,"status":"in_progress","blocked_by":[]}]}'
  mk_nested_ledger "$w" g 7 "$(task QA0 QA in_progress corpflow:qa-engineer)"
  local before; before="$(checksum_ledgers "$w")"

  run_script_env --cwd "$w" "$SCRIPT"
  assert_success
  [ "$before" = "$(checksum_ledgers "$w")" ] || fail "status-view mutated a ledger"
}

@test "--watch mutates nothing and exits cleanly when signalled" {
  local w; w="$(mk_tmpworkdir)"
  mk_ledger "$w" "$(task DV0 DV in_progress corpflow:developer)"
  local before; before="$(checksum_ledgers "$w")"

  # SIGTERM shares the handler and the loop-exit path with the Ctrl-C (SIGINT)
  # route; a backgrounded job here inherits SIGINT as SIG_IGN, so INT is not
  # deliverable from a non-interactive shell and TERM is what a test can send.
  # exec so $! is the script itself and not a wrapping subshell the signal would
  # kill without ever reaching the handler under test.
  bash -c 'cd "$1" && exec bash "$2" --watch 1' _ "$w" "$PLUGIN_ROOT/$SCRIPT" \
    > "$w/watch.out" 2>&1 &
  local pid=$!
  perl -e 'select(undef,undef,undef,2.3)'
  kill -TERM "$pid" 2>/dev/null || true
  perl -e 'select(undef,undef,undef,1.5)'

  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null || true
    fail "--watch did not exit on a terminating signal"
  fi
  [ "$before" = "$(checksum_ledgers "$w")" ] || fail "--watch mutated a ledger"
  grep -q "polling every 1s" "$w/watch.out" || fail "--watch omitted its poll interval"
  grep -q "refreshed " "$w/watch.out" || fail "--watch omitted its refresh timestamp"
}

@test "a single-shot run labels itself a snapshot rather than a live view" {
  local w; w="$(mk_tmpworkdir)"
  mk_ledger "$w" "$(task DV0 DV in_progress corpflow:developer)"

  run_script_env --cwd "$w" "$SCRIPT"
  assert_success
  assert_output --partial "point-in-time snapshot, not live"
}

# --- machine-readable output and argument handling ---------------------------

@test "--json emits every row with the shared shape" {
  local w; w="$(mk_tmpworkdir)"
  mk_ledger "$w" "$(task DV0 DV in_progress corpflow:developer)"
  mk_group "$w" g '{"group":"g","issues":[{"number":7,"status":"blocked","blocked_by":[6]}]}'

  run_script_env --cwd "$w" "$SCRIPT" --json
  assert_success
  local json="$output"
  jq -e '(.rows | length) == 2' <<< "$json" > /dev/null \
    || fail "expected one local row and one megatask row: $json"
  jq -e '.rows[] | select(.task == "DV0") | .source == "state" and .stage == "DV"' <<< "$json" > /dev/null \
    || fail "local row shape: $json"
  jq -e '.rows[] | select(.task == "#7") | .source == "g" and .blocked_by == "#6"' <<< "$json" > /dev/null \
    || fail "megatask row shape: $json"
}

@test "an unknown argument is a usage error" {
  local w; w="$(mk_tmpworkdir)"

  run_script_env --cwd "$w" "$SCRIPT" --nope
  assert_failure 2
  assert_output --partial "unknown argument"
}

@test "--watch rejects a non-positive or non-numeric interval" {
  local w; w="$(mk_tmpworkdir)"

  run_script_env --cwd "$w" "$SCRIPT" --watch 0
  assert_failure 2
  assert_output --partial "positive integer"

  run_script_env --cwd "$w" "$SCRIPT" --watch abc
  assert_failure 2
  assert_output --partial "positive integer"
}

@test "--watch with --json is refused rather than silently ignored" {
  local w; w="$(mk_tmpworkdir)"

  run_script_env --cwd "$w" "$SCRIPT" --watch 2 --json
  assert_failure 2
  assert_output --partial "mutually exclusive"
}

@test "--help prints the header and exits 0" {
  run_script_env "$SCRIPT" --help
  assert_success
  assert_output --partial "STRICTLY READ-ONLY"
}

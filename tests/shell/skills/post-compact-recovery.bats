#!/usr/bin/env bats
# Contract tests for skills/context-compression/scripts/post-compact-recovery.sh
# Contracts (from source + self-test):
#   --dry-run: prints JSON to stdout; does NOT write file.
#   Output JSON shape: .recovery.interrupted_stage.{agent,task_id,error_file,stopped_at}
#                       .recovery.audit_tail_count  .recovery.detected_via
#   Most recent non-advisory subagent_stopped entry wins.
#   Advisory entries (metadata.advisory=true) are filtered out.
#   Plugin prefix stripped: "apple-developer:ios-developer" -> agent "ios-developer".
#   error_file = ".context/errors/<basename>.md".
#   Empty audit file -> agent is null.
#   jq required; --self-test -> exit 0.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/context-compression/scripts/post-compact-recovery.sh"
FIX_AUDIT="${FIXTURES}/skills/post-compact-audit.jsonl"

# --- happy path -----------------------------------------------------------
@test "happy: --dry-run emits JSON recovery pointer with expected top-level keys" {
  local json
  json="$(bash "$PLUGIN_ROOT/$SCRIPT" --audit-file "$FIX_AUDIT" --dry-run)"
  run jq -e '.recovery.detected_via' <<< "$json"
  assert_output '"audit.jsonl-tail"'
  run jq -e '.recovery.interrupted_stage | keys | sort' <<< "$json"
  assert_success
}

@test "happy: most recent non-advisory subagent_stopped entry wins; plugin prefix stripped" {
  # Fixture: taskOLD (product-manager) -> tool -> taskNEW (ios-developer, advisory dup)
  # Most recent non-advisory stop: ios-developer, task taskNEW.
  local json
  json="$(bash "$PLUGIN_ROOT/$SCRIPT" --audit-file "$FIX_AUDIT" --dry-run)"
  run jq -r '.recovery.interrupted_stage.agent' <<< "$json"
  assert_output "ios-developer"
  run jq -r '.recovery.interrupted_stage.task_id' <<< "$json"
  assert_output "taskNEW"
  run jq -r '.recovery.interrupted_stage.error_file' <<< "$json"
  assert_output ".context/errors/ios-developer.md"
}

# --- edge/boundary --------------------------------------------------------
@test "edge: empty audit file yields null agent in recovery pointer" {
  WD="$(mk_tmpworkdir)"
  : > "$WD/empty.jsonl"
  local json
  json="$(bash "$PLUGIN_ROOT/$SCRIPT" --audit-file "$WD/empty.jsonl" --dry-run)"
  run jq -r '.recovery.interrupted_stage.agent' <<< "$json"
  assert_output "null"
}

@test "edge: advisory duplicates are excluded from audit_tail_count" {
  # Fixture has 4 lines: 3 non-advisory (2 stops + 1 tool) + 1 advisory.
  local json
  json="$(bash "$PLUGIN_ROOT/$SCRIPT" --audit-file "$FIX_AUDIT" --dry-run)"
  run jq -r '.recovery.audit_tail_count' <<< "$json"
  assert_output "3"
}

@test "edge: --dry-run does not write any file to --out-dir" {
  WD="$(mk_tmpworkdir)"
  bash "$PLUGIN_ROOT/$SCRIPT" --audit-file "$FIX_AUDIT" --dry-run --out-dir "$WD" > /dev/null
  run find "$WD" -name 'post-compact-*.json'
  assert_output ""
}

@test "edge: --tail-lines 1 only sees last line (advisory dup) -> null agent" {
  local json
  json="$(bash "$PLUGIN_ROOT/$SCRIPT" --audit-file "$FIX_AUDIT" --tail-lines 1 --dry-run)"
  run jq -r '.recovery.interrupted_stage.agent' <<< "$json"
  assert_output "null"
}

# --- failure / exit-code --------------------------------------------------
@test "failure: unknown argument exits 1" {
  run_script "$SCRIPT" --bogus-flag
  assert_failure 1
}

@test "failure: --tail-lines with non-integer exits 1" {
  run_script "$SCRIPT" --tail-lines abc
  assert_failure 1
}

# --- self-test smoke (NON-counting) ---------------------------------------
@test "contract: --self-test passes (smoke)" {
  run_script "$SCRIPT" --self-test
  assert_success
  assert_output --partial "All self-tests passed"
}

# --- default paths --------------------------------------------------------
# The defaults were cwd-relative, so a PostCompact firing from a linked worktree
# or any subdirectory read an empty audit trail and wrote the pointer where no
# resume looks — the hazard state-merge.sh was already hardened against.

@test "paths: defaults are rooted on CLAUDE_PROJECT_DIR, not on cwd" {
  local wd elsewhere
  wd="$(mk_tmpworkdir)"
  elsewhere="$(mk_tmpworkdir)"
  mkdir -p "$wd/.context/logs"
  cp "$FIX_AUDIT" "$wd/.context/logs/audit.jsonl"
  printf '%s' '{"version":2,"tasks":{}}' > "$wd/.context/state.json"

  # Run from an unrelated cwd with no .context/ of its own.
  run bash -c 'cd "$2" && CLAUDE_PROJECT_DIR="$1" bash "$3" >/dev/null 2>&1' \
    _ "$wd" "$elsewhere" "$PLUGIN_ROOT/$SCRIPT"
  assert_success

  # The pointer landed under the project dir...
  run bash -c 'ls "$1"/.context/logs/post-compact-*.json' _ "$wd"
  assert_success
  # ...and it resolved a stage, so the audit file was read from there too.
  run bash -c 'jq -r ".recovery.interrupted_stage.agent" "$1"/.context/logs/post-compact-*.json' _ "$wd"
  refute_output "null"
  # Nothing was written beside the caller.
  [ ! -d "$elsewhere/.context" ]
}

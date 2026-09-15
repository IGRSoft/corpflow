#!/usr/bin/env bats
# Tests for hooks/dv-screenshot-gate.sh: ledger scope, the --check classifier and the live policy.
# Row grammar is owned by skills/worktask/scripts/attach-visual-evidence.sh, so its changes re-run this.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="hooks/dv-screenshot-gate.sh"
DEV_PAYLOAD="${FIXTURES}/hooks/dv-screenshot-gate-developer.payload.json"
NONDEV_PAYLOAD="${FIXTURES}/hooks/dv-screenshot-gate-nondeveloper.payload.json"
BASH_PAYLOAD="${FIXTURES}/hooks/dv-screenshot-gate-bash-developer.payload.json"
BASH_DEV="system-developer:bash-developer"
FULL_TOOLS='["silicon","magick","convert"]'
HDR='| # | Slug | Path | Bytes | Platform | Adapter | Caption | Captured | Design Ref |
|---|------|------|-------|----------|---------|---------|----------|------------|'
TOOLS_ROW='| 01 | diff | — | 0 | backend | cli_fallback | tool_missing: silicon(absent), magick(absent), convert(absent) | 2026-01-01T00:00:00Z | — |'

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context"
  IMG="$WD/.context/images/wt"
  AUDIT="$WD/.context/logs/audit.jsonl"
}

task() { # <agent> <platform> [status]
  jq -cn --arg a "$1" --arg p "$2" --arg s "${3:-in_progress}" \
    '{status: $s, metadata: {stage: "DV", agent: $a, platform: $p}}'
}

ledger() { # <tasks-json> [dispatched-json] [metadata-json] [platform]
  local rows="${2:-}" meta="${3:-}"
  [ -n "$rows" ] || rows='[]'
  [ -n "$meta" ] || meta='{"requires_screenshots":true}'
  jq -n --argjson t "$1" --argjson r "$rows" --argjson m "$meta" --arg p "${4:-web}" \
    '{version: 2, worktask_id: "wt", platform: $p, metadata: $m, tasks: $t, facts: {dispatched_agents: $r}}' \
    > "$WD/.context/state.json"
}

one_dv() { # <platform> [agent] [metadata-json]
  ledger "{\"DV0\": $(task "${2:-$BASH_DEV}" "$1")}" "" "${3:-}" "$1"
}

preflight_meta() { # <tools_absent> <accepted_absent> <accepted_by> [recorded_at]
  jq -cn --argjson a "$1" --argjson c "$2" --arg by "$3" --arg at "${4-2026-01-01T00:00:00Z}" \
    '{requires_screenshots: true, autonomy_preflight: {recorded_at: $at, platform: "backend",
      tools_absent: $a, accepted_absent: $c, accepted_by: $by}}'
}

png() {
  mkdir -p "$IMG"
  printf '\211PNG\r\n\032\nfixture' > "$IMG/$1"
}

manifest() { # <task> <row>...
  local t="$1"
  shift
  mkdir -p "$IMG"
  { printf '# Screenshots — wt / %s\n\n%s\n' "$t" "$HDR"; printf '%s\n' "$@"; } > "$IMG/screenshots-$t.md"
}

img_row() { # <task> <nn> <slug>
  printf '| %s | %s | dv-%s-%s-%s.png | 15 | web | web/playwright | %s | 2026-01-01T00:00:00Z | — |' \
    "$2" "$3" "$1" "$2" "$3" "$3"
}

gate() { run_script_env --env "WORKSPACE_ROOT=$WD" --stdin-string "$1" "$SCRIPT"; }
gate_file() { run_script_env --env "WORKSPACE_ROOT=$WD" --stdin-file "$1" "$SCRIPT"; }
check() { run bash "$PLUGIN_ROOT/$SCRIPT" --check "$1" --state "$WD/.context/state.json"; }

assert_block() { # <block_kind>
  assert_success
  echo "$output" | jq -e --arg k "$1" '.decision == "block" and (.reason | startswith($k))
    and .hookSpecificOutput.hookEventName == "SubagentStop"
    and (.hookSpecificOutput.additionalContext | length > 0)'
  assert_audit_row screenshot_gate_block --file "$AUDIT" --result block --meta "block_kind=$1"
}

assert_pass() { # <class>
  assert_success
  assert_output ''
  assert_audit_row screenshot_gate_pass --file "$AUDIT" --result ok --meta "class=$1"
}

assert_noop() {
  assert_success
  assert_output ''
  [ ! -e "$AUDIT" ]
}

# --- evidence classes on the live path ----------------------------------------

@test "prose-only manifest on a web stream blocks no_captures, scoped without a dispatched row" {
  one_dv web
  mkdir -p "$IMG"
  printf '# Screenshots\n\nHeadless CI, nothing captured.\n' > "$IMG/screenshots-DV0.md"
  gate_file "$BASH_PAYLOAD"
  assert_block no_captures
  assert_audit_row screenshot_gate_block --file "$AUDIT" \
    --meta task_id=DV0 --meta class=no_captures --meta platform=web \
    --meta dedupe_key=sess_fix:agt_bash:screenshot-gate
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("dv-screenshot-capture")'
}

@test "a prose-only manifest beside a dv-DV0 capture blocks invalid_evidence" {
  one_dv web
  mkdir -p "$IMG"
  printf '# Screenshots\n\nnone\n' > "$IMG/screenshots-DV0.md"
  png dv-DV0-01-x.png
  gate_file "$BASH_PAYLOAD"
  assert_block invalid_evidence
  echo "$output" | jq -e '.reason | test("images_unreferenced")'
}

@test "a valid capture row passes as captured" {
  one_dv web
  png dv-DV0-01-home.png
  manifest DV0 "$(img_row DV0 01 home)"
  gate_file "$BASH_PAYLOAD"
  assert_pass captured
  assert_audit_row screenshot_gate_pass --file "$AUDIT" --meta task_id=DV0 --meta platform=web
}

@test "a text file renamed .png blocks with a mime reason" {
  one_dv web
  mkdir -p "$IMG"
  printf 'plain text\n' > "$IMG/dv-DV0-01-home.png"
  manifest DV0 "$(img_row DV0 01 home)"
  gate_file "$BASH_PAYLOAD"
  assert_block invalid_evidence
  echo "$output" | jq -e '.reason | test("mime:dv-DV0-01-home.png")'
}

@test "JPEG bytes behind a .png name block with a mime reason" {
  one_dv web
  mkdir -p "$IMG"
  printf '\377\330\377\340JFIF' > "$IMG/dv-DV0-01-home.png"
  manifest DV0 "$(img_row DV0 01 home)"
  gate_file "$BASH_PAYLOAD"
  assert_block invalid_evidence
  echo "$output" | jq -e '.reason | test("mime:")'
}

@test "a symlinked or empty image row is invalid" {
  one_dv web
  mkdir -p "$IMG"
  printf '\211PNG\r\n\032\nx' > "$WD/outside.png"
  ln -s "$WD/outside.png" "$IMG/dv-DV0-01-link.png"
  manifest DV0 "$(img_row DV0 01 link)"
  check DV0
  assert_failure 1
  assert_output --partial 'symlink:dv-DV0-01-link.png'
  rm "$IMG/dv-DV0-01-link.png"
  : > "$IMG/dv-DV0-01-link.png"
  check DV0
  assert_failure 1
  assert_output --partial 'empty:dv-DV0-01-link.png'
}

# --- per-stream isolation ------------------------------------------------------

@test "two streams: DV1 blocks on DV0's captures while DV0 passes" {
  ledger "{\"DV0\": $(task corpflow:developer web), \"DV1\": $(task corpflow:developer web)}" \
    '[{"task_id":"DV0","stage":"DV","agent_id":"agt_dv0"},{"task_id":"DV1","stage":"DV","agent_id":"agt_dv1"}]'
  png dv-DV0-01-home.png
  manifest DV0 "$(img_row DV0 01 home)"
  gate '{"agent_type":"corpflow:developer","agent_id":"agt_dv1","session_id":"s"}'
  assert_block no_captures
  assert_audit_row screenshot_gate_block --file "$AUDIT" --meta task_id=DV1
  gate '{"agent_type":"corpflow:developer","agent_id":"agt_dv0","session_id":"s"}'
  assert_pass captured
}

@test "a DV1 row citing DV0's capture is invalid" {
  ledger "{\"DV0\": $(task corpflow:developer web), \"DV1\": $(task corpflow:developer web)}"
  png dv-DV0-01-home.png
  manifest DV1 "$(img_row DV0 01 home)"
  check DV1
  assert_failure 1
  assert_output --partial 'class=invalid task=DV1'
  assert_output --partial 'name:dv-DV0-01-home.png'
}

# --- tool_missing and the preflight record --------------------------------------

@test "backend tool_missing passes with a complete operator-accepted preflight record" {
  ledger "{\"DV0\": $(task "$BASH_DEV" backend)}" "" "$(preflight_meta "$FULL_TOOLS" "$FULL_TOOLS" operator)" backend
  manifest DV0 "$TOOLS_ROW"
  gate_file "$BASH_PAYLOAD"
  assert_pass tool_missing_only
}

@test "tool_missing blocks when the record is absent, partial, not operator-accepted, or off backend" {
  local short='["silicon","magick"]' variant
  for variant in absent short auto no-recorded-at web; do
    rm -rf "$WD/.context/logs"
    case "$variant" in
      absent) ledger "{\"DV0\": $(task "$BASH_DEV" backend)}" "" "" backend ;;
      short) ledger "{\"DV0\": $(task "$BASH_DEV" backend)}" "" "$(preflight_meta "$FULL_TOOLS" "$short" operator)" backend ;;
      auto) ledger "{\"DV0\": $(task "$BASH_DEV" backend)}" "" "$(preflight_meta "$FULL_TOOLS" "$FULL_TOOLS" auto)" backend ;;
      no-recorded-at) ledger "{\"DV0\": $(task "$BASH_DEV" backend)}" "" "$(preflight_meta "$FULL_TOOLS" "$FULL_TOOLS" operator "")" backend ;;
      web) ledger "{\"DV0\": $(task "$BASH_DEV" web)}" "" "$(preflight_meta "$FULL_TOOLS" "$FULL_TOOLS" operator)" web ;;
    esac
    manifest DV0 "$TOOLS_ROW"
    gate_file "$BASH_PAYLOAD"
    assert_success
    echo "$output" | jq -e '.decision == "block" and (.reason | startswith("tool_missing_unaccepted"))' > /dev/null \
      || fail "variant $variant did not block: $output"
  done
}

@test "platform table: only backend and systems pass no_captures or accepted tool_missing" {
  local p shape
  for p in web android apple ai unknown backend systems; do
    for shape in none tools; do
      rm -rf "$WD/.context/logs" "$IMG"
      ledger "{\"DV0\": $(task "$BASH_DEV" "$p")}" "" "$(preflight_meta "$FULL_TOOLS" "$FULL_TOOLS" operator)" "$p"
      [ "$shape" = none ] || manifest DV0 "$TOOLS_ROW"
      gate_file "$BASH_PAYLOAD"
      assert_success
      case "$p" in
        backend | systems) [ -z "$output" ] || fail "$p/$shape should pass: $output" ;;
        *) echo "$output" | jq -e '.decision == "block"' > /dev/null || fail "$p/$shape should block" ;;
      esac
    done
  done
}

@test "a task with no platform anywhere is unknown and blocks no_captures" {
  jq -n --arg a "$BASH_DEV" '{version: 2, worktask_id: "wt", tasks: {DV0: {status: "in_progress", metadata: {agent: $a}}}}' \
    > "$WD/.context/state.json"
  gate_file "$BASH_PAYLOAD"
  assert_block no_captures
  assert_audit_row screenshot_gate_block --file "$AUDIT" --meta platform=unknown
}

# --- the --check classifier ------------------------------------------------------

@test "--check exits 0 captured, 1 invalid, 3 no_captures, 4 tool_missing_only" {
  one_dv web
  check DV0
  assert_failure 3
  assert_output --partial 'class=no_captures task=DV0 manifest=- reason='
  manifest DV0 "$TOOLS_ROW"
  check DV0
  assert_failure 4
  assert_output --partial 'class=tool_missing_only'
  png dv-DV0-01-home.png
  manifest DV0 "$(img_row DV0 01 home)"
  check DV0
  assert_success
  assert_output --partial "class=captured task=DV0 manifest=$IMG/screenshots-DV0.md"
  printf 'text' > "$IMG/dv-DV0-01-home.png"
  check DV0
  assert_failure 1
  assert_output --partial 'class=invalid'
}

@test "--check exits 2 for a bad task id, an unresolved ledger or root, or no jq" {
  one_dv web
  run bash "$PLUGIN_ROOT/$SCRIPT" --check dv0 --state "$WD/.context/state.json"
  assert_failure 2
  assert_output --partial 'class=usage'
  run bash "$PLUGIN_ROOT/$SCRIPT" --check DV0 --state "$WD/nope.json"
  assert_failure 2
  printf '{"tasks":{}}' > "$WD/nowid.json"
  run bash "$PLUGIN_ROOT/$SCRIPT" --check DV0 --state "$WD/nowid.json"
  assert_failure 2
  run_script_env --hide jq "$SCRIPT" --check DV0 --state "$WD/.context/state.json"
  assert_failure 2
  assert_output --partial 'jq not found'
  local cwd
  cwd="$(mk_tmpworkdir)"
  run_script_env --cwd "$cwd" --unset WORKSPACE_ROOT --unset CLAUDE_PROJECT_DIR \
    --env "GIT_CEILING_DIRECTORIES=$cwd" "$SCRIPT" --check DV0
  assert_failure 2
  [ ! -e "$cwd/.context" ]
}

@test "--check writes no audit row and creates no directory" {
  one_dv web
  check DV0
  assert_failure 3
  [ ! -e "$WD/.context/logs" ]
  [ ! -e "$WD/.context/images" ]
}

@test "the legacy ## DV0 section counts for DV0 only; a sectionless legacy file is absent" {
  ledger "{\"DV0\": $(task "$BASH_DEV" web), \"DV1\": $(task "$BASH_DEV" web)}"
  png dv-DV0-01-home.png
  printf '# Screenshots — wt\n\n## DV0\n\n%s\n%s\n' "$HDR" "$(img_row DV0 01 home)" > "$IMG/screenshots.md"
  check DV0
  assert_success
  check DV1
  assert_failure 3
  rm "$IMG/dv-DV0-01-home.png"
  printf '# Screenshots — wt\n\n%s\n%s\n' "$HDR" "$(img_row DV0 01 home)" > "$IMG/screenshots.md"
  check DV0
  assert_failure 3
}

@test "the per-task manifest wins over the legacy file" {
  one_dv web
  png dv-DV0-01-home.png
  printf '# legacy\n\n## DV0\n\n%s\n| 01 | broken |\n' "$HDR" > "$IMG/screenshots.md"
  manifest DV0 "$(img_row DV0 01 home)"
  check DV0
  assert_success
  assert_output --partial "manifest=$IMG/screenshots-DV0.md"
}

# --- scope resolution ------------------------------------------------------------

@test "an agent_type no DV task names is a no-op" {
  one_dv web
  gate '{"agent_type":"system-developer:python-developer","agent_id":"agt_py","session_id":"s"}'
  assert_noop
  gate_file "$NONDEV_PAYLOAD"
  assert_noop
}

@test "a dispatched row for a non-DV task is a no-op" {
  ledger "{\"DV0\": $(task "$BASH_DEV" web), \"QA0\": {\"status\": \"in_progress\"}}" \
    '[{"task_id":"QA0","stage":"QA","agent_id":"agt_bash"}]'
  gate_file "$BASH_PAYLOAD"
  assert_noop
}

@test "no in_progress DV task is a no-op" {
  ledger "{\"DV0\": $(task "$BASH_DEV" web completed)}"
  gate_file "$BASH_PAYLOAD"
  assert_noop
}

@test "two in_progress DV tasks for one agent and no dispatched row block task_unresolved" {
  ledger "{\"DV0\": $(task "$BASH_DEV" web), \"DV1\": $(task "$BASH_DEV" web)}"
  gate_file "$BASH_PAYLOAD"
  assert_block task_unresolved
}

@test "an unresolved task passes when the ledger flag is false" {
  ledger "{\"DV0\": $(task "$BASH_DEV" web), \"DV1\": $(task "$BASH_DEV" web)}" "" '{"requires_screenshots":false}'
  gate_file "$BASH_PAYLOAD"
  assert_pass unresolved
}

@test "an agent whose DV task finished blocks task_unresolved while another DV task runs" {
  ledger "{\"DV0\": $(task "$BASH_DEV" web completed), \"DV1\": $(task corpflow:prompt-engineer web)}"
  gate_file "$BASH_PAYLOAD"
  assert_block task_unresolved
}

@test "one agent_id recorded against two tasks blocks task_unresolved" {
  ledger "{\"DV0\": $(task "$BASH_DEV" web), \"DV1\": $(task "$BASH_DEV" web)}" \
    '[{"task_id":"DV0","stage":"DV","agent_id":"agt_bash"},{"task_id":"DV1","stage":"DV","agent_id":"agt_bash"}]'
  gate_file "$BASH_PAYLOAD"
  assert_block task_unresolved
}

@test "corpflow:developer resolves to the sole in_progress DV task whatever its metadata.agent" {
  one_dv web corpflow:prompt-engineer
  gate_file "$DEV_PAYLOAD"
  assert_block no_captures
  assert_audit_row screenshot_gate_block --file "$AUDIT" --meta task_id=DV0
}

@test "the task flag beats the ledger flag in both directions" {
  ledger "{\"DV0\": {\"status\":\"in_progress\",\"metadata\":{\"agent\":\"$BASH_DEV\",\"platform\":\"web\",\"requires_screenshots\":false}}}" \
    "" '{"requires_screenshots":true}'
  gate_file "$BASH_PAYLOAD"
  assert_pass unclassified
  rm -rf "$WD/.context/logs"
  ledger "{\"DV0\": {\"status\":\"in_progress\",\"metadata\":{\"agent\":\"$BASH_DEV\",\"platform\":\"web\",\"requires_screenshots\":true}}}" \
    "" '{"requires_screenshots":false}'
  gate_file "$BASH_PAYLOAD"
  assert_block no_captures
}

# --- fail-closed edges --------------------------------------------------------------

@test "an unreadable ledger blocks corpflow:developer and no-ops other agents" {
  printf '{not json' > "$WD/.context/state.json"
  gate_file "$BASH_PAYLOAD"
  assert_noop
  gate_file "$DEV_PAYLOAD"
  assert_block gate_unresolved
}

@test "a missing manifest validator blocks gate_unresolved instead of passing" {
  mkdir -p "$WD/plug/hooks"
  cp "$PLUGIN_ROOT/$SCRIPT" "$WD/plug/hooks/"
  one_dv web
  png dv-DV0-01-home.png
  manifest DV0 "$(img_row DV0 01 home)"
  run_script_env --env "WORKSPACE_ROOT=$WD" --stdin-file "$BASH_PAYLOAD" "$WD/plug/hooks/dv-screenshot-gate.sh"
  assert_block gate_unresolved
}

@test "contract: --self-test passes (smoke, NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "self-test OK"
}

@test "SR: a symlinked audit.jsonl is refused on the block path" {
  one_dv web
  mkdir -p "$WD/.context/logs" "$WD/target-dir"
  ln -s "$WD/target-dir/escaped.txt" "$WD/.context/logs/audit.jsonl"
  gate_file "$BASH_PAYLOAD"
  assert_success
  echo "$output" | jq -e '.decision == "block"'
  [ ! -e "$WD/target-dir/escaped.txt" ]
}

@test "SR: a symlinked audit.jsonl is refused on the pass path" {
  one_dv web
  png dv-DV0-01-home.png
  manifest DV0 "$(img_row DV0 01 home)"
  mkdir -p "$WD/.context/logs" "$WD/target-dir"
  ln -s "$WD/target-dir/escaped.txt" "$WD/.context/logs/audit.jsonl"
  gate_file "$BASH_PAYLOAD"
  assert_success
  assert_output ''
  [ ! -e "$WD/target-dir/escaped.txt" ]
}

# A non-zero exit after the JSON is a non-blocking hook error, so the stop would slip through.
@test "an unwritable logs/ still exits 0 with the block JSON on stdout" {
  one_dv web
  printf 'not a directory' > "$WD/.context/logs"
  run_script_env --separate-stderr --env "WORKSPACE_ROOT=$WD" --stdin-file "$BASH_PAYLOAD" "$SCRIPT"
  assert_success
  echo "$output" | jq -e '.decision == "block" and (.reason | startswith("no_captures"))'
}

@test "unresolved root exits 0, no block, no .context under cwd" {
  local cwd
  cwd="$(mk_tmpworkdir)"
  run_script_env --cwd "$cwd" --unset WORKSPACE_ROOT --unset CLAUDE_PROJECT_DIR --unset CONTEXT_DIR \
    --env "GIT_CEILING_DIRECTORIES=$cwd" --stdin-file "$DEV_PAYLOAD" "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  [ -z "$output" ]
  [ ! -e "$cwd/.context" ]
}

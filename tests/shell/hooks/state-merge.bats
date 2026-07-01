#!/usr/bin/env bats
# tests/shell/hooks/state-merge.bats — DV0c
# Target: .claude/hooks/state-merge.sh
# Covers: F1 absent-state.json no-op, happy merge DV→completed, corrupt-state no-op (KNOWN BUG),
#         absent-artifact no-op.
#
# Note: state-merge.sh resolves .context/state.json relative to CWD.
# Tests run via `bash -c "cd WD && ..."` to set the working directory correctly.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT=".claude/hooks/state-merge.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context/logs"
}

# -- helpers --

_seed_state() {
  cat > "$WD/.context/state.json" <<'EOF'
{"run_index":0,"worktask_id":"wt-fix","stages":{"PL":{"status":"completed","verdict":"ok"},"DV":{"status":"in_progress"}}}
EOF
}

_seed_artifact() {
  cat > "$WD/.context/development-0.md" <<'EOF'
---
handoff:
  stage: DV
  verdict: ok
  summary: "widget done"
---

# Development

Done.
EOF
}

# ---------------------------------------------------------------------------

@test "F1: absent state.json -> exit 0, no state.json created" {
  _seed_artifact
  # Deliberately no .context/state.json
  run bash -c "cd '$WD' && CLAUDE_ARTIFACT_PATH=.context/development-0.md CLAUDE_TASK_METADATA_STAGE=DV bash '$PLUGIN_ROOT/$SCRIPT'"
  assert_success
  [ ! -f "$WD/.context/state.json" ]
}

@test "happy: merges DV->completed/verdict=ok from artifact frontmatter" {
  _seed_state
  _seed_artifact
  run bash -c "cd '$WD' && CLAUDE_ARTIFACT_PATH=.context/development-0.md CLAUDE_TASK_METADATA_STAGE=DV bash '$PLUGIN_ROOT/$SCRIPT'"
  assert_success
  local dv_status
  dv_status=$(jq -r '.stages.DV.status' "$WD/.context/state.json")
  local dv_verdict
  dv_verdict=$(jq -r '.stages.DV.verdict' "$WD/.context/state.json")
  [ "$dv_status" = "completed" ]
  [ "$dv_verdict" = "ok" ]
}

@test "corrupt state.json -> exit 0, state unchanged (KNOWN BUG: no ledger repair performed)" {
  # KNOWN BUG: when state.json is corrupt JSON, state-patch.sh logs an error and
  # exits non-zero; the hook swallows the error and exits 0, leaving state.json
  # unchanged. The mandate says 'ledger repair from artifact frontmatter when
  # state.json absent/corrupt' but the current implementation does NOT rebuild
  # state.json — it only logs the jq failure and continues. Assert actual behavior.
  printf 'NOT JSON {{{' > "$WD/.context/state.json"
  _seed_artifact
  run bash -c "cd '$WD' && CLAUDE_ARTIFACT_PATH=.context/development-0.md CLAUDE_TASK_METADATA_STAGE=DV bash '$PLUGIN_ROOT/$SCRIPT'"
  assert_success
  # File is unchanged — still contains the corrupt content
  local content
  content=$(cat "$WD/.context/state.json")
  [ "$content" = "NOT JSON {{{" ]
}

@test "absent artifact -> no-op exit 0, DV stage remains in_progress" {
  _seed_state
  # No artifact on disk; CLAUDE_ARTIFACT_PATH not set → state-patch gets no --artifact
  run bash -c "cd '$WD' && CLAUDE_TASK_METADATA_STAGE=DV bash '$PLUGIN_ROOT/$SCRIPT'"
  assert_success
  local dv_status
  dv_status=$(jq -r '.stages.DV.status' "$WD/.context/state.json")
  [ "$dv_status" = "in_progress" ]
}

#!/usr/bin/env bats
# tests/shell/hooks/state-merge.bats — DV0c
# Target: .claude/hooks/state-merge.sh
# Covers: F1 absent-state.json no-op, happy merge DV→completed, corrupt-ledger repair
#         (rebuild + backup + audit row) and its fail-safe non-trigger path,
#         absent-artifact no-op, state-patch.sh resolution from a project-local install.
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

# --- corrupt-ledger repair (R4.4) ------------------------------------------
# The repair rebuilds the SKELETON only and re-enters the normal state-patch.sh
# delegation. Its one non-negotiable invariant is that the corrupt original is
# always recoverable, so each test below asserts the backup as well as the outcome.

_backup_paths() {
  # Prints one path per line; empty when no repair happened.
  find "$WD/.context" -maxdepth 1 -name 'state.json.corrupt.*' | sort
}

@test "corrupt state.json + parseable artifact -> backed up, ledger rebuilt, merge lands, state_repair row" {
  printf 'NOT JSON {{{' > "$WD/.context/state.json"
  _seed_artifact
  run bash -c "cd '$WD' && CLAUDE_ARTIFACT_PATH=.context/development-0.md CLAUDE_TASK_METADATA_STAGE=DV bash '$PLUGIN_ROOT/$SCRIPT'"
  assert_success

  # 1. The corrupt original survives, byte-for-byte, before anything else is judged.
  local backups
  backups=$(_backup_paths)
  [ "$(printf '%s\n' "$backups" | wc -l | tr -d ' ')" = "1" ]
  [ "$(cat "$backups")" = "NOT JSON {{{" ]

  # 2. The ledger parses and carries the skeleton's identity fields.
  jq -e . "$WD/.context/state.json" > /dev/null
  local run_index plan_file
  run_index=$(jq -r '.run_index' "$WD/.context/state.json")
  plan_file=$(jq -r '.plan_file' "$WD/.context/state.json")
  [ "$run_index" = "0" ]
  [ "$plan_file" = ".context/planning-0.md" ]

  # 3. The real field merge still happens in state-patch.sh — the skeleton alone
  #    would leave .stages empty, so this is what proves the fall-through.
  #    (AR0 S6 T1 says `.verdict == "ok"`; no top-level verdict key exists in the
  #    schema — state-patch.sh writes it under the stage object. Corrected here.)
  local dv_status dv_verdict
  dv_status=$(jq -r '.stages.DV.status' "$WD/.context/state.json")
  dv_verdict=$(jq -r '.stages.DV.verdict' "$WD/.context/state.json")
  [ "$dv_status" = "completed" ]
  [ "$dv_verdict" = "ok" ]

  assert_audit_row state_repair --actor hook:state-merge --result repaired \
    --meta reason=corrupt_state_json --meta run_index=0 --meta stage=DV \
    --meta "artifact=.context/development-0.md" \
    --meta "backup=.context/$(basename "$backups")" --count 1
}

@test "corrupt state.json + no artifact -> fail-safe: file byte-identical, no backup, no audit row" {
  printf 'NOT JSON {{{' > "$WD/.context/state.json"
  # Pre-image taken from disk rather than re-derived from the literal, so a
  # write that merely round-trips the same bytes still has to match exactly.
  cp "$WD/.context/state.json" "$WD/preimage"
  # Deliberately no artifact and no CLAUDE_ARTIFACT_PATH — the non-trigger path.
  run bash -c "cd '$WD' && CLAUDE_TASK_METADATA_STAGE=DV bash '$PLUGIN_ROOT/$SCRIPT'"
  assert_success

  cmp "$WD/preimage" "$WD/.context/state.json"
  [ -z "$(_backup_paths)" ]
  assert_audit_row state_repair --absent
}

@test "repair backup: named state.json.corrupt.<ts> and an earlier backup is never overwritten" {
  _seed_artifact
  local payload
  for payload in 'CORRUPT-ALPHA {{{' 'CORRUPT-BETA }}}'; do
    printf '%s' "$payload" > "$WD/.context/state.json"
    run bash -c "cd '$WD' && CLAUDE_ARTIFACT_PATH=.context/development-0.md CLAUDE_TASK_METADATA_STAGE=DV bash '$PLUGIN_ROOT/$SCRIPT'"
    assert_success
  done

  # Two repairs, two backups. Whether they land in the same second (collision
  # suffix) or not, neither payload may be lost — that is the invariant.
  local backups count f name found_alpha=0 found_beta=0
  backups=$(_backup_paths)
  count=$(printf '%s\n' "$backups" | wc -l | tr -d ' ')
  [ "$count" = "2" ]

  while read -r f; do
    name=$(basename "$f")
    [[ "$name" =~ ^state\.json\.corrupt\.[0-9]{8}T[0-9]{6}Z(-[0-9]+)?$ ]] \
      || fail "backup name off contract: $name"
    case "$(cat "$f")" in
      'CORRUPT-ALPHA {{{') found_alpha=$((found_alpha + 1)) ;;
      'CORRUPT-BETA }}}') found_beta=$((found_beta + 1)) ;;
      *) fail "backup $name holds neither payload: $(cat "$f")" ;;
    esac
  done <<< "$backups"
  [ "$found_alpha" = "1" ]
  [ "$found_beta" = "1" ]

  assert_audit_row state_repair --result repaired --count 2
}

@test "repair backup: a dangling symlink at the backup path is never written through" {
  _seed_artifact
  printf 'NOT JSON {{{' > "$WD/.context/state.json"

  # `[[ -e ]]` is FALSE for a dangling symlink, so a candidate name occupied by one
  # reads as free; `cp` then follows it to the link's target and `cmp -s` verifies
  # through the same link, so the write lands on an attacker-chosen path silently.
  # The link is planted across a small second-window because the script picks the
  # timestamp itself — one of these is guaranteed to be the name it computes.
  local victim="$WD/pwned" i now ts
  now=$(date -u +%s)
  for i in 0 1 2 3 4; do
    ts=$(date -u -r "$((now + i))" +%Y%m%dT%H%M%SZ 2> /dev/null) \
      || ts=$(date -u -d "@$((now + i))" +%Y%m%dT%H%M%SZ)
    ln -s "$victim" "$WD/.context/state.json.corrupt.$ts"
  done

  run bash -c "cd '$WD' && CLAUDE_ARTIFACT_PATH=.context/development-0.md CLAUDE_TASK_METADATA_STAGE=DV bash '$PLUGIN_ROOT/$SCRIPT'"
  assert_success

  # 1. The invariant under test: nothing was written through the link.
  [ ! -e "$victim" ] || fail "backup was written through the dangling symlink to $victim"

  # 2. The repair still completed onto a real, non-symlink path holding the original
  #    bytes — so the fix skips the planted name rather than aborting the repair.
  local real_backups
  real_backups=$(find "$WD/.context" -maxdepth 1 -type f -name 'state.json.corrupt.*' | sort)
  [ "$(printf '%s\n' "$real_backups" | wc -l | tr -d ' ')" = "1" ]
  [ "$(cat "$real_backups")" = "NOT JSON {{{" ]

  local dv_status
  dv_status=$(jq -r '.stages.DV.status' "$WD/.context/state.json")
  [ "$dv_status" = "completed" ]
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

# ---------------------------------------------------------------------------
# v1 additive upgrade — --via pass-through with STATE_MERGE_VIA override (#199).
# ---------------------------------------------------------------------------

@test "via: delegation defaults completed_via=hook (Layer 2 provenance)" {
  _seed_state
  _seed_artifact
  run bash -c "cd '$WD' && CLAUDE_ARTIFACT_PATH=.context/development-0.md CLAUDE_TASK_METADATA_STAGE=DV bash '$PLUGIN_ROOT/$SCRIPT'"
  assert_success
  local via
  via=$(jq -r '.stages.DV.completed_via' "$WD/.context/state.json")
  [ "$via" = "hook" ]
}

@test "via: STATE_MERGE_VIA=step6_5 overrides completed_via" {
  _seed_state
  _seed_artifact
  run bash -c "cd '$WD' && STATE_MERGE_VIA=step6_5 CLAUDE_ARTIFACT_PATH=.context/development-0.md CLAUDE_TASK_METADATA_STAGE=DV bash '$PLUGIN_ROOT/$SCRIPT'"
  assert_success
  local via
  via=$(jq -r '.stages.DV.completed_via' "$WD/.context/state.json")
  [ "$via" = "step6_5" ]
}

# --- state-patch.sh resolution (Layer-2 safety net) -------------------------
# worktask.md Step 3b copies this hook into <project>/.claude/hooks/, where the
# relative arm resolves to a skills/ tree that does not exist. These pin the
# resolution so the net can never silently become a no-op again.

_install_project_local() {
  mkdir -p "$WD/.claude/hooks"
  cp "$PLUGIN_ROOT/$SCRIPT" "$WD/.claude/hooks/state-merge.sh"
  chmod +x "$WD/.claude/hooks/state-merge.sh"
}

@test "project-local copy: CLAUDE_PLUGIN_ROOT resolves state-patch.sh and the merge still lands" {
  _seed_state
  _seed_artifact
  _install_project_local
  run bash -c "cd '$WD' && CLAUDE_PLUGIN_ROOT='$PLUGIN_ROOT' CLAUDE_ARTIFACT_PATH=.context/development-0.md CLAUDE_TASK_METADATA_STAGE=DV bash '$WD/.claude/hooks/state-merge.sh'"
  assert_success
  local dv_status
  dv_status=$(jq -r '.stages.DV.status' "$WD/.context/state.json")
  [ "$dv_status" = "completed" ]
}

@test "absent state-patch.sh: exit 0 (never blocks) and the stage is left untouched" {
  _seed_state
  _seed_artifact
  _install_project_local
  # Plugin root with no skills/ tree, and no skills/ beside the project-local copy.
  run bash -c "cd '$WD' && CLAUDE_PLUGIN_ROOT='$WD/nowhere' CLAUDE_ARTIFACT_PATH=.context/development-0.md CLAUDE_TASK_METADATA_STAGE=DV bash '$WD/.claude/hooks/state-merge.sh'"
  assert_success
  local dv_status
  dv_status=$(jq -r '.stages.DV.status' "$WD/.context/state.json")
  [ "$dv_status" = "in_progress" ]
}

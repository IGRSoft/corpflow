#!/usr/bin/env bats
# Contract tests for skills/worktask/scripts/cache-lint.sh.
# Contracts (from header):
#   - --anchor-lint <file>: stage anchors all present => "ok", exit 0
#   - --anchor-lint <file>: anchors missing => "FAIL, missing:", exit 1
#   - --filename-lint <dir>: canonical artifact names => "all canonical", exit 0
#   - prefix-lint <log.jsonl>: consistent sections => "no drift", exit 0;
#     drifted sections => "DRIFT" on stderr, exit 1
#   - --self-test => "ALL PASS", exit 0
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/cache-lint.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  # A well-formed DV artifact (has all required DV anchors) using the shared fixture.
  cp "$FIXTURES/worktask/development-0.sample.md" "$WD/development-0.md"
  # A bad artifact (DV frontmatter but missing required anchors).
  cat > "$WD/incomplete-dev.md" <<'EOF'
---
handoff:
  stage: DV
  verdict: ok
  summary: "incomplete — missing required H2s"
  refs: { dev: development.md#files-changed }
---
# Development

No required H2 sections.
EOF
  # A valid prefix-lint jsonl: two stages of the same worktask with stable
  # sections [1] contract-reminder, [2] worktask-header, and per-stage [4].
  local common_header="preamble unchanged"
  cat > "$WD/stable.jsonl" <<'EOF'
{"worktask_id":"wt1","stage":"DV","prompt":"<<<contract-reminder>>>\nstable reminder\n<<<contract-reminder>>>\n<<<worktask-header>>>\nstable header\n<<<worktask-header>>>\n<<<stage-contract>>>\nDV contract\n<<<stage-contract>>>"}
{"worktask_id":"wt1","stage":"DR","prompt":"<<<contract-reminder>>>\nstable reminder\n<<<contract-reminder>>>\n<<<worktask-header>>>\nstable header\n<<<worktask-header>>>\n<<<stage-contract>>>\nDR contract\n<<<stage-contract>>>"}
EOF
  # A drifted jsonl: second line has different [1] contract-reminder.
  cat > "$WD/drift.jsonl" <<'EOF'
{"worktask_id":"wt2","stage":"DV","prompt":"<<<contract-reminder>>>\noriginal reminder\n<<<contract-reminder>>>\n<<<worktask-header>>>\nheader\n<<<worktask-header>>>\n<<<stage-contract>>>\nDV\n<<<stage-contract>>>"}
{"worktask_id":"wt2","stage":"DR","prompt":"<<<contract-reminder>>>\nDRIFTED reminder\n<<<contract-reminder>>>\n<<<worktask-header>>>\nheader\n<<<worktask-header>>>\n<<<stage-contract>>>\nDR\n<<<stage-contract>>>"}
EOF
  # L1 forbidden-token fixtures (REQ-3/AC-4): a previously-uncaught class — an
  # ISO-8601 timestamp baked into section [2] worktask-header. Byte-identical
  # across every stage of THIS worktask (so the drift check alone misses it),
  # but a live/production run would regenerate a NEW timestamp on the NEXT
  # worktask_id, breaking cross-worktask cache-prefix reuse. Only ONE line —
  # forbidden-token-lint is an intrinsic per-section check, not cross-line.
  cat > "$WD/forbidden-timestamp.jsonl" <<'EOF'
{"worktask_id":"wt3","stage":"PL","prompt":"<<<contract-reminder>>>\nstable reminder\n<<<contract-reminder>>>\n<<<worktask-header>>>\nworktask_id=wt3\ngenerated_at=2026-07-05T15:15:39Z\n<<<worktask-header>>>\n<<<stage-contract>>>\nPL contract\n<<<stage-contract>>>"}
EOF
  # Happy-path counterpart: same shape, no forbidden token — must still pass.
  cat > "$WD/forbidden-clean.jsonl" <<'EOF'
{"worktask_id":"wt4","stage":"PL","prompt":"<<<contract-reminder>>>\nstable reminder\n<<<contract-reminder>>>\n<<<worktask-header>>>\nworktask_id=wt4\nplan_file=planning-0.md\n<<<worktask-header>>>\n<<<stage-contract>>>\nPL contract\n<<<stage-contract>>>"}
EOF
}

@test "happy: --anchor-lint on a complete DV artifact passes (exit 0, 'ok')" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --anchor-lint "$WD/development-0.md"
  assert_success
  assert_output --partial "ok"
}

@test "failure: --anchor-lint on a DV artifact missing required H2s fails (exit 1)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --anchor-lint "$WD/incomplete-dev.md"
  assert_failure 1
  assert_output --partial "FAIL"
  assert_output --partial "missing"
}

@test "happy: prefix-lint with stable sections reports no drift (exit 0)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" "$WD/stable.jsonl"
  assert_success
  assert_output --partial "no drift"
}

@test "failure: prefix-lint with drifted contract-reminder reports DRIFT (exit 1)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" "$WD/drift.jsonl"
  assert_failure 1
  assert_output --partial "DRIFT"
}

@test "failure: prefix-lint catches an ISO-8601 timestamp in section [2] (REQ-3/AC-4)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" "$WD/forbidden-timestamp.jsonl"
  assert_failure 1
  assert_output --partial "forbidden-token-lint"
  assert_output --partial "timestamp"
}

@test "happy: prefix-lint with no forbidden tokens still reports no drift (REQ-3/AC-4)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" "$WD/forbidden-clean.jsonl"
  assert_success
  assert_output --partial "no drift"
}

@test "happy: --filename-lint on canonical artifacts passes (exit 0, 'canonical')" {
  # Fixture dir, not the live .context: nothing under .context/ is tracked
  # (git ls-files .context is empty), so its contents are runtime state that any
  # worktask run may add to or clear.
  mkdir -p "$WD/ctx"
  cp "$WD/development-0.md" "$WD/ctx/development-0.md"
  cat > "$WD/ctx/coordination-0.md" <<'EOF'
---
handoff:
  stage: TL
  verdict: ok
  summary: "canonical TL artifact"
  refs: { plan: planning-0.md#requirements }
---
# Coordination
EOF
  run bash "$PLUGIN_ROOT/$SCRIPT" --filename-lint "$WD/ctx"
  assert_success
  assert_output --partial "canonical"
}

@test "contract: --self-test passes (smoke, NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "ALL PASS"
}

# ---------------------------------------------------------------------------
# --filename-lint against artifacts with REAL bodies (3.42.0). The pre-existing
# fixtures have bodies simple enough that yq parses the whole file by accident,
# which hid extract_stage()'s whole-file parse from the suite entirely.
# ---------------------------------------------------------------------------

# A body with a markdown table — the construct that makes a whole-file yq parse abort.
real_artifact() {
  local path="$1" stage="$2"
  cat > "$path" <<EOF
---
handoff:
  stage: $stage
  verdict: ok
  summary: "artifact with a body yq cannot parse as YAML"
  files_touched: [a.md]
  next_stage_focus: "next"
  refs: { dev: development.md#files-changed }
---

# Body

| Column | Meaning |
|--------|---------|
| \`key\` | value: with a colon that breaks a whole-file YAML parse |

## files-changed

- a.md
EOF
}

@test "filename-lint: an artifact with a table body is still detected (not silently skipped)" {
  mkdir -p "$WD/ctx"
  real_artifact "$WD/ctx/development-0.md" DV
  run bash "$PLUGIN_ROOT/$SCRIPT" --filename-lint "$WD/ctx"
  assert_success
  assert_output --partial "1 artifacts checked"
  refute_output --partial "no artifacts with handoff frontmatter found"
}

@test "filename-lint: per-stream development-N-<stream>.md is accepted (AC-8)" {
  mkdir -p "$WD/ctx"
  real_artifact "$WD/ctx/development-0.md" DV
  real_artifact "$WD/ctx/development-0-swift-app.md" DV
  real_artifact "$WD/ctx/development-0-backend.md" DV
  run bash "$PLUGIN_ROOT/$SCRIPT" --filename-lint "$WD/ctx"
  assert_success
  assert_output --partial "3 artifacts checked, all canonical"
}

@test "filename-lint: a non-canonical stream suffix is still rejected (AC-8)" {
  mkdir -p "$WD/ctx"
  real_artifact "$WD/ctx/development-0-Swift_App.md" DV
  run bash "$PLUGIN_ROOT/$SCRIPT" --filename-lint "$WD/ctx"
  assert_failure 1
  assert_output --partial "development-N.md or development-N-<stream>.md"
}

@test "filename-lint: a non-DV stage gets no stream-suffix latitude" {
  mkdir -p "$WD/ctx"
  real_artifact "$WD/ctx/planning-0-extra.md" PL
  run bash "$PLUGIN_ROOT/$SCRIPT" --filename-lint "$WD/ctx"
  assert_failure 1
  assert_output --partial "expected 'planning-N.md'"
}

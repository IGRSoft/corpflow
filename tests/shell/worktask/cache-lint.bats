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

@test "edge: --filename-lint on our .context dir passes (exit 0, 'canonical')" {
  # The live .context dir has development-0.md and coordination-0.md — both canonical.
  run bash "$PLUGIN_ROOT/$SCRIPT" --filename-lint "$PLUGIN_ROOT/.context"
  assert_success
  assert_output --partial "canonical"
}

@test "contract: --self-test passes (smoke, NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "ALL PASS"
}

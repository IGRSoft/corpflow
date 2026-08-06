#!/usr/bin/env bats
# Contract tests for skills/worktask/scripts/state-patch.sh (AC-4 priority).
# Contracts asserted (from the script header + body):
#   - atomic completion merge into .context/state.json (stages.<S>.status=completed)
#   - idempotent re-run leaves state.json byte-identical
#   - disk-guard hard-halt exits 2 below DISK_MIN_GB
#   - absent artifact / absent state.json => no-op exit 0
#   - --self-test => "ALL PASS" exit 0
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/state-patch.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context/logs"
  cp "$FIXTURES/worktask/state.sample.json" "$WD/.context/state.json"
  cp "$FIXTURES/worktask/development-0.sample.md" "$WD/.context/development-0.md"
}

@test "happy: merges completed DV verdict into stages.DV (atomic)" {
  cd "$WD"
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --artifact .context/development-0.md
  assert_success
  run jq -r '.stages.DV.status' .context/state.json
  assert_output "completed"
  run jq -r '.stages.DV.verdict' .context/state.json
  assert_output "ok"
  run jq -r '.stages.DV.artifact' .context/state.json
  assert_output --partial "development-0.md"
}

@test "happy: --stage with no --artifact resolves via run_index=0 from state.json" {
  cd "$WD"
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage DV
  assert_success
  run jq -r '.stages.DV.status' .context/state.json
  assert_output "completed"
  run jq -r '.stages.DV.artifact' .context/state.json
  assert_output --partial "development-0.md"
}

@test "edge: idempotent re-run leaves state.json byte-identical" {
  cd "$WD"
  bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --artifact .context/development-0.md
  cp .context/state.json snap
  bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --artifact .context/development-0.md
  run diff -q .context/state.json snap
  assert_success
}

@test "edge: absent artifact for an un-run stage is a no-op (exit 0, state unchanged)" {
  cd "$WD"
  cp .context/state.json snap
  # No testing-*.md / QA artifact exists in the fixture workdir.
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage QA
  assert_success
  run diff -q .context/state.json snap
  assert_success
}

@test "edge: absent state.json is F1 fallback no-op (exit 0)" {
  cd "$WD"
  rm -f .context/state.json
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --artifact .context/development-0.md
  assert_success
  [ ! -f .context/state.json ]
}

@test "failure: disk-guard hard-halt exits 2 below DISK_MIN_GB" {
  cd "$WD"
  # --disk-check accepts an OPTIONAL root value. A bare --disk-check (last arg, or
  # followed by another -flag) defaults root=".". The real disk-guard halt fires
  # when DISK_MIN_GB exceeds free space on that root.
  DISK_MIN_GB=99999999 run bash "$PLUGIN_ROOT/$SCRIPT" \
    --stage DV --artifact .context/development-0.md --disk-check
  assert_failure 2
  assert_output --partial "HALT"
}

@test "disk-check: explicit root value is consumed (documented contract)" {
  cd "$WD"
  # An unparseable root (df fails) degrades silently → guard returns 0, patch applies.
  run bash "$PLUGIN_ROOT/$SCRIPT" \
    --stage DV --artifact .context/development-0.md --disk-check /no_such_mount_xyz
  assert_success
  run jq -r '.stages.DV.status' .context/state.json
  assert_output "completed"
}

@test "failure: unknown argument exits 2 via usage" {
  cd "$WD"
  run bash "$PLUGIN_ROOT/$SCRIPT" --bogus-flag
  assert_failure 2
  assert_output --partial "unknown argument"
}

@test "contract: --self-test runs T1-T9 green and reaches ALL PASS (AC-5)" {
  # --disk-check now consumes its optional root value, so T6's unparseable-mount
  # path degrades gracefully instead of aborting. T8 (--prev) and T9 (bounds) are
  # the new self-tests. The suite must reach "ALL PASS" (exit 0).
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "T1: explicit artifact"
  assert_output --partial "T6: disk-guard degrade"
  assert_output --partial "T8: --prev writes handoffs"
  assert_output --partial "T9: facts.decisions clamped"
  assert_output --partial "T9: dispatched_agents clamped"
  assert_output --partial "ALL PASS"
}

# ---------------------------------------------------------------------------
# Phase 2.0 --prev + B3 bounds (issue #221). --prev writes the handoffs edge the
# 13 stage agents used to hand-roll; bounds are enforced in atomic_merge (AD-7).
# ---------------------------------------------------------------------------

@test "prev: --prev writes handoffs[PREV→CODE] from summary + artifact basename" {
  cd "$WD"
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --prev TL --artifact .context/development-0.md
  assert_success
  run jq -r '.handoffs["TL→DV"]' .context/state.json
  assert_output --partial "ref:development-0.md"
  # Stage patch still lands alongside the handoffs edge.
  run jq -r '.stages.DV.status' .context/state.json
  assert_output "completed"
}

@test "prev: absent --prev leaves handoffs untouched (byte-stable default)" {
  cd "$WD"
  cp .context/state.json snap
  bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --artifact .context/development-0.md
  run jq -r '.handoffs | length' .context/state.json
  assert_output "0"
}

@test "prev: invalid --prev value exits 2 via usage" {
  cd "$WD"
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --artifact .context/development-0.md --prev ZZ
  assert_failure 2
  assert_output --partial "invalid --prev value"
}

@test "bounds: facts.decisions clamps to newest-8, dispatched_agents to 6 (launched survive)" {
  cd "$WD"
  jq -n '
    {version:1, worktask_id:"b", plan_file:".context/planning-0.md", platform:"all",
     run_index:0, stages:{PL:{status:"completed", verdict:"ok"}},
     facts:{files_modified:[], tests_added:[], open_questions:[], verdicts:{PL:"ok"},
       decisions:[ range(0;11) | {id:("d"+(.|tostring)), summary:"s", ref:"x.md#y"} ],
       dispatched_agents:(
         [ range(0;6) | {stage:"DV", task_id:("t"+(.|tostring)), subagent_type:"a", status:"completed"} ]
         + [ range(6;9) | {stage:"DV", task_id:("t"+(.|tostring)), subagent_type:"a", status:"launched"} ])},
     handoffs:{}}' > .context/state.json
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --artifact .context/development-0.md
  assert_success
  run jq -r '.facts.decisions | length' .context/state.json
  assert_output "8"
  run jq -r '.facts.decisions[-1].id' .context/state.json
  assert_output "d10"
  run jq -r '.facts.dispatched_agents | length' .context/state.json
  assert_output "6"
  run jq -r '[.facts.dispatched_agents[] | select(.status=="launched")] | length' .context/state.json
  assert_output "3"
}

@test "bounds: small arrays are untouched (no clamp, byte-stable)" {
  cd "$WD"
  # The fixture state has short decisions/dispatched_agents; a patch must not perturb them.
  before_dec="$(jq -c '.facts.decisions // []' .context/state.json)"
  bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --artifact .context/development-0.md
  run jq -c '.facts.decisions // []' .context/state.json
  assert_output "$before_dec"
}

# ---------------------------------------------------------------------------
# v1 additive upgrade — mkdir-spinlock + --via + worktree mapping (issue #199).
# All lock tests are deterministic via STATE_LOCK_TIMEOUT_S / STATE_LOCK_STALE_S
# env knobs — NO sleep-races.
# ---------------------------------------------------------------------------

@test "lock: held-but-fresh lock defers then times out → proceeds UNLOCKED + WARN, patch applied" {
  cd "$WD"
  # Pre-create the lock dir and keep it FRESH (STALE huge) so the stale-break path
  # does NOT fire — this exercises the pure timeout→unlocked-proceed branch.
  mkdir .context/state.json.lock.d
  STATE_LOCK_TIMEOUT_S=1 STATE_LOCK_STALE_S=99999 \
    run bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --artifact .context/development-0.md \
    --log .context/logs/lock.log
  assert_success
  run jq -r '.stages.DV.status' .context/state.json
  assert_output "completed"
  run grep -c 'proceeding UNLOCKED' .context/logs/lock.log
  assert_output "1"
}

@test "lock: stale lock (older than STATE_LOCK_STALE_S) is broken via mtime, patch applied, lock released" {
  cd "$WD"
  mkdir .context/state.json.lock.d
  # STALE=0 → any existing lock is immediately stale and broken.
  STATE_LOCK_TIMEOUT_S=3 STATE_LOCK_STALE_S=0 \
    run bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --artifact .context/development-0.md \
    --log .context/logs/lock.log
  assert_success
  run jq -r '.stages.DV.status' .context/state.json
  assert_output "completed"
  run grep -c 'lock stale' .context/logs/lock.log
  assert_output "1"
  # Lock released after a successful merge.
  [ ! -d .context/state.json.lock.d ]
}

@test "lock: EXIT-trap releases the lock even when the jq merge fails (release-on-fail)" {
  cd "$WD"
  # Corrupt state.json so the jq merge inside atomic_merge() fails (rc=1), then
  # assert the lock the run acquired is still released by _lock_release / EXIT trap.
  printf 'NOT JSON {{{' > .context/state.json
  STATE_LOCK_TIMEOUT_S=2 STATE_LOCK_STALE_S=60 \
    run bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --artifact .context/development-0.md \
    --log .context/logs/lock.log
  # jq merge failure → state-patch exits 1 (script contract), but the lock dir it
  # created must NOT be leaked.
  assert_failure 1
  [ ! -d .context/state.json.lock.d ]
}

@test "via: --via hook stamps stages.DV.completed_via=hook (additive, version unchanged)" {
  cd "$WD"
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --artifact .context/development-0.md --via hook
  assert_success
  run jq -r '.stages.DV.completed_via' .context/state.json
  assert_output "hook"
  run jq -r '.version' .context/state.json
  assert_output "1"
}

@test "via: --via step6_5 stamps completed_via=step6_5; invalid --via value exits 2" {
  cd "$WD"
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --artifact .context/development-0.md --via step6_5
  assert_success
  run jq -r '.stages.DV.completed_via' .context/state.json
  assert_output "step6_5"
  # Invalid enum value is a caller bug → exit 2 via usage.
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --artifact .context/development-0.md --via bogus
  assert_failure 2
  assert_output --partial "invalid --via value"
}

@test "worktree: worktree_path/worktree_branch frontmatter maps to stages.DV.worktree" {
  cd "$WD"
  cat > .context/development-0.md <<'EOART'
---
handoff:
  stage: DV
  verdict: ok
  summary: "worktree mapping fixture"
  worktree: true
  worktree_path: /tmp/wt/agent-abc
  worktree_branch: feature/xyz
---

# Development
EOART
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --artifact .context/development-0.md
  assert_success
  run jq -r '.stages.DV.worktree.path' .context/state.json
  assert_output "/tmp/wt/agent-abc"
  run jq -r '.stages.DV.worktree.branch' .context/state.json
  assert_output "feature/xyz"
  # Additive: absent worktree frontmatter must NOT synthesize the key.
  run jq -e '.stages.PL | has("worktree")' .context/state.json
  assert_output "false"
}

@test "parallel: concurrent DV+QA patches both land (no last-rename-wins drop)" {
  cd "$WD"
  # Two backgrounded state-patch invocations against the SAME state.json, one per
  # stage KEY (legal sibling overlap). The lock serializes read-merge-rename so
  # BOTH stages must read 'completed' — deterministic via a short stale window.
  cat > .context/testing-0.md <<'EOART'
---
handoff:
  stage: QA
  verdict: go
  summary: "parallel QA patch"
---
EOART
  STATE_LOCK_TIMEOUT_S=10 STATE_LOCK_STALE_S=30 \
    bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --artifact .context/development-0.md \
    --log .context/logs/p.log &
  local dv_pid=$!
  STATE_LOCK_TIMEOUT_S=10 STATE_LOCK_STALE_S=30 \
    bash "$PLUGIN_ROOT/$SCRIPT" --stage QA --artifact .context/testing-0.md \
    --log .context/logs/p.log &
  local qa_pid=$!
  wait "$dv_pid"
  wait "$qa_pid"
  run jq -r '.stages.DV.status' .context/state.json
  assert_output "completed"
  run jq -r '.stages.QA.status' .context/state.json
  assert_output "completed"
}

# ---------------------------------------------------------------------------
# Conditional handoff edges for the optional AR/TL stages (3.42.0). PL0 sizes
# the stage set, so DV's predecessor is TL, AR or PL and TL's is AR or PL.
# ---------------------------------------------------------------------------

@test "prev: --stage DV --prev AR records the AR→DV edge (TL excluded)" {
  cd "$WD"
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --prev AR --artifact .context/development-0.md
  assert_success
  run jq -r '.handoffs["AR→DV"]' .context/state.json
  assert_output --partial "ref:development-0.md"
  run jq -r '.handoffs | has("TL→DV")' .context/state.json
  assert_output "false"
}

@test "prev: --stage DV --prev PL records the PL→DV edge (AR and TL excluded)" {
  cd "$WD"
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --prev PL --artifact .context/development-0.md
  assert_success
  run jq -r '.handoffs["PL→DV"]' .context/state.json
  assert_output --partial "ref:development-0.md"
  run jq -r '.handoffs | keys | length' .context/state.json
  assert_output "1"
}

@test "prev: --stage TL --prev PL records the PL→TL edge (AR excluded)" {
  cd "$WD"
  cat > .context/coordination-0.md <<'EOF'
---
handoff:
  stage: TL
  verdict: ok
  summary: "Single workstream, no fan-out"
  next_stage_focus: "DV implements in one batch"
  refs: { plan: planning-0.md#requirements }
---

# Coordination

## fan-out

Single stream.
EOF
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage TL --prev PL --artifact .context/coordination-0.md
  assert_success
  run jq -r '.handoffs["PL→TL"]' .context/state.json
  assert_output --partial "ref:coordination-0.md"
  run jq -r '.stages.TL.status' .context/state.json
  assert_output "completed"
}

@test "prev: --stage DV --prev IR records the IR→DV edge (emergency pipeline, no PL)" {
  cd "$WD"
  # The emergency pipeline is IR→DV→DR→QA→RE→FN — there is no PL/AR/TL stage at all,
  # so PL→DV here would be exactly the phantom edge R8 exists to eliminate.
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --prev IR --artifact .context/development-0.md
  assert_success
  run jq -r '.handoffs["IR→DV"]' .context/state.json
  assert_output --partial "ref:development-0.md"
  run jq -r '.handoffs | has("PL→DV")' .context/state.json
  assert_output "false"
}

@test "remediation: same verdict with a new summary refreshes the handoffs edge" {
  cd "$WD"
  bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --prev AR --artifact .context/development-0.md
  run jq -r '.handoffs["AR→DV"]' .context/state.json
  assert_output --partial "DV0a fixture development artifact"

  # A DV→DR→DV loop re-completes DV at the same verdict; the edge must follow the new summary.
  sed -i.bak 's/DV0a fixture development artifact/remediated after DR round 1/' \
    .context/development-0.md
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --prev AR --artifact .context/development-0.md
  assert_success
  run jq -r '.handoffs["AR→DV"]' .context/state.json
  assert_output --partial "remediated after DR round 1"
  refute_output --partial "DV0a fixture development artifact"
}

@test "remediation: an unchanged re-run is still byte-identical (idempotence preserved)" {
  cd "$WD"
  bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --prev AR --artifact .context/development-0.md
  cp .context/state.json snap
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --prev AR --artifact .context/development-0.md
  assert_success
  run diff -q .context/state.json snap
  assert_success
}

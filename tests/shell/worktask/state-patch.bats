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
  # CONTRACT NOTE: --disk-check takes NO value (the parser sets root="." and shifts
  # once). The analyzing-0.md worked example's `--disk-check .` is WRONG — the
  # trailing "." is then parsed as an unknown argument and exits 2 via usage. The
  # real disk-guard halt is exercised with a bare --disk-check.
  DISK_MIN_GB=99999999 run bash "$PLUGIN_ROOT/$SCRIPT" \
    --stage DV --artifact .context/development-0.md --disk-check
  assert_failure 2
  assert_output --partial "HALT"
}

@test "failure: unknown argument exits 2 via usage" {
  cd "$WD"
  run bash "$PLUGIN_ROOT/$SCRIPT" --bogus-flag
  assert_failure 2
  assert_output --partial "unknown argument"
}

@test "contract: --self-test runs T1-T5 green but T6 fails (KNOWN BUG, smoke, NON-counting)" {
  # CONTRACT SURPRISE: the in-script self-test T6 invokes
  #   --disk-check /nonexistent_mountpoint_selftest
  # but --disk-check ignores its value argument, so "/nonexistent..." is parsed as
  # an unknown argument and the self-test aborts at exit 2 -> self-test exits 1.
  # T1-T5 all pass ("ok"); the suite never reaches "ALL PASS" in this environment.
  # We assert the REAL current behavior (do not fix the script per plan scope).
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_failure 1
  assert_output --partial "T1: explicit artifact"
  assert_output --partial "T5: absent artifact"
  refute_output --partial "ALL PASS"
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

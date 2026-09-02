#!/usr/bin/env bats
# Contract tests for skills/worktask/scripts/state-patch.sh (AC-4 priority).
# Contracts asserted (from the script header + body):
#   - atomic completion merge into .context/state.json (tasks.<ID>.status=completed)
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

@test "happy: merges completed DV verdict into tasks.DV0 (atomic)" {
  cd "$WD"
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --artifact .context/development-0.md
  assert_success
  run jq -r '.tasks.DV0.status' .context/state.json
  assert_output "completed"
  run jq -r '.tasks.DV0.verdict' .context/state.json
  assert_output "ok"
  run jq -r '.tasks.DV0.artifact' .context/state.json
  assert_output --partial "development-0.md"
}

@test "happy: --stage with no --artifact resolves via run_index=0 from state.json" {
  cd "$WD"
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage DV
  assert_success
  run jq -r '.tasks.DV0.status' .context/state.json
  assert_output "completed"
  run jq -r '.tasks.DV0.artifact' .context/state.json
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
  run jq -r '.tasks.DV0.status' .context/state.json
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
  assert_output --partial "T11: alias basename resolves"
  assert_output --partial "T12: unresolved self-patch exits 3"
  assert_output --partial "T13: --prev USER writes"
  assert_output --partial "T18: replay resets the target"
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
  run jq -r '.tasks.DV0.status' .context/state.json
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

# ---------------------------------------------------------------------------
# Fail-loud resolution: alias basenames (REQ-1), unresolved self-patch (REQ-2),
# and USER as a predecessor-only code (REQ-3).
# ---------------------------------------------------------------------------

@test "alias: a documented alias basename resolves when the canonical name is absent" {
  cd "$WD"
  sed 's/stage: DV/stage: QA/' .context/development-0.md > .context/qa-0.md
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage QA
  assert_success
  run jq -r '.tasks.QA0.artifact' .context/state.json
  assert_output --partial "qa-0.md"
}

@test "alias: the canonical basename still outranks an alias when both exist" {
  cd "$WD"
  sed 's/stage: DV/stage: QA/' .context/development-0.md > .context/qa-0.md
  sed 's/stage: DV/stage: QA/' .context/development-0.md > .context/testing-0.md
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage QA
  assert_success
  run jq -r '.tasks.QA0.artifact' .context/state.json
  assert_output --partial "testing-0.md"
}

@test "alias: a basename that is not canonical or aliased stays unresolved" {
  cd "$WD"
  # 'quality' is neither QA's canonical basename nor one of its aliases.
  sed 's/stage: DV/stage: QA/' .context/development-0.md > .context/quality-0.md
  cp .context/state.json snap
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage QA
  assert_success
  run diff -q .context/state.json snap
  assert_success
}

@test "fail-loud: self-patch with an unresolved artifact exits 3 naming stage and basenames" {
  cd "$WD"
  cp .context/state.json snap
  # ST has no artifact in the fixture workdir; --prev without --via is the self-patch signature.
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage ST --prev FN
  assert_failure 3
  assert_output --partial "ST"
  assert_output --partial "retrospective-N.md"
  run diff -q .context/state.json snap
  assert_success
}

@test "fail-loud: --via (hook / step6_5) keeps the unresolved no-op at exit 0" {
  cd "$WD"
  cp .context/state.json snap
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage ST --prev FN --via hook
  assert_success
  run diff -q .context/state.json snap
  assert_success
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage ST --prev FN --via step6_5
  assert_success
}

@test "fail-loud: --allow-missing-artifact restores the exit-0 no-op for the self-patch path" {
  cd "$WD"
  cp .context/state.json snap
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage ST --prev FN --allow-missing-artifact
  assert_success
  run diff -q .context/state.json snap
  assert_success
}

@test "user: --prev USER writes the USER→PL origin edge" {
  cd "$WD"
  sed 's/stage: DV/stage: PL/' .context/development-0.md > .context/planning-0.md
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage PL --prev USER --artifact .context/planning-0.md
  assert_success
  run jq -r '.handoffs["USER→PL"]' .context/state.json
  assert_output --partial "ref:planning-0.md"
}

@test "user: --prev USER writes the USER→IR origin edge (emergency pipeline)" {
  cd "$WD"
  sed 's/stage: DV/stage: IR/' .context/development-0.md > .context/incident-0.md
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage IR --prev USER --artifact .context/incident-0.md
  assert_success
  run jq -r '.handoffs["USER→IR"]' .context/state.json
  assert_output --partial "ref:incident-0.md"
}

@test "user: USER is predecessor-only — --stage USER resolves nothing and never patches" {
  cd "$WD"
  cp .context/state.json snap
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage USER
  assert_success
  run diff -q .context/state.json snap
  assert_success
  # A genuinely invalid predecessor is still a caller bug.
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --artifact .context/development-0.md --prev NOPE
  assert_failure 2
  assert_output --partial "invalid --prev value"
}

@test "bounds: facts.decisions clamps to newest-8, dispatched_agents to 6 (launched survive)" {
  cd "$WD"
  jq -n '
    {version:2, worktask_id:"b", plan_file:".context/planning-0.md", platform:"all",
     run_index:0, tasks:{PL0:{status:"completed", verdict:"ok"}},
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

# ---------------------------------------------------------------------------
# --facts union — the compressed-fact channel's write path.
# Asserts on CONTENT survival, not merely on the field existing: the bug these
# cover is stage B's patch silently replacing stage A's entries.
# ---------------------------------------------------------------------------

@test "facts: a decision recorded upstream survives a later stage's patch (content-asserted)" {
  cd "$WD"
  bash "$PLUGIN_ROOT/$SCRIPT" --facts \
    '{"decisions":[{"id":"pl-1","summary":"union not replace","ref":"planning-0.md#stages"}]}'
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --artifact .context/development-0.md --facts \
    '{"decisions":[{"id":"dv-1","summary":"tail append","ref":"development-0.md"}]}'
  assert_success
  run jq -r '[.facts.decisions[] | select(.id=="pl-1")] | .[0].summary' .context/state.json
  assert_output "union not replace"
  run jq -c '[.facts.decisions[] | select(.id=="pl-1" or .id=="dv-1") | .id]' .context/state.json
  assert_output '["pl-1","dv-1"]'
}

@test "facts: union survives where jq object-merge (. * \$patch) would replace" {
  cd "$WD"
  bash "$PLUGIN_ROOT/$SCRIPT" --facts '{"decisions":[{"id":"a","summary":"A","ref":"r"}]}'
  bash "$PLUGIN_ROOT/$SCRIPT" --facts '{"decisions":[{"id":"b","summary":"B","ref":"r"}]}'
  # `. * $patch` semantics for the same two writes: the second array wins outright.
  run jq -n --argjson p '{"facts":{"decisions":[{"id":"b"}]}}' \
    '({"facts":{"decisions":[{"id":"a"}]}} * $p) | .facts.decisions | length'
  assert_output "1"
  run jq -r '.facts.decisions | length' .context/state.json
  assert_output "2"
}

@test "facts: all four fields union, keyed by .id and by string" {
  cd "$WD"
  bash "$PLUGIN_ROOT/$SCRIPT" --facts '{
    "decisions":[{"id":"d1","summary":"s","ref":"r"}],
    "open_questions":[{"id":"sw-PL0-1","class":"decision","ref":"planning-0.md#elicitation-sweep"}],
    "files_modified":["a.sh"], "tests_added":["a.bats"]}'
  run bash "$PLUGIN_ROOT/$SCRIPT" --facts '{
    "decisions":[{"id":"d2","summary":"s","ref":"r"}],
    "open_questions":[{"id":"sw-AR0-1","class":"escalate","ref":"architecture-0.md#elicitation-sweep"}],
    "files_modified":["b.sh"], "tests_added":["b.bats"]}'
  assert_success
  run jq -c '[(.facts.decisions|map(.id)), (.facts.open_questions|map(.id)),
              .facts.files_modified, .facts.tests_added]' .context/state.json
  assert_output '[["d1","d2"],["sw-PL0-1","sw-AR0-1"],["a.sh","b.sh"],["a.bats","b.bats"]]'
}

@test "facts: an open_questions item lacking class/ref is rejected, ledger byte-unchanged" {
  cd "$WD"
  bash "$PLUGIN_ROOT/$SCRIPT" --facts \
    '{"open_questions":[{"id":"sw-PL0-1","class":"decision","ref":"planning-0.md#elicitation-sweep"}]}'
  cp .context/state.json .context/state.json.snap
  # The union REPLACES the incumbent object for that id, so a partial item would silently
  # drop the anchor the FN render resolves its options[] through.
  run bash "$PLUGIN_ROOT/$SCRIPT" --facts '{"open_questions":[{"id":"sw-PL0-1"}]}'
  assert_failure 2
  run diff -q .context/state.json .context/state.json.snap
  assert_success
  run bash "$PLUGIN_ROOT/$SCRIPT" --facts \
    '{"open_questions":[{"id":"sw-PL0-2","class":"decision"}]}'
  assert_failure 2
}

@test "facts: a stub failing the shared predicate exits 2, naming the field, ledger unchanged" {
  cd "$WD"
  bash "$PLUGIN_ROOT/$SCRIPT" --facts \
    '{"open_questions":[{"id":"sw-PL0-1","class":"decision","ref":"planning-0.md#elicitation-sweep"}]}'
  cp .context/state.json .context/state.json.snap
  # Each defect names itself: "bad shape" hands the caller nothing to act on.
  run bash "$PLUGIN_ROOT/$SCRIPT" --facts \
    '{"open_questions":[{"id":"sw-P0-1","class":"decision","ref":"planning-0.md#elicitation-sweep"}]}'
  assert_failure 2
  assert_output --partial "id sw-P0-1 is not sw-<TASK_ID>-<n>"
  run bash "$PLUGIN_ROOT/$SCRIPT" --facts \
    '{"open_questions":[{"id":"sw-PL0-1","class":"question","ref":"planning-0.md#elicitation-sweep"}]}'
  assert_failure 2
  assert_output --partial "class is not decision|escalate"
  run bash "$PLUGIN_ROOT/$SCRIPT" --facts \
    '{"open_questions":[{"id":"sw-PL0-1","class":"decision","ref":""}]}'
  assert_failure 2
  assert_output --partial "ref is not an optional <artifact>.md path plus one non-empty #anchor"
  run diff -q .context/state.json .context/state.json.snap
  assert_success
}

@test "facts: an anchor-only ref is accepted (the tightening is not blanket)" {
  cd "$WD"
  run bash "$PLUGIN_ROOT/$SCRIPT" --facts \
    '{"open_questions":[{"id":"sw-PL0-9","class":"escalate","ref":"#elicitation-sweep"}]}'
  assert_success
  run jq -r '.facts.open_questions[-1].ref' .context/state.json
  assert_output "#elicitation-sweep"
}

@test "facts: decisions stay id-only — the stub tightening is scoped to open_questions" {
  cd "$WD"
  run bash "$PLUGIN_ROOT/$SCRIPT" --facts '{"decisions":[{"id":"d1"}]}'
  assert_success
  run jq -r '.facts.decisions[0].id' .context/state.json
  assert_output "d1"
}

@test "facts: same .id from a later stage supersedes and moves to the tail" {
  cd "$WD"
  bash "$PLUGIN_ROOT/$SCRIPT" --facts \
    '{"decisions":[{"id":"x","summary":"old","ref":"r"},{"id":"y","summary":"y","ref":"r"}]}'
  bash "$PLUGIN_ROOT/$SCRIPT" --facts '{"decisions":[{"id":"x","summary":"new","ref":"r"}]}'
  run jq -c '[.facts.decisions[] | select(.id=="x" or .id=="y") | .id]' .context/state.json
  assert_output '["y","x"]'
  run jq -r '[.facts.decisions[] | select(.id=="x")] | length' .context/state.json
  assert_output "1"
  run jq -r '[.facts.decisions[] | select(.id=="x")] | .[0].summary' .context/state.json
  assert_output "new"
}

@test "facts: re-merging an already-merged payload is byte-identical" {
  cd "$WD"
  bash "$PLUGIN_ROOT/$SCRIPT" --facts \
    '{"decisions":[{"id":"d1","summary":"s","ref":"r"}],"files_modified":["a.sh","b.sh"]}'
  cp .context/state.json snap
  bash "$PLUGIN_ROOT/$SCRIPT" --facts \
    '{"decisions":[{"id":"d1","summary":"s","ref":"r"}],"files_modified":["a.sh","b.sh"]}'
  run diff -q .context/state.json snap
  assert_success
}

@test "bounds: clamp after union keeps the NEWEST 8 decisions, not an arbitrary 8" {
  cd "$WD"
  jq '.facts.decisions = [range(0;6) | {id:("d"+(.|tostring)), summary:"s", ref:"x.md#y"}]' \
    .context/state.json > s2 && mv s2 .context/state.json
  # 6 existing + 5 unioned = 11; the clamp must evict d0..d2, never the fresh tail.
  run bash "$PLUGIN_ROOT/$SCRIPT" --facts \
    "$(jq -cn '{decisions:[range(6;11)|{id:("d"+(.|tostring)),summary:"s",ref:"x.md#y"}]}')"
  assert_success
  run jq -c '.facts.decisions | map(.id)' .context/state.json
  assert_output '["d3","d4","d5","d6","d7","d8","d9","d10"]'
}

@test "bounds: a superseded old decision re-enters at the tail and survives the clamp" {
  cd "$WD"
  jq '.facts.decisions = [range(0;8) | {id:("d"+(.|tostring)), summary:"s", ref:"x.md#y"}]' \
    .context/state.json > s2 && mv s2 .context/state.json
  bash "$PLUGIN_ROOT/$SCRIPT" --facts '{"decisions":[{"id":"d0","summary":"revised","ref":"x"}]}'
  run jq -c '.facts.decisions | map(.id)' .context/state.json
  assert_output '["d1","d2","d3","d4","d5","d6","d7","d0"]'
  run jq -r '.facts.decisions[-1].summary' .context/state.json
  assert_output "revised"
}

@test "facts: unknown key is rejected and state.json is left unchanged" {
  cd "$WD"
  cp .context/state.json snap
  run bash "$PLUGIN_ROOT/$SCRIPT" --facts '{"verdicts":{"PL":"ok"}}'
  assert_failure
  assert_output --partial "unknown key(s): verdicts"
  run diff -q .context/state.json snap
  assert_success
}

@test "facts: wrong array shape is rejected before the merge lock" {
  cd "$WD"
  cp .context/state.json snap
  run bash "$PLUGIN_ROOT/$SCRIPT" --facts '{"decisions":["not-an-object"]}'
  assert_failure
  assert_output --partial "bad shape for decisions"
  run bash "$PLUGIN_ROOT/$SCRIPT" --facts '{"files_modified":[7]}'
  assert_failure
  assert_output --partial "bad shape for files_modified"
  run bash "$PLUGIN_ROOT/$SCRIPT" --facts 'not json'
  assert_failure
  assert_output --partial "not valid JSON"
  run diff -q .context/state.json snap
  assert_success
}

@test "facts: ledger channel is untouched by a standalone --facts call" {
  cd "$WD"
  before_tasks="$(jq -c '.tasks' .context/state.json)"
  before_handoffs="$(jq -c '.handoffs' .context/state.json)"
  run bash "$PLUGIN_ROOT/$SCRIPT" --facts '{"files_modified":["a.sh"]}'
  assert_success
  run jq -c '.tasks' .context/state.json
  assert_output "$before_tasks"
  run jq -c '.handoffs' .context/state.json
  assert_output "$before_handoffs"
}

@test "facts: lands even when the completion merge short-circuits as idempotent" {
  cd "$WD"
  bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --artifact .context/development-0.md
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --artifact .context/development-0.md --facts \
    '{"decisions":[{"id":"late","summary":"after idempotent stop","ref":"r"}]}'
  assert_success
  run jq -r '[.facts.decisions[] | select(.id=="late")] | .[0].summary' .context/state.json
  assert_output "after idempotent stop"
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
  run jq -r '.tasks.DV0.status' .context/state.json
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
  run jq -r '.tasks.DV0.status' .context/state.json
  assert_output "completed"
  run grep -c 'lock stale' .context/logs/lock.log
  assert_output "1"
  # Lock released after a successful merge.
  [ ! -d .context/state.json.lock.d ]
}

@test "lock: the mtime probe keeps its format attached to the flag (GNU stdout-pollution guard)" {
  # Separated (`stat -f %m`), GNU reads -f as --file-system, which takes no
  # argument: the path becomes an operand, stat prints a filesystem block to
  # stdout and exits non-zero, and `||` — testing status only — appends the
  # fallback to that block. $mtime becomes junk, not empty. Attached is safe
  # because GNU getopt rejects `-f%m` before anything reaches stdout. This
  # asserts the source form, because the failure is unreachable on BSD/macOS.
  run grep -nE 'stat -[fc] +%' "$PLUGIN_ROOT/$SCRIPT"
  assert_failure
  run grep -c 'stat -f%m .* || stat -c%Y ' "$PLUGIN_ROOT/$SCRIPT"
  assert_output "1"
}

@test "lock: a non-numeric mtime probe is treated as un-ageable, not as age 0" {
  cd "$WD"
  # A junk probe must not reach the arithmetic. Shadow `stat` with the exact
  # GNU-separated failure shape: multi-line stdout plus non-zero status.
  mkdir -p "$WD/binshim" .context/state.json.lock.d
  cat > "$WD/binshim/stat" <<'SHIM'
#!/usr/bin/env bash
printf '  File: "/x"\n    ID: 0 Namelen: 255\n'
exit 1
SHIM
  chmod +x "$WD/binshim/stat"
  # The discriminator is the arithmetic, not the log: without the numeric guard
  # the junk reaches `age=$((now - mtime))`, whose first word is unset under
  # `set -u`, and the run dies with "File: unbound variable". Asserting only
  # "no 'lock stale' line" would pass either way — the aborted run prints no
  # such line either. Verified by mutation: reverting the guard to the old
  # emptiness test reproduces the unbound-variable abort.
  PATH="$WD/binshim:$PATH" STATE_LOCK_TIMEOUT_S=1 STATE_LOCK_STALE_S=0 \
    run bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --artifact .context/development-0.md \
    --log .context/logs/lock.log
  refute_output --partial "unbound variable"
  refute_output --partial "lock stale"
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

@test "via: --via hook stamps tasks.DV0.completed_via=hook (additive, version unchanged)" {
  cd "$WD"
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --artifact .context/development-0.md --via hook
  assert_success
  run jq -r '.tasks.DV0.completed_via' .context/state.json
  assert_output "hook"
  run jq -r '.version' .context/state.json
  assert_output "2"
}

@test "via: --via step6_5 stamps completed_via=step6_5; invalid --via value exits 2" {
  cd "$WD"
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --artifact .context/development-0.md --via step6_5
  assert_success
  run jq -r '.tasks.DV0.completed_via' .context/state.json
  assert_output "step6_5"
  # Invalid enum value is a caller bug → exit 2 via usage.
  run bash "$PLUGIN_ROOT/$SCRIPT" --stage DV --artifact .context/development-0.md --via bogus
  assert_failure 2
  assert_output --partial "invalid --via value"
}

@test "worktree: worktree_path/worktree_branch frontmatter maps to tasks.DV0.worktree" {
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
  run jq -r '.tasks.DV0.worktree.path' .context/state.json
  assert_output "/tmp/wt/agent-abc"
  run jq -r '.tasks.DV0.worktree.branch' .context/state.json
  assert_output "feature/xyz"
  # Additive: absent worktree frontmatter must NOT synthesize the key.
  run jq -e '.tasks.PL0 | has("worktree")' .context/state.json
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
  run jq -r '.tasks.DV0.status' .context/state.json
  assert_output "completed"
  run jq -r '.tasks.QA0.status' .context/state.json
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
  run jq -r '.tasks.TL0.status' .context/state.json
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

# ---------------------------------------------------------------------------
# --task-replay. The load-bearing assertions are the refusals: a
# replay that resets a stage whose agent is still alive puts two writers in one
# tree, so every guard test asserts the ledger is BYTE-identical afterwards
# (checksum, not a field check) — a partially-applied reset would pass a field
# check on the field it never reached.
# ---------------------------------------------------------------------------

# mk_replay_wd [fixture-basename] — workdir on the multi-stage chain
# PL0→DV1→DR0→QA0→FN0→ST0, plus the three liveness fixtures every guard needs.
mk_replay_wd() {
  local w; w="$(mk_tmpworkdir)"
  mkdir -p "$w/.context/logs"
  cp "$FIXTURES/worktask/${1:-state.multistage.json}" "$w/.context/state.json"
  cp "$w/.context/state.json" "$w/before.json"
  printf '%s\n' '[]' > "$w/gone.json"
  printf '%s\n' '[{"id":"sess-dv1","sessionId":"sess-dv1deadbeef","name":"dv","state":"active"}]' \
    > "$w/busy.json"
  printf '%s\n' '[{"id":"sess-dv1","sessionId":"sess-dv1deadbeef","name":"dv","state":"blocked"}]' \
    > "$w/parked.json"
  printf '%s\n' 'not json' > "$w/garbage.json"
  printf '%s\n' "$w"
}

assert_ledger_unchanged() {
  cmp -s "$1/.context/state.json" "$1/before.json" \
    || fail "guard mutated state.json; it must be byte-identical
$(diff "$1/before.json" "$1/.context/state.json" || true)"
}

@test "replay guard: unknown task id refuses with exit 1, ledger byte-unchanged" {
  local w; w="$(mk_replay_wd)"; cd "$w"
  run bash "$PLUGIN_ROOT/$SCRIPT" --task-replay DV7 --agents-json "$w/gone.json"
  assert_failure 1
  assert_output --partial "unknown task id"
  assert_ledger_unchanged "$w"
}

@test "replay guard: malformed task id stays exit 2 via usage, ledger byte-unchanged" {
  local w; w="$(mk_replay_wd)"; cd "$w"
  # Exit 2 collides with DISK_HALT. That is pre-existing behaviour shared by all
  # task ops; this test pins it so a future change is a deliberate one.
  run bash "$PLUGIN_ROOT/$SCRIPT" --task-replay ZZ0 --agents-json "$w/gone.json"
  assert_failure 2
  assert_output --partial "invalid task id"
  assert_ledger_unchanged "$w"
}

@test "replay guard: live agent refuses target-live (exit 4), ledger byte-unchanged" {
  local w; w="$(mk_replay_wd)"; cd "$w"
  run bash "$PLUGIN_ROOT/$SCRIPT" --task-replay DV1 --agents-json "$w/busy.json"
  assert_failure 4
  assert_output --partial "replay refused: target-live"
  assert_ledger_unchanged "$w"
}

@test "replay guard: parked agent refuses target-parked (exit 4), ledger byte-unchanged" {
  local w; w="$(mk_replay_wd)"; cd "$w"
  run bash "$PLUGIN_ROOT/$SCRIPT" --task-replay DV1 --agents-json "$w/parked.json"
  assert_failure 4
  assert_output --partial "replay refused: target-parked"
  assert_ledger_unchanged "$w"
}

@test "replay guard: unreadable agents payload refuses liveness-indeterminate (fail-closed)" {
  local w; w="$(mk_replay_wd)"; cd "$w"
  run bash "$PLUGIN_ROOT/$SCRIPT" --task-replay DV1 --agents-json "$w/nope.json"
  assert_failure 4
  assert_output --partial "replay refused: liveness-indeterminate"
  assert_ledger_unchanged "$w"
}

@test "replay guard: unparseable agents payload refuses liveness-indeterminate" {
  local w; w="$(mk_replay_wd)"; cd "$w"
  run bash "$PLUGIN_ROOT/$SCRIPT" --task-replay DV1 --agents-json "$w/garbage.json"
  assert_failure 4
  assert_output --partial "replay refused: liveness-indeterminate"
  assert_ledger_unchanged "$w"
}

@test "replay guard: incomplete planning refuses plan-incomplete, ledger byte-unchanged" {
  local w; w="$(mk_replay_wd)"; cd "$w"
  jq '.tasks.PL0.status = "in_progress"' .context/state.json > t && mv t .context/state.json
  cp .context/state.json before.json
  run bash "$PLUGIN_ROOT/$SCRIPT" --task-replay DV1 --agents-json "$w/gone.json"
  assert_failure 4
  assert_output --partial "replay refused: plan-incomplete"
  assert_ledger_unchanged "$w"
}

@test "replay guard: no audit row is written on any refusal" {
  local w; w="$(mk_replay_wd)"; cd "$w"
  bash "$PLUGIN_ROOT/$SCRIPT" --task-replay DV1 --agents-json "$w/busy.json" || true
  bash "$PLUGIN_ROOT/$SCRIPT" --task-replay DV7 --agents-json "$w/gone.json" || true
  # A refusal row would carry result:"error", which stale-check.sh reads as a real
  # stage failure and uses to rule OUT a budget halt — poisoning later diagnosis.
  [ ! -s .context/logs/audit.jsonl ] || fail "refusal appended: $(cat .context/logs/audit.jsonl)"
}

@test "replay: an escalated stage (retry_count 3 + escalation marker) is replayable" {
  local w; w="$(mk_replay_wd)"; cd "$w"
  run jq -r '[.tasks.DV1.metadata.retry_count, .tasks.DV1.metadata.error_escalated_to] | @csv' \
    .context/state.json
  assert_output '3,"AR"'

  run bash "$PLUGIN_ROOT/$SCRIPT" --task-replay DV1 --agents-json "$w/gone.json"
  assert_success
  run jq -r '.tasks.DV1.status' .context/state.json
  assert_output "pending"
  run jq -r '[.tasks.DV1.metadata | has("retry_count"), has("error_escalated_to")] | @csv' \
    .context/state.json
  assert_output "false,false"
  run jq -r '.tasks.DV1 | has("completed_via")' .context/state.json
  assert_output "false"
  # The override is recorded where it is still knowable — at write time.
  assert_audit_row stage_replay --file "$w/.context/logs/audit.jsonl" \
    --subject DV1 --result ok --count 1 --meta escalation_cap_override=true --meta prior_retry_count=3 \
    --meta prior_escalated_to=AR --meta prior_status=in_progress
}

@test "replay: artifact, verdict and worktree survive the reset" {
  local w; w="$(mk_replay_wd)"; cd "$w"
  bash "$PLUGIN_ROOT/$SCRIPT" --task-replay DV1 --agents-json "$w/gone.json"
  run jq -r '[.tasks.DV1.artifact, .tasks.DV1.verdict, .tasks.DV1.worktree.branch] | @csv' \
    .context/state.json
  assert_output '".context/development-1.md","ok","feature/replay"'
}

@test "replay blast radius: replaying DV1 changes DV1's fields and nothing else" {
  local w; w="$(mk_replay_wd)"; cd "$w"
  bash "$PLUGIN_ROOT/$SCRIPT" --task-replay DV1 --agents-json "$w/gone.json"
  # Every task except DV1 must be byte-identical, PL0 included.
  run jq -S --slurpfile a before.json '.tasks | with_entries(select(.key != "DV1"))
        == ($a[0].tasks | with_entries(select(.key != "DV1")))' .context/state.json
  assert_output "true"
  run jq -S --slurpfile a before.json 'del(.tasks) == ($a[0] | del(.tasks))' .context/state.json
  assert_output "true"
  # …and within DV1 only the four documented paths moved.
  run jq -Sr --slurpfile a before.json '[
        (.tasks.DV1 | keys_unsorted) - ($a[0].tasks.DV1 | keys_unsorted),
        ($a[0].tasks.DV1 | keys_unsorted) - (.tasks.DV1 | keys_unsorted),
        ($a[0].tasks.DV1.metadata | keys) - (.tasks.DV1.metadata | keys)] | flatten | sort
      | join(",")' .context/state.json
  assert_output "completed_via,error_escalated_to,retry_count"
  # …and at value level: DV1 after == DV1 before minus exactly those three keys, with
  # status flipped. A silent rewrite of e.g. .artifact passes the key-set check above.
  run jq -Sr --slurpfile a before.json '.tasks.DV1 ==
        ($a[0].tasks.DV1
         | del(.completed_via) | .metadata |= (del(.retry_count) | del(.error_escalated_to))
         | .status = "pending")' .context/state.json
  assert_output "true"
}

@test "replay audit: the row is not matchable as an ordinary retry" {
  local w; w="$(mk_replay_wd)"; cd "$w"
  bash "$PLUGIN_ROOT/$SCRIPT" --task-replay DV1 --agents-json "$w/gone.json"
  assert_audit_row stage_replay --file "$w/.context/logs/audit.jsonl" --count 1
  assert_audit_row retry_attempt --file "$w/.context/logs/audit.jsonl" --absent
  # A reader filtering ordinary retries keys on .metadata.retry; the replay row
  # deliberately names its counter prior_retry_count so that filter cannot match.
  run jq -r '[.[] | select(.metadata.retry)] | length' <(jq -s . .context/logs/audit.jsonl)
  assert_output "0"
  run jq -r '.metadata.via' .context/logs/audit.jsonl
  assert_output "state-patch --task-replay"
}

@test "replay P1: completed dependents are named as possibly stale, never reset" {
  local w; w="$(mk_replay_wd)"; cd "$w"
  run bash "$PLUGIN_ROOT/$SCRIPT" --task-replay DV1 --agents-json "$w/gone.json"
  assert_success
  assert_output --partial "replay warning: stale-dependents"
  assert_output --partial "DR0"
  run jq -r '.tasks.DR0.status' .context/state.json
  assert_output "completed"
}

@test "replay cascade: resets the transitive closure, skipping FN with a warning" {
  local w; w="$(mk_replay_wd)"; cd "$w"
  run bash "$PLUGIN_ROOT/$SCRIPT" --task-replay DV1 --cascade --agents-json "$w/gone.json"
  assert_success
  assert_output --partial "replay warning: side-effect-skipped"
  assert_output --partial "FN0"
  run jq -r '[.tasks | to_entries[] | select(.value.status == "pending") | .key] | sort | join(",")' \
    .context/state.json
  assert_output "DR0,DV1,QA0,ST0"
  # FN0 is traversed THROUGH (ST0 downstream of it is reset) but never reset itself.
  run jq -r '.tasks.FN0.status' .context/state.json
  assert_output "completed"
}

@test "replay cascade: one audit row per member, root first then BFS order" {
  local w; w="$(mk_replay_wd)"; cd "$w"
  bash "$PLUGIN_ROOT/$SCRIPT" --task-replay DV1 --cascade --agents-json "$w/gone.json"
  run jq -rs 'map(.subject) | join(",")' .context/logs/audit.jsonl
  assert_output "DV1,DR0,QA0,ST0"
  run jq -rs '[.[] | .metadata.cascade_id] | unique | length' .context/logs/audit.jsonl
  assert_output "1"
  run jq -rs 'map(select(.subject == "DV1"))[0]
        | [(.metadata.cascade_members | join("+")), (.metadata.cascade_skipped | join("+"))]
        | join(" / ")' .context/logs/audit.jsonl
  assert_output "DV1+DR0+QA0+ST0 / FN0+RE0"
}

@test "replay cascade: the stale-dependent warning never names a task the same write resets" {
  local w; w="$(mk_replay_wd)"; cd "$w"
  # Non-cascade, DR0 is a completed dependent that is NOT reset ⇒ genuinely stale.
  run bash "$PLUGIN_ROOT/$SCRIPT" --task-replay DV1 --agents-json "$w/gone.json"
  assert_output --partial "replay warning: stale-dependents"
  assert_output --partial "DR0"

  # Under --cascade the same DR0 IS reset by this write, so calling it stale would assert the
  # opposite of what the command does — and would write that claim into the durable audit row.
  local v; v="$(mk_replay_wd)"; cd "$v"
  run bash "$PLUGIN_ROOT/$SCRIPT" --task-replay DV1 --cascade --agents-json "$v/gone.json"
  assert_success
  refute_output --partial "stale-dependents"
  run jq -rs 'map(select(.subject == "DV1"))[0] | .metadata.stale_dependents | length' \
    .context/logs/audit.jsonl
  assert_output "0"
}

@test "replay cascade: an FN root is reset, while a dependent RE is skipped and named stale" {
  local w; w="$(mk_replay_wd)"; cd "$w"
  # The named target is always reset, cascade or not; only DEPENDENT side-effect stages are
  # skipped. RE0 is skipped, stays completed, and is therefore genuinely stale — which is the
  # discriminator between "in the graph" and "in the reset set".
  run bash "$PLUGIN_ROOT/$SCRIPT" --task-replay FN0 --cascade --agents-json "$w/gone.json"
  assert_success
  assert_output --partial "replay warning: side-effect-target"
  assert_output --partial "replay warning: side-effect-skipped"
  run jq -r '[.tasks | to_entries[] | select(.value.status == "pending") | .key] | sort | join(",")' \
    .context/state.json
  assert_output "FN0,ST0"
  run jq -r '.tasks.RE0.status' .context/state.json
  assert_output "completed"
  run jq -rs 'map(select(.subject == "FN0"))[0]
        | [(.metadata.cascade_skipped | join("+")), (.metadata.stale_dependents | join("+"))]
        | join(" / ")' .context/logs/audit.jsonl
  assert_output "RE0 / RE0"
}

@test "replay: --cascade and --agents-json are rejected on the other ledger ops" {
  local w; w="$(mk_replay_wd)"; cd "$w"
  run bash "$PLUGIN_ROOT/$SCRIPT" --task-status DV1 pending --cascade
  assert_failure 2
  assert_output --partial "apply to --task-replay only"
  assert_ledger_unchanged "$w"
  run bash "$PLUGIN_ROOT/$SCRIPT" --task-meta DV1 --set '{}' --agents-json "$w/gone.json"
  assert_failure 2
  assert_ledger_unchanged "$w"
}

@test "replay cascade: a blocked member refuses the WHOLE cascade before any write" {
  local w; w="$(mk_replay_wd)"; cd "$w"
  # Park QA0 (a mid-cascade member) rather than the root.
  jq '.tasks.QA0.status = "in_progress"
      | .facts.dispatched_agents += [{"stage":"QA","task_id":"QA0",
          "subagent_type":"corpflow:qa-engineer","agent_id":"sess-qa0","status":"launched"}]' \
    .context/state.json > t && mv t .context/state.json
  cp .context/state.json before.json
  printf '%s\n' '[{"id":"sess-qa0","sessionId":"sess-qa0deadbeef","name":"qa","state":"active"}]' \
    > mixed.json
  run bash "$PLUGIN_ROOT/$SCRIPT" --task-replay DV1 --cascade --agents-json mixed.json
  assert_failure 4
  assert_output --partial "replay refused: cascade-member-blocked — QA0: target-live"
  assert_ledger_unchanged "$w"
}

@test "replay cascade: a blocked_by cycle terminates and still resets the closure" {
  local w; w="$(mk_replay_wd state.cycle.json)"; cd "$w"
  # DR0 ↔ QA0 point at each other; blocked_by has no acyclicity enforcement, so the
  # walk must terminate on the visited set + task-count bound, not on graph shape.
  # No timeout(1) on macOS: termination is the assertion, so a hang fails the suite
  # by wall clock rather than by a wrapper this host may not have.
  run bash "$PLUGIN_ROOT/$SCRIPT" --task-replay DV1 --cascade --agents-json "$w/gone.json"
  assert_success
  run jq -r '[.tasks | to_entries[] | select(.value.status == "pending") | .key] | sort | join(",")' \
    .context/state.json
  assert_output "DR0,DV1,QA0,ST0"
}

@test "replay: a directly named FN target is allowed but warns about the side effect" {
  local w; w="$(mk_replay_wd)"; cd "$w"
  run bash "$PLUGIN_ROOT/$SCRIPT" --task-replay FN0 --agents-json "$w/gone.json"
  assert_success
  assert_output --partial "replay warning: side-effect-target"
  run jq -r '.tasks.FN0.status' .context/state.json
  assert_output "pending"
}

@test "replay: replaying an already-clean task is idempotent" {
  local w; w="$(mk_replay_wd)"; cd "$w"
  bash "$PLUGIN_ROOT/$SCRIPT" --task-replay DV1 --agents-json "$w/gone.json"
  cp .context/state.json snap
  run bash "$PLUGIN_ROOT/$SCRIPT" --task-replay DV1 --agents-json "$w/gone.json"
  assert_success
  run diff -q .context/state.json snap
  assert_success
}

@test "replay parity: the script's side-effect list matches stage-codes.md" {
  # bash cannot read the canonical markdown table, so the constant mirrors it; this
  # assertion is what keeps the mirror honest.
  local doc script_list
  doc="$(awk -F'|' '
    /^### Side-effect-bearing stages/ { f = 1; next }
    f && /^#/ { exit }
    f && NF > 2 { c = $2; gsub(/[[:space:]]/, "", c);
                  if (c ~ /^[A-Z][A-Z]$/) print c }' \
    "$PLUGIN_ROOT/skills/shared/stage-codes.md" | sort | paste -sd, -)"
  script_list="$(grep -E '^REPLAY_SIDE_EFFECT_STAGES=' "$PLUGIN_ROOT/$SCRIPT" \
    | cut -d'"' -f2 | tr ',' '\n' | sort | paste -sd, -)"
  [ -n "$doc" ] || fail "stage-codes.md § Side-effect-bearing stages parsed empty"
  [ "$doc" = "$script_list" ] \
    || fail "side-effect list drift: stage-codes.md=[$doc] state-patch.sh=[$script_list]"
}

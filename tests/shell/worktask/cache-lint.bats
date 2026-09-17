#!/usr/bin/env bats
# Contract tests for skills/worktask/scripts/cache-lint.sh.
# Contracts (from header):
#   - --anchor-lint <file>: stage anchors all present => "ok", exit 0
#   - --anchor-lint <file>: anchors missing => "FAIL, missing:", exit 1
#   - --filename-lint <dir>: canonical artifact names => "all canonical", exit 0
#   - prefix-lint <log.jsonl>: consistent sections => "no drift", exit 0;
#     drifted sections => "DRIFT" on stderr, exit 1
#   - --self-test => "ALL PASS", exit 0
#
# RK5 (stderr honesty): the diagnostics below are asserted against the stream
# that actually carries them, via `run_script_env --separate-stderr`. Under a
# plain `run` the two streams are merged into $output, so every "on stderr"
# claim in this file was satisfied by a message printed on stdout — and the
# reverse. Each test now also pins the OTHER stream, which is what makes the
# routing itself falsifiable.
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
  run_script_env --separate-stderr -- "$SCRIPT" --anchor-lint "$WD/development-0.md"
  assert_success
  assert_output --partial "ok"
}

@test "failure: --anchor-lint on a DV artifact missing required H2s fails (exit 1)" {
  run_script_env --separate-stderr -- "$SCRIPT" --anchor-lint "$WD/incomplete-dev.md"
  assert_failure 1
  [[ "$stderr" == *"FAIL"* ]]
  [[ "$stderr" == *"missing"* ]]
  # The failure is a diagnostic, not output a caller would consume.
  assert_output ""
}

# --- the universal `## elicitation-sweep` anchor ------------------------------

@test "failure: --anchor-lint rejects a DV artifact whose only gap is the sweep anchor" {
  # Every DV table anchor present; only the universal one is missing, so the diagnostic
  # cannot be satisfied by an unrelated omission.
  cat > "$WD/no-sweep.md" <<'EOF'
---
handoff:
  stage: DV
  verdict: ok
  summary: "all four DV anchors, no sweep heading"
  refs: { dev: development.md#files-changed }
---
# Development

## files-changed

x

## tests-added

x

## deviations

none

## follow-ups

none
EOF
  run_script_env --separate-stderr -- "$SCRIPT" --anchor-lint "$WD/no-sweep.md"
  assert_failure 1
  [[ "$stderr" == *"missing: elicitation-sweep"* ]]
  assert_output ""
}

@test "happy: the same artifact passes once ## elicitation-sweep is appended (twin)" {
  cp "$WD/development-0.md" "$WD/twin.md"
  run_script_env --separate-stderr -- "$SCRIPT" --anchor-lint "$WD/twin.md"
  assert_success
  # Strip the sweep heading and it must fail — the fixture's pass is not incidental.
  grep -v '^## elicitation-sweep$' "$WD/twin.md" > "$WD/twin-stripped.md"
  run_script_env --separate-stderr -- "$SCRIPT" --anchor-lint "$WD/twin-stripped.md"
  assert_failure 1
  [[ "$stderr" == *"missing: elicitation-sweep"* ]]
}

# Per-stage anchor rows come from the script itself, so a new stage cannot be added
# without this loop covering it. The rows live in one `_STAGE_TABLE` — code, agent
# basename, artifact basename, then the anchors — so the anchors are fields 4..NF.
_anchors_for_stage() {  # <stage>
  # \047 is the single quote: the table is a single-quoted shell string, and
  # writing that quote literally inside this awk program is not possible.
  awk -v s="$1" '
    /^_STAGE_TABLE=/ { intbl = 1; sub(/^_STAGE_TABLE=\047/, "") }
    !intbl { next }
    { last = ($0 ~ /\047$/); sub(/\047$/, "") }
    $1 == s {
      out = ""
      for (i = 4; i <= NF; i++) out = out (i > 4 ? " " : "") $i
      print out; exit
    }
    last { exit }
  ' "$PLUGIN_ROOT/$SCRIPT"
}

@test "contract: for all 13 stages the exact table anchors fail without the sweep heading and pass with it" {
  local stage anchors a n=0
  for stage in PL AR TL DV DR SR QA DC RE FN ST IR ET; do
    anchors="$(_anchors_for_stage "$stage")"
    [ -n "$anchors" ] || fail "non-vacuity: no anchor row extracted for $stage"
    n=$((n + 1))
    {
      printf -- '---\nhandoff:\n  stage: %s\n  verdict: ok\n  summary: "s"\n' "$stage"
      printf '  refs: { dev: development.md#files-changed }\n---\n\n'
      for a in $anchors; do printf '## %s\n\nx\n\n' "$a"; done
    } > "$WD/loop-$stage.md"
    run_script_env --separate-stderr -- "$SCRIPT" --anchor-lint "$WD/loop-$stage.md"
    assert_failure 1
    [[ "$stderr" == *"missing: elicitation-sweep"* ]] \
      || fail "$stage: expected a missing-sweep diagnostic, got: $stderr"
    printf '## elicitation-sweep\n\nnothing to elicit\n' >> "$WD/loop-$stage.md"
    run_script_env --separate-stderr -- "$SCRIPT" --anchor-lint "$WD/loop-$stage.md"
    assert_success
  done
  [ "$n" -eq 13 ] || fail "non-vacuity: only $n stages exercised"
}

# --- PL: ## summary is mandatory; design-preview / test-strategy are optional ---

_pl_artifact() {  # _pl_artifact <path> <extra-headings...>
  local path="$1" h
  shift
  {
    printf -- '---\nhandoff:\n  stage: PL\n  verdict: ok\n  summary: "s"\n'
    printf '  refs: { plan: planning-0.md#requirements }\n---\n\n'
    for h in requirements acceptance-criteria scope out-of-scope risks complexity stages \
             elicitation-sweep "$@"; do
      printf '## %s\n\nx\n\n' "$h"
    done
  } > "$path"
}

@test "failure: --anchor-lint rejects a PL plan with no ## summary" {
  # `## summary` is mandatory in every PL plan (pl0-procedure.md), so the lint must
  # require it: a PL artifact without one is incomplete, not merely unconventional.
  _pl_artifact "$WD/pl-no-summary.md"
  run_script_env --separate-stderr -- "$SCRIPT" --anchor-lint "$WD/pl-no-summary.md"
  assert_failure 1
  [[ "$stderr" == *"missing: summary"* ]]
}

@test "happy: a PL plan with ## summary, ## design-preview and ## test-strategy passes" {
  _pl_artifact "$WD/pl-full.md" summary design-preview test-strategy
  run_script_env --separate-stderr -- "$SCRIPT" --anchor-lint "$WD/pl-full.md"
  assert_success
}

@test "failure: the PL allowance is scoped — an invented heading is still rejected" {
  _pl_artifact "$WD/pl-invented.md" summary design-preview test-strategy not-an-anchor
  run_script_env --separate-stderr -- "$SCRIPT" --anchor-lint "$WD/pl-invented.md"
  assert_failure 1
  [[ "$stderr" == *"unexpected: not-an-anchor"* ]]
}

# --- AR: the two title-case H2s the architect agent mandates -----------------

@test "happy: an architect-merged AR artifact with the two platform H2s passes" {
  # agents/software-architector.md mandates `## <Platform> App Architecture` and
  # `## Test Architecture`, so a merged AR artifact must not read as unexpected.
  cp "$FIXTURES/worktask/architecture-0.merged.sample.md" "$WD/architecture-0.md"
  run_script_env --separate-stderr -- "$SCRIPT" --anchor-lint "$WD/architecture-0.md"
  assert_success
  assert_output --partial "ok"
}

@test "failure: the App Architecture allowance is scoped to that exact suffix" {
  cp "$FIXTURES/worktask/architecture-0.merged.sample.md" "$WD/arch-invented.md"
  printf '\n## Deployment Architecture\n\nx\n' >> "$WD/arch-invented.md"
  run_script_env --separate-stderr -- "$SCRIPT" --anchor-lint "$WD/arch-invented.md"
  assert_failure 1
  [[ "$stderr" == *"unexpected: Deployment Architecture"* ]]
}

@test "happy: prefix-lint with stable sections reports no drift (exit 0)" {
  run_script_env --separate-stderr -- "$SCRIPT" "$WD/stable.jsonl"
  assert_success
  assert_output --partial "no drift"
  # A clean run is silent on stderr.
  assert_equal "$stderr" ""
}

@test "failure: prefix-lint with drifted contract-reminder reports DRIFT (exit 1)" {
  run_script_env --separate-stderr -- "$SCRIPT" "$WD/drift.jsonl"
  assert_failure 1
  # The header claims "DRIFT on stderr" — assert exactly that, and that stdout
  # stays clean so a consumer piping stdout sees nothing misleading.
  [[ "$stderr" == *"DRIFT"* ]]
  [[ "$stderr" == *"section [1] contract-reminder"* ]]
  assert_output ""
}

# --- section [3], the ledger pointer + readiness digest ----------------------

@test "happy: prefix-lint accepts a well-formed section [3] ledger digest" {
  cat > "$WD/ledger-ok.jsonl" <<'EOF'
{"worktask_id":"wtL1","stage":"DV","prompt":"<<<contract-reminder>>>\nr\n<<<worktask-header>>>\nh\n<<<state-json>>>\nledger: .context/state.json\nrun_index: 0\nready: none\nin_progress: none\nblocked: none\nopen_blocking_questions: 0\n<<<stage-contract>>>\nDV\n<<<task-description>>>\nwork"}
EOF
  run_script_env --separate-stderr -- "$SCRIPT" "$WD/ledger-ok.jsonl"
  assert_success
  assert_output --partial "no drift"
  assert_equal "$stderr" ""
}

@test "failure: prefix-lint rejects an inlined ledger in section [3]" {
  cat > "$WD/ledger-inline.jsonl" <<'EOF'
{"worktask_id":"wtL2","stage":"DV","prompt":"<<<contract-reminder>>>\nr\n<<<worktask-header>>>\nh\n<<<state-json>>>\n{\"tasks\": {\"PL0\": {\"status\": \"completed\"}}}\n<<<stage-contract>>>\nDV\n<<<task-description>>>\nwork"}
EOF
  run_script_env --separate-stderr -- "$SCRIPT" "$WD/ledger-inline.jsonl"
  assert_failure 1
  [[ "$stderr" == *"embeds the ledger"* ]]
  assert_output ""
}

@test "failure: prefix-lint rejects section [3] missing the ledger: pointer" {
  cat > "$WD/ledger-nopointer.jsonl" <<'EOF'
{"worktask_id":"wtL3","stage":"DV","prompt":"<<<contract-reminder>>>\nr\n<<<worktask-header>>>\nh\n<<<state-json>>>\nrun_index: 0\nready: none\nin_progress: none\nblocked: none\nopen_blocking_questions: 0\n<<<stage-contract>>>\nDV\n<<<task-description>>>\nwork"}
EOF
  run_script_env --separate-stderr -- "$SCRIPT" "$WD/ledger-nopointer.jsonl"
  assert_failure 1
  [[ "$stderr" == *"first line must be 'ledger: .context/state.json'"* ]]
  assert_output ""
}

@test "happy: a prompt with no section [3] at all is skipped, not rejected" {
  # stable.jsonl (setup()) carries no <<<state-json>>> marker — an absent [3]
  # section must stay lintable, not fail as if the digest were missing.
  run_script_env --separate-stderr -- "$SCRIPT" "$WD/stable.jsonl"
  assert_success
  assert_output --partial "no drift"
  assert_equal "$stderr" ""
}

@test "failure: prefix-lint catches an ISO-8601 timestamp in section [2] (REQ-3/AC-4)" {
  run_script_env --separate-stderr -- "$SCRIPT" "$WD/forbidden-timestamp.jsonl"
  assert_failure 1
  [[ "$stderr" == *"forbidden-token-lint"* ]]
  [[ "$stderr" == *"timestamp"* ]]
  assert_output ""
}

@test "failure: the ENV-expansion report names the variables, never their values" {
  # The message was in double quotes, so a report about per-call values leaked
  # the running shell's own $USER, $PWD and hostname into the lint output.
  cat > "$WD/forbidden-env.jsonl" <<'EOF'
{"worktask_id":"wt5","stage":"PL","prompt":"<<<contract-reminder>>>\nrun as $USER\n<<<contract-reminder>>>\n<<<worktask-header>>>\nworktask_id=wt5\n<<<worktask-header>>>\n<<<stage-contract>>>\nPL contract\n<<<stage-contract>>>"}
EOF
  run_script_env --separate-stderr -- "$SCRIPT" "$WD/forbidden-env.jsonl"
  assert_failure 1
  [[ "$stderr" == *'ENV expansion ($HOSTNAME/$USER/$PWD/$RANDOM) found'* ]] \
    || fail "expected the literal variable names, got: $stderr"
  local me
  me="$(id -un)"
  [[ "$stderr" != *"$me"* ]] || fail "the report leaked the invoking user: $stderr"
  [[ "$stderr" != *"$PWD"* ]] || fail "the report leaked the working directory: $stderr"
}

@test "happy: prefix-lint with no forbidden tokens still reports no drift (REQ-3/AC-4)" {
  run_script_env --separate-stderr -- "$SCRIPT" "$WD/forbidden-clean.jsonl"
  assert_success
  assert_output --partial "no drift"
  assert_equal "$stderr" ""
}

# --- section [4b], the per-model discipline block -----------------------------
# Two independent checks guard [4b], and each catches what the other cannot:
# byte-identity catches a block that changes between calls of one stage, and
# the canon check catches a block that never changes and is consistently the
# WRONG model's. A stage mis-keyed at the assembler fails only the second.

@test "failure: prefix-lint reports [4b] drift within one stage" {
  cat > "$WD/md-drift.jsonl" <<'EOF'
{"worktask_id":"wt6","stage":"DV","prompt":"<<<contract-reminder>>>\nr\n<<<worktask-header>>>\nh\n<<<stage-contract>>>\nDV\n<<<model-discipline>>>\nblock A\n<<<task-description>>>\nwork"}
{"worktask_id":"wt6","stage":"DV","prompt":"<<<contract-reminder>>>\nr\n<<<worktask-header>>>\nh\n<<<stage-contract>>>\nDV\n<<<model-discipline>>>\nblock B\n<<<task-description>>>\nwork"}
EOF
  run_script_env --separate-stderr -- "$SCRIPT" "$WD/md-drift.jsonl"
  assert_failure 1
  [[ "$stderr" == *"section [4b] model-discipline DRIFT"* ]]
  assert_output ""
}

@test "happy: a haiku stage with an empty [4b] matches the canon (exit 0)" {
  # model-prompting.md deliberately gives haiku no block, and the marker is
  # emitted with an empty body rather than omitted so the section count does
  # not vary by model. That empty body is the canonical value, not a miss.
  cat > "$WD/md-haiku.jsonl" <<'EOF'
{"worktask_id":"wt7","stage":"DC","model":"haiku","prompt":"<<<contract-reminder>>>\nr\n<<<worktask-header>>>\nh\n<<<stage-contract>>>\nDC\n<<<model-discipline>>>\n<<<task-description>>>\nwork"}
EOF
  run_script_env --separate-stderr -- "$SCRIPT" "$WD/md-haiku.jsonl"
  assert_success
  assert_output --partial "no drift"
  assert_equal "$stderr" ""
}

@test "failure: a haiku stage carrying another model's [4b] fails the canon check" {
  # The byte-identity check passes here — one line cannot drift from itself.
  # Only the canon check can see this, which is the whole reason it exists.
  cat > "$WD/md-wrong.jsonl" <<'EOF'
{"worktask_id":"wt8","stage":"DC","model":"haiku","prompt":"<<<contract-reminder>>>\nr\n<<<worktask-header>>>\nh\n<<<stage-contract>>>\nDC\n<<<model-discipline>>>\nDeliver what the stage contract asks for\n<<<task-description>>>\nwork"}
EOF
  run_script_env --separate-stderr -- "$SCRIPT" "$WD/md-wrong.jsonl"
  assert_failure 1
  [[ "$stderr" == *"section [4b] does not match model-prompting.md block for model=haiku"* ]]
  assert_output ""
}

@test "failure: an opus stage carrying a hand-written [4b] fails the canon check" {
  cat > "$WD/md-opus.jsonl" <<'EOF'
{"worktask_id":"wt9","stage":"DV","model":"opus","prompt":"<<<contract-reminder>>>\nr\n<<<worktask-header>>>\nh\n<<<stage-contract>>>\nDV\n<<<model-discipline>>>\nbe careful and double-check your work\n<<<task-description>>>\nwork"}
EOF
  run_script_env --separate-stderr -- "$SCRIPT" "$WD/md-opus.jsonl"
  assert_failure 1
  [[ "$stderr" == *"section [4b] does not match model-prompting.md block for model=opus"* ]]
}

@test "happy: the real opus block from model-prompting.md passes the canon check" {
  # Built FROM the canon file, so it cannot rot when the block is reworded — and it is the
  # only test here that would fail if the canon and the extractor disagreed about whether
  # the <<<model-discipline>>> marker belongs to the block or to the envelope. Both
  # mismatch tests above pass either way, which is exactly why this one is needed.
  python3 - "$WD/md-canon.jsonl" "skills/shared/model-prompting.md" <<'PYEOF'
import json, re, sys

out, canon = sys.argv[1], sys.argv[2]
body = open(canon).read()
sec = re.search(r"^## opus(?: |$).*?^```text\n(.*?)^```", body, re.S | re.M)
assert sec, "no fenced opus block in " + canon
block = sec.group(1).rstrip("\n")
assert block, "the opus block is empty"

prompt = (
    "<<<contract-reminder>>>\nr\n"
    "<<<worktask-header>>>\nh\n"
    "<<<stage-contract>>>\nDV\n"
    "<<<model-discipline>>>\n" + block + "\n"
    "<<<task-description>>>\nwork"
)
with open(out, "w") as fh:
    fh.write(json.dumps({"worktask_id": "wtc", "stage": "DV",
                         "model": "opus", "prompt": prompt}) + "\n")
PYEOF

  run_script_env --separate-stderr -- "$SCRIPT" "$WD/md-canon.jsonl"
  assert_success
  assert_output --partial "no drift"
  assert_equal "$stderr" ""
}

# --- section [1], the contract_canon opt-in -----------------------------------
# Same shape as the [4b] model canon checks above: byte-identity alone cannot
# see a stage that consistently carries a hand-written [1] instead of the
# shipped contract-reminder.md block.

@test "happy: the real contract-reminder.md block passes the canon check (contract_canon)" {
  # Built FROM the canon file, so it cannot rot when the text is reworded.
  python3 - "$WD/ccanon.jsonl" "skills/worktask/references/contract-reminder.md" <<'PYEOF'
import json, re, sys

out, canon = sys.argv[1], sys.argv[2]
body = open(canon).read()
sec = re.search(r"^```text\n(.*?)^```", body, re.S | re.M)
assert sec, "no fenced text block in " + canon
block = sec.group(1).rstrip("\n")
assert block, "the contract-reminder block is empty"

prompt = (
    "<<<contract-reminder>>>\n" + block + "\n"
    "<<<worktask-header>>>\nh\n"
    "<<<stage-contract>>>\nDV\n"
    "<<<task-description>>>\nwork"
)
with open(out, "w") as fh:
    fh.write(json.dumps({"worktask_id": "wtc2", "stage": "DV",
                         "contract_canon": True, "prompt": prompt}) + "\n")
PYEOF

  run_script_env --separate-stderr -- "$SCRIPT" "$WD/ccanon.jsonl"
  assert_success
  assert_output --partial "no drift"
  assert_equal "$stderr" ""
}

@test "failure: prefix-lint rejects a [1] mismatch when contract_canon is true" {
  cat > "$WD/ccanon-bad.jsonl" <<'EOF'
{"worktask_id":"wtc3","stage":"DV","contract_canon":true,"prompt":"<<<contract-reminder>>>\na hand-written reminder that does not match contract-reminder.md\n<<<worktask-header>>>\nh\n<<<stage-contract>>>\nDV\n<<<task-description>>>\nwork"}
EOF
  run_script_env --separate-stderr -- "$SCRIPT" "$WD/ccanon-bad.jsonl"
  assert_failure 1
  [[ "$stderr" == *"section [1] does not match contract-reminder.md"* ]]
  assert_output ""
}

@test "happy: a log line without a model field skips the canon check" {
  # Backwards compatibility is load-bearing, not politeness: every fixture in
  # this file predates the field, and a log captured before it existed must
  # stay lintable rather than fail as if its block were wrong.
  run_script_env --separate-stderr -- "$SCRIPT" "$WD/stable.jsonl"
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

# ---------------------------------------------------------------------------
# --anchor-lint against a body yq cannot parse (P2-2 / sw-DR0-2).
#
# extract_stage() used to fall back to awk only when yq was ABSENT, never when yq
# RAN AND FAILED. On any host with yq installed, an artifact whose body is ordinary
# markdown (a table, a `key: value` line) aborted the whole-file parse, the stage came
# back empty, and --anchor-lint reported "no stage in handoff frontmatter" and linted
# NOTHING — it failed OPEN. It cost QA0 all anchor coverage on this run.
#
# Mutation-verified: both arms below go red against that implementation (the first on
# exit code, the second on the diagnostic it prints). On a host with no yq the premise
# is vacuous and both arms pass either way, which is the correct behaviour, not coverage.
# ---------------------------------------------------------------------------

# A DV artifact carrying every required anchor under a body yq refuses to parse.
unparsable_dv_artifact() {
  local path="$1"
  cat > "$path" <<'EOF'
---
handoff:
  stage: DV
  verdict: ok
  summary: "anchors complete; body is markdown yq cannot read as YAML"
  refs: { dev: development.md#files-changed }
---

# Development

| Column | Meaning |
|--------|---------|
| `key` | value: a colon that aborts a whole-file YAML parse |

## files-changed

x

## tests-added

x

## deviations

none

## follow-ups

none

## elicitation-sweep

No items.
EOF
}

@test "anchor-lint: a body yq cannot parse still resolves its stage and passes on merit" {
  unparsable_dv_artifact "$WD/unparsable-ok.md"
  # Premise check: the whole-file parse the old extract_stage() used really does fail here.
  if command -v yq >/dev/null 2>&1; then
    run yq eval '.handoff.stage // ""' "$WD/unparsable-ok.md"
    assert_failure
  fi
  run_script_env --separate-stderr -- "$SCRIPT" --anchor-lint "$WD/unparsable-ok.md"
  assert_success
  assert_output --partial "stage=DV"
  assert_output --partial "ok"
  [[ "$stderr" != *"no stage in handoff frontmatter"* ]]
}

@test "anchor-lint: the same unparsable body is LINTED, not waved through (fail-open guard)" {
  unparsable_dv_artifact "$WD/unparsable-gap.md"
  # Remove one required anchor. A vacuous pass and a "no stage" bail both look like
  # "not ok"; only the anchor-level diagnostic proves the anchors were actually compared.
  grep -v '^## tests-added$' "$WD/unparsable-gap.md" > "$WD/unparsable-gap2.md"
  run_script_env --separate-stderr -- "$SCRIPT" --anchor-lint "$WD/unparsable-gap2.md"
  assert_failure 1
  [[ "$stderr" == *"(stage=DV) FAIL"* ]]
  [[ "$stderr" == *"missing: tests-added"* ]]
  [[ "$stderr" != *"no stage in handoff frontmatter"* ]]
}

@test "anchor-lint: a REAL absent stage is still reported as absent, not guessed at" {
  # The other half of the absent-vs-failed distinction: yq parses this frontmatter
  # cleanly and finds no stage. That is a genuine absence and must not be papered over
  # by the awk fallback, which would happily read the unrelated `stage:` line below.
  cat > "$WD/no-stage.md" <<'EOF'
---
handoff:
  verdict: ok
  summary: "no stage key under handoff"
  notes:
    stage: DV
---
# Development

## files-changed
EOF
  run_script_env --separate-stderr -- "$SCRIPT" --anchor-lint "$WD/no-stage.md"
  assert_failure 1
  [[ "$stderr" == *"no stage in handoff frontmatter"* ]]
}

# ---------------------------------------------------------------------------
# --agent-section-lint — the #16 letter-(b) cross-check.
# Guards the contradiction shape "an agent mandates an H2 that anchor_lint rejects",
# which no artifact author can satisfy. The extraction UNDER-matches by design (AD-6):
# a false negative is today's state, a false positive would block correct work.
# ---------------------------------------------------------------------------

mk_agent_repo() {   # $1 = agent basename, $2… = file body lines
  local base="$1"; shift
  mkdir -p "$WD/repo/agents"
  printf '%s\n' "$@" > "$WD/repo/agents/$base.md"
}

@test "agent-section-lint: an unlisted mandated section fails and names BOTH files" {
  mk_agent_repo developer \
    'Write the summary to `development-N.md` under `## not-an-anchor` please.'
  run bash "$PLUGIN_ROOT/$SCRIPT" --agent-section-lint "$WD/repo"
  assert_failure 1
  assert_output --partial "not-an-anchor"
  assert_output --partial "agents/developer.md"
  assert_output --partial "cache-lint.sh"
}

@test "agent-section-lint: a section on the stage's allow-list row passes" {
  mk_agent_repo developer \
    'Write the summary to `development-N.md` under `## files-changed` please.'
  run bash "$PLUGIN_ROOT/$SCRIPT" --agent-section-lint "$WD/repo"
  assert_success
  assert_output --partial "all mandated sections accepted"
}

@test "agent-section-lint: an OPTIONAL_ANCHOR_RE section passes (the ST/#16 case)" {
  mk_agent_repo stakeholder \
    'In retrospective-N.md, add a short `## Self-Improvement` section referencing it.'
  run bash "$PLUGIN_ROOT/$SCRIPT" --agent-section-lint "$WD/repo"
  assert_success
}

@test "agent-section-lint: a backticked H2 with no artifact filename is NOT matched" {
  mk_agent_repo developer \
    'Read one `## made-up-heading` section when the diff is insufficient.'
  run bash "$PLUGIN_ROOT/$SCRIPT" --agent-section-lint "$WD/repo"
  assert_success
}

@test "agent-section-lint: a placement word must be ADJACENT, not merely same-line" {
  # The exact shape of security-reviewer.md L65: an artifact filename, a stray ` as `,
  # and a `## X` span that is a cross-reference rather than a mandate.
  mk_agent_repo developer \
    'A path is read as `git diff` output; anchor-scoped `## anchor` reads, see `development-N.md`.'
  run bash "$PLUGIN_ROOT/$SCRIPT" --agent-section-lint "$WD/repo"
  assert_success
}

@test "agent-section-lint: a placeholder section name is dropped, never compared" {
  mk_agent_repo technical-lead \
    'A `## rework-N` section appearing in `development-N.md` re-opens the surface.'
  run bash "$PLUGIN_ROOT/$SCRIPT" --agent-section-lint "$WD/repo"
  assert_success
}

@test "agent-section-lint: sections written to a NON-artifact file are out of scope" {
  mk_agent_repo developer \
    'Append a `## Retry log` block to `.context/errors/developer.md` under the schema.'
  run bash "$PLUGIN_ROOT/$SCRIPT" --agent-section-lint "$WD/repo"
  assert_success
}

@test "agent-section-lint: the real tree satisfies the invariant (the DV2->DV3 gate)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --agent-section-lint "$PLUGIN_ROOT"
  assert_success
  assert_output --partial "13 stage agents checked"
}

@test "agent-section-lint: an empty agents/ dir is reported, never silently green" {
  mkdir -p "$WD/repo/agents"
  run bash "$PLUGIN_ROOT/$SCRIPT" --agent-section-lint "$WD/repo"
  assert_failure 1
  assert_output --partial "no stage agents found"
}

@test "--selftest is accepted as an alias for --self-test (the #16 contract command)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --selftest
  assert_success
  assert_output --partial "ALL PASS"
}

# --- --allow-list / --anchor-diff: the read-only core ------------------------

@test "allow-list: TSV rows per stage, sweep as universal, any-optional rows last" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --allow-list --stage QA
  assert_success
  assert_line "$(printf 'QA\tqa-engineer\ttesting\trequired\tresults')"
  assert_line "$(printf 'QA\tqa-engineer\ttesting\tuniversal\telicitation-sweep')"
  assert_line "$(printf 'QA\tqa-engineer\ttesting\toptional\tVisual Evidence')"
  [ "${lines[${#lines[@]}-1]}" = "$(printf '*\t\t\tany-optional\ttest-strategy')" ]
  run bash "$PLUGIN_ROOT/$SCRIPT" --allow-list
  assert_success
  [ "$(cut -f1 <<< "$output" | grep -v '^\*$' | sort -u | wc -l | tr -d ' ')" -eq 13 ]
}

@test "allow-list: an unknown stage exits 2" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --allow-list --stage ZZ
  assert_failure 2
}

@test "anchor-diff: missing rows in allow-list order, unexpected in document order, fences skipped" {
  printf '## Zeta\n```\n## fenced\n```\n## files-changed\n## Alpha\n## Zeta\n' > "$WD/d.md"
  run bash "$PLUGIN_ROOT/$SCRIPT" --anchor-diff --stage DV "$WD/d.md"
  assert_failure 1
  [ "$output" = "$(printf 'missing\ttests-added\nmissing\tdeviations\nmissing\tfollow-ups\nmissing\telicitation-sweep\nunexpected\tZeta\nunexpected\tAlpha')" ]
}

@test "anchor-diff: --for-path resolves only an exact canonical basename" {
  printf '## results\n' > "$WD/d.md"
  run bash "$PLUGIN_ROOT/$SCRIPT" --anchor-diff --for-path /x/.context/testing-4.md "$WD/d.md"
  assert_failure 1
  assert_output --partial "missing	coverage"
  for p in /x/.context/testing.md /x/.context/testing-4-ui.md /x/.context/arch-0.md; do
    run bash "$PLUGIN_ROOT/$SCRIPT" --anchor-diff --for-path "$p" "$WD/d.md"
    assert_failure 2
  done
}

@test "anchor-diff: --baseline headings are never unexpected; stdin is accepted" {
  printf '## Notes\n' > "$WD/base.md"
  run bash -c 'printf "## Notes\n## Extra\n" | bash "$1" --anchor-diff --stage QA --baseline "$2" -' _ "$PLUGIN_ROOT/$SCRIPT" "$WD/base.md"
  assert_failure 1
  refute_output --partial "unexpected	Notes"
  assert_output --partial "unexpected	Extra"
}

@test "anchor-diff: a clean artifact exits 0 with no rows; usage errors exit 2" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --anchor-diff --stage DV "$WD/development-0.md"
  assert_success
  assert_output ""
  run bash "$PLUGIN_ROOT/$SCRIPT" --anchor-diff "$WD/development-0.md"
  assert_failure 2
  run bash "$PLUGIN_ROOT/$SCRIPT" --anchor-diff --stage DV --for-path x/.context/testing-0.md "$WD/development-0.md"
  assert_failure 2
  run bash "$PLUGIN_ROOT/$SCRIPT" --anchor-diff --stage DV "$WD/nope.md"
  assert_failure 2
}

@test "optional: title-case optionals are scoped to their owning stage" {
  cp "$FIXTURES/worktask/anchors/developer-review-0.md" "$WD/dr.md"
  printf '\n## Blockers\n\nx\n' >> "$WD/dr.md"
  run_script_env --separate-stderr -- "$SCRIPT" --anchor-lint "$WD/dr.md"
  assert_failure 1
  [[ "$stderr" == *"unexpected: Blockers"* ]]
  cp "$FIXTURES/worktask/anchors/development-0.md" "$WD/dv.md"
  printf '\n## Blockers\n\nx\n\n## rework-2\n\nx\n' >> "$WD/dv.md"
  run_script_env --separate-stderr -- "$SCRIPT" --anchor-lint "$WD/dv.md"
  assert_success
}

# team-lead.md logs a rejected TC under coordination-N.md § Blockers.
@test "optional: TL may carry ## Blockers in coordination-0.md" {
  cp "$FIXTURES/worktask/anchors/coordination-0.md" "$WD/coordination-0.md"
  printf '\n## Blockers\n\nx\n' >> "$WD/coordination-0.md"
  run_script_env --separate-stderr -- "$SCRIPT" --anchor-lint "$WD/coordination-0.md"
  assert_success
  run bash "$PLUGIN_ROOT/$SCRIPT" --anchor-diff --for-path x/.context/coordination-0.md "$WD/coordination-0.md"
  assert_success
  assert_output ""
}

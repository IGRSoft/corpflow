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

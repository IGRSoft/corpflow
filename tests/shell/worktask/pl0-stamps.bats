#!/usr/bin/env bats
# Contract tests for what /worktask Step 4 stamps on PL0 (commands/worktask.md):
#   - PL0's model/effort pair comes from model-matrix.sh --resolve, never a typed alias,
#     and /megatask's per-issue PL0 stamp (commands/megatask.md Phase 2 Step 3) does the same;
#   - that stamp rides a background general-purpose subagent running the corpflow:worktask
#     skill, which the command is granted and whose stop the SubagentStop monitor sees;
#   - `--with-design` stamps `with_design: true`, the key the Designer gate in
#     skills/worktask/references/pl0-procedure.md § Designer Invocation reads.
#
# The stamp is an orchestrator action, so nothing here runs the orchestrator. What is
# proven is the composition: the payload and key written in the doc, applied with the
# real state-patch.sh, satisfy the reader extracted from its own file. Every extraction
# is guarded so an empty match fails instead of passing vacuously.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

WORKTASK_DOC="commands/worktask.md"
MEGATASK_DOC="commands/megatask.md"
PL0_DOC="skills/worktask/references/pl0-procedure.md"
LEDGER_DOC="skills/shared/state-ledger.md"
PATCH_SCRIPT="skills/worktask/scripts/state-patch.sh"
RESOLVER="skills/worktask/scripts/model-matrix.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  export WORKSPACE_ROOT="$WD"
  mk_state_fixture "$WD/.context/state.json" \
    '.version = 2' \
    '.tasks.PL0 = {"status":"pending","metadata":{"stage":"PL"}}' \
    > /dev/null
}

# section <file> <heading> — the heading line plus its body up to the next heading.
section() {
  awk -v h="$2" '$0 == h {f=1; print; next} f && /^#/ {exit} f {print}' "$PLUGIN_ROOT/$1"
}

# The Step 4 payload with placeholders left in; empty when the stamp is gone.
step4_payload() {
  section "$WORKTASK_DOC" "### Step 4 — attach PL0 metadata" \
    | sed -n "s/.*task-meta PL0 --set '\([^']*\)'.*/\1/p" | head -1
}

@test "PL0 pair: Step 4 types no model alias; the resolver's pair lands on the ledger" {
  local payload pair model effort filled
  payload="$(step4_payload)"
  [ -n "$payload" ] || fail "no task-meta PL0 payload under Step 4 of $WORKTASK_DOC"
  [ "$(printf '%s' "$payload" | jq -r '.model')" = "<model>" ] \
    || fail "Step 4 stamps a literal model instead of the resolved <model>: $payload"
  [ "$(printf '%s' "$payload" | jq -r '.effort')" = "<effort>" ] \
    || fail "Step 4 stamps no resolved <effort>: $payload"
  section "$WORKTASK_DOC" "#### Step 4 — PL0's model and effort" \
    | grep -qF "$RESOLVER --resolve product-manager" \
    || fail "Step 4 no longer names '$RESOLVER --resolve product-manager'"

  cd "$WD"
  pair="$(bash "$PLUGIN_ROOT/$RESOLVER" --resolve product-manager)"
  model="$(printf '%s' "$pair" | cut -f1)"
  effort="$(printf '%s' "$pair" | cut -f2)"
  [ -n "$model" ] && [ -n "$effort" ] || fail "resolver printed no pair: [$pair]"
  filled="$(printf '%s' "$payload" | jq -c --arg m "$model" --arg e "$effort" '.model = $m | .effort = $e')"
  run bash "$PLUGIN_ROOT/$PATCH_SCRIPT" --task-meta PL0 --set "$filled"
  assert_success
  run jq -r '.tasks.PL0.metadata | "\(.model) \(.effort)"' .context/state.json
  assert_output "$model $effort"
}

@test "PL0 pair: /megatask's per-issue stamp takes the resolver's pair and holds the grant" {
  local stamp grant
  stamp="$(section "$MEGATASK_DOC" "### Phase 2 loop · Step 3 — Launch the per-issue worktask")"
  [ -n "$stamp" ] || fail "no Phase 2 Step 3 section in $MEGATASK_DOC"
  printf '%s' "$stamp" | grep -qF 'model:"<model>", effort:"<effort>"' \
    || fail "megatask Step 3 stamps no resolved model/effort pair"
  run grep -nE 'model: ?"(opus|sonnet|haiku|fable)"' <<< "$stamp"
  assert_failure
  section "$MEGATASK_DOC" "#### Step 3 — PL0's model and effort" \
    | grep -qF "$RESOLVER --resolve product-manager" \
    || fail "megatask Step 3 no longer names '$RESOLVER --resolve product-manager'"
  grant="$(sed -n 's/^allowed-tools: //p' "$PLUGIN_ROOT/$MEGATASK_DOC")"
  printf '%s' "$grant" | grep -qF "Bash(bash \${CLAUDE_PLUGIN_ROOT}/$RESOLVER --resolve *)" \
    || fail "$MEGATASK_DOC does not grant '$RESOLVER --resolve'"
}

@test "launch: /megatask Step 3 names the general-purpose subagent + worktask skill and holds the grant" {
  local step3 grant
  step3="$(section "$MEGATASK_DOC" "### Phase 2 loop · Step 3 — Launch the per-issue worktask")"
  [ -n "$step3" ] || fail "no Phase 2 Step 3 section in $MEGATASK_DOC"
  printf '%s' "$step3" | grep -qF 'background `general-purpose` subagent' \
    || fail "megatask Step 3 does not name the background general-purpose subagent"
  printf '%s' "$step3" | grep -qF '`corpflow:worktask` skill' \
    || fail "megatask Step 3 does not name the corpflow:worktask skill"
  printf '%s' "$step3" | grep -qF '`SubagentStop`' \
    || fail "megatask Step 3 no longer says why a subagent (SubagentStop monitor)"
  grant="$(sed -n 's/^allowed-tools: //p' "$PLUGIN_ROOT/$MEGATASK_DOC")"
  [ -n "$grant" ] || fail "$MEGATASK_DOC has no allowed-tools line"
  printf '%s' "$grant" | grep -qE '(^|, )Task\(general-purpose\)(,|$)' \
    || fail "$MEGATASK_DOC does not grant Task(general-purpose)"
  # The monitor the launch relies on must actually be on SubagentStop.
  jq -e '.hooks.SubagentStop[].hooks[].command | select(endswith("/hooks/megatask-monitor.sh"))' \
    "$PLUGIN_ROOT/.claude-plugin/plugin.json" >/dev/null \
    || fail "megatask-monitor.sh is not registered on SubagentStop"
}

@test "with_design: --with-design stamps the key the Designer gate reads" {
  local row reader
  row="$(section "$WORKTASK_DOC" "#### Step 4 — option-flag stamping" \
    | grep -F '`with_design: true`' | grep -F '`--with-design`')" || true
  [ -n "$row" ] || fail "Step 4 has no with_design row keyed to --with-design"
  reader="$(section "$PL0_DOC" "#### Designer Invocation" \
    | grep -o 'PL0\.metadata\.with_design == true')" || true
  [ -n "$reader" ] || fail "$PL0_DOC § Designer Invocation no longer reads PL0.metadata.with_design"

  cd "$WD"
  run bash "$PLUGIN_ROOT/$PATCH_SCRIPT" --task-meta PL0 --set '{"with_design":true}'
  assert_success
  run jq -r '.tasks.PL0.metadata.with_design == true' .context/state.json
  assert_output "true"
}

@test "with_design: the ledger doc names a writer, not an absent one" {
  run grep -n 'No component stamps' "$PLUGIN_ROOT/$LEDGER_DOC"
  assert_failure
  grep -qE '^\| `with_design` \| `--with-design`' "$PLUGIN_ROOT/$LEDGER_DOC" \
    || fail "$LEDGER_DOC § PL0 option fields has no with_design row"
}

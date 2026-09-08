#!/usr/bin/env bash
# state-patch-selftest.sh — the `--self-test` harness for state-patch.sh.
#
# SOURCED, never executed: state-patch.sh loads this file only on the
# `--self-test` path, so the ledger-write path never pays for it. Sourcing
# leaves `$0` pointing at state-patch.sh, which the harness depends on: every
# case re-invokes the caller through `bash "$SELF"`, and `SELF` is rebuilt from
# `$0`. Do not rewrite that against BASH_SOURCE.
#
# Contract: defines exactly one function, `run_self_test`, which owns the exit
# for this invocation (0 on ALL PASS, 1 on the first failing case).

run_self_test() {
  # Resolve path BEFORE any cd so subprocess calls work.
  local SELF
  SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")

  local td
  td=$(mktemp -d -t state-patch-selftest-XXXXXX)
  # shellcheck disable=SC2064   # expand $td now so the trap removes the right dir
  trap "rm -rf '${td}'" EXIT

  cd "$td"
  mkdir -p .context/logs

  # ---- Fixture helpers ----
  make_state() {
    cat > .context/state.json << 'EOSTATE'
{"version":2,"worktask_id":"selftest","plan_file":".context/planning-0.md","platform":"all","run_index":0,"tasks":{"PL0":{"status":"completed","verdict":"ok"}},"facts":{"files_modified":[],"tests_added":[],"decisions":[],"open_questions":[],"verdicts":{"PL":"ok"}},"handoffs":{}}
EOSTATE
  }

  # ---- T1: explicit --artifact path, frontmatter present ----
  make_state
  cat > .context/development-0.md << 'EOART'
---
handoff:
  stage: DV
  verdict: ok
  summary: "self-test artifact T1"
  files_touched: [a.md]
  next_stage_focus: "DR reviews"
  refs: { dev: development.md#files-changed }
---

# Development
EOART
  bash "$SELF" --stage DV --artifact .context/development-0.md \
    || {
      printf 'T1: state-patch returned non-zero\n' >&2
      exit 1
    }
  if jq -e '.tasks.DV0.status == "completed" and .tasks.DV0.verdict == "ok"' \
    .context/state.json > /dev/null; then
    printf 'T1: explicit artifact → patched: ok\n'
  else
    printf 'T1: explicit artifact → patch missing: FAIL\n' >&2
    exit 1
  fi

  # ---- T2: idempotency — re-run must leave state.json byte-identical ----
  cp .context/state.json .context/state.json.snap
  bash "$SELF" --stage DV --artifact .context/development-0.md
  if diff -q .context/state.json .context/state.json.snap > /dev/null; then
    printf 'T2: idempotent re-run: ok\n'
  else
    printf 'T2: idempotent re-run: FAIL (state changed)\n' >&2
    exit 1
  fi

  # ---- T3: no --artifact, resolve via run_index=0 from state.json ----
  make_state
  # development-0.md already exists from T1.
  bash "$SELF" --stage DV \
    || {
      printf 'T3: state-patch returned non-zero\n' >&2
      exit 1
    }
  if jq -e '.tasks.DV0.status == "completed" and (.tasks.DV0.artifact | endswith("development-0.md"))' \
    .context/state.json > /dev/null; then
    printf 'T3: run_index-resolved artifact: ok\n'
  else
    printf 'T3: run_index-resolved artifact: FAIL\n' >&2
    exit 1
  fi

  # ---- T4: highest-N fallback when run_index absent from state.json ----
  cat > .context/state.json << 'EOSTATE'
{"version":2,"worktask_id":"selftest","plan_file":".context/planning-0.md","platform":"all","tasks":{"PL0":{"status":"completed","verdict":"ok"}},"facts":{"verdicts":{"PL":"ok"}},"handoffs":{}}
EOSTATE
  cat > .context/architecture-1.md << 'EOART'
---
handoff:
  stage: AR
  verdict: blocked
  summary: "highest-N artifact"
  refs: { plan: planning-0.md#requirements }
---
EOART
  cat > .context/architecture-0.md << 'EOART'
---
handoff:
  stage: AR
  verdict: ok
  summary: "lower-N artifact"
  refs: { plan: planning-0.md#requirements }
---
EOART
  bash "$SELF" --stage AR \
    || {
      printf 'T4: state-patch returned non-zero\n' >&2
      exit 1
    }
  if jq -e '.tasks.AR0.verdict == "blocked" and (.tasks.AR0.artifact | endswith("architecture-1.md"))' \
    .context/state.json > /dev/null; then
    printf 'T4: highest-N wins when run_index absent: ok\n'
  else
    printf 'T4: highest-N resolution: FAIL\n' >&2
    jq '.tasks.AR0' .context/state.json >&2
    exit 1
  fi

  # ---- T5: absent artifact → no-op, state unchanged ----
  cat > .context/state.json << 'EOSTATE'
{"version":2,"worktask_id":"selftest","plan_file":".context/planning-0.md","platform":"all","tasks":{"PL0":{"status":"completed","verdict":"ok"}},"facts":{"verdicts":{"PL":"ok"}},"handoffs":{}}
EOSTATE
  cp .context/state.json .context/state.json.snap2
  # No QA artifact exists.
  bash "$SELF" --stage QA \
    || {
      printf 'T5: state-patch returned non-zero\n' >&2
      exit 1
    }
  if diff -q .context/state.json .context/state.json.snap2 > /dev/null; then
    printf 'T5: absent artifact → no-op: ok\n'
  else
    printf 'T5: absent artifact → no-op: FAIL (state changed)\n' >&2
    exit 1
  fi

  # ---- T6: disk guard — warn threshold only (no halt) ----
  # We can't safely drop disk space in a test, so we prove the guard degrades
  # gracefully when df output is unparseable (empty avail_gb).
  make_state
  cat > .context/testing-0.md << 'EOART'
---
handoff:
  stage: QA
  verdict: go
  summary: "disk guard T6"
  refs: { dev: development-0.md#files-changed }
---
EOART
  bash "$SELF" --stage QA --artifact .context/testing-0.md --disk-check /nonexistent_mountpoint_selftest \
    || {
      printf 'T6: disk-guard degrade: non-zero exit\n' >&2
      exit 1
    }
  if jq -e '.tasks.QA0.status == "completed"' .context/state.json > /dev/null; then
    printf 'T6: disk-guard degrade on unparseable df → patch applied: ok\n'
  else
    printf 'T6: disk-guard degrade: FAIL\n' >&2
    exit 1
  fi

  # ---- T8: --prev writes handoffs["PREV→TASK_ID"] from the parsed summary + ref ----
  make_state
  cat > .context/architecture-0.md << 'EOART'
---
handoff:
  stage: AR
  verdict: ok
  summary: "approach validated; DV split confirmed"
  refs: { plan: planning-0.md#requirements }
---
EOART
  bash "$SELF" --stage AR --prev PL --artifact .context/architecture-0.md \
    || {
      printf 'T8: state-patch returned non-zero\n' >&2
      exit 1
    }
  if jq -e '(.handoffs["PL→AR0"] // "") | test("approach validated") and test("ref:architecture-0.md")' \
    .context/state.json > /dev/null; then
    printf 'T8: --prev writes handoffs edge from summary+ref: ok\n'
  else
    printf 'T8: --prev handoffs edge: FAIL\n' >&2
    jq '.handoffs' .context/state.json >&2
    exit 1
  fi
  # Absent --prev must NOT synthesize a handoffs edge (byte-stable default path).
  make_state
  bash "$SELF" --stage AR --artifact .context/architecture-0.md
  if jq -e '(.handoffs | length) == 0' .context/state.json > /dev/null; then
    printf 'T8: absent --prev leaves handoffs untouched: ok\n'
  else
    printf 'T8: absent --prev must not add handoffs: FAIL\n' >&2
    exit 1
  fi

  # ---- T10: remediation re-merge — same verdict, new summary must refresh the handoff edge ----
  make_state
  cat > .context/development-0.md << 'EOART'
---
handoff:
  stage: DV
  verdict: ok
  summary: "first pass, pre-review"
  refs: { dev: development.md#files-changed }
---
EOART
  bash "$SELF" --stage DV --prev AR --artifact .context/development-0.md \
    || {
      printf 'T10: state-patch returned non-zero (round 1)\n' >&2
      exit 1
    }
  cat > .context/development-0.md << 'EOART'
---
handoff:
  stage: DV
  verdict: ok
  summary: "remediated after DR round 1"
  refs: { dev: development.md#files-changed }
---
EOART
  bash "$SELF" --stage DV --prev AR --artifact .context/development-0.md \
    || {
      printf 'T10: state-patch returned non-zero (round 2)\n' >&2
      exit 1
    }
  if jq -e '(.handoffs["AR→DV0"] // "") | test("remediated after DR round 1")' \
    .context/state.json > /dev/null; then
    printf 'T10: same-verdict remediation refreshes handoff edge: ok\n'
  else
    printf 'T10: same-verdict remediation left a stale handoff edge: FAIL\n' >&2
    jq '.handoffs' .context/state.json >&2
    exit 1
  fi
  # A third identical run must still be a byte-identical no-op (T2 invariant preserved).
  cp .context/state.json .context/state.before
  bash "$SELF" --stage DV --prev AR --artifact .context/development-0.md
  if cmp -s .context/state.json .context/state.before; then
    printf 'T10: unchanged re-run stays idempotent: ok\n'
  else
    printf 'T10: unchanged re-run must not rewrite state: FAIL\n' >&2
    exit 1
  fi

  # ---- T9: B3 bounds — decisions clamp to newest-8 PER TASK, dispatched_agents to 6 ----
  # Seed 10 PL0 decisions + 10 AR0 decisions + 8 dispatched_agents (mix launched/completed),
  # then patch any stage; atomic_merge must clamp at the single chokepoint, and the two
  # decision buckets must survive each other — a global ring keeps 8 of the 20 in total.
  jq -n '
    {version:2, worktask_id:"selftest", plan_file:".context/planning-0.md",
     platform:"all", run_index:0,
     tasks:{PL0:{status:"completed", verdict:"ok", metadata:{}}},
     facts:{
       files_modified:[], tests_added:[], open_questions:[], verdicts:{PL:"ok"},
       decisions:(
         [ range(0;10) | {id:("d"+(.|tostring)), summary:("dec "+(.|tostring)),
                          ref:"x.md#y", stage:"PL0"} ]
       + [ range(0;10) | {id:("a"+(.|tostring)), summary:("arc "+(.|tostring)),
                          ref:"x.md#y", stage:"AR0"} ]),
       dispatched_agents:(
         [ range(0;6) | {stage:"DV", task_id:("t"+(.|tostring)), subagent_type:"a", status:"completed"} ]
         + [ range(6;8) | {stage:"DV", task_id:("t"+(.|tostring)), subagent_type:"a", status:"launched"} ])
     },
     handoffs:{}}' > .context/state.json
  bash "$SELF" --stage DV --artifact .context/development-0.md \
    || {
      printf 'T9: state-patch returned non-zero\n' >&2
      exit 1
    }
  if jq -e '(.facts.decisions | length) == 16
            and ([.facts.decisions[] | select(.stage == "PL0") | .id] == ["d2","d3","d4","d5","d6","d7","d8","d9"])
            and ([.facts.decisions[] | select(.stage == "AR0") | .id] == ["a2","a3","a4","a5","a6","a7","a8","a9"])' \
    .context/state.json > /dev/null; then
    printf 'T9: facts.decisions clamped to newest-8 per task, both buckets survive: ok\n'
  else
    printf 'T9: decisions bound: FAIL\n' >&2
    jq '.facts.decisions | map(.id)' .context/state.json >&2
    exit 1
  fi
  if jq -e '(.facts.dispatched_agents | length) == 6 and ([.facts.dispatched_agents[] | select(.status == "launched")] | length) == 2' \
    .context/state.json > /dev/null; then
    printf 'T9: dispatched_agents clamped to 6, launched survive: ok\n'
  else
    printf 'T9: dispatched_agents bound: FAIL\n' >&2
    jq '.facts.dispatched_agents | map({task_id, status})' .context/state.json >&2
    exit 1
  fi

  # ---- T11: alias basename resolves; canonical still wins when both exist ----
  make_state
  rm -f .context/testing-*.md .context/qa-*.md
  cat > .context/qa-0.md << 'EOART'
---
handoff:
  stage: QA
  verdict: go
  summary: "alias-named artifact"
  refs: { dev: development-0.md#files-changed }
---
EOART
  bash "$SELF" --stage QA \
    || {
      printf 'T11: state-patch returned non-zero\n' >&2
      exit 1
    }
  if jq -e '.tasks.QA0.status == "completed" and (.tasks.QA0.artifact | endswith("qa-0.md"))' \
    .context/state.json > /dev/null; then
    printf 'T11: alias basename resolves: ok\n'
  else
    printf 'T11: alias basename resolution: FAIL\n' >&2
    exit 1
  fi
  make_state
  cat > .context/testing-0.md << 'EOART'
---
handoff:
  stage: QA
  verdict: go
  summary: "canonical artifact"
  refs: { dev: development-0.md#files-changed }
---
EOART
  bash "$SELF" --stage QA
  if jq -e '(.tasks.QA0.artifact | endswith("testing-0.md"))' .context/state.json > /dev/null; then
    printf 'T11: canonical preferred over alias: ok\n'
  else
    printf 'T11: canonical must outrank alias: FAIL\n' >&2
    exit 1
  fi
  rm -f .context/qa-0.md

  # ---- T12: self-patch (--prev, no --via) with no artifact ⇒ exit 3, state unchanged ----
  make_state
  rm -f .context/retrospective-*.md
  cp .context/state.json .context/state.json.snap3
  set +e
  st12_out=$(bash "$SELF" --stage ST --prev FN 2>&1)
  st12_rc=$?
  set -e
  if [[ "$st12_rc" -eq 3 ]] && printf '%s' "$st12_out" | grep -q 'retrospective-N.md'; then
    printf 'T12: unresolved self-patch exits 3 naming the basenames: ok\n'
  else
    printf 'T12: unresolved self-patch must exit 3 (got %s): FAIL\n' "$st12_rc" >&2
    exit 1
  fi
  if diff -q .context/state.json .context/state.json.snap3 > /dev/null; then
    printf 'T12: exit 3 leaves state untouched: ok\n'
  else
    printf 'T12: exit 3 must not alter state: FAIL\n' >&2
    exit 1
  fi
  # The hook path (--via) keeps the exit-0 no-op contract even with --prev present.
  set +e
  bash "$SELF" --stage ST --prev FN --via hook > /dev/null 2>&1
  st12b_rc=$?
  set -e
  if [[ "$st12b_rc" -eq 0 ]]; then
    printf 'T12: --via keeps the unresolved no-op at exit 0: ok\n'
  else
    printf 'T12: --via must not fail loudly (got %s): FAIL\n' "$st12b_rc" >&2
    exit 1
  fi

  # ---- T13: --prev USER writes the origin edge ----
  make_state
  cat > .context/planning-0.md << 'EOART'
---
handoff:
  stage: PL
  verdict: ok
  summary: "origin edge from the user"
  refs: { plan: planning-0.md#requirements }
---
EOART
  bash "$SELF" --stage PL --prev USER --artifact .context/planning-0.md \
    || {
      printf 'T13: state-patch returned non-zero\n' >&2
      exit 1
    }
  if jq -e '(.handoffs["USER→PL0"] // "") | test("origin edge from the user")' \
    .context/state.json > /dev/null; then
    printf 'T13: --prev USER writes the USER→PL0 edge: ok\n'
  else
    printf 'T13: --prev USER edge: FAIL\n' >&2
    jq '.handoffs' .context/state.json >&2
    exit 1
  fi

  # ---- Fixture for T15: the ledger shape the split-stage cases resolve against ----
  # The ledger-op ASSERTIONS that used to live here (create / duplicate-create /
  # bare create / block union / unblock / unblock no-op / malformed id / unknown
  # id) moved to state-patch.bats — the seven "ledger ops:" arms. Only the state
  # they left behind is kept, because T15 reads it and never seeds its own.
  make_state
  bash "$SELF" --task-create DV0 --metadata '{"stage":"DV","agent":"corpflow:developer"}' \
    && bash "$SELF" --task-create DV1 --metadata '{"stage":"DV","agent":"corpflow:developer"}' \
    && bash "$SELF" --task-create DR0 --metadata '{"stage":"DR","agent":"corpflow:technical-lead"}' \
    && bash "$SELF" --task-block DR0 --on DV0,DV1 \
    && bash "$SELF" --task-create QA0 \
    && bash "$SELF" --task-unblock DR0 --off DV1 \
    && bash "$SELF" --task-status DV0 in_progress \
    || {
      printf 'T15 fixture: ledger op returned non-zero\n' >&2
      exit 1
    }
  # ---- T15: split-stage id resolution (the case bare stage codes could not express) ----
  # DV0 in_progress + DV1 pending: the running instance outranks the queued one, so a
  # bare --stage DV cannot stamp the higher-numbered track that has not started.
  t15_id=$(bash "$SELF" --resolve-task-id DV)
  if [[ "$t15_id" == "DV0" ]]; then
    printf 'T15: in_progress instance outranks pending: ok\n'
  else
    printf 'T15: in_progress must win (got %s): FAIL\n' "$t15_id" >&2
    jq '.tasks' .context/state.json >&2
    exit 1
  fi

  bash "$SELF" --task-status DV0 completed > /dev/null
  t15_id=$(bash "$SELF" --resolve-task-id DV)
  if [[ "$t15_id" == "DV1" ]]; then
    printf 'T15: settled instance yields to the pending one: ok\n'
  else
    printf 'T15: pending must win once DV0 settles (got %s): FAIL\n' "$t15_id" >&2
    exit 1
  fi
  cat > .context/development-0.md << 'EOSPLIT'
---
handoff:
  stage: DV
  verdict: ok
  summary: "second track"
---
EOSPLIT
  bash "$SELF" --stage DV --via step6_5 \
    || {
      printf 'T15: state-patch returned non-zero\n' >&2
      exit 1
    }
  if jq -e '.tasks.DV1.status == "completed" and .tasks.DV1.verdict == "ok"
            and (.tasks.DV0.artifact // "") == ""' .context/state.json > /dev/null; then
    printf 'T15: --stage resolves to the open split instance: ok\n'
  else
    printf 'T15: split-stage resolution: FAIL\n' >&2
    jq '.tasks' .context/state.json >&2
    exit 1
  fi

  bash "$SELF" --stage DV --task-id DV0 --via step6_5 > /dev/null
  if jq -e '(.tasks.DV0.artifact // "") | endswith("development-0.md")' \
    .context/state.json > /dev/null; then
    printf 'T15: explicit --task-id overrides resolution: ok\n'
  else
    printf 'T15: --task-id override: FAIL\n' >&2
    exit 1
  fi

  # ---- T15b/c/d/e: artifact-first resolution for a genuinely ambiguous split stage ----
  # T15 above only ever has ONE open instance, so it passes with or without the artifact
  # tier — which is how the mis-slotting defect stayed invisible.  These four put two
  # `in_progress` instances in the ledger, the shape a fanned-out DV run actually has.
  cat > .context/state.json << 'EOSTATE'
{"version":2,"worktask_id":"selftest","plan_file":".context/planning-0.md","platform":"all","run_index":0,"tasks":{"DV0":{"status":"in_progress","metadata":{"artifact":".context/development-0-gate.md"}},"DV1":{"status":"in_progress","metadata":{"artifact":".context/development-0-ledger.md"}}},"facts":{},"handoffs":{}}
EOSTATE
  t15b_id=$(bash "$SELF" --resolve-task-id DV --artifact .context/development-0-ledger.md)
  if [[ "$t15b_id" == "DV1" ]]; then
    printf 'T15b: --artifact picks the matching instance out of two in_progress: ok\n'
  else
    printf 'T15b: artifact-first resolution (got %s, want DV1): FAIL\n' "$t15b_id" >&2
    exit 1
  fi

  # Absolute and ./-prefixed callers must land on the same key as the stored relative path.
  t15e_id=$(bash "$SELF" --resolve-task-id DV --artifact "$PWD/.context/development-0-ledger.md")
  t15e_id2=$(bash "$SELF" --resolve-task-id DV --artifact ./.context/development-0-ledger.md)
  if [[ "$t15e_id" == "DV1" && "$t15e_id2" == "DV1" ]]; then
    printf 'T15e: absolute and ./-prefixed artifacts resolve like the relative one: ok\n'
  else
    printf 'T15e: path normalisation (abs=%s dot=%s, want DV1): FAIL\n' "$t15e_id" "$t15e_id2" >&2
    exit 1
  fi

  # The recorded artifact beats another instance's PLANNED one: PL0 seeds metadata from the
  # plan, and a split stage routinely writes a file the plan did not predict.
  jq '.tasks.DV0.artifact = ".context/development-1.md"
      | .tasks.DV1.metadata.artifact = ".context/development-1.md"' \
    .context/state.json > .context/state.json.t15f && mv .context/state.json.t15f .context/state.json
  t15f_id=$(bash "$SELF" --resolve-task-id DV --artifact .context/development-1.md)
  if [[ "$t15f_id" == "DV0" ]]; then
    printf 'T15f: recorded artifact outranks a stale planned one: ok\n'
  else
    printf 'T15f: recorded-before-planned precedence (got %s, want DV0): FAIL\n' "$t15f_id" >&2
    exit 1
  fi

  # No discriminator: refuse, name both candidates, and leave the ledger byte-identical.
  cat > .context/state.json << 'EOSTATE'
{"version":2,"worktask_id":"selftest","plan_file":".context/planning-0.md","platform":"all","run_index":0,"tasks":{"DV0":{"status":"in_progress"},"DV1":{"status":"in_progress"}},"facts":{},"handoffs":{}}
EOSTATE
  cp .context/state.json .context/state.json.snap15c
  t15c_rc=0
  t15c_err=$(bash "$SELF" --stage DV --artifact .context/development-0.md --via step6_5 2>&1 > /dev/null) \
    || t15c_rc=$?
  if [[ "$t15c_rc" == "4" ]] \
    && printf '%s' "$t15c_err" | grep -q 'DV0,DV1' \
    && diff -q .context/state.json .context/state.json.snap15c > /dev/null; then
    printf 'T15c: ambiguous stage refuses with exit 4, both named, state byte-unchanged: ok\n'
  else
    printf 'T15c: ambiguity must fail closed (rc=%s err=%s): FAIL\n' "$t15c_rc" "$t15c_err" >&2
    exit 1
  fi
  rm -f .context/state.json.snap15c

  # T15d is the hooks/agent-stop.sh regression guard: one open instance, no --artifact,
  # behaviour identical to before the artifact tier existed.
  cat > .context/state.json << 'EOSTATE'
{"version":2,"worktask_id":"selftest","plan_file":".context/planning-0.md","platform":"all","run_index":0,"tasks":{"DV0":{"status":"in_progress"},"DV1":{"status":"pending"}},"facts":{},"handoffs":{}}
EOSTATE
  t15d_id=$(bash "$SELF" --resolve-task-id DV)
  t15d_rc=0
  bash "$SELF" --stage DV --via step6_5 > /dev/null 2>&1 || t15d_rc=$?
  if [[ "$t15d_id" == "DV0" && "$t15d_rc" == "0" ]] \
    && jq -e '.tasks.DV0.status == "completed" and .tasks.DV1.status == "pending"' \
      .context/state.json > /dev/null; then
    printf 'T15d: bare --stage with one open instance is unchanged: ok\n'
  else
    printf 'T15d: bare --stage regression (id=%s rc=%s): FAIL\n' "$t15d_id" "$t15d_rc" >&2
    exit 1
  fi

  # ---- T18: --task-replay resets one task, and refuses while its agent is alive ----
  # Liveness is fixture-injected so the self-test needs no live agent and no claude CLI.
  make_state
  rm -f .context/logs/audit.jsonl
  printf '[]\n' > agents-gone.json
  printf '%s\n' '[{"id":"sess-dv0","sessionId":"sess-dv0deadbeef","name":"dv","state":"active"}]' \
    > agents-busy.json
  bash "$SELF" --task-create DV0 \
    --metadata '{"stage":"DV","agent":"corpflow:developer","retry_count":3,"error_escalated_to":"AR"}' \
    > /dev/null
  bash "$SELF" --task-status DV0 in_progress > /dev/null
  # An in_progress task with no dispatch row classifies no-dispatch-record, which the guard
  # (correctly) refuses — absence of a record proves nothing about liveness. Seed one.
  jq '.facts.dispatched_agents = [{stage:"DV", task_id:"DV0",
        subagent_type:"corpflow:developer", agent_id:"sess-dv0", status:"launched"}]' \
    .context/state.json > .context/state.next && mv .context/state.next .context/state.json
  bash "$SELF" --task-replay DV0 --agents-json agents-gone.json 2> /dev/null \
    || {
      printf 'T18: --task-replay returned non-zero\n' >&2
      exit 1
    }
  if jq -e '.tasks.DV0.status == "pending"
            and (.tasks.DV0.metadata | has("retry_count") | not)
            and (.tasks.DV0.metadata | has("error_escalated_to") | not)
            and .tasks.PL0.status == "completed"' .context/state.json > /dev/null; then
    printf 'T18: replay resets the target and leaves PL0 alone: ok\n'
  else
    printf 'T18: replay blast radius: FAIL\n' >&2
    jq '.tasks' .context/state.json >&2
    exit 1
  fi
  if jq -e 'select(.action == "stage_replay")
            | .task_id == "DV0" and .metadata.escalation_cap_override == true' \
    .context/logs/audit.jsonl > /dev/null; then
    printf 'T18: replay audits the cap override on success: ok\n'
  else
    printf 'T18: stage_replay audit row missing: FAIL\n' >&2
    cat .context/logs/audit.jsonl >&2 2> /dev/null || true
    exit 1
  fi

  jq '.tasks.DV0.status = "in_progress"
      | .facts.dispatched_agents = [{stage:"DV", task_id:"DV0",
          subagent_type:"corpflow:developer", agent_id:"sess-dv0", status:"launched"}]' \
    .context/state.json > .context/state.next && mv .context/state.next .context/state.json
  cp .context/state.json .context/state.json.snap18
  st18_rc=0
  bash "$SELF" --task-replay DV0 --agents-json agents-busy.json > /dev/null 2>&1 || st18_rc=$?
  if [[ "$st18_rc" -eq 4 ]] \
    && diff -q .context/state.json .context/state.json.snap18 > /dev/null; then
    printf 'T18: live target refuses with exit 4, state byte-unchanged: ok\n'
  else
    printf 'T18: live-target guard (rc=%s): FAIL\n' "$st18_rc" >&2
    exit 1
  fi

  # ---- T19: a partial sweep stub via --facts is rejected before the lock ----
  # The union REPLACES the incumbent object for that id, so admitting {id} alone would
  # silently drop the class/ref the FN render resolves options[] through.
  make_state
  bash "$SELF" --facts '{"open_questions":[{"id":"sw-PL0-1","class":"decision","ref":"planning-0.md#elicitation-sweep","blocks_next_stage":false}]}' \
    > /dev/null || {
      printf 'T19: a full sweep stub was rejected\n' >&2
      exit 1
    }
  cp .context/state.json .context/state.json.snap19
  st19_rc=0
  bash "$SELF" --facts '{"open_questions":[{"id":"sw-PL0-1"}]}' > /dev/null 2>&1 || st19_rc=$?
  if [[ "$st19_rc" -eq 2 ]] \
    && diff -q .context/state.json .context/state.json.snap19 > /dev/null; then
    printf 'T19: partial sweep stub exits 2, state byte-unchanged: ok\n'
  else
    printf 'T19: partial-stub guard (rc=%s): FAIL\n' "$st19_rc" >&2
    exit 1
  fi
  # blocks_next_stage is required too: a stub that omits it is the demotion-by-omission the
  # union's sticky arm used to absorb, refused here instead — at the door, before any merge.
  cp .context/state.json .context/state.json.snap19b
  st19b_rc=0
  bash "$SELF" --facts '{"open_questions":[{"id":"sw-PL0-1","class":"decision","ref":"planning-0.md#elicitation-sweep"}]}' \
    > /dev/null 2>&1 || st19b_rc=$?
  if [[ "$st19b_rc" -eq 2 ]] \
    && diff -q .context/state.json .context/state.json.snap19b > /dev/null; then
    printf 'T19: a stub omitting blocks_next_stage exits 2, state byte-unchanged: ok\n'
  else
    printf 'T19: missing-blocks_next_stage guard (rc=%s): FAIL\n' "$st19b_rc" >&2
    exit 1
  fi
  # decisions keeps the id-only contract: the tightening is scoped to open_questions.
  bash "$SELF" --facts '{"decisions":[{"id":"d1","summary":"s","ref":"planning-0.md#stages"}]}' \
    > /dev/null || {
      printf 'T19: decisions payload was rejected: FAIL\n' >&2
      exit 1
    }

  # ---- T20: raising blocks_next_stage is honoured ----
  # The lattice's live half: an item written non-blocking can be raised to blocking later.
  # Its other half — a stub that OMITS the key cannot demote — is now enforced one layer
  # earlier by the T19 shape gate, so it can no longer be reached through --facts at all;
  # the union's sticky arm survives for legacy payloads and is covered directly against the
  # filter in tests/shell/skills/elicitation-sweep-contracts.bats.
  make_state
  bash "$SELF" --facts '{"open_questions":[{"id":"sw-DV0-1","class":"decision","ref":"development-0.md#elicitation-sweep","blocks_next_stage":false}]}' > /dev/null
  bash "$SELF" --facts '{"open_questions":[{"id":"sw-DV0-1","class":"decision","ref":"development-0.md#elicitation-sweep","blocks_next_stage":true}]}' > /dev/null
  if jq -e '.facts.open_questions[0].blocks_next_stage == true' .context/state.json > /dev/null; then
    printf 'T20: raising blocks_next_stage is honoured: ok\n'
  else
    printf 'T20: a raise to blocking was refused: FAIL\n' >&2
    exit 1
  fi

  # ---- T20b: an EXPLICIT false clears an incumbent true ----
  # The OV-183 defect: the join ORed the flag, so once `true` landed no payload could clear
  # it — not even the author's own artifact value — and the ledger permanently outvoted the
  # stub it was derived from. Absent still sticks (T19 refuses it); explicit false does not.
  make_state
  bash "$SELF" --facts '{"open_questions":[{"id":"sw-DV0-1","class":"decision","ref":"development-0.md#elicitation-sweep","blocks_next_stage":true}]}' > /dev/null
  bash "$SELF" --facts '{"open_questions":[{"id":"sw-DV0-1","class":"decision","ref":"development-0.md#elicitation-sweep","blocks_next_stage":false}]}' > /dev/null
  if jq -e '.facts.open_questions[0].blocks_next_stage == false' .context/state.json > /dev/null; then
    printf 'T20b: an explicit false clears an incumbent true: ok\n'
  else
    printf 'T20b: explicit false could not clear the flag: FAIL\n' >&2
    exit 1
  fi

  # ---- T24: --facts rejects per item, persisting the valid remainder ----
  # One bad class value used to discard the whole write — decisions, changed files and
  # every valid sweep stub in the same object.
  make_state
  st24_rc=0
  bash "$SELF" --facts '{
      "decisions":[{"id":"d-good","summary":"kept"},{"summary":"no id"}],
      "files_modified":["a.sh", 42],
      "open_questions":[
        {"id":"sw-DV0-1","class":"decision","ref":"development-0.md#elicitation-sweep","blocks_next_stage":false},
        {"id":"sw-DV0-2","class":"risk","ref":"development-0.md#elicitation-sweep","blocks_next_stage":false}]
    }' > /dev/null 2> .context/t24.err || st24_rc=$?
  if [[ "$st24_rc" -eq 2 ]] \
    && jq -e '(.facts.decisions | map(.id)) == ["d-good"]
              and (.facts.files_modified) == ["a.sh"]
              and (.facts.open_questions | map(.id)) == ["sw-DV0-1"]' \
      .context/state.json > /dev/null \
    && grep -q 'sw-DV0-2' .context/t24.err; then
    printf 'T24: --facts persists the valid remainder and names each rejection (rc=2): ok\n'
  else
    printf 'T24: per-item rejection did not partition the payload (rc=%s): FAIL\n' "$st24_rc" >&2
    jq -c '.facts' .context/state.json >&2
    cat .context/t24.err >&2
    exit 1
  fi

  # ---- T24b: an unknown key is still a whole-payload refusal ----
  # Per-item rejection is about item shape; an unknown key means the caller is writing to a
  # slot that does not exist, and no part of that payload can be trusted to land where meant.
  cp .context/state.json .context/state.json.snap24b
  st24b_rc=0
  bash "$SELF" --facts '{"decisions":[{"id":"d-x"}],"nope":[]}' > /dev/null 2>&1 || st24b_rc=$?
  if [[ "$st24b_rc" -eq 2 ]] \
    && diff -q .context/state.json .context/state.json.snap24b > /dev/null; then
    printf 'T24b: an unknown key refuses the whole payload, state byte-unchanged: ok\n'
  else
    printf 'T24b: unknown-key guard (rc=%s): FAIL\n' "$st24b_rc" >&2
    exit 1
  fi

  # ---- T24c: a rejection diagnostic is not buried under the help text ----
  # The reproduction: the real message scrolled past behind a ~100-line usage dump.
  bash "$SELF" --facts '{"open_questions":[{"id":"sw-PL0-1"}]}' > /dev/null 2> .context/t24c.err || true
  if [[ "$(grep -c '^' .context/t24c.err)" -le 6 ]] \
    && ! grep -q 'state-patch.sh --stage' .context/t24c.err; then
    printf 'T24c: a rejection prints its diagnostic, not the usage block: ok\n'
  else
    printf 'T24c: rejection diagnostic buried under usage (%s lines): FAIL\n' \
      "$(grep -c '^' .context/t24c.err)" >&2
    exit 1
  fi

  # ---- T24d: an EMPTY payload is a no-op success, not a refusal ----
  # The sweep contract tells a stage with nothing to ask to emit `open_questions: []`. Refusing
  # that aborted the stage-completion merge the same call was paired with.
  make_state
  cp .context/state.json .context/state.json.snap24d
  st24d_rc=0
  bash "$SELF" --facts '{"open_questions":[]}' > /dev/null 2>&1 || st24d_rc=$?
  if [[ "$st24d_rc" -eq 0 ]] \
    && diff -q .context/state.json .context/state.json.snap24d > /dev/null; then
    printf 'T24d: an empty --facts payload is a no-op success, state byte-unchanged: ok\n'
  else
    printf 'T24d: empty payload refused (rc=%s): FAIL\n' "$st24d_rc" >&2
    exit 1
  fi
  # And it must not abort the stage merge it is paired with — the shape every agent emits.
  st24e_rc=0
  bash "$SELF" --stage DV --artifact .context/development-0.md --facts '{"open_questions":[]}' \
    > /dev/null 2>&1 || st24e_rc=$?
  if [[ "$st24e_rc" -eq 0 ]] \
    && [[ "$(jq -r '.tasks.DV0.status' .context/state.json)" == "completed" ]]; then
    printf 'T24e: --stage paired with an empty --facts still patches the ledger: ok\n'
  else
    printf 'T24e: empty --facts aborted the stage merge (rc=%s): FAIL\n' "$st24e_rc" >&2
    jq -c '.tasks.DV0' .context/state.json >&2
    exit 1
  fi

  # ---- T24f: a partial payload paired with --stage still exits 2 ----
  # The rejection must survive the fall-through, or a combined call hides it.
  make_state
  st24f_rc=0
  bash "$SELF" --stage DV --artifact .context/development-0.md --facts \
    '{"decisions":[{"id":"d-ok"},{"summary":"no id"}]}' > /dev/null 2>&1 || st24f_rc=$?
  if [[ "$st24f_rc" -eq 2 ]] \
    && [[ "$(jq -r '.tasks.DV0.status' .context/state.json)" == "completed" ]] \
    && jq -e '[.facts.decisions[].id] | index("d-ok")' .context/state.json > /dev/null; then
    printf 'T24f: a partial --facts beside --stage completes the merge and still exits 2: ok\n'
  else
    printf 'T24f: combined partial-facts exit wrong (rc=%s): FAIL\n' "$st24f_rc" >&2
    exit 1
  fi

  # ---- T25: a --facts write that lands nothing is loud ----
  # log_msg writes only to the log file, so an absent ledger exited 0 with nothing on stderr.
  rm -rf .context
  mkdir -p .context
  st25_rc=0
  bash "$SELF" --facts '{"decisions":[{"id":"d-1"}]}' > /dev/null 2> t25.err || st25_rc=$?
  if [[ "$st25_rc" -ne 0 ]] && grep -q 'no ledger' t25.err; then
    printf 'T25: a facts write with no ledger fails loudly on stderr: ok\n'
  else
    printf 'T25: absent-ledger facts write was silent (rc=%s): FAIL\n' "$st25_rc" >&2
    exit 1
  fi

  # ---- T26: metadata.description is capped on the two ledger write paths ----
  make_state
  T26_LONG=$(printf 'x%.0s' $(seq 1 400))
  bash "$SELF" --task-create DV9 --metadata "$(jq -nc --arg d "$T26_LONG" '{stage:"DV",description:$d}')" > /dev/null
  bash "$SELF" --task-meta DV9 --set "$(jq -nc --arg d "$T26_LONG" '{description:$d}')" > /dev/null
  if jq -e '(.tasks.DV9.metadata.description | length) == 240
            and (.tasks.DV9.metadata.description | endswith("…"))
            and .tasks.DV9.metadata.stage == "DV"' .context/state.json > /dev/null; then
    printf 'T26: an over-long description is truncated, not rejected, on create and meta: ok\n'
  else
    printf 'T26: description cap did not apply: FAIL\n' >&2
    jq -c '.tasks.DV9' .context/state.json >&2
    exit 1
  fi

  printf 'self-test: ALL PASS\n'
  exit 0
}

#!/usr/bin/env bash
# blocked-on-dispatch-selftest.sh — the `--self-test` harness for blocked-on-dispatch.sh.
#
# SOURCED, never executed: blocked-on-dispatch.sh loads this file only on `--self-test`, so the
# production path never pays for it. Drives the real CLI end to end against a throwaway ledger
# through the real state-patch.sh; only the host_environment re-probe is a stub, because the real
# preflight's verdict depends on the host it runs on.
#
# Contract: defines `self_test`, returning 0 when every case passes.

self_test() {
  local self td state audit stub out rc fails=0 before
  self="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/blocked-on-dispatch.sh"
  command -v jq > /dev/null 2>&1 || { echo "blocked-on-dispatch: self-test FAIL (jq missing)"; return 1; }
  td=$(mktemp -d) || return 1
  # shellcheck disable=SC2064  # expand now: td is local and gone by the time EXIT fires
  trap "rm -rf '$td'" EXIT
  mkdir -p "$td/.context/logs"
  state="$td/.context/state.json"
  audit="$td/.context/logs/audit.jsonl"
  printf '%s' '{"version":2,"run_index":0,"facts":{},"metadata":{"preflight":{"platforms":["systems"]}},"tasks":{
    "PL0":{"status":"completed","metadata":{}},
    "DV0":{"status":"completed","metadata":{"artifact":"development-0.md"}},
    "DC0":{"status":"in_progress","metadata":{"workspace_path":"/tmp/wt"}},
    "DR0":{"status":"in_progress","metadata":{}},
    "QA0":{"status":"in_progress","metadata":{}},
    "FN0":{"status":"in_progress","metadata":{}}}}' > "$state"
  stub="$td/preflight-stub.sh"
  # The stub answers pass for gh-pr-create only, so one stub serves the pass and the fail case.
  printf '%s\n' '#!/usr/bin/env bash' \
    'printf "result_json=%s\n" "{\"version\":1,\"result\":\"fail\",\"ran_at\":\"unknown\",\"platforms\":[],\"checks\":[{\"id\":\"gh-pr-create\",\"kind\":\"permission\",\"status\":\"pass\",\"detail\":\"ok\"},{\"id\":\"git-push\",\"kind\":\"permission\",\"status\":\"fail\",\"detail\":\"no\"}],\"tools_absent\":[]}"' \
    > "$stub"

  _st_pass() { printf '  ok   %s\n' "$1"; }
  _st_fail() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }
  # MAILBOX_DIR and MAILBOX_NOW are set for every case, not just the peer one: without them the
  # peer arm would resolve the real run's mailbox and write an ask into it from a self-test.
  _st_run() {
    env -u WORKSPACE_ROOT -u CONTEXT_DIR -u CLAUDE_PROJECT_DIR -u MILESTONE_MODE \
      BLOCKED_ON_PREFLIGHT="$stub" MAILBOX_DIR="$td/mailbox" MAILBOX_NOW=1789646700 \
      bash "$self" "$@" --state "$state" 2> /dev/null
  }
  _st_rows() {
    [ -f "$audit" ] || { echo 0; return 0; }
    jq -nR --arg a "$1" '[inputs | fromjson? | select(.action == $a)] | length' "$audit"
  }

  rc=0
  before=$(cat "$state")
  out=$(_st_run route --task-id FN0 --payload '{"verdict":"blocked","blocked_on":{"kind":"permission","detail":{"tool":"Bash","command":"gh pr merge 1","classifier_reason":"Blocked by classifier","allow_rule":""},"resume_with":"decision_ref"}}') || rc=$?
  if [ "$rc" -eq 0 ] && [ "$(cat "$state")" = "$before" ] && [ ! -f "$audit" ] \
    && printf '%s' "$out" | jq -e '.arm == "permission" and .leg == null and .parked == false' > /dev/null 2>&1; then
    _st_pass "route: a permission need writes nothing and names the permission arm"
  else
    _st_fail "route: a permission need writes nothing and names the permission arm"
  fi

  rc=0
  out=$(_st_run route --task-id DC0 --payload '{"verdict":"blocked","blocked_on":{"kind":"correction","detail":{"target_task":"DV0","finding":"SECRET-FINDING-TEXT","evidence_ref":"a.sh:1","severity":"blocking"},"resume_with":"artifact_path"}}') || rc=$?
  if [ "$rc" -eq 0 ] \
    && printf '%s' "$out" | jq -e '.arm == "correction" and .leg == "opened" and .parked == true
      and (has("fallback_from") | not) and (has("owner_issue") | not)' > /dev/null 2>&1 \
    && jq -e '.tasks.DC0.status == "blocked" and .tasks.DC0.metadata.blocked_on.kind == "correction"
      and .tasks.DV0.status == "pending" and .tasks.DV0.metadata.fix_round == 1
      and .tasks.DV0.metadata.gate_from_stage == "DC"
      and (.tasks.DV0.metadata.gate_blockers[0] | startswith("SECRET-FINDING-TEXT"))
      and (.tasks.DV0.metadata.gate_blockers[0] | contains("evidence_ref: a.sh:1"))
      and (.tasks.DV0.metadata.gate_blockers[0] | contains("source_task: DC0"))
      and .tasks.DV0.metadata.artifact == "development-0.md"' "$state" > /dev/null 2>&1 \
    && [ "$(_st_rows blocked_on)" = 1 ] && ! grep -qF 'SECRET-FINDING-TEXT' "$audit"; then
    _st_pass "route: a correction re-opens its target, parks the source and writes one opened row"
  else
    _st_fail "route: a correction re-opens its target, parks the source and writes one opened row"
  fi

  rc=0
  _st_run route --task-id DC0 --payload '{"verdict":"blocked","blocked_on":{"kind":"correction","detail":{"target_task":"DV0","finding":"SECRET-FINDING-TEXT","evidence_ref":"a.sh:1","severity":"blocking"},"resume_with":"artifact_path"}}' > /dev/null || rc=$?
  if [ "$rc" -eq 0 ] && [ "$(_st_rows blocked_on)" = 1 ] \
    && jq -e '.tasks.DV0.metadata.fix_round == 1' "$state" > /dev/null 2>&1; then
    _st_pass "route: re-routing a still-open correction writes no second opened row and bumps nothing"
  else
    _st_fail "route: re-routing a still-open correction writes no second opened row and bumps nothing"
  fi

  # Each refusal is the router's own guard, so it must land BEFORE any write: an unchanged file
  # and an unchanged row count are the assertion, not just the exit code.
  before=$(cat "$state")
  rc=0
  local rc_self=0 rc_absent=0 rows_before
  rows_before=$(_st_rows blocked_on)
  _st_run route --task-id QA0 --payload '{"blocked_on":{"kind":"correction","detail":{"target_task":"DV0","finding":"f","evidence_ref":"a.sh:1","severity":"blocking"},"resume_with":"artifact_path"}}' > /dev/null || rc=$?
  _st_run route --task-id QA0 --payload '{"blocked_on":{"kind":"correction","detail":{"target_task":"QA0","finding":"f","evidence_ref":"a.sh:1","severity":"blocking"},"resume_with":"artifact_path"}}' > /dev/null || rc_self=$?
  _st_run route --task-id QA0 --payload '{"blocked_on":{"kind":"correction","detail":{"target_task":"DV9","finding":"f","evidence_ref":"a.sh:1","severity":"blocking"},"resume_with":"artifact_path"}}' > /dev/null || rc_absent=$?
  if [ "$rc" -eq 1 ] && [ "$rc_self" -eq 1 ] && [ "$rc_absent" -eq 1 ] \
    && [ "$(cat "$state")" = "$before" ] && [ "$(_st_rows blocked_on)" = "$rows_before" ]; then
    _st_pass "route: a target that is not completed, is the source, or is absent refuses and writes nothing"
  else
    _st_fail "route: a target that is not completed, is the source, or is absent refuses and writes nothing"
  fi

  before=$(cat "$state")
  rc=0
  _st_run route --task-id QA0 --payload '{"blocked_on":{"kind":"coffee","detail":{"a":"b"},"resume_with":"decision_ref"}}' > /dev/null || rc=$?
  local rc2=0 rc3=0 rc4=0
  _st_run route --task-id QA0 --payload '{"blocked_on":{"kind":"artifact","detail":{"producer_task":"DV0"},"resume_with":"artifact_path"}}' > /dev/null || rc2=$?
  _st_run route --task-id QA0 --payload '{"blocked_on":{"kind":"artifact","detail":{"producer_task":"DV0","path":"x.md"},"resume_with":"reply_ref"}}' > /dev/null || rc3=$?
  _st_run route --task-id QA0 --payload '{"blocked_on":{"kind":"artifact","detail":{},"resume_with":"artifact_path"}}' > /dev/null || rc4=$?
  if [ "$rc" -eq 1 ] && [ "$rc2" -eq 1 ] && [ "$rc3" -eq 1 ] && [ "$rc4" -eq 1 ] && [ "$(cat "$state")" = "$before" ]; then
    _st_pass "route: unknown kind, missing key, wrong pairing and empty detail exit 1 and write nothing"
  else
    _st_fail "route: unknown kind, missing key, wrong pairing and empty detail exit 1 and write nothing"
  fi

  rc=0
  out=$(_st_run route --task-id DR0 --payload '{"verdict":"blocked","blocked_on":{"kind":"peer_session","detail":{"to":"peer","question":"which base?"},"resume_with":"reply_ref"}}') || rc=$?
  if [ "$rc" -eq 0 ] \
    && printf '%s' "$out" | jq -e '.source == "blocked_on" and .kind == "peer_session"
      and .arm == "peer_session" and .parked == true and .audit_row_written == false
      and (.ask_id | test("^ask-[0-9]{8}t[0-9]{6}z-[0-9a-f]{12}$"))
      and .message == ("mailbox ask " + .ask_id)' > /dev/null 2>&1 \
    && jq -e --arg a "$(printf '%s' "$out" | jq -r '.ask_id')" \
      '.tasks.DR0.status == "blocked" and .tasks.DR0.metadata.ask_id == $a' "$state" > /dev/null 2>&1 \
    && [ -f "$td/mailbox/requests/$(printf '%s' "$out" | jq -r '.ask_id').json" ]; then
    _st_pass "route: a peer_session need parks natively and writes its mailbox request"
  else
    _st_fail "route: a peer_session need parks natively and writes its mailbox request"
  fi

  rc=0
  out=$(_st_run route --task-id DR0 --payload '{"verdict":"blocked","blocked_on":{"kind":"peer_session","detail":{"to":"peer","question":"which base?"},"resume_with":"reply_ref"}}') || rc=$?
  if [ "$rc" -eq 0 ] \
    && printf '%s' "$out" | jq -e '.reused == true and (.ask_id | test("^ask-"))' > /dev/null 2>&1 \
    && [ "$(find "$td/mailbox/requests" -name 'ask-*.json' | wc -l | tr -d ' ')" = 1 ]; then
    _st_pass "route: a retried peer return reuses its open ask and mints no second request"
  else
    _st_fail "route: a retried peer return reuses its open ask and mints no second request"
  fi

  before=$(cat "$state")
  rc=0
  rows_before=$(_st_rows blocked_on)
  _st_run route --task-id DR0 --payload '{"verdict":"blocked","cross_session_ask":{"to":"peer","question":"which base?"}}' > /dev/null || rc=$?
  if [ "$rc" -eq 1 ] && [ "$(cat "$state")" = "$before" ] && [ "$(_st_rows blocked_on)" = "$rows_before" ]; then
    _st_pass "route: cross_session_ask is not a need; it exits 1 and writes nothing"
  else
    _st_fail "route: cross_session_ask is not a need; it exits 1 and writes nothing"
  fi

  rc=0
  out=$(_st_run route --task-id FN0 --payload '{"verdict":"blocked","blocked_on":{"kind":"host_environment","detail":{"check":"gh-pr-create","observed":"not logged in"},"resume_with":"decision_ref"}}') || rc=$?
  if [ "$rc" -eq 0 ] \
    && printf '%s' "$out" | jq -e '.leg == "probed" and .parked == false and .decision_ref == "blocked_on:FN0:host_environment:1" and .resume_block.do_not_rerun == true' > /dev/null 2>&1 \
    && jq -e '.tasks.FN0.status == "in_progress" and .tasks.FN0.metadata.blocked_on == null' "$state" > /dev/null 2>&1; then
    _st_pass "route: a host_environment re-probe that passes clears the need and names decision_ref"
  else
    _st_fail "route: a host_environment re-probe that passes clears the need and names decision_ref"
  fi

  rc=0
  out=$(_st_run route --task-id QA0 --payload '{"verdict":"blocked","blocked_on":{"kind":"host_environment","detail":{"check":"git-push","observed":"denied"},"resume_with":"decision_ref"}}') || rc=$?
  if [ "$rc" -eq 0 ] \
    && printf '%s' "$out" | jq -e '.arm == "user_action" and .leg == "requested" and .fallback_from == "host_environment" and (has("owner_issue") | not)' > /dev/null 2>&1 \
    && jq -e '.tasks.QA0.status == "blocked"' "$state" > /dev/null 2>&1; then
    _st_pass "route: a host_environment re-probe that still fails parks as a user_action"
  else
    _st_fail "route: a host_environment re-probe that still fails parks as a user_action"
  fi

  rc=0
  out=$(_st_run batch) || rc=$?
  if [ "$rc" -eq 0 ] \
    && printf '%s' "$out" | jq -e '.mode == "ask" and ([.needs[].task_id] | sort) == ["DC0", "QA0"]
      and (.needs[] | select(.task_id == "DC0") | .arm == "correction" and .resume_leg == "closed"
           and (has("fallback_from") | not))
      and all(.needs[] | select(.task_id != "DC0"); .resume_leg == "verified")
      and (.payloads[0].questions | length) == 2
      and all(.payloads[0].questions[]; (.question | contains("! ") | not))' > /dev/null 2>&1; then
    _st_pass "batch: every parked need is asked except permission and the open peer ask, and a fallback offers no ! line"
  else
    _st_fail "batch: every parked need is asked except permission and the open peer ask, and a fallback offers no ! line"
  fi

  rc=0
  _st_run resume --task-id DC0 --leg requested > /dev/null || rc=$?
  local rc5=0
  out=$(_st_run resume --task-id DC0 --leg closed) || rc5=$?
  if [ "$rc" -eq 1 ] && [ "$rc5" -eq 0 ] \
    && printf '%s' "$out" | jq -e '.cleared == true and .resume_block.arm == "correction"
      and .resume_block.leg == "closed" and .resume_block.decision_ref == "blocked_on:DC0:correction:1"
      and .resume_block.artifact_path == "development-0.md"' > /dev/null 2>&1 \
    && jq -e '.tasks.DC0.status == "in_progress" and .tasks.DC0.metadata.blocked_on == null' "$state" > /dev/null 2>&1 \
    && ! grep -qF 'SECRET-FINDING-TEXT' "$audit"; then
    _st_pass "resume: only the closing leg resumes, and the ref and artifact_path are named"
  else
    _st_fail "resume: only the closing leg resumes, and the ref and artifact_path are named"
  fi

  if [ "$fails" -eq 0 ]; then
    echo "blocked-on-dispatch: self-test OK"
    return 0
  fi
  echo "blocked-on-dispatch: self-test FAIL ($fails)"
  return 1
}

#!/usr/bin/env bash
# dv-screenshot-gate self-test body — sourced by hooks/dv-screenshot-gate.sh under --self-test only,
# never on the hook dispatch path. Sourced, not executed, so it sees every
# helper the caller already defined; it owns the exit for this invocation.
# Indentation is the caller's — kept byte-identical so this stays a pure move.

  _tmp=$(mktemp -d)
  trap 'rm -rf "$_tmp"' EXIT
  _fail=0

  # --- Block fixture: developer agent, worktask id, NO manifest, flag unset ---
  _bctx="$_tmp/block/.context"
  mkdir -p "$_bctx/images/ov56-edit-mode-fix"
  printf '%s' '{"version":1,"worktask_id":"ov56-edit-mode-fix","metadata":{}}' > "$_bctx/state.json"
  _bpayload='{"agent_type":"corpflow:developer","agent_id":"agt_b","session_id":"sess_b","parent_agent_id":"agt_pb"}'
  _bout=$(run_gate "$_bpayload" "$_bctx")
  printf '%s' "$_bout" | jq -e '.decision == "block" and (.reason | test("missing screenshots.md"))' >/dev/null 2>&1 \
    || { echo "dv-screenshot-gate: self-test FAIL (block: no block decision)"; _fail=1; }
  # Gate-feedback contract: block JSON carries actionable remediation.
  printf '%s' "$_bout" | jq -e '
    .hookSpecificOutput.hookEventName == "SubagentStop"
    and (.hookSpecificOutput.additionalContext | length > 0)
    and (.hookSpecificOutput.additionalContext | test("dv-screenshot-capture"))
  ' >/dev/null 2>&1 \
    || { echo "dv-screenshot-gate: self-test FAIL (block: additionalContext)"; _fail=1; }
  tail -n 1 "$_bctx/logs/audit.jsonl" | jq -e '
    .action == "screenshot_gate_block"
    and .result == "block"
    and .subject == "corpflow:developer"
    and .metadata.worktask_id == "ov56-edit-mode-fix"
    and (.metadata.dedupe_key == "sess_b:agt_b:screenshot-gate")
  ' >/dev/null 2>&1 \
    || { echo "dv-screenshot-gate: self-test FAIL (block: audit row)"; _fail=1; }

  # --- Pass fixture A: manifest present on disk ---
  _pctx="$_tmp/pass/.context"
  mkdir -p "$_pctx/images/wid-pass"
  printf '%s' '{"version":1,"worktask_id":"wid-pass","metadata":{}}' > "$_pctx/state.json"
  printf '# screenshots\n' > "$_pctx/images/wid-pass/screenshots.md"
  _ppayload='{"agent_type":"corpflow:developer","agent_id":"agt_p","session_id":"sess_p","parent_agent_id":"agt_pp"}'
  _pout=$(run_gate "$_ppayload" "$_pctx")
  [ -z "$_pout" ] || { echo "dv-screenshot-gate: self-test FAIL (pass-A: unexpected stdout)"; _fail=1; }
  tail -n 1 "$_pctx/logs/audit.jsonl" | jq -e '
    .action == "screenshot_gate_pass"
    and .result == "ok"
    and .metadata.worktask_id == "wid-pass"
    and .metadata.reason == "manifest present"
  ' >/dev/null 2>&1 \
    || { echo "dv-screenshot-gate: self-test FAIL (pass-A: audit row)"; _fail=1; }

  # --- Pass fixture B: requires_screenshots == false, NO manifest ---
  _fctx="$_tmp/flagfalse/.context"
  mkdir -p "$_fctx/images/wid-noui"
  printf '%s' '{"version":1,"worktask_id":"wid-noui","metadata":{"requires_screenshots":false}}' > "$_fctx/state.json"
  _fpayload='{"agent_type":"corpflow:developer","agent_id":"agt_f","session_id":"sess_f","parent_agent_id":"agt_pf"}'
  _fout=$(run_gate "$_fpayload" "$_fctx")
  [ -z "$_fout" ] || { echo "dv-screenshot-gate: self-test FAIL (pass-B: unexpected block)"; _fail=1; }
  tail -n 1 "$_fctx/logs/audit.jsonl" | jq -e '
    .action == "screenshot_gate_pass"
    and .metadata.reason == "requires_screenshots=false"
  ' >/dev/null 2>&1 \
    || { echo "dv-screenshot-gate: self-test FAIL (pass-B: audit row)"; _fail=1; }

  # --- No-op fixture: non-developer agent, no manifest -> no block, no row ---
  _nctx="$_tmp/nonagent/.context"
  mkdir -p "$_nctx/images/wid-x"
  printf '%s' '{"version":1,"worktask_id":"wid-x","metadata":{}}' > "$_nctx/state.json"
  _nout=$(run_gate '{"agent_type":"corpflow:qa-engineer","agent_id":"agt_n","session_id":"sess_n"}' "$_nctx")
  [ -z "$_nout" ] || { echo "dv-screenshot-gate: self-test FAIL (no-op: unexpected output)"; _fail=1; }
  [ ! -f "$_nctx/logs/audit.jsonl" ] || { echo "dv-screenshot-gate: self-test FAIL (no-op: wrote a row)"; _fail=1; }

  if [ "$_fail" -ne 0 ]; then
    echo "dv-screenshot-gate: self-test FAIL"
    exit 1
  fi
  echo "dv-screenshot-gate: self-test OK"
  exit 0

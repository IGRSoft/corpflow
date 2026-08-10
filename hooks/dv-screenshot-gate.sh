#!/usr/bin/env bash
# DV screenshot-gate hook — blocks the developer agent's SubagentStop when the
# DV implementation manifest is missing (company-workflow worktask plugin).
#
# Closes the OV-56 failure class: a headless DV reasoning its way out of capture
# with a checkbox + prose, and DR reclassifying the absent manifest as a
# QA-deferred non-blocker. The gate is now machine-verified on the filesystem.
#
# Fires on SubagentStop (wired alongside audit-subagent.sh / state-merge.sh in
# .claude-plugin/plugin.json — no matcher; the hook self-filters by agent name,
# the same convention audit-subagent.sh self-tests under: "company-workflow:developer").
#
# Behavior:
#   - No-op (exit 0) for any agent that is not company-workflow:developer.
#   - Resolves .context/ via CLAUDE_PROJECT_DIR (fallback pwd, like siblings).
#   - Reads state.json.worktask_id and metadata.requires_screenshots; the flag
#     may live in state.json metadata and/or the stdin payload. Default TRUE
#     when unset (matches agents/developer.md:184).
#   - Assertion: when requires_screenshots != false, require
#     .context/images/<worktask_id>/screenshots.md on disk.
#       absent  -> emit {"decision":"block", ...,
#                    "hookSpecificOutput":{"hookEventName":"SubagentStop",
#                    "additionalContext":"<remediation>"}} + screenshot_gate_block row.
#       present -> pass + screenshot_gate_pass row.
#       requires_screenshots == false -> pass + screenshot_gate_pass row.
#   - Gate-feedback contract: the block JSON carries
#     hookSpecificOutput.additionalContext so the remediation (run
#     dv-screenshot-capture; headless is not a skip reason; expected manifest
#     path) flows into the developer re-run's context instead of a dead-end
#     error. decision:block still enforces the gate; exit stays 0. See
#     skills/agent-coordination/references/hook-monitoring.md §"Gate-feedback
#     contract" for the symmetric orchestrator surface (blockers[] injection).
#   - Safe degrade: jq absent -> exit 0 (no block), like the siblings.
#   - --self-test: covers a block fixture and a pass fixture (temp dirs).
set -eu

SELF_TEST=0
[ "${1:-}" = "--self-test" ] && SELF_TEST=1

read_stdin() {
  if [ "$SELF_TEST" -eq 1 ]; then
    # Block-fixture payload: developer agent, no requires_screenshots flag.
    printf '%s' '{"agent_type":"company-workflow:developer","agent_id":"agt_test","session_id":"sess_test","parent_agent_id":"agt_parent"}'
  else
    cat
  fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "dv-screenshot-gate: jq not found, skipping" >&2
  exit 0
fi

# ---------------------------------------------------------------------------
# run_gate: core logic, parameterized over the .context/ root + stdin payload.
# Echoes the block decision to stdout (when blocking) and appends one audit row
# to <ctx>/logs/audit.jsonl. Returns 0 always (a block is communicated via the
# decision JSON on stdout, never a non-zero exit — matching the sibling hooks'
# exit discipline).
# ---------------------------------------------------------------------------
run_gate() {
  _payload="$1"
  _ctx="$2"

  _agent=$(printf '%s' "$_payload" | jq -r '.agent_type // "unknown"' 2>/dev/null || echo unknown)
  # No-op for any non-developer agent (same match as audit-subagent.sh:14).
  if [ "$_agent" != "company-workflow:developer" ]; then
    return 0
  fi

  _state="$_ctx/state.json"
  _worktask_id="unknown"
  _req_state="null"
  if [ -f "$_state" ]; then
    _worktask_id=$(jq -r '.worktask_id // "unknown"' "$_state" 2>/dev/null || echo unknown)
    # Use `has`-style presence check: `// null` is wrong here because a literal
    # `false` is jq-falsy and would collapse to "null", hiding an explicit skip.
    _req_state=$(jq -r 'if (.metadata|type=="object") and (.metadata|has("requires_screenshots")) then (.metadata.requires_screenshots|tostring) else "null" end' "$_state" 2>/dev/null || echo null)
  fi
  # Payload-level flag (stdin) takes precedence when present.
  _req_payload=$(printf '%s' "$_payload" | jq -r 'if (.metadata|type=="object") and (.metadata|has("requires_screenshots")) then (.metadata.requires_screenshots|tostring) else "null" end' 2>/dev/null || echo null)

  _required="true"
  if [ "$_req_payload" = "false" ] || { [ "$_req_payload" = "null" ] && [ "$_req_state" = "false" ]; }; then
    _required="false"
  fi

  _manifest="$_ctx/images/$_worktask_id/screenshots.md"
  _log_dir="$_ctx/logs"
  mkdir -p "$_log_dir"
  _ts=$(date -u +%FT%TZ)

  # Presence does not imply readability: a manifest with no canonical rows passes a
  # -f test while carrying no evidence any consumer can join on. The schema verdict is
  # delegated to attach-visual-evidence.sh --validate-manifest so the 9-column grammar
  # keeps exactly one parser and the gate never grows a second copy.
  _schema_err=""
  _schema_ok=1
  if [ "$_required" != "false" ] && [ -f "$_manifest" ]; then
    # Resolved from this file's own location rather than the plugin-root env var:
    # plugin-root-refs.bats pins the set of scripts allowed to read that variable, and a
    # sibling lookup needs no such privilege. An unresolvable sibling simply skips the
    # check (below) rather than inventing a block.
    _validator="$(CDPATH= cd -- "$(dirname "$0")/.." 2>/dev/null && pwd -P)/skills/worktask/scripts/attach-visual-evidence.sh"
    if [ -f "$_validator" ]; then
      # An absent or unrunnable validator must not invent a block; only a real
      # exit-1 schema verdict does.
      # `set -e` is on: capture the validator's status explicitly rather than letting a
      # non-zero assignment abort the gate, which would swallow the block it just earned.
      _schema_err=$(bash "$_validator" --validate-manifest "$_manifest" 2>/dev/null) \
        && _schema_rc=0 || _schema_rc=$?
      [ "$_schema_rc" -eq 1 ] && _schema_ok=0 || true
      # rc 3 = well-formed but no capture rows. Legitimate ONLY when nothing was captured:
      # a prose-only manifest sitting beside real images is the silent evidence drop this
      # gate exists to catch, and the parser cannot see the directory to tell them apart.
      if [ "$_schema_rc" -eq 3 ]; then
        _img_count=$(find "$(dirname "$_manifest")" -maxdepth 1 -type f \
          \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.webp' \) 2>/dev/null \
          | grep -c . || true)
        if [ "${_img_count:-0}" -gt 0 ]; then
          _schema_ok=0
          _schema_err="$_schema_err
${_img_count} image file(s) sit beside it, so the captures exist but no canonical row references them."
        fi
      fi
    fi
  fi

  if [ "$_required" = "false" ] || { [ -f "$_manifest" ] && [ "$_schema_ok" -eq 1 ]; }; then
    _reason="manifest present"
    [ "$_required" = "false" ] && _reason="requires_screenshots=false"
    _row=$(printf '%s' "$_payload" | jq -c \
      --arg ts "$_ts" --arg wid "$_worktask_id" --arg reason "$_reason" '
      {
        ts: $ts,
        actor: "hook:dv-screenshot-gate",
        action: "screenshot_gate_pass",
        subject: (.agent_type // "unknown"),
        result: "ok",
        metadata: {
          worktask_id: $wid,
          reason: $reason,
          dedupe_key: ((.session_id // "nosession") + ":" + (.agent_id // "noagent") + ":screenshot-gate")
        }
      }') || { echo "dv-screenshot-gate: jq parse failed" >&2; return 0; }
    printf '%s\n' "$_row" >> "$_log_dir/audit.jsonl"
    return 0
  fi

  # Required + manifest absent -> BLOCK.
  # Build the block JSON via jq -c (matching the audit-row construction below),
  # adding hookSpecificOutput.additionalContext (gate-feedback contract) so
  # the remediation flows into the re-run's context. The decision:block verb
  # + exit-0 discipline are unchanged.
  # The gate is platform-agnostic; so is the remediation. Naming a concrete
  # adapter here told a Go or web DV to run the Apple canvas. The skill resolves
  # its own adapter from state.platform and always has cli/fallback under it.
  _reason="missing screenshots.md — run the dv-screenshot-capture skill (it selects the adapter for state.platform, with cli/fallback under it); headless is not a skip reason"
  _additional_context="run the dv-screenshot-capture skill; it selects the adapter for state.platform and falls back to cli/fallback, so headless is not a skip reason; expected manifest $_manifest"
  _block_action="screenshot_gate_block"
  if [ "$_schema_ok" -eq 0 ]; then
    # A manifest that exists but does not parse fails for a different reason and
    # needs different remediation: fix the rows, do not re-capture.
    _reason="screenshot_manifest_schema — $_manifest exists but does not match the canonical 9-column capture table (| # | Slug | Path | Bytes | Platform | Adapter | Caption | Captured | Design Ref |, two-digit index)"
    _additional_context="$_schema_err
Rewrite the offending rows in $_manifest to the canonical 9-column schema with a two-digit index; the captures themselves are fine, the table is not."
  fi
  _block=$(jq -cn \
    --arg reason "$_reason" --arg ac "$_additional_context" '
    {
      decision: "block",
      reason: $reason,
      hookSpecificOutput: {
        hookEventName: "SubagentStop",
        additionalContext: $ac
      }
    }') || { echo "dv-screenshot-gate: jq parse failed" >&2; return 0; }
  printf '%s\n' "$_block"
  _row=$(printf '%s' "$_payload" | jq -c \
    --arg ts "$_ts" --arg wid "$_worktask_id" --arg manifest "$_manifest" \
    --arg reason "$_reason" --arg schema_ok "$_schema_ok" '
    {
      ts: $ts,
      actor: "hook:dv-screenshot-gate",
      action: "screenshot_gate_block",
      subject: (.agent_type // "unknown"),
      result: "block",
      metadata: {
        worktask_id: $wid,
        missing_manifest: $manifest,
        block_kind: (if $schema_ok == "0" then "screenshot_manifest_schema" else "missing_manifest" end),
        reason: $reason,
        dedupe_key: ((.session_id // "nosession") + ":" + (.agent_id // "noagent") + ":screenshot-gate")
      }
    }') || { echo "dv-screenshot-gate: jq parse failed" >&2; return 0; }
  printf '%s\n' "$_row" >> "$_log_dir/audit.jsonl"
  return 0
}

# ---------------------------------------------------------------------------
# --self-test: block fixture + pass fixture in throwaway temp dirs.
# ---------------------------------------------------------------------------
if [ "$SELF_TEST" -eq 1 ]; then
  _tmp=$(mktemp -d)
  trap 'rm -rf "$_tmp"' EXIT
  _fail=0

  # --- Block fixture: developer agent, worktask id, NO manifest, flag unset ---
  _bctx="$_tmp/block/.context"
  mkdir -p "$_bctx/images/ov56-edit-mode-fix"
  printf '%s' '{"version":1,"worktask_id":"ov56-edit-mode-fix","metadata":{}}' > "$_bctx/state.json"
  _bpayload='{"agent_type":"company-workflow:developer","agent_id":"agt_b","session_id":"sess_b","parent_agent_id":"agt_pb"}'
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
    and .subject == "company-workflow:developer"
    and .metadata.worktask_id == "ov56-edit-mode-fix"
    and (.metadata.dedupe_key == "sess_b:agt_b:screenshot-gate")
  ' >/dev/null 2>&1 \
    || { echo "dv-screenshot-gate: self-test FAIL (block: audit row)"; _fail=1; }

  # --- Pass fixture A: manifest present on disk ---
  _pctx="$_tmp/pass/.context"
  mkdir -p "$_pctx/images/wid-pass"
  printf '%s' '{"version":1,"worktask_id":"wid-pass","metadata":{}}' > "$_pctx/state.json"
  printf '# screenshots\n' > "$_pctx/images/wid-pass/screenshots.md"
  _ppayload='{"agent_type":"company-workflow:developer","agent_id":"agt_p","session_id":"sess_p","parent_agent_id":"agt_pp"}'
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
  _fpayload='{"agent_type":"company-workflow:developer","agent_id":"agt_f","session_id":"sess_f","parent_agent_id":"agt_pf"}'
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
  _nout=$(run_gate '{"agent_type":"company-workflow:qa-engineer","agent_id":"agt_n","session_id":"sess_n"}' "$_nctx")
  [ -z "$_nout" ] || { echo "dv-screenshot-gate: self-test FAIL (no-op: unexpected output)"; _fail=1; }
  [ ! -f "$_nctx/logs/audit.jsonl" ] || { echo "dv-screenshot-gate: self-test FAIL (no-op: wrote a row)"; _fail=1; }

  if [ "$_fail" -ne 0 ]; then
    echo "dv-screenshot-gate: self-test FAIL"
    exit 1
  fi
  echo "dv-screenshot-gate: self-test OK"
  exit 0
fi

# ---------------------------------------------------------------------------
# Live invocation.
# ---------------------------------------------------------------------------
PAYLOAD=$(read_stdin)
CTX="${CLAUDE_PROJECT_DIR:-.}/.context"
run_gate "$PAYLOAD" "$CTX"
exit 0

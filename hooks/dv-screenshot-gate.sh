#!/usr/bin/env bash
# dv-screenshot-gate — SubagentStop gate blocking the developer agent when the DV
# implementation manifest is missing, so capture is verified on the filesystem
# rather than asserted in prose. No matcher in plugin.json; self-filters by name.
#
# Behavior:
#   - No-op (exit 0) for any agent that is not corpflow:developer.
#   - Resolves .context/ via CLAUDE_PROJECT_DIR (fallback pwd, like siblings).
#   - Reads state.json.worktask_id and metadata.requires_screenshots, which may
#     come from state.json metadata and/or the stdin payload. Defaults TRUE.
#   - When requires_screenshots != false, requires
#     .context/images/<worktask_id>/screenshots.md on disk: absent -> decision
#     "block" plus a screenshot_gate_block row; present, or the flag false ->
#     pass plus a screenshot_gate_pass row.
#   - The block JSON carries hookSpecificOutput.additionalContext, so the
#     remediation reaches the developer's re-run instead of a dead-end error.
#     decision:block enforces the gate; the exit code stays 0.
#   - jq absent -> exit 0 (no block), like the siblings.
#   - --self-test covers a block fixture and a pass fixture.
set -eu

SELF_TEST=0
[ "${1:-}" = "--self-test" ] && SELF_TEST=1

read_stdin() {
  if [ "$SELF_TEST" -eq 1 ]; then
    # Block-fixture payload: developer agent, no requires_screenshots flag.
    printf '%s' '{"agent_type":"corpflow:developer","agent_id":"agt_test","session_id":"sess_test","parent_agent_id":"agt_parent"}'
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
  if [ "$_agent" != "corpflow:developer" ]; then
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
    # Refuse a symlinked audit.jsonl: following it makes this append a write primitive
    # against an arbitrary target. A lost row never blocks the caller.
    if [ ! -L "$_log_dir/audit.jsonl" ]; then
      printf '%s\n' "$_row" >> "$_log_dir/audit.jsonl"
    fi
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
  # Refuse a symlinked audit.jsonl: following it makes this append a write primitive
  # against an arbitrary target. A lost row never blocks the caller.
  if [ ! -L "$_log_dir/audit.jsonl" ]; then
    printf '%s\n' "$_row" >> "$_log_dir/audit.jsonl"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# --self-test: block fixture + pass fixture in throwaway temp dirs.
# ---------------------------------------------------------------------------
# Body lives in lib/ — test code, sourced only here and never on the dispatch
# path below. This arm fails CLOSED: a self-test that cannot find its cases must
# report a failure, never "OK".
if [ "$SELF_TEST" -eq 1 ]; then
  _selftest_body="$(dirname "$0")/lib/dv-screenshot-gate-selftest.sh"
  if [ ! -f "$_selftest_body" ]; then
    echo "dv-screenshot-gate: self-test body missing at $_selftest_body" >&2
    exit 1
  fi
  . "$_selftest_body"
fi

# ---------------------------------------------------------------------------
# Live invocation.
# ---------------------------------------------------------------------------
PAYLOAD=$(read_stdin)
CTX="${CLAUDE_PROJECT_DIR:-.}/.context"
run_gate "$PAYLOAD" "$CTX"
exit 0

#!/usr/bin/env bash
# Read-helper for audit.jsonl dedupe-key mode selection (company-workflow worktask plugin, v3.10.6+).
# NOT wired in plugin.json hooks block — invoked manually by audit consumers
# (e.g. /cost-report aggregation) per agent-coordination/SKILL.md § Dedupe Key Migration.
#
# Auto-detection rule:
#   - File missing/empty               → base
#   - First row lacks dedupe_key_ext   → base (pre-v3.10.6 compat mode)
#   - Tail-100 has no non-"none" parent → base
#   - Tail-100 has ≥1 non-"none" parent → extended
set -eu

MODE=""
SELF_TEST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check-mode) MODE="check" ;;
    --self-test)  SELF_TEST=1 ;;
    -h|--help)
      cat >&2 <<USAGE
Usage: audit-dedup.sh --check-mode      Print 'base' or 'extended' for current audit.jsonl.
       audit-dedup.sh --self-test       Run built-in fixture tests.
USAGE
      exit 0
      ;;
  esac
  shift
done

if ! command -v jq >/dev/null 2>&1; then
  echo "audit-dedup: jq not found, skipping" >&2
  echo "base"
  exit 0
fi

# Pure scan function — operates on a given audit.jsonl path. Echoes base|extended.
scan_audit() {
  local path="$1"
  if [ ! -s "$path" ]; then
    echo "base"; return 0
  fi
  # Pre-v3.10.6 compat: if first row lacks dedupe_key_extended, fall back to base.
  if ! head -n 1 "$path" | jq -e 'has("metadata") and (.metadata | has("dedupe_key_extended"))' >/dev/null 2>&1; then
    echo "base"; return 0
  fi
  if tail -n 100 "$path" | jq -r '.metadata.parent_agent_id // "none"' 2>/dev/null | grep -qv '^none$'; then
    echo "extended"
  else
    echo "base"
  fi
}

if [ "$SELF_TEST" -eq 1 ]; then
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT

  # Fixture 1: no file
  R1=$(scan_audit "$TMP/missing.jsonl")
  [ "$R1" = "base" ] || { echo "audit-dedup: self-test FAIL (missing → $R1)"; exit 1; }

  # Fixture 2: all-none parents, with dedupe_key_extended present
  cat > "$TMP/all_none.jsonl" <<'F2'
{"ts":"2026-05-25T00:00:00Z","actor":"hook:audit-subagent","metadata":{"parent_agent_id":"none","dedupe_key":"s1:a1:stop","dedupe_key_extended":"none:s1:a1:stop"}}
{"ts":"2026-05-25T00:00:01Z","actor":"hook:agent-stop","metadata":{"parent_agent_id":"none","dedupe_key":"s1:a2:stage:DV","dedupe_key_extended":"none:s1:a2:stage:DV"}}
F2
  R2=$(scan_audit "$TMP/all_none.jsonl")
  [ "$R2" = "base" ] || { echo "audit-dedup: self-test FAIL (all_none → $R2)"; exit 1; }

  # Fixture 3: one row carries a real parent_agent_id
  cat > "$TMP/has_parent.jsonl" <<'F3'
{"ts":"2026-05-25T00:00:00Z","actor":"hook:audit-subagent","metadata":{"parent_agent_id":"none","dedupe_key":"s1:a1:stop","dedupe_key_extended":"none:s1:a1:stop"}}
{"ts":"2026-05-25T00:00:01Z","actor":"hook:audit-subagent","metadata":{"parent_agent_id":"agt_P","dedupe_key":"s1:a2:stop","dedupe_key_extended":"agt_P:s1:a2:stop"}}
F3
  R3=$(scan_audit "$TMP/has_parent.jsonl")
  [ "$R3" = "extended" ] || { echo "audit-dedup: self-test FAIL (has_parent → $R3)"; exit 1; }

  # Fixture 4: pre-v3.10.6 row (no dedupe_key_extended)
  cat > "$TMP/pre_v3106.jsonl" <<'F4'
{"ts":"2026-05-20T00:00:00Z","actor":"hook:audit-subagent","metadata":{"dedupe_key":"s1:a1:stop"}}
{"ts":"2026-05-25T00:00:01Z","actor":"hook:audit-subagent","metadata":{"parent_agent_id":"agt_P","dedupe_key":"s1:a2:stop","dedupe_key_extended":"agt_P:s1:a2:stop"}}
F4
  R4=$(scan_audit "$TMP/pre_v3106.jsonl")
  [ "$R4" = "base" ] || { echo "audit-dedup: self-test FAIL (pre_v3106 → $R4)"; exit 1; }

  echo "audit-dedup: self-test OK"
  exit 0
fi

if [ "$MODE" = "check" ]; then
  AUDIT_PATH="${CLAUDE_PROJECT_DIR:-.}/.context/logs/audit.jsonl"
  scan_audit "$AUDIT_PATH"
  exit 0
fi

# No mode flag: print usage to stderr, succeed silently.
cat >&2 <<USAGE
Usage: audit-dedup.sh --check-mode      Print 'base' or 'extended' for current audit.jsonl.
       audit-dedup.sh --self-test       Run built-in fixture tests.
USAGE
exit 0

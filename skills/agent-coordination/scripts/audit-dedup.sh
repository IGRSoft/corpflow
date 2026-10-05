#!/usr/bin/env bash
# Audit-trail dedup filter (corpflow plugin).
#
# Reads `.context/logs/audit.jsonl` (or stdin) and emits a deduped stream:
# for every group of rows sharing `metadata.dedupe_key`, prefer a hook-written
# row (skills/agent-coordination/SKILL.md § Hook authority + dedupe rule).
# Agent-emitted rows for the same key are dropped.
# Rows lacking `metadata.dedupe_key` pass through unchanged (one-shot events).
#
# A hook row is `hook:<name>` or `<plugin>:hook:<name>` — sibling plugins mirror
# this hook under their own prefix. Their copies set `advisory: true` and carry
# thinner metadata, so the unprefixed writer outranks them within the group.
#
# Usage:
#   audit-dedup.sh [PATH_TO_AUDIT_JSONL]      # default: .context/logs/audit.jsonl
#   audit-dedup.sh -                          # read from stdin
#   audit-dedup.sh --self-test                # synthetic fixture, exits 0 on success
#
# Pipe into any audit aggregation to avoid double-counting effort/duration
# on (session, agent, tool) pairs that emit both hook and agent rows.
#
# Stability: input order within a dedup group is preserved (jq groups by key,
# then folds preferring hook:* actors); rows outside any group keep arrival order.
set -eu

if ! command -v jq >/dev/null 2>&1; then
  echo "audit-dedup: jq not found" >&2
  exit 2
fi

if [ "${1:-}" = "--self-test" ]; then
  # Sourced HERE, not at the top: the harness is test code the production path
  # never runs. `[ -r ]` first, not a bare `.`: sourcing a missing file with the
  # `.` builtin is a special-builtin error that exits the shell immediately,
  # bypassing an `if ! . …` guard entirely.
  SELFTEST_LIB_PATH="$(dirname "${BASH_SOURCE[0]}")/audit-dedup-selftest.sh"
  if [ -r "$SELFTEST_LIB_PATH" ]; then
    # shellcheck source=audit-dedup-selftest.sh
    # shellcheck disable=SC1090
    . "$SELFTEST_LIB_PATH"
  else
    printf >&2 'audit-dedup: self-test harness unreachable at %s — plugin install broken\n' \
      "$SELFTEST_LIB_PATH"
    exit 2
  fi
  run_self_test
  exit $?
fi

SRC="${1:-.context/logs/audit.jsonl}"
if [ "$SRC" = "-" ]; then
  INPUT=$(cat)
elif [ -r "$SRC" ]; then
  INPUT=$(cat "$SRC")
else
  echo "audit-dedup: cannot read $SRC" >&2
  exit 1
fi

# Strategy:
#   1. Parse every line as JSON; attach original index + normalized key for stable ordering.
#   2. Partition by presence of metadata.dedupe_key.
#   3. For grouped rows, keep the authoritative hook row (canonical before
#      advisory mirror), else the first by index.
#   4. Re-merge with ungrouped rows and sort by original index.
# `fromjson?` below drops malformed rows silently, so a corrupt log reads exactly
# like a clean one with nothing to dedupe. Count the drops and name them on stderr;
# stdout stays the deduped stream so callers are unaffected.
_ad_total=$(printf '%s\n' "$INPUT" | grep -c '[^[:space:]]' || true)
_ad_parsed=$(printf '%s\n' "$INPUT" | jq -ncR '[ inputs | select(length > 0) | fromjson? | objects ] | length' 2> /dev/null || echo 0)
if [ "$_ad_total" -gt "$_ad_parsed" ]; then
  echo "audit-dedup: $((_ad_total - _ad_parsed)) unparseable row(s) skipped in $SRC" >&2
fi

printf '%s' "$INPUT" | jq -ncR '
  def is_hook: (.actor // "") | (startswith("hook:") or contains(":hook:"));
  def is_advisory: (.metadata.advisory // false) == true;
  [inputs | select(length > 0) | fromjson?] as $rows
  | $rows
  | to_entries
  | map(.value + {__idx: .key})
  | (map(select(.metadata.dedupe_key)) | group_by(.metadata.dedupe_key)
       | map(  (map(select(is_hook and (is_advisory | not))) | first)
            // (map(select(is_hook)) | first)
            // (sort_by(.__idx) | .[0])
            )) as $deduped
  | (map(select(.metadata.dedupe_key | not))) as $singletons
  | ($deduped + $singletons)
  | sort_by(.__idx)
  | map(del(.__idx))
  | .[]
' 2>/dev/null

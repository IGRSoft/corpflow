#!/usr/bin/env bash
# anchor-preflight — PostToolUse (Write|Edit) lint for written files. Every write whose
# extension is on the control-byte-lib text allowlist is scanned for raw C0 control bytes;
# a path matching the canonical .context/<stage>-N.md regex also runs cache-lint.sh
# --anchor-lint, so a bad H2 anchor surfaces at the producing write rather than at the DR gate.
#
# Reads tool_input.file_path from the hook stdin JSON, falling back to
# CLAUDE_TOOL_INPUT_FILE_PATH without jq. Exit 2 on any finding: in PostToolUse only exit 2
# routes stderr to the model, and continueOnBlock keeps the turn going.
#
# Plugin root is env-first ($CLAUDE_PLUGIN_ROOT), else self-located from $0. An empty root
# skips both lints. --self-test asserts the gating regex and the control-byte scan.
set -eu

SELF_TEST=0
[ "${1:-}" = "--self-test" ] && SELF_TEST=1

# Canonical artifact basenames (mirrors handoff-protocol.md#stage-artifact-map).
#
# DV also matches the per-stream development-N-<stream>.md: under handoff-protocol.md
# § DV fan-out — ledger tasks each stream file IS its row's DV handoff, read directly by
# DR/QA through refs.dev, so it carries the same anchor contract as development-N.md.
# The stream arm is the S1 slug grammar; its 40-char cap cannot be said in one ERE, so
# STREAM_TOO_LONG_RE subtracts over-long slugs. Other stages have no stream suffix.
ARTIFACT_RE='\.context/((planning|architecture|coordination|development|developer-review|security-review|testing|documentation|release|complete-summary|retrospective|incident|ethics-review)-[0-9]+|development-[0-9]+-[a-z0-9]+(-[a-z0-9]+)*)\.md$'
STREAM_TOO_LONG_RE='\.context/development-[0-9]+-[a-z0-9-]{41,}\.md$'

# is_artifact <path> — true when <path> is a lintable stage artifact name.
is_artifact() {
  printf '%s' "$1" | grep -qE "$ARTIFACT_RE" || return 1
  ! printf '%s' "$1" | grep -qE "$STREAM_TOO_LONG_RE"
}

if [ "$SELF_TEST" -eq 1 ]; then
  ok=0
  for p in \
    ".context/development-0.md" \
    ".context/development-0-swift-app.md" \
    ".context/development-2-backend.md" \
    ".context/development-0-a234567890123456789012345678901234567890.md" \
    ".context/developer-review-12.md" \
    "/abs/path/.context/planning-3.md"; do
    is_artifact "$p" || { echo "anchor-preflight: self-test FAIL (should match: $p)"; exit 1; }
  done
  for p in \
    "skills/worktask/SKILL.md" \
    ".context/state.json" \
    ".context/development.md" \
    ".context/development-0-.md" \
    ".context/development-0-Stream.md" \
    ".context/development-0--web.md" \
    ".context/development-0-web-.md" \
    ".context/development-N-web.md" \
    ".context/development-0-a2345678901234567890123456789012345678901.md" \
    ".context/planning-0-stream.md" \
    ".context/developer-review-0-web.md" \
    ".context/worktask-comms.md"; do
    is_artifact "$p" && { echo "anchor-preflight: self-test FAIL (should NOT match: $p)"; exit 1; }
    ok=$((ok + 1))
  done

  # An unreachable library is a FAIL here, never a vacuous OK: the hook itself fails open.
  _ST_LIB="${CLAUDE_PLUGIN_ROOT:-$(dirname -- "$0")/..}/skills/worktask/scripts/control-byte-lib.sh"
  if [ ! -r "$_ST_LIB" ]; then
    echo "anchor-preflight: self-test FAIL (control-byte-lib.sh unreachable at $_ST_LIB)"
    exit 1
  fi
  # shellcheck source=skills/worktask/scripts/control-byte-lib.sh
  . "$_ST_LIB"
  _st_td=$(mktemp -d "${TMPDIR:-/tmp}/anchor-preflight-selftest.XXXXXX")
  # shellcheck disable=SC2064  # the path is fixed at set time on purpose
  trap "rm -rf '$_st_td'" EXIT
  # shellcheck disable=SC2016  # the backticks are fixture text, not a command substitution
  printf 'escape spellings `\\0` then a raw \000 byte\n' > "$_st_td/nul.md"
  printf 'tab\tcr\r\nliteral \\0 \\x00 ^@\n' > "$_st_td/clean.md"
  _st_rc=0
  _st_out=$(cb_scan_file "$_st_td/nul.md" nul.md) || _st_rc=$?
  [ "$_st_rc" -eq 1 ] && [ "$_st_out" = "nul.md:33:0x00" ] \
    || { echo "anchor-preflight: self-test FAIL (NUL not flagged: rc=$_st_rc out=$_st_out)"; exit 1; }
  _st_rc=0
  cb_scan_file "$_st_td/clean.md" clean.md > /dev/null || _st_rc=$?
  [ "$_st_rc" -eq 0 ] || { echo "anchor-preflight: self-test FAIL (clean file flagged: rc=$_st_rc)"; exit 1; }

  echo "anchor-preflight: self-test OK"
  exit 0
fi

# Resolve the written file path: prefer hook stdin JSON, fall back to env.
FILE_PATH=""
if command -v jq >/dev/null 2>&1; then
  PAYLOAD=$(cat 2>/dev/null || true)
  if [ -n "$PAYLOAD" ]; then
    FILE_PATH=$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || true)
  fi
fi
[ -z "$FILE_PATH" ] && FILE_PATH="${CLAUDE_TOOL_INPUT_FILE_PATH:-}"
[ -n "$FILE_PATH" ] || exit 0

# An explicitly set env var always wins; otherwise derive the root from the shared
# resolver, which validates the .claude-plugin/plugin.json marker.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "$PLUGIN_ROOT" ]; then
  # A TRUNCATED library is worse than an absent one: a syntax error in a sourced file is
  # fatal under `set -e` and `||` does not rescue it. Drop -e across the source and probe
  # for the symbol afterwards, so an unusable library degrades this preflight to a no-op
  # instead of turning it into a hard block on every artifact write.
  _LIB="$(dirname -- "$0")/lib/corpflow-base.sh"
  _cf_opts=$-
  set +e
  # shellcheck source=hooks/lib/corpflow-base.sh
  [ -f "$_LIB" ] && . "$_LIB"
  case "$_cf_opts" in *e*) set -e ;; esac
  if command -v corpflow_plugin_root > /dev/null 2>&1; then
    PLUGIN_ROOT="$(corpflow_plugin_root)" || PLUGIN_ROOT=""
  fi
fi
# Never fall back to `.`: an empty root would load skills/ out of the user's project (CWE-427).
[ -n "$PLUGIN_ROOT" ] || exit 0

cbrc=0
CB_LIB="$PLUGIN_ROOT/skills/worktask/scripts/control-byte-lib.sh"
if [ -f "$FILE_PATH" ] && [ -r "$CB_LIB" ]; then
  _cf_opts=$-
  set +e
  # shellcheck source=skills/worktask/scripts/control-byte-lib.sh
  . "$CB_LIB"
  case "$_cf_opts" in *e*) set -e ;; esac
  if command -v cb_scan_file > /dev/null 2>&1 && cb_is_lintable "$FILE_PATH"; then
    cbhits=$(cb_scan_file "$FILE_PATH" "$FILE_PATH") || cbrc=$?
    if [ "$cbrc" -eq 1 ]; then
      printf >&2 'anchor-preflight: control bytes in %s — a typed escape was decoded into a raw byte; rewrite each named byte\n' "$FILE_PATH"
      printf >&2 '%s\n' "$cbhits"
    else
      cbrc=0
    fi
  fi
fi

if ! is_artifact "$FILE_PATH" || [ ! -f "$FILE_PATH" ]; then
  [ "$cbrc" -eq 0 ] || exit 2
  exit 0
fi

arc=0
LINT="$PLUGIN_ROOT/skills/worktask/scripts/cache-lint.sh"
if [ -f "$LINT" ]; then
  bash "$LINT" --anchor-lint "$FILE_PATH" || arc=$?
fi
[ "$cbrc" -eq 0 ] && [ "$arc" -eq 0 ] || exit 2
exit 0

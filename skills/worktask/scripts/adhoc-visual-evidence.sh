#!/usr/bin/env bash
# adhoc-visual-evidence.sh — visual evidence for a PR opened OUTSIDE a worktask.
#
# The worktask path already attaches DV screenshots at FN via
# dv-screenshot-capture + attach-visual-evidence.sh. This wires the same two
# pieces into the direct "commit and open a PR" flow, which has no DV stage to
# capture and no FN stage to attach. It adds no capture and no hosting logic of
# its own: detection reads detect-ui-change.sh's vocabulary, capture is
# cli-fallback.sh, and the rendered block is attach-visual-evidence.sh --emit pr,
# so both paths produce a byte-identical "## Visual evidence" shape.
#
# Modes:
#   --emit pr [--base <ref>] [--force]
#                 Print a ready-to-insert "## Visual evidence" block to stdout,
#                 or NOTHING when this PR has no visual surface. The PR-body
#                 composer inserts it between ## Test plan and ## Notes, BEFORE
#                 `gh pr create`, so no second API call patches the body after.
#                 Callers invoke UNCONDITIONALLY; gating lives here. --force
#                 re-captures and re-hosts instead of replaying.
#   --detect [--base <ref>]
#                 Heuristic only. One JSON line:
#                 {"visual_surface":<bool>,"files":<N>,"reason":"<one line>"}
#   --self-test   Built-in fixture tests. Exit 0 pass, 2 fail.
#
# Skip-by-default, the inverse of detect-ui-change.sh's fail-safe. That detector
# serves a gated stage where a missed capture re-opens the bug it was added for,
# so it defaults toward capturing. Here there is no gate and no reviewer
# expecting evidence, so an unprompted diff-render on every ad-hoc PR is pure
# noise that teaches reviewers to scroll past the section. Every uncertain
# outcome — no git, unresolvable base ref, no path-class hit, capture failure —
# emits nothing and exits 0.
#
# NEVER blocks the PR. Exit 0 on every operational path including total failure;
# 1 only for a caller argv error, 2 only for --self-test failure. A missing
# screenshot is a smaller loss than an unopenable PR.
#
# Worktask trees are refused: a readable .context/state.json carrying a
# worktask_id means FN owns the attachment, and a second block would duplicate
# it. That refusal is what keeps worktask-driven PRs bit-identical to before.
#
# Heuristic (single owner: detect-ui-change.sh --path-classes):
#   Views/ Screens/ UI/ Components/ .storyboard .xib .tsx .jsx .vue .svelte
#   .css .scss .html res/layout res/drawable res/values res/menu /ui/ .kt
# Applied to `git diff --name-only <base>...HEAD`. `.kt` and `/ui/` are the
# false-positive edge: a Kotlin service file trips them. Set ADHOC_SKIP=1 to
# suppress a run the heuristic gets wrong.
#
# Env: WORKSPACE_ROOT, BASE_REF, ADHOC_ID, ADHOC_SKIP, GH_BIN, DRY_RUN, plus
# every ASSET_* hook attach-visual-evidence.sh honours (passed straight through).

set -u

WORKSPACE_ROOT="${WORKSPACE_ROOT:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DETECTOR="$SCRIPT_DIR/detect-ui-change.sh"
ATTACHER="$SCRIPT_DIR/attach-visual-evidence.sh"
CAPTURER="$SCRIPT_DIR/../../dv-screenshot-capture/scripts/cli-fallback.sh"
LOG_DIR="$WORKSPACE_ROOT/.context/logs"
AUDIT_FILE="$LOG_DIR/audit.jsonl"
BASE_REF="${BASE_REF:-}"
FORCE=0
# Fixed stream id: an ad-hoc PR has no ledger task, and the capture scripts require one.
STREAM_ID="AD0"

# ---------- audit -----------------------------------------------------------
# Shared audit-row appender. `[ -r ]` before the `.`: a bare `.` on a missing file is a
# special-builtin error that exits the shell, bypassing an `if !` guard.
_AUDIT_LIB="$SCRIPT_DIR/../../shared/lib/audit-lib.sh"
if [ ! -r "$_AUDIT_LIB" ]; then
  printf >&2 'adhoc-visual-evidence: plugin install broken — audit-lib.sh not found\n'
  exit 2
fi
# shellcheck source=../../shared/lib/audit-lib.sh
. "$_AUDIT_LIB"

audit_adhoc() {
  # $1=result, $2=reason, $3=extra-json-object. Never fatal on its own.
  # jq-absent stays a silent no-row: the reason/extra merge below needs jq anyway.
  command -v jq >/dev/null 2>&1 || return 0
  local meta
  meta=$(jq -cn --arg reason "$2" --argjson extra "${3:-\{\}}" \
    '$extra + {reason:$reason}' 2>/dev/null) || meta='{}'
  corpflow_audit_row --file "$AUDIT_FILE" --actor orchestrator \
    --action adhoc_visual_evidence --subject adhoc --result "$1" --task-id none --meta "$meta"
}

# ---------- gating ----------------------------------------------------------
# Non-empty output = the reason to skip; empty = proceed.
skip_reason() {
  [ "${ADHOC_SKIP:-0}" = "1" ] && { printf 'skip_requested'; return 0; }
  local state="$WORKSPACE_ROOT/.context/state.json"
  if [ -r "$state" ] && command -v jq >/dev/null 2>&1 \
     && [ -n "$(jq -r '.worktask_id // empty' "$state" 2>/dev/null)" ]; then
    printf 'worktask_path'
    return 0
  fi
  command -v git >/dev/null 2>&1 || { printf 'git_absent'; return 0; }
  git -C "$WORKSPACE_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
    || { printf 'not_a_git_repo'; return 0; }
  printf ''
}

# First resolvable candidate wins. Three-dot diff downstream makes this the merge
# base, so naming the branch is enough — no explicit merge-base call.
resolve_base_ref() {
  local c
  for c in "$BASE_REF" origin/HEAD origin/main origin/master main master; do
    [ -n "$c" ] || continue
    if git -C "$WORKSPACE_ROOT" rev-parse --verify --quiet "$c" >/dev/null 2>&1; then
      printf '%s' "$c"
      return 0
    fi
  done
  return 1
}

# Changed paths matching the shared UI vocabulary, one per line.
ui_files() {
  local base="$1" classes
  classes=$(bash "$DETECTOR" --path-classes 2>/dev/null) || return 1
  [ -n "$classes" ] || return 1
  git -C "$WORKSPACE_ROOT" diff --name-only "$base...HEAD" 2>/dev/null \
    | grep -E "$classes" 2>/dev/null
  return 0
}

# Stable across reruns so the emission cache and the capture index both replay
# rather than accumulating a second copy per invocation.
adhoc_id() {
  if [ -n "${ADHOC_ID:-}" ]; then printf '%s' "$ADHOC_ID"; return 0; fi
  local name
  name=$(git -C "$WORKSPACE_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  [ -z "$name" ] || [ "$name" = "HEAD" ] \
    && name=$(git -C "$WORKSPACE_ROOT" rev-parse --short HEAD 2>/dev/null || printf 'unknown')
  printf 'adhoc-%s' "$(printf '%s' "$name" | LC_ALL=C tr '[:upper:]' '[:lower:]' \
    | LC_ALL=C tr -c 'a-z0-9-' '-' | LC_ALL=C sed -e 's/--*/-/g' -e 's/^-//' -e 's/-$//' \
    | cut -c1-40)"
}

# ---------- capture ---------------------------------------------------------
# Echoes "<path>\t<bytes>\t<adapter>" for the produced file, or nothing.
# ONLY exit 0 is a capture. cli-fallback.sh's floor writes no file: exit 2 is
# tool_missing and exit 3 is render_failed, and both print the intended .png path
# on the contract line. Treating either as success manifests a row naming a file
# that is not on disk, which is the "placeholder counted as evidence" defect with
# nothing behind it at all. The path is verified against the filesystem too, so a
# future adapter cannot reintroduce the claim by exiting 0 without writing.
capture_one() {
  local id="$1" base="$2" files="$3"
  local out rc path bytes
  mkdir -p "$WORKSPACE_ROOT/.context" 2>/dev/null || return 1
  out=$(cd "$WORKSPACE_ROOT" && CONTEXT_DIR="$WORKSPACE_ROOT/.context" bash "$CAPTURER" \
          --worktask-id "$id" --task-id "$STREAM_ID" --slug pr-diff --base-ref "$base" \
          --platform all --run-index 0 --files "$files" 2>/dev/null)
  rc=$?
  [ "$rc" -eq 0 ] || return 1
  path=$(printf '%s' "$out" | sed -n 's/.*path=\([^ ]*\).*/\1/p')
  bytes=$(printf '%s' "$out" | sed -n 's/.*bytes=\([0-9]*\).*/\1/p')
  [ -n "$path" ] || return 1
  [ -s "${WORKSPACE_ROOT}/${path}" ] || [ -s "$path" ] || return 1
  printf '%s\t%s\t%s' "$path" "${bytes:-0}" 'cli_fallback'
}

# ---------- manifest --------------------------------------------------------
# The canonical 9-column schema attach-visual-evidence.sh parses; the two-digit
# index is load-bearing, and a row that misses it makes the attach step a silent
# no-op. Rewritten whole, never edited piecemeal.
write_manifest() {
  local mf="$1" id="$2" file="$3" bytes="$4" adapter="$5" count="$6" name nn
  mkdir -p "$(dirname "$mf")" 2>/dev/null || return 1
  name=$(basename "$file")
  nn="${name#dv-"$STREAM_ID"-}"
  nn="${nn%%-*}"
  case "$nn" in [0-9][0-9]) ;; *) nn=01 ;; esac
  {
    printf '# Screenshots — %s / %s\n\n' "$id" "$STREAM_ID"
    printf '> Authored by the ad-hoc PR flow via `adhoc-visual-evidence.sh`. Run index: 0.\n\n'
    printf '| # | Slug | Path | Bytes | Platform | Adapter | Caption | Captured | Design Ref |\n'
    printf '|---|------|------|-------|----------|---------|---------|----------|------------|\n'
    printf '| %s | pr-diff | %s | %s | all | %s | ad-hoc PR diff — %s UI file(s) | %s | — |\n' \
      "$nn" "$name" "$bytes" "$adapter" "$count" "$(date -u +%FT%TZ)"
  } > "$mf" 2>/dev/null
}

# ---------- mode: --emit pr -------------------------------------------------
emit_pr() {
  local why; why=$(skip_reason)
  if [ -n "$why" ]; then
    audit_adhoc skipped "$why" '{}'
    return 0
  fi

  local base
  if ! base=$(resolve_base_ref); then
    audit_adhoc skipped base_ref_unresolvable '{}'
    return 0
  fi

  local files count
  files=$(ui_files "$base")
  count=$(printf '%s' "$files" | grep -c . 2>/dev/null || true)
  if [ "${count:-0}" -eq 0 ]; then
    audit_adhoc skipped no_ui_surface "$(jq -cn --arg b "$base" '{base:$b}' 2>/dev/null || printf '{}')"
    return 0
  fi

  local id img_dir mf
  id=$(adhoc_id)
  img_dir="$WORKSPACE_ROOT/.context/images/$id"
  mf="$img_dir/screenshots-$STREAM_ID.md"

  # Reuse an existing capture unless forced: cli-fallback.sh derives its NN from
  # the files already in the dir, so re-capturing every run would stack
  # dv-AD0-02, dv-AD0-03… beside a manifest that names only one of them.
  local existing="" path bytes adapter cap
  [ "$FORCE" = "1" ] || existing=$(find "$img_dir" -maxdepth 1 -type f -name "dv-$STREAM_ID-[0-9][0-9]-pr-diff.*" 2>/dev/null | LC_ALL=C sort | head -1)
  if [ -n "$existing" ]; then
    path="$existing"
    bytes=$(stat -f%z "$existing" 2>/dev/null || stat -c%s "$existing" 2>/dev/null || printf '0')
    case "$existing" in *.txt) adapter='cli_fallback (.txt)' ;; *) adapter='cli_fallback' ;; esac
  else
    local list; list=$(mktemp 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/adhoc-files.$$")
    printf '%s\n' "$files" > "$list"
    cap=$(capture_one "$id" "$base" "$list"); local rc=$?
    rm -f "$list"
    if [ "$rc" -ne 0 ] || [ -z "$cap" ]; then
      audit_adhoc skipped capture_failed "$(jq -cn --arg b "$base" '{base:$b}' 2>/dev/null || printf '{}')"
      return 0
    fi
    path=$(printf '%s' "$cap" | cut -f1)
    bytes=$(printf '%s' "$cap" | cut -f2)
    adapter=$(printf '%s' "$cap" | cut -f3)
  fi

  if ! write_manifest "$mf" "$id" "$path" "$bytes" "$adapter" "$count"; then
    audit_adhoc skipped manifest_write_failed '{}'
    return 0
  fi

  # Synthetic state lives in a tempfile, never in the tree: writing a real
  # .context/state.json here would look like a worktask to every other tool and
  # to this script's own refusal on the next run.
  local st; st=$(mktemp 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/adhoc-state.$$")
  jq -cn --arg w "$id" '{version:1, worktask_id:$w, run_index:0,
                         metadata:{requires_screenshots:true}}' > "$st" 2>/dev/null \
    || printf '{"version":1,"worktask_id":"%s","run_index":0,"metadata":{"requires_screenshots":true}}' "$id" > "$st"

  local block; local -a attach_args=(--emit pr)
  [ "$FORCE" = "1" ] && attach_args+=(--force)
  block=$(STATE_FILE="$st" WORKSPACE_ROOT="$WORKSPACE_ROOT" MANIFEST_FILE="$mf" \
          bash "$ATTACHER" "${attach_args[@]}" 2>/dev/null)
  rm -f "$st"

  if [ -z "$block" ]; then
    audit_adhoc skipped attach_emitted_nothing "$(jq -cn --arg i "$id" '{adhoc_id:$i}' 2>/dev/null || printf '{}')"
    return 0
  fi
  printf '%s' "$block"
  audit_adhoc ok emitted \
    "$(jq -cn --arg i "$id" --arg b "$base" --argjson f "${count:-0}" \
       '{adhoc_id:$i, base:$b, ui_files:$f}' 2>/dev/null || printf '{}')"
  return 0
}

# ---------- mode: --detect --------------------------------------------------
emit_detect() {
  local why base files count
  why=$(skip_reason)
  if [ -n "$why" ]; then
    detect_json false 0 "$why"
    return 0
  fi
  if ! base=$(resolve_base_ref); then
    detect_json false 0 base_ref_unresolvable
    return 0
  fi
  files=$(ui_files "$base")
  count=$(printf '%s' "$files" | grep -c . 2>/dev/null || true)
  if [ "${count:-0}" -eq 0 ]; then
    detect_json false 0 "no path-class match against $base"
  else
    detect_json true "$count" "UI path classes matched against $base"
  fi
}

detect_json() {
  if command -v jq >/dev/null 2>&1; then
    jq -cn --argjson v "$1" --argjson f "${2:-0}" --arg r "$3" \
      '{visual_surface:$v, files:$f, reason:$r}'
  else
    printf '{"visual_surface":%s,"files":%s,"reason":"%s"}\n' "$1" "${2:-0}" "$3"
  fi
}

# ---------- entrypoint ------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  # Sourced HERE, not at the top: the harness is test code the production path
  # never runs. `[ -r ]` first, not a bare `.`: sourcing a missing file with the
  # `.` builtin is a special-builtin error that exits the shell immediately,
  # bypassing an `if ! . …` guard entirely.
  SELFTEST_LIB_PATH="$(dirname "${BASH_SOURCE[0]}")/adhoc-visual-evidence-selftest.sh"
  if [ -r "$SELFTEST_LIB_PATH" ]; then
    # shellcheck source=adhoc-visual-evidence-selftest.sh
    # shellcheck disable=SC1090
    . "$SELFTEST_LIB_PATH"
  else
    printf >&2 'adhoc-visual-evidence: self-test harness unreachable at %s — plugin install broken\n' \
      "$SELFTEST_LIB_PATH"
    exit 2
  fi
  run_self_tests || exit 2
  exit 0
fi

usage() {
  echo "usage: $0 {--emit pr [--base <ref>] [--force] | --detect [--base <ref>] | --self-test}" >&2
}

MODE="${1:-}"; shift 2>/dev/null || true
case "$MODE" in
  --emit)
    [ "${1:-}" = "pr" ] || { usage; exit 1; }
    shift ;;
  --detect) ;;
  *) usage; exit 1 ;;
esac

while [ "$#" -gt 0 ]; do
  case "$1" in
    --base) BASE_REF="${2:-}"; shift 2 ;;
    --base=*) BASE_REF="${1#*=}"; shift ;;
    --force) FORCE=1; shift ;;
    *) usage; exit 1 ;;
  esac
done

case "$MODE" in
  --emit)   emit_pr ;;
  --detect) emit_detect ;;
esac
exit 0

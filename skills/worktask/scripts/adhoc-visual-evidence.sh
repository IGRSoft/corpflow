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

# ---------- audit -----------------------------------------------------------
audit_adhoc() {
  # $1=result, $2=reason, $3=extra-json-object. Never fatal on its own.
  command -v jq >/dev/null 2>&1 || return 0
  mkdir -p "$LOG_DIR" 2>/dev/null || return 0
  jq -cn \
    --arg ts "$(date -u +%FT%TZ)" \
    --arg actor "orchestrator" \
    --arg result "$1" \
    --arg reason "$2" \
    --argjson extra "${3:-\{\}}" \
    '{ts:$ts, actor:$actor, action:"adhoc_visual_evidence", result:$result,
      metadata:($extra + {reason:$reason})}' \
    >> "$AUDIT_FILE" 2>/dev/null || true
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
# cli-fallback.sh writes relative to CWD and exits 2 on its .txt floor, which is
# a successful capture here — only its hard-error exit 1 means no file.
capture_one() {
  local id="$1" base="$2" files="$3"
  local out rc path bytes err
  out=$(cd "$WORKSPACE_ROOT" && bash "$CAPTURER" \
          --worktask-id "$id" --slug pr-diff --base-ref "$base" \
          --platform all --run-index 0 --files "$files" 2>/dev/null)
  rc=$?
  [ "$rc" -eq 0 ] || [ "$rc" -eq 2 ] || return 1
  path=$(printf '%s' "$out" | sed -n 's/.*path=\([^ ]*\).*/\1/p')
  bytes=$(printf '%s' "$out" | sed -n 's/.*bytes=\([0-9]*\).*/\1/p')
  err=$(printf '%s' "$out" | sed -n 's/.*error=\([^ ]*\).*/\1/p')
  [ -n "$path" ] || return 1
  printf '%s\t%s\t%s' "$path" "${bytes:-0}" \
    "$([ "$err" = "tool_missing" ] && printf 'cli_fallback (.txt)' || printf 'cli_fallback')"
}

# ---------- manifest --------------------------------------------------------
# The canonical 9-column schema attach-visual-evidence.sh parses; the two-digit
# index is load-bearing, and a row that misses it makes the attach step a silent
# no-op. Rewritten whole, never edited piecemeal.
write_manifest() {
  local mf="$1" id="$2" file="$3" bytes="$4" adapter="$5" count="$6"
  mkdir -p "$(dirname "$mf")" 2>/dev/null || return 1
  {
    printf '# Screenshots — %s\n\n' "$id"
    printf '> Authored by the ad-hoc PR flow via `adhoc-visual-evidence.sh`. Run index: 0.\n\n'
    printf '| # | Slug | Path | Bytes | Platform | Adapter | Caption | Captured | Design Ref |\n'
    printf '|---|------|------|-------|----------|---------|---------|----------|------------|\n'
    printf '| 01 | pr-diff | %s | %s | all | %s | ad-hoc PR diff — %s UI file(s) | %s | — |\n' \
      "$(basename "$file")" "$bytes" "$adapter" "$count" "$(date -u +%FT%TZ)"
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
  mf="$img_dir/screenshots.md"

  # Reuse an existing capture unless forced: cli-fallback.sh derives its NN from
  # the files already in the dir, so re-capturing every run would leave dv-02,
  # dv-03… beside a manifest that only ever names dv-01.
  local existing="" path bytes adapter cap
  [ "$FORCE" = "1" ] || existing=$(find "$img_dir" -maxdepth 1 -type f -name 'dv-01-pr-diff.*' 2>/dev/null | head -1)
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

# ---------- self-test -------------------------------------------------------
run_self_tests() {
  local pass=0 fail=0 self="$0"
  _ok()   { echo "adhoc-visual-evidence: $1 PASS"; pass=$((pass+1)); }
  _fail() { echo "adhoc-visual-evidence: $1 FAIL${2:+ — $2}"; fail=$((fail+1)); }

  # A repo with one commit on master and a checked-out feature branch, so
  # `master...HEAD` is a real PR-shaped diff rather than an empty one.
  _mk_repo() {
    local td; td=$(mktemp -d)
    git -C "$td" init -q -b master >/dev/null 2>&1
    git -C "$td" config user.email t@t; git -C "$td" config user.name t
    mkdir -p "$td/Views"
    printf 'a\n' > "$td/README.md"
    git -C "$td" add -A >/dev/null 2>&1
    git -C "$td" commit -qm base >/dev/null 2>&1
    git -C "$td" checkout -q -b feature >/dev/null 2>&1
    printf '%s' "$td"
  }

  # ---- t1: a docs-only diff emits nothing (the false-positive gate)
  local d1; d1=$(_mk_repo)
  printf 'b\n' >> "$d1/README.md"
  git -C "$d1" commit -qam docs >/dev/null 2>&1
  local o1; o1=$(WORKSPACE_ROOT="$d1" BASE_REF="master" bash "$self" --emit pr 2>/dev/null)
  if [ -z "$o1" ] && grep -q '"reason":"no_ui_surface"' "$d1/.context/logs/audit.jsonl" 2>/dev/null; then
    _ok "t1-docs-only-silent"
  else
    _fail "t1-docs-only-silent" "out='${o1:0:60}'"
  fi
  rm -rf "$d1"

  # ---- t2: a UI diff yields a Visual evidence block with no broken embeds
  local d2; d2=$(_mk_repo)
  printf 'body { color: red }\n' > "$d2/Views/app.css"
  git -C "$d2" add -A >/dev/null 2>&1; git -C "$d2" commit -qm ui >/dev/null 2>&1
  local o2
  o2=$(WORKSPACE_ROOT="$d2" BASE_REF="master" ASSET_HOST_MODE=none DRY_RUN=1 \
       bash "$self" --emit pr 2>/dev/null)
  if printf '%s' "$o2" | grep -q '^## Visual evidence' \
     && ! printf '%s' "$o2" | grep -qE '\]\(\)|\]\(\.context/'; then
    _ok "t2-ui-emits-block"
  else
    _fail "t2-ui-emits-block" "$(printf '%s' "$o2" | head -6 | tr '\n' '~')"
  fi

  # ---- t3: rerun replays the cache instead of stacking a second capture
  local o3 caps
  o3=$(WORKSPACE_ROOT="$d2" BASE_REF="master" ASSET_HOST_MODE=none DRY_RUN=1 \
       bash "$self" --emit pr 2>/dev/null)
  caps=$(find "$d2/.context/images" -type f -name 'dv-*' 2>/dev/null | wc -l | tr -d ' ')
  if [ "$o3" = "$o2" ] && [ "$caps" = "1" ]; then
    _ok "t3-idempotent"
  else
    _fail "t3-idempotent" "caps=$caps same=$([ "$o3" = "$o2" ] && echo y || echo n)"
  fi

  # ---- t4: manifest satisfies the attacher's own schema check
  local mf; mf=$(find "$d2/.context/images" -name screenshots.md 2>/dev/null | head -1)
  if bash "$ATTACHER" --validate-manifest "$mf" >/dev/null 2>&1; then
    _ok "t4-manifest-schema"
  else
    _fail "t4-manifest-schema" "$(bash "$ATTACHER" --validate-manifest "$mf" 2>&1 | head -2 | tr '\n' '~')"
  fi
  rm -rf "$d2"

  # ---- t5: a worktask tree is refused, leaving FN's attachment the only one
  local d5; d5=$(_mk_repo)
  printf 'x\n' > "$d5/Views/app.css"
  git -C "$d5" add -A >/dev/null 2>&1; git -C "$d5" commit -qm ui >/dev/null 2>&1
  mkdir -p "$d5/.context"
  printf '{"version":1,"worktask_id":"wid-real","run_index":0}' > "$d5/.context/state.json"
  local o5; o5=$(WORKSPACE_ROOT="$d5" BASE_REF="master" bash "$self" --emit pr 2>/dev/null)
  if [ -z "$o5" ] && grep -q '"reason":"worktask_path"' "$d5/.context/logs/audit.jsonl" 2>/dev/null; then
    _ok "t5-worktask-refused"
  else
    _fail "t5-worktask-refused" "out='${o5:0:60}'"
  fi
  rm -rf "$d5"

  # ---- t7: a PNG capture renders as a hosted embed, not a bullet. Seeded on
  # disk because neither silicon nor ImageMagick is a suite prerequisite.
  local d7; d7=$(_mk_repo)
  printf 'x\n' > "$d7/Views/app.css"
  git -C "$d7" add -A >/dev/null 2>&1; git -C "$d7" commit -qm ui >/dev/null 2>&1
  mkdir -p "$d7/.context/images/adhoc-feature"
  printf 'x' > "$d7/.context/images/adhoc-feature/dv-01-pr-diff.png"
  local o7
  o7=$(WORKSPACE_ROOT="$d7" BASE_REF="master" ADHOC_ID=adhoc-feature \
       ASSET_HOST_MODE=raw ASSET_OWNER_REPO=o/r ASSET_REF=main DRY_RUN=1 \
       bash "$self" --emit pr 2>/dev/null)
  if printf '%s' "$o7" | grep -q '^!\[dv-01 ad-hoc PR diff.*\](https://raw\.githubusercontent\.com/'; then
    _ok "t7-png-embeds"
  else
    _fail "t7-png-embeds" "$(printf '%s' "$o7" | head -6 | tr '\n' '~')"
  fi
  rm -rf "$d7"

  # ---- t6: outside a git repo, --emit is silent and --detect says so
  local d6; d6=$(mktemp -d)
  local o6 j6
  o6=$(WORKSPACE_ROOT="$d6" bash "$self" --emit pr 2>/dev/null)
  j6=$(WORKSPACE_ROOT="$d6" bash "$self" --detect 2>/dev/null)
  if [ -z "$o6" ] && printf '%s' "$j6" | grep -q '"visual_surface":false'; then
    _ok "t6-no-git-silent"
  else
    _fail "t6-no-git-silent" "out='${o6:0:40}' json='$j6'"
  fi
  rm -rf "$d6"

  echo "adhoc-visual-evidence: self-test summary — pass=$pass fail=$fail"
  [ "$fail" -eq 0 ]
}

# ---------- entrypoint ------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
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

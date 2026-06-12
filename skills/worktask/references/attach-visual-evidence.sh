#!/usr/bin/env bash
# attach-visual-evidence.sh — embed DV screenshot captures into the PR body and
# the GitHub issue, on a UI-change run (metadata.requires_screenshots=true).
#
# Two modes (analyzing-0.md ad4, change-map #4):
#   --emit pr     Print a ready-to-insert "## Visual evidence" markdown block to
#                 stdout. The PR-body composer (FN agent / create-pr command /
#                 conductor-attachments skeleton) inserts it between ## Test plan
#                 and ## Notes. Empty stdout ⇒ insert nothing (flag false / no
#                 captures). Callers invoke UNCONDITIONALLY; gating lives here.
#   --post issue  Post ONE marker-deduped `gh issue comment` carrying the same
#                 block. Run by the orchestrator at stage-loop exit (post-FN /
#                 post-push). Non-blocking: operational failures → audit row +
#                 exit 0 (mirrors publish-pl-issue.sh's contract class).
#
# Image hosting (REQ-5, ad7): reuse publish-pl-issue.sh's host-tier degradation
# by sourcing it under PUBLISH_LIB_ONLY=1 — select_host_tier / host_one_asset /
# raw_asset_url_reachable, with every ASSET_* env mock inherited for free.
# Relative .context/ refs are REJECTED (they never render in PR/issue bodies and
# camo can't fetch private/internal raw). none-tier emits a note line, never a
# broken ![]().
#
# Idempotency (ad5): the issue comment is tagged with an HTML marker
#   <!-- visual-evidence:<worktask_id>:<run_index> -->
# Before posting, existing comments are grepped for the exact marker; present ⇒
# skipped/already_published, no second comment.
#
# Exit codes: 0 all operational paths (incl. deferred/skipped), 1 catastrophic
# (jq missing / state corrupt — mirrors publish helper), 2 --self-test failure.
#
# Env (injection / test hooks): STATE_FILE, WORKSPACE_ROOT, GH_BIN, DRY_RUN, plus
# every ASSET_* / *_URL_BASE hook honoured by publish-pl-issue.sh (inherited via
# the source-guard). MANIFEST_FILE overrides manifest discovery in self-tests.

set -u

# ---------- defaults / env --------------------------------------------------
STATE_FILE="${STATE_FILE:-.context/state.json}"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-${CLAUDE_PROJECT_DIR:-.}}"
GH_BIN="${GH_BIN:-gh}"
DRY_RUN="${DRY_RUN:-0}"
LOG_DIR="${WORKSPACE_ROOT}/.context/logs"
AUDIT_FILE="$LOG_DIR/audit.jsonl"
MAX_EMBED=5   # PR/issue embed cap (mirrors capture skill's 5-per-run cap)

# Source publish-pl-issue.sh for tier logic (library mode — returns before main).
_LIB="$(dirname "$0")/publish-pl-issue.sh"

# ---------- audit -----------------------------------------------------------
audit_av() {
  # $1=action, $2=result, $3=metadata-json (compact). Never fatal on its own.
  local action="$1" result="$2" meta="$3"
  command -v jq >/dev/null 2>&1 || return 0
  mkdir -p "$LOG_DIR" 2>/dev/null || return 0
  jq -cn \
    --arg ts "$(date -u +%FT%TZ)" \
    --arg actor "orchestrator" \
    --arg action "$action" \
    --arg result "$result" \
    --argjson meta "$meta" \
    '{ts:$ts, actor:$actor, action:$action, result:$result, metadata:$meta}' \
    >> "$AUDIT_FILE" 2>/dev/null || true
}

# ---------- state accessors -------------------------------------------------
state_get() { jq -r "$1 // \"\"" "$STATE_FILE" 2>/dev/null || printf ''; }

# requires_screenshots from state.json with the SAME has()-presence semantics the
# gate uses (literal false must survive — see hooks/dv-screenshot-gate.sh:78).
state_requires_screenshots() {
  jq -r 'if (.metadata|type=="object") and (.metadata|has("requires_screenshots"))
         then (.metadata.requires_screenshots|tostring) else "true" end' \
    "$STATE_FILE" 2>/dev/null || echo true
}

# ---------- manifest discovery + parse --------------------------------------
# Manifest path: MANIFEST_FILE override, else
# <root>/.context/images/<worktask_id>/screenshots.md.
manifest_path() {
  if [ -n "${MANIFEST_FILE:-}" ]; then printf '%s' "$MANIFEST_FILE"; return 0; fi
  printf '%s/.context/images/%s/screenshots.md' "$WORKSPACE_ROOT" "$WORKTASK_ID"
}

# Echo manifest capture rows as TSV: NN<TAB>path<TAB>caption<TAB>kind
#   kind ∈ {png, placeholder, oversize}
# A "skip-rationale" manifest (no table rows) yields zero lines.
parse_manifest() {
  local mf="$1"
  [ -f "$mf" ] || return 0
  # Table rows look like: | 01 | slug | dv-01-slug.png | 187234 | apple | adapter | caption | ts | ref |
  # Header + separator rows are filtered (col1 not two-digit; separator has ---).
  LC_ALL=C awk -F'|' '
    /^[[:space:]]*\|/ {
      # Trim each field.
      for (i=1;i<=NF;i++){ gsub(/^[[:space:]]+|[[:space:]]+$/,"",$i) }
      num=$2; path=$4; cap=$8
      if (num !~ /^[0-9][0-9]$/) next            # skip header / non-data
      if (path ~ /^-+$/ || path=="") next        # skip separator
      kind="png"
      if (path ~ /\.txt$/) kind="placeholder"
      printf "%s\t%s\t%s\t%s\n", num, path, cap, kind
    }
  ' "$mf"
  # Out-of-budget (oversize, link-only) rows live under a "§ Out-of-budget" head
  # as bullets "- <path>: <bytes> ..."; surface them as oversize kind.
  LC_ALL=C awk '
    /^##?[[:space:]]+Out-of-budget/ { inblk=1; next }
    /^##?[[:space:]]/ && inblk { inblk=0 }
    inblk && /^[[:space:]]*-[[:space:]]+/ {
      line=$0; sub(/^[[:space:]]*-[[:space:]]+/,"",line)
      p=line; sub(/:.*/,"",p); gsub(/^[[:space:]]+|[[:space:]]+$/,"",p)
      if (p=="" || p ~ /^\(none\)/) next
      printf "99\t%s\t%s\toversize\n", p, "oversize (link-only)"
    }
  ' "$mf"
}

# ---------- block builder ---------------------------------------------------
# Build the "## Visual evidence" block from a parsed manifest.
#   stdout: the block (may be empty)
#   Globs read: BLOCK_HEADING, BLOCK_MANIFEST_REF (set by caller)
# Hosting decisions go through the sourced select_host_tier/host_one_asset.
# Returns the chosen host tier via the HOST_TIER global (set by select_host_tier).
build_block() {
  local mf="$1" heading="$2"
  local rows; rows=$(parse_manifest "$mf")
  # No capture rows at all → empty emission (skip-rationale manifest / no captures).
  if [ -z "$rows" ]; then
    return 1   # signal "no captures" to caller
  fi

  select_host_tier   # sets HOST_TIER (+ owner/ref for raw)
  # Propagate HOST_TIER past the command-substitution subshell boundary: callers
  # pass a tempfile path via HOST_TIER_FILE and read it back after $() returns.
  [ -n "${HOST_TIER_FILE:-}" ] && printf '%s' "$HOST_TIER" > "$HOST_TIER_FILE"

  local img_dir; img_dir=$(dirname "$mf")
  local out="" embed_count=0 num path cap kind src url bullets=""

  while IFS="$(printf '\t')" read -r num path cap kind; do
    [ -z "$path" ] && continue
    case "$kind" in
      png)
        if [ "$embed_count" -ge "$MAX_EMBED" ]; then
          bullets="${bullets}- ${path} — omitted (embed cap ${MAX_EMBED}); see manifest."$'\n'
          continue
        fi
        # none-tier: never embed an image; list as bullet instead (no broken ![]()).
        if [ "$HOST_TIER" = "none" ]; then
          bullets="${bullets}- ${path} — inline hosting unavailable; see manifest."$'\n'
          continue
        fi
        src="$img_dir/$(basename "$path")"
        if [ ! -f "$src" ]; then
          # Source PNG missing on disk → cannot host; list as bullet, never embed.
          bullets="${bullets}- ${path} — file not found on disk; see manifest."$'\n'
          continue
        fi
        url=$(WORKTASK_ID="$WORKTASK_ID" host_one_asset "$(basename "$path")" "$src" 2>/dev/null || true)
        if [ -z "$url" ]; then
          # Hosting miss for this asset → degrade to bullet (never a broken embed).
          bullets="${bullets}- ${path} — inline hosting unavailable; see manifest."$'\n'
          continue
        fi
        out="${out}![dv-${num} ${cap}](${url})"$'\n'
        embed_count=$((embed_count+1))
        ;;
      placeholder)
        bullets="${bullets}- ${path} — placeholder (tool_missing); see manifest."$'\n'
        ;;
      oversize)
        bullets="${bullets}- ${path} — ${cap}; see manifest."$'\n'
        ;;
    esac
  done <<EOF
$rows
EOF

  # Assemble. Always emit heading + manifest ref so the section is never broken.
  printf '%s\n\n' "$heading"
  [ -n "$out" ] && printf '%s' "$out"
  [ -n "$bullets" ] && printf '%s' "$bullets"
  if [ "$HOST_TIER" = "none" ] || { [ -z "$out" ] && [ -z "$bullets" ]; }; then
    # none-tier (or nothing hostable): single note line, zero broken image refs.
    printf 'Screenshots persisted on disk; inline hosting unavailable — see manifest.\n'
  fi
  # Manifest reference as a code-span path (relative links never resolve in
  # PR/issue bodies — ad7); emitted, not linked.
  printf '\nManifest: `%s`\n' "${BLOCK_MANIFEST_REF:-.context/images/$WORKTASK_ID/screenshots.md}"
  return 0
}

# ---------- mode: --emit pr -------------------------------------------------
emit_pr() {
  local req; req=$(state_requires_screenshots)
  local dk="$WORKTASK_ID:$RUN_INDEX:visual_evidence:pr"
  if [ "$req" = "false" ]; then
    audit_av "visual_evidence_pr_emitted" "skipped" \
      "$(jq -cn --arg w "$WORKTASK_ID" --argjson r "$RUN_INDEX" --arg dk "$dk" \
         '{worktask_id:$w, run_index:$r, captures:0, host_tier:"none", reason:"requires_screenshots_false", dedupe_key:$dk}')"
    return 0   # empty stdout
  fi
  local mf; mf=$(manifest_path)
  local block _tier_tmp _tier; _tier="none"
  _tier_tmp=$(mktemp 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/ave-tier-pr.$$")
  if block=$(HOST_TIER_FILE="$_tier_tmp" BLOCK_MANIFEST_REF=".context/images/$WORKTASK_ID/screenshots.md" \
             build_block "$mf" "## Visual evidence"); then
    _tier=$(cat "$_tier_tmp" 2>/dev/null || printf 'none'); rm -f "$_tier_tmp"
    printf '%s' "$block"
    local caps; caps=$(printf '%s' "$block" | grep -c '^!\[' || true)
    audit_av "visual_evidence_pr_emitted" "ok" \
      "$(jq -cn --arg w "$WORKTASK_ID" --argjson r "$RUN_INDEX" --argjson c "${caps:-0}" \
         --arg t "$_tier" --arg dk "$dk" \
         '{worktask_id:$w, run_index:$r, captures:$c, host_tier:$t, reason:"emitted", dedupe_key:$dk}')"
  else
    rm -f "$_tier_tmp"
    # No captures → empty emission.
    audit_av "visual_evidence_pr_emitted" "skipped" \
      "$(jq -cn --arg w "$WORKTASK_ID" --argjson r "$RUN_INDEX" --arg dk "$dk" \
         '{worktask_id:$w, run_index:$r, captures:0, host_tier:"none", reason:"no_captures", dedupe_key:$dk}')"
  fi
  return 0
}

# ---------- mode: --post issue ----------------------------------------------
post_issue() {
  local dk="$WORKTASK_ID:$RUN_INDEX:visual_evidence:issue"
  local marker="<!-- visual-evidence:$WORKTASK_ID:$RUN_INDEX -->"

  # Gate 0: milestone mode → defer (parent milestone issue is canonical).
  if [ "${MILESTONE_MODE:-0}" = "1" ] || \
     { [ -f "$STATE_FILE" ] && [ -n "$(jq -r '.metadata.milestone // empty' "$STATE_FILE" 2>/dev/null)" ]; }; then
    audit_av "visual_evidence_issue_commented" "deferred" \
      "$(_issue_meta 0 none milestone_mode "" "$dk")"
    return 0
  fi

  # Gate 1: flag false → skip, no gh call.
  local req; req=$(state_requires_screenshots)
  if [ "$req" = "false" ]; then
    audit_av "visual_evidence_issue_commented" "skipped" \
      "$(_issue_meta 0 none flag_false "" "$dk")"
    return 0
  fi

  # Gate 2: no issue url → defer (publish deferred / failed at Step 6.5).
  local issue_url; issue_url=$(state_get '.metadata.github_issue_url')
  if [ -z "$issue_url" ]; then
    audit_av "visual_evidence_issue_commented" "deferred" \
      "$(_issue_meta 0 none no_issue_url "" "$dk")"
    return 0
  fi

  # Gate 3: build block; no captures → skip.
  local mf; mf=$(manifest_path)
  local block _tier_tmp _tier; _tier="none"
  _tier_tmp=$(mktemp 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/ave-tier-issue.$$")
  if ! block=$(HOST_TIER_FILE="$_tier_tmp" BLOCK_MANIFEST_REF=".context/images/$WORKTASK_ID/screenshots.md" \
               build_block "$mf" "## Visual evidence (DV captures, run $RUN_INDEX)"); then
    rm -f "$_tier_tmp"
    audit_av "visual_evidence_issue_commented" "skipped" \
      "$(_issue_meta 0 none no_captures "$issue_url" "$dk")"
    return 0
  fi
  _tier=$(cat "$_tier_tmp" 2>/dev/null || printf 'none'); rm -f "$_tier_tmp"
  local caps; caps=$(printf '%s' "$block" | grep -c '^!\[' || true)

  # Gate 4: idempotency — marker already present on the issue → skip.
  if issue_has_marker "$issue_url" "$marker"; then
    audit_av "visual_evidence_issue_commented" "skipped" \
      "$(_issue_meta "${caps:-0}" "$_tier" already_published "$issue_url" "$dk")"
    return 0
  fi

  # Post a single marker-tagged comment. gh failure → deferred (non-blocking).
  # NOTE: DRY_RUN governs only ASSET hosting (no cp / reachability probe), NOT the
  # gh call — the orchestrator decides live invocation, and self-tests inject a
  # GH_BIN mock, so the comment path is always exercised through $GH_BIN.
  local comment_body
  comment_body="$(printf '%s\n%s' "$marker" "$block")"
  if printf '%s' "$comment_body" | "$GH_BIN" issue comment "$issue_url" --body-file - >/dev/null 2>&1; then
    audit_av "visual_evidence_issue_commented" "ok" \
      "$(_issue_meta "${caps:-0}" "$_tier" commented "$issue_url" "$dk")"
  else
    audit_av "visual_evidence_issue_commented" "deferred" \
      "$(_issue_meta "${caps:-0}" "$_tier" gh_error "$issue_url" "$dk")"
  fi
  return 0
}

# Build the issue audit metadata JSON. $1=captures $2=tier $3=reason $4=url $5=dk
_issue_meta() {
  jq -cn --arg w "$WORKTASK_ID" --argjson r "$RUN_INDEX" --argjson c "${1:-0}" \
    --arg t "$2" --arg reason "$3" --arg url "$4" --arg dk "$5" \
    '{worktask_id:$w, run_index:$r, issue_url:$url, captures:$c, host_tier:$t, reason:$reason, dedupe_key:$dk}'
}

# Return 0 if the issue already carries the marker (idempotency grep).
issue_has_marker() {
  local url="$1" marker="$2" body
  body=$("$GH_BIN" issue view "$url" --json comments --jq '.comments[].body' 2>/dev/null || true)
  printf '%s' "$body" | grep -qF "$marker"
}

# ---------- context bootstrap ----------------------------------------------
load_context() {
  command -v jq >/dev/null 2>&1 || { echo "attach-visual-evidence: jq not found" >&2; exit 1; }
  [ -r "$STATE_FILE" ] || { echo "attach-visual-evidence: state unreadable: $STATE_FILE" >&2; exit 1; }
  jq -e . "$STATE_FILE" >/dev/null 2>&1 || { echo "attach-visual-evidence: state corrupt" >&2; exit 1; }
  WORKTASK_ID=$(jq -r '.worktask_id // "unknown"' "$STATE_FILE")
  RUN_INDEX=$(jq -r '.run_index // 0' "$STATE_FILE")
}

# ---------- self-test -------------------------------------------------------
run_self_tests() {
  local pass=0 fail=0
  local self="$0"

  _mk_sandbox() { # echoes a fresh sandbox dir with .context/{logs,images/<wid>}
    local td; td=$(mktemp -d)
    mkdir -p "$td/.context/logs" "$td/.context/images/wid-test"
    printf '{"version":1,"worktask_id":"wid-test","run_index":0,"metadata":{"requires_screenshots":true,"github_issue_url":"https://github.com/o/r/issues/9"}}' \
      > "$td/.context/state.json"
    printf '%s' "$td"
  }
  _manifest_with_captures() { # $1=dir : write a 2-capture manifest + dummy PNGs
    local d="$1/.context/images/wid-test"
    cat > "$d/screenshots.md" <<'MD'
# Screenshots — wid-test
| # | Slug | Path | Bytes | Platform | Adapter | Caption | Captured | Design Ref |
|---|------|------|-------|----------|---------|---------|----------|------------|
| 01 | home | dv-01-home.png | 1000 | apple | apple_adapter | home screen | 2026-01-01T00:00:00Z | — |
| 02 | diff | dv-02-diff.txt | 0 | all | cli_fallback | tool_missing | 2026-01-01T00:00:00Z | — |
MD
    printf 'x' > "$d/dv-01-home.png"
  }
  _check() { # $1=label $2=cond(0/1 in $?) -- uses prior exit
    if [ "$1" = ok ]; then pass=$((pass+1)); else fail=$((fail+1)); fi
  }
  _ok()   { echo "attach-visual-evidence: $1 PASS"; pass=$((pass+1)); }
  _fail() { echo "attach-visual-evidence: $1 FAIL${2:+ — $2}"; fail=$((fail+1)); }

  # GH mock: records calls, simulates `issue view` (marker presence via file) and
  # `issue comment`. Marker store = $GH_MARKER_FILE.
  _mk_gh() { # $1=dir
    cat > "$1/bin/gh" <<'MOCK'
#!/usr/bin/env bash
case "$1 $2" in
  "issue view")
    # --json comments --jq ... : echo stored comment bodies (marker store file).
    [ -f "${GH_MARKER_FILE:-/nonexistent}" ] && cat "$GH_MARKER_FILE"
    exit 0 ;;
  "issue comment")
    # read body from stdin (--body-file -) and append to marker store.
    body=$(cat); printf '%s\n' "$body" >> "${GH_MARKER_FILE:-/dev/null}"
    echo "https://github.com/o/r/issues/9#comment-1"; exit 0 ;;
  "auth status") exit 0 ;;
esac
exit 0
MOCK
    chmod +x "$1/bin/gh"
  }

  # ---- f1: --emit pr with captures + mock raw tier → hosted URLs, no broken ![]()
  local d1; d1=$(_mk_sandbox); _manifest_with_captures "$d1"
  local out1
  out1=$(STATE_FILE="$d1/.context/state.json" WORKSPACE_ROOT="$d1" \
         ASSET_HOST_MODE=raw ASSET_OWNER_REPO=o/r ASSET_REF=main DRY_RUN=1 \
         bash "$self" --emit pr 2>/dev/null)
  if printf '%s' "$out1" | grep -q '^## Visual evidence' && \
     printf '%s' "$out1" | grep -q '^!\[dv-01 home screen\](https://raw.githubusercontent.com/' && \
     ! printf '%s' "$out1" | grep -qE '\]\(\)|\]\(\.context/'; then
    _ok "f1-emit-pr-hosted"
  else
    _fail "f1-emit-pr-hosted" "$(printf '%s' "$out1" | head -8 | tr '\n' '~')"
  fi
  # .txt placeholder must be a bullet, never an embed.
  if printf '%s' "$out1" | grep -q '^- dv-02-diff.txt' && \
     ! printf '%s' "$out1" | grep -q '!\[.*dv-02-diff.txt'; then
    _ok "f1-txt-bullet"
  else
    _fail "f1-txt-bullet"
  fi
  rm -rf "$d1"

  # ---- f2: --emit pr PRIVATE + no gist mock → none-tier note, zero ![](
  local d2; d2=$(_mk_sandbox); _manifest_with_captures "$d2"
  local out2
  out2=$(STATE_FILE="$d2/.context/state.json" WORKSPACE_ROOT="$d2" \
         ASSET_HOST_MODE=none ASSET_REPO_VISIBILITY=PRIVATE DRY_RUN=1 \
         bash "$self" --emit pr 2>/dev/null)
  if printf '%s' "$out2" | grep -q '^## Visual evidence' && \
     printf '%s' "$out2" | grep -qi 'inline hosting unavailable' && \
     ! printf '%s' "$out2" | grep -qE '!\['; then
    _ok "f2-private-none-tier"
  else
    _fail "f2-private-none-tier" "$(printf '%s' "$out2" | head -8 | tr '\n' '~')"
  fi
  rm -rf "$d2"

  # ---- f3: --emit pr with skip-rationale manifest → empty stdout + skipped row
  local d3; d3=$(_mk_sandbox)
  cat > "$d3/.context/images/wid-test/screenshots.md" <<'MD'
# Screenshots — wid-test

> Skipped: `metadata.requires_screenshots = false`. Rationale: no UI.
MD
  local out3
  out3=$(STATE_FILE="$d3/.context/state.json" WORKSPACE_ROOT="$d3" \
         ASSET_HOST_MODE=raw DRY_RUN=1 bash "$self" --emit pr 2>/dev/null)
  if [ -z "$out3" ] && grep -q '"reason":"no_captures"' "$d3/.context/logs/audit.jsonl" 2>/dev/null; then
    _ok "f3-skip-manifest-empty"
  else
    _fail "f3-skip-manifest-empty" "out='${out3:0:40}'"
  fi
  rm -rf "$d3"

  # ---- f4: --post issue first run → one comment + ok row
  local d4; d4=$(_mk_sandbox); _manifest_with_captures "$d4"
  mkdir -p "$d4/bin"; _mk_gh "$d4"
  local mfile4="$d4/markers.txt"; : > "$mfile4"
  ( PATH="$d4/bin:$PATH" STATE_FILE="$d4/.context/state.json" WORKSPACE_ROOT="$d4" \
    GH_BIN=gh GH_MARKER_FILE="$mfile4" ASSET_HOST_MODE=raw ASSET_OWNER_REPO=o/r ASSET_REF=main DRY_RUN=1 \
    bash "$self" --post issue >/dev/null 2>&1 )
  if grep -q '"action":"visual_evidence_issue_commented"' "$d4/.context/logs/audit.jsonl" 2>/dev/null && \
     grep -q '"result":"ok"' "$d4/.context/logs/audit.jsonl" 2>/dev/null && \
     grep -qF "<!-- visual-evidence:wid-test:0 -->" "$mfile4"; then
    _ok "f4-post-issue-first"
  else
    _fail "f4-post-issue-first" "$(tail -1 "$d4/.context/logs/audit.jsonl" 2>/dev/null)"
  fi

  # ---- f5: --post issue second run, marker present → skipped/already_published
  ( PATH="$d4/bin:$PATH" STATE_FILE="$d4/.context/state.json" WORKSPACE_ROOT="$d4" \
    GH_BIN=gh GH_MARKER_FILE="$mfile4" ASSET_HOST_MODE=raw ASSET_OWNER_REPO=o/r ASSET_REF=main DRY_RUN=1 \
    bash "$self" --post issue >/dev/null 2>&1 )
  local marker_count; marker_count=$(grep -cF "<!-- visual-evidence:wid-test:0 -->" "$mfile4")
  if [ "$marker_count" -eq 1 ] && \
     grep -q '"reason":"already_published"' "$d4/.context/logs/audit.jsonl" 2>/dev/null; then
    _ok "f5-post-issue-idempotent"
  else
    _fail "f5-post-issue-idempotent" "marker_count=$marker_count"
  fi
  rm -rf "$d4"

  # ---- f6: --post issue without github_issue_url → deferred/no_issue_url
  local d6; d6=$(_mk_sandbox); _manifest_with_captures "$d6"
  # strip the url
  jq 'del(.metadata.github_issue_url)' "$d6/.context/state.json" > "$d6/.context/state.json.t" \
    && mv "$d6/.context/state.json.t" "$d6/.context/state.json"
  mkdir -p "$d6/bin"; _mk_gh "$d6"
  ( PATH="$d6/bin:$PATH" STATE_FILE="$d6/.context/state.json" WORKSPACE_ROOT="$d6" \
    GH_BIN=gh ASSET_HOST_MODE=raw DRY_RUN=1 bash "$self" --post issue >/dev/null 2>&1 )
  if grep -q '"result":"deferred"' "$d6/.context/logs/audit.jsonl" 2>/dev/null && \
     grep -q '"reason":"no_issue_url"' "$d6/.context/logs/audit.jsonl" 2>/dev/null; then
    _ok "f6-post-issue-no-url"
  else
    _fail "f6-post-issue-no-url" "$(tail -1 "$d6/.context/logs/audit.jsonl" 2>/dev/null)"
  fi
  rm -rf "$d6"

  # ---- f7: .txt placeholder + oversize rows → bullets only, zero broken ![](
  local d7; d7=$(_mk_sandbox)
  local dd="$d7/.context/images/wid-test"
  cat > "$dd/screenshots.md" <<'MD'
# Screenshots — wid-test
| # | Slug | Path | Bytes | Platform | Adapter | Caption | Captured | Design Ref |
|---|------|------|-------|----------|---------|---------|----------|------------|
| 01 | diff | dv-01-diff.txt | 0 | all | cli_fallback | tool_missing | 2026-01-01T00:00:00Z | — |

## Out-of-budget files (link-only)

- oversize/dv-02-big.png: 740000 after quantize, exceeds 500 KB
MD
  local out7
  out7=$(STATE_FILE="$d7/.context/state.json" WORKSPACE_ROOT="$d7" \
         ASSET_HOST_MODE=raw ASSET_OWNER_REPO=o/r ASSET_REF=main DRY_RUN=1 \
         bash "$self" --emit pr 2>/dev/null)
  if printf '%s' "$out7" | grep -q '^- dv-01-diff.txt' && \
     printf '%s' "$out7" | grep -q '^- oversize/dv-02-big.png' && \
     ! printf '%s' "$out7" | grep -qE '!\['; then
    _ok "f7-bullets-no-embed"
  else
    _fail "f7-bullets-no-embed" "$(printf '%s' "$out7" | tr '\n' '~')"
  fi
  rm -rf "$d7"

  echo "attach-visual-evidence: self-test summary — pass=$pass fail=$fail"
  [ "$fail" -eq 0 ]
}

# ---------- entrypoint ------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  run_self_tests || exit 2
  exit 0
fi

# Source the tier library (after self-test branch so tests fork fresh processes).
if [ -f "$_LIB" ]; then
  # shellcheck disable=SC1090
  PUBLISH_LIB_ONLY=1 . "$_LIB"
else
  echo "attach-visual-evidence: tier library not found: $_LIB" >&2
  exit 1
fi

load_context

MODE="${1:-}"; TARGET="${2:-}"
case "$MODE" in
  --emit)
    [ "$TARGET" = "pr" ] || { echo "usage: $0 --emit pr" >&2; exit 1; }
    emit_pr ;;
  --post)
    [ "$TARGET" = "issue" ] || { echo "usage: $0 --post issue" >&2; exit 1; }
    post_issue ;;
  *)
    echo "usage: $0 {--emit pr | --post issue | --self-test}" >&2
    exit 1 ;;
esac
exit 0

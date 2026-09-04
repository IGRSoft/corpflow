#!/usr/bin/env bash
# attach-visual-evidence.sh — embed DV screenshot captures into the PR body and
# the GitHub issue, on a UI-change run (metadata.requires_screenshots=true).
#
# Publishing modes (analyzing-0.md ad4, change-map #4), plus a read-only
# --validate-manifest <path> documented with the others below. The publishing modes'
# exit-0 contract is load-bearing — their stdout is spliced into the PR body — so the
# schema check is a SEPARATE mode with its own exit codes and never alters theirs:
#   --emit pr [--force]
#                 Print a ready-to-insert "## Visual evidence" markdown block to
#                 stdout. The PR-body composer (FN agent / FN PR flow /
#                 conductor-attachments skeleton, and adhoc-visual-evidence.sh for
#                 a PR opened outside a worktask) inserts it between ## Test plan
#                 and ## Notes. Empty stdout ⇒ insert nothing (flag false / no
#                 captures). Callers invoke UNCONDITIONALLY; gating lives here.
#                 Idempotent: a second run replays the first run's hosted URLs from
#                 the emission cache instead of re-uploading. --force re-hosts.
#   --post issue  Post ONE marker-deduped `gh issue comment` carrying the same
#                 block. Run by the orchestrator at stage-loop exit (post-FN /
#                 post-push). Non-blocking: operational failures → audit row +
#                 exit 0 (mirrors publish-pl-issue.sh's contract class).
#   --post completion [<pr-ref>]
#                 (AC2) Post-merge completion: resolve every issue the PR closes
#                 via PR-body keywords (Closes|Fixes|Resolves #N, case-insensitive)
#                 ∪ gh closingIssuesReferences, deduped to integers (no untrusted
#                 text in argv). Post ONE completion comment per issue carrying:
#                 1. Work-summary: sourced from .context/complete-summary-<run_index>.md
#                    → state.json facts.goal → PR title+body (sanitised via
#                    sanitise_body; never local paths). 2. Visual-evidence block
#                    (when requires_screenshots=true and captures exist; summary-only
#                    otherwise). Per-issue HTML-marker idempotency
#                    (<!-- completion-summary:<worktask_id>:<run_index>:<issue_n> -->):
#                    a retry never double-posts; partial prior failure re-posts only
#                    missing issues. Each gh failure audits and continues (overall
#                    exit 0 always). Run by orchestrator post-loop after FN merge
#                    ("when the PR closes"). <pr-ref> optional; defaults to current
#                    branch's PR. Defers under milestone mode (parent milestone issue
#                    is canonical); audits no_related_issues when PR closes nothing.
#   --validate-manifest <path>
#                 Read-only schema assertion over the canonical 9-column capture
#                 table. Writes nothing, posts nothing, loads no state. exit 0 valid,
#                 1 schema violation (diagnostic on stdout), 2 manifest not found,
#                 3 no capture rows at all (caller decides whether that is legitimate).
#                 Called by hooks/dv-screenshot-gate.sh so the grammar has one owner.
#
# Image hosting (REQ-5, ad7): reuse publish-pl-issue.sh's host-tier degradation
# by sourcing it under PUBLISH_LIB_ONLY=1 — select_host_tier / host_one_asset /
# gist_raw_url_reachable, with every ASSET_* env mock inherited for free. Relative
# .context/ refs are REJECTED (never render in PR/issue bodies; camo can't fetch
# private/internal raw). none-tier emits note line, never broken ![](). Both
# --post modes share the gist privacy posture: ASSET_GIST_PUBLIC is tri-state —
# 1 forces a world-readable gist, 0 forces secret/unlisted, and empty (the
# default) auto-derives from repo visibility, declining --public on a
# PRIVATE/INTERNAL repo where it adds indexing without improving rendering.
# Neither kind preserves screenshot confidentiality (camo fetches anonymously);
# do not capture secrets/tokens/PII (C3 capture policy), and use
# ASSET_HOST_MODE=none for material that must not leave the org. See
# publish-pl-issue.sh header § AC1 Privacy posture for full rationale.
#
# Idempotency (all three publishing modes):
#   --emit pr:    cached at .context/logs/visual-evidence-pr-<worktask_id>-<run_index>.md,
#                 written on a successful emission and replayed verbatim on any later
#                 run. The --post modes dedupe on a marker they can read back off the
#                 issue; --emit has no such remote to consult, so the cache IS the
#                 marker. Without it a second run re-hosts every asset and orphans the
#                 first set on GitHub. --force bypasses (re-hosts and rewrites cache).
#   --post issue: marked with <!-- visual-evidence:<worktask_id>:<run_index> -->
#   --post completion: marked with <!-- completion-summary:<worktask_id>:<run_index>:<issue_n> -->
# Exact-match grep (no regex breakout); retry never double-posts.
#
# Exit codes: 0 all operational paths (incl. deferred/skipped), 1 catastrophic
# (jq missing / state corrupt — mirrors publish helper), 2 --self-test failure.
#
# Env (injection / test hooks): STATE_FILE, WORKSPACE_ROOT, GH_BIN, DRY_RUN, plus
# every ASSET_* / *_URL_BASE hook honoured by publish-pl-issue.sh (inherited via
# the source-guard). MANIFEST_FILE overrides manifest discovery in self-tests.
# MILESTONE_MODE=1 env override for offline testing.

set -u

# ---------- defaults / env --------------------------------------------------
STATE_FILE="${STATE_FILE:-.context/state.json}"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-${CLAUDE_PROJECT_DIR:-.}}"
GH_BIN="${GH_BIN:-gh}"
DRY_RUN="${DRY_RUN:-0}"
LOG_DIR="${WORKSPACE_ROOT}/.context/logs"
AUDIT_FILE="$LOG_DIR/audit.jsonl"
MAX_EMBED="${MAX_EMBED:-5}"   # PR/issue embed cap (mirrors capture skill's 5-per-run cap)

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

# ---------- mode: --validate-manifest (read-only) ---------------------------
# Schema assertion for hooks/dv-screenshot-gate.sh, living HERE so the 9-column
# grammar has exactly one implementation. A second copy in the gate would recreate
# the duplicated-map drift the artifact-map parity guard exists to police.
#
# Canonical row: | # | Slug | Path | Bytes | Platform | Adapter | Caption | Captured | Design Ref |
# with a mandatory two-digit index. A manifest carrying NO capture rows is reported as
# exit 3 rather than judged here: whether that is a skip rationale or dropped evidence
# depends on what sits beside the file, which the caller sees and this parser does not.
#
#   exit 0  structurally valid, at least one canonical capture row
#   exit 1  schema violation (diagnostic on stdout)
#   exit 2  manifest missing or unreadable
#   exit 3  well-formed but carries no capture rows — legitimate only when no captures
#           exist beside it, which the caller (not this parser) is the one that knows
validate_manifest() {
  local mf="$1" bad rows
  if [ -z "$mf" ] || [ ! -f "$mf" ]; then
    printf 'manifest not found: %s\n' "${mf:-<unset>}"
    return 2
  fi

  # Candidate rows are pipe-tables minus the header and the --- separator. Each
  # violation is reported with its line number so the writer can fix the row, not
  # re-author the file.
  bad=$(LC_ALL=C awk -F'|' '
    /^[[:space:]]*\|/ {
      for (i=1;i<=NF;i++){ gsub(/^[[:space:]]+|[[:space:]]+$/,"",$i) }
      if ($2 == "#" || tolower($2) == "no." ) next          # header
      if ($2 ~ /^:?-+:?$/ || $3 ~ /^:?-+:?$/) next          # separator, incl. alignment rows
      if ($2 == "" && $3 == "") next                        # blank filler
      if (NF - 2 != 9) {
        printf "line %d: %d columns, expected 9\n", NR, NF - 2
        next
      }
      if ($2 !~ /^[0-9][0-9]$/) {
        printf "line %d: index \"%s\" is not a two-digit ordinal\n", NR, $2
        next
      }
      if ($4 == "") { printf "line %d: empty Path column\n", NR }
    }
  ' "$mf")

  if [ -n "$bad" ]; then
    printf 'manifest schema violation(s) in %s:\n%s\n' "$mf" "$bad"
    return 1
  fi

  rows=$(parse_manifest "$mf" | grep -c . || true)
  if [ "$rows" -eq 0 ]; then
    if grep -qE '^[[:space:]]*\|[[:space:]]*[0-9]' "$mf"; then
      printf 'manifest schema violation in %s: table rows present but none matches the canonical schema\n' "$mf"
      return 1
    fi
    # No capture rows at all. Whether that is a legitimate skip-rationale manifest or a
    # silently dropped capture depends on what sits NEXT to the file, which is the caller's
    # knowledge, not the parser's — so report the fact and let the gate apply the policy.
    printf 'manifest %s carries no canonical capture rows\n' "$mf"
    return 3
  fi

  return 0
}

# ---------- block builder ---------------------------------------------------
# Build the "## Visual evidence" block from a parsed manifest.
#   stdout: the block (may be empty)
#   Heading arrives as $2. BLOCK_MANIFEST_REF is the one global read here, a
#   test-only override callers leave unset so the path-free default applies.
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
  # Counts EMBEDDABLE rows only (kind=png). placeholder/oversize rows are never
  # embedded by design, so counting them would fire the degradation notice on
  # every healthy run and train the operator to ignore it.
  local hostable=0
  # Per-bullet text stays short; the WHY is emitted once below (host_fail_note) so
  # a 5-capture run does not repeat a paragraph five times.
  local HOST_FAIL_HINT="not embeddable; see note below." host_fail=0
  # The embed cap and a hosting failure are different degradations with different
  # remedies, and only the second is fixed by a token. Tracked separately so the reason,
  # the body note and the operator advice can each name the one that actually fired.
  local cap_hit=0
  local host_fail_note
  case "$(repo_visibility 2>/dev/null || printf '')" in
    PRIVATE|INTERNAL)
      host_fail_note="Could not host these inline. On a private/internal repo the raw tier is refused (camo fetches anonymously and would 404) and gists reject binary files, so the working path is GitHub's user-attachments store — install the uploader with \`gh extension install drogers0/gh-image\` and re-run, or drag the files into this body via the web UI. The captures are on disk at the manifest path." ;;
    *)
      host_fail_note="Hosting failed for the captures above; they remain on disk at the manifest path." ;;
  esac

  while IFS="$(printf '\t')" read -r num path cap kind; do
    [ -z "$path" ] && continue
    case "$kind" in
      png)
        hostable=$((hostable+1))
        if [ "$embed_count" -ge "$MAX_EMBED" ]; then
          bullets="${bullets}- ${path} — omitted (embed cap ${MAX_EMBED}); see manifest."$'\n'
          cap_hit=1
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
          bullets="${bullets}- ${path} — ${HOST_FAIL_HINT}"$'\n'
          host_fail=1
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
  elif [ "$host_fail" = "1" ]; then
    # Explain the degradation once, in terms an operator can act on.
    printf '\n%s\n' "$host_fail_note"
  fi
  # State the cap in the body itself. The per-row bullets already said "omitted", but the
  # summary read as a healthy run: a reader had no way to tell a capped run from one that
  # captured only what is shown.
  if [ "$cap_hit" = "1" ]; then
    # "hosting is healthy" only when no row failed to host; both can fire in one run.
    printf '\nOnly the first %d capture(s) are embedded inline (embed cap %d). The rest are listed above and on disk at the manifest path%s\n' \
      "$MAX_EMBED" "$MAX_EMBED" "$([ "$host_fail" = "1" ] && printf '.' || printf '; hosting is healthy.')"
  fi
  # Manifest reference, deliberately PATH-FREE. Two independent reasons: relative
  # links never resolve in PR/issue bodies (ad7), and the working-folder path is
  # local + gitignored, so it is meaningless to a reviewer. It used to be emitted
  # as a code span, which also happened to be the one shape that defeated the
  # sanitiser's pass-1 anchors -- that is now closed in publish-pl-issue.sh, and a
  # path here would simply be stripped, leaving "see manifest" naming nothing.
  # Assigned in two steps rather than via ${VAR:-word}: bash treats an apostrophe
  # inside the word part as an opening quote even within double quotes.
  local manifest_ref="${BLOCK_MANIFEST_REF:-}"
  [ -n "$manifest_ref" ] || manifest_ref="screenshots.md, in this run's local images folder (not committed)."
  printf '\nManifest: %s\n' "$manifest_ref"

  # D4 -- notify when captures exist but did not reach the reader. Emitted from
  # inside build_block on purpose: callers wrap this in $(), which captures stdout
  # only, so stderr and the audit append both still escape. Uses "<" not "== 0" so
  # partial loss (e.g. the MAX_EMBED cap silently dropping the 6th capture) is
  # caught too, not just total failure.
  if [ "$hostable" -gt 0 ] && [ "$embed_count" -lt "$hostable" ]; then
    # The reason used to come from the hosting probe ALONE, so a capped-but-healthy run
    # reported a hosting reason (often `unknown`) on a row nothing was wrong with.
    local reason seen
    if [ "$cap_hit" = "1" ] && [ "$host_fail" = "1" ]; then
      reason="embed_cap+${GH_IMAGE_FAIL_REASON:-unknown}"
    elif [ "$cap_hit" = "1" ]; then
      reason="embed_cap"
    else
      reason="${GH_IMAGE_FAIL_REASON:-unknown}"
    fi
    if [ "$embed_count" -eq 0 ]; then
      seen="no images"
    else
      seen="only $embed_count of $hostable images"
    fi
    printf >&2 'attach-visual-evidence: NOTICE — %d capture(s) on disk, %d embedded (reason=%s).\n' \
      "$hostable" "$embed_count" "$reason"
    # A token fixes hosting; it does not raise the cap. Telling a capped run to supply one
    # sends the operator after a credential that changes nothing.
    if [ "$cap_hit" = "1" ] && [ "$host_fail" != "1" ]; then
      printf >&2 '  Reviewers will see %s. This is the embed cap (%d), not a hosting failure — the remaining captures are on disk and listed in the body; a session token would not change it.\n' \
        "$seen" "$MAX_EMBED"
    else
      printf >&2 '  Reviewers will see %s. Set GH_SESSION_TOKEN to make tier-0 non-interactive.\n' "$seen"
    fi
    audit_av visual_evidence_degraded degraded \
      "$(jq -cn --argjson c "$hostable" --argjson e "$embed_count" \
              --arg r "$reason" --arg t "${HOST_TIER:-unknown}" \
          '{captured:$c, embedded:$e, reason:$r, host_tier:$t}' 2>/dev/null || printf '{}')"
  fi
  return 0
}

# Classify a zero-row outcome. "no_captures" means DV genuinely produced nothing;
# "manifest_unparseable" means a manifest exists AND image files sit beside it, but
# no table row parsed — i.e. the manifest does not follow the canonical schema
#   | NN | slug | path | bytes | platform | adapter | caption | captured | ref |
# (col2 MUST be two digits: `01`, not `1`). That case is a silent-evidence-loss
# trap: the screenshots gate passes on file presence while the attach step no-ops,
# so the PR ships with the evidence missing and nothing says so. Warn loudly and
# audit distinguishably instead of reporting it as "no captures".
manifest_diagnosis() {
  local mf="$1"
  [ -f "$mf" ] || { printf 'no_captures'; return 0; }
  local dir imgs
  dir=$(dirname "$mf")
  imgs=$(find "$dir" -maxdepth 1 -type f \
           \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) 2>/dev/null | wc -l | tr -d ' ')
  if [ "${imgs:-0}" -gt 0 ]; then
    printf 'manifest_unparseable'
    echo "attach-visual-evidence: WARNING — $mf has $imgs image file(s) beside it but zero parseable table rows." >&2
    echo "attach-visual-evidence: the manifest must use the canonical 9-column schema with a TWO-DIGIT index:" >&2
    echo "attach-visual-evidence:   | # | Slug | Path | Bytes | Platform | Adapter | Caption | Captured | Design Ref |" >&2
    echo "attach-visual-evidence:   | 01 | header | dv-01-header.png | 78683 | apple | apple_sim | after | <ts> | — |" >&2
    echo "attach-visual-evidence: evidence was NOT attached. See skills/dv-screenshot-capture/references/examples/README.md" >&2
    return 0
  fi
  printf 'no_captures'
}

# ---------- mode: --emit pr -------------------------------------------------
# Path of the emission cache for this worktask run.
emit_pr_cache_path() {
  printf '%s/visual-evidence-pr-%s-%s.md' "$LOG_DIR" "$WORKTASK_ID" "$RUN_INDEX"
}

# True when this run already emitted successfully: an `ok` audit row carrying this
# run's dedupe key AND a cache file to replay. Both halves are required — a pruned
# cache must re-host rather than emit nothing, which would drop evidence silently.
emit_pr_already_emitted() {
  local dk="$1" cache="$2"
  [ -s "$cache" ] || return 1
  [ -f "$AUDIT_FILE" ] || return 1
  grep -F "\"dedupe_key\":\"$dk\"" "$AUDIT_FILE" 2>/dev/null \
    | grep -qF '"action":"visual_evidence_pr_emitted","result":"ok"'
}

emit_pr() {
  local req; req=$(state_requires_screenshots)
  local dk="$WORKTASK_ID:$RUN_INDEX:visual_evidence:pr"
  local cache; cache=$(emit_pr_cache_path)

  if [ "${FORCE:-0}" != "1" ] && emit_pr_already_emitted "$dk" "$cache"; then
    cat "$cache"
    audit_av "visual_evidence_pr_emitted" "reused" \
      "$(jq -cn --arg w "$WORKTASK_ID" --argjson r "$RUN_INDEX" --arg dk "$dk" --arg c "$cache" \
         '{worktask_id:$w, run_index:$r, host_tier:"cache", reason:"already_emitted", cache:$c, dedupe_key:$dk}')"
    return 0
  fi

  if [ "$req" = "false" ]; then
    audit_av "visual_evidence_pr_emitted" "skipped" \
      "$(jq -cn --arg w "$WORKTASK_ID" --argjson r "$RUN_INDEX" --arg dk "$dk" \
         '{worktask_id:$w, run_index:$r, captures:0, host_tier:"none", reason:"requires_screenshots_false", dedupe_key:$dk}')"
    return 0   # empty stdout
  fi
  local mf; mf=$(manifest_path)
  local block _tier_tmp _tier; _tier="none"
  _tier_tmp=$(mktemp 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/ave-tier-pr.$$")
  if block=$(HOST_TIER_FILE="$_tier_tmp" \
             build_block "$mf" "## Visual evidence"); then
    _tier=$(cat "$_tier_tmp" 2>/dev/null || printf 'none'); rm -f "$_tier_tmp"
    printf '%s' "$block"
    mkdir -p "$LOG_DIR" 2>/dev/null && printf '%s' "$block" > "$cache" 2>/dev/null || true
    local caps; caps=$(printf '%s' "$block" | grep -c '^!\[' || true)
    audit_av "visual_evidence_pr_emitted" "ok" \
      "$(jq -cn --arg w "$WORKTASK_ID" --argjson r "$RUN_INDEX" --argjson c "${caps:-0}" \
         --arg t "$_tier" --arg dk "$dk" \
         '{worktask_id:$w, run_index:$r, captures:$c, host_tier:$t, reason:"emitted", dedupe_key:$dk}')"
  else
    rm -f "$_tier_tmp"
    # Zero rows → empty emission. Distinguish "nothing captured" from "captures on
    # disk that the manifest failed to describe" (manifest_diagnosis warns on stderr).
    local reason; reason=$(manifest_diagnosis "$mf")
    audit_av "visual_evidence_pr_emitted" "skipped" \
      "$(jq -cn --arg w "$WORKTASK_ID" --argjson r "$RUN_INDEX" --arg dk "$dk" --arg reason "$reason" \
         '{worktask_id:$w, run_index:$r, captures:0, host_tier:"none", reason:$reason, dedupe_key:$dk}')"
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
  if ! block=$(HOST_TIER_FILE="$_tier_tmp" \
               build_block "$mf" "## Visual evidence (DV captures, run $RUN_INDEX)"); then
    rm -f "$_tier_tmp"
    audit_av "visual_evidence_issue_commented" "skipped" \
      "$(_issue_meta 0 none no_captures "$issue_url" "$dk")"
    return 0
  fi
  _tier=$(cat "$_tier_tmp" 2>/dev/null || printf 'none'); rm -f "$_tier_tmp"
  local caps; caps=$(printf '%s' "$block" | grep -c '^!\[' || true)

  # Gate 4: idempotency — marker already present on the issue → skip.
  if pl_issue_has_marker "$issue_url" "$marker"; then
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

# ---------- context bootstrap ----------------------------------------------
load_context() {
  command -v jq >/dev/null 2>&1 || { echo "attach-visual-evidence: jq not found" >&2; exit 1; }
  [ -r "$STATE_FILE" ] || { echo "attach-visual-evidence: state unreadable: $STATE_FILE" >&2; exit 1; }
  jq -e . "$STATE_FILE" >/dev/null 2>&1 || { echo "attach-visual-evidence: state corrupt" >&2; exit 1; }
  WORKTASK_ID=$(jq -r '.worktask_id // "unknown"' "$STATE_FILE")
  RUN_INDEX=$(jq -r '.run_index // 0' "$STATE_FILE")
}

# ---------- mode: --post completion (AC2) -----------------------------------
# Post-merge completion summary to every issue the PR closes. Resolves related
# issues (PR-body keywords ∪ closingIssuesReferences, deduped ints), posts one
# marker-deduped comment per issue. Non-blocking: each gh failure → audit row +
# continue; overall exit 0. Marker grammar (EXACT):
#   <!-- completion-summary:<worktask_id>:<run_index>:<issue_n> -->

# Emit the per-issue idempotency marker. $1=issue_n.
_completion_marker() {
  printf '<!-- completion-summary:%s:%s:%s -->' "$WORKTASK_ID" "$RUN_INDEX" "$1"
}

# Resolve related issues for a PR. $1=optional pr-ref (number or URL); default =
# current branch's PR (gh resolves it inside the worktree). Output: newline-sep
# sorted-unique INTEGERS on stdout. Empty on no refs / gh failure. Always rc 0,
# never blocks. SECURITY: output is filtered to ^[0-9]+$ so no shell metachar
# from an untrusted PR body can ever reach a downstream gh argv.
resolve_related_issues() {
  local ref="${1:-}"
  local body_json refs_json kw_nums ref_nums
  # Source 1: PR body keywords (Closes|Fixes|Resolves #N, case-insensitive).
  if [ -n "$ref" ]; then
    body_json=$("$GH_BIN" pr view "$ref" --json body --jq '.body' 2>/dev/null || true)
  else
    body_json=$("$GH_BIN" pr view --json body --jq '.body' 2>/dev/null || true)
  fi
  kw_nums=$(printf '%s\n' "$body_json" \
    | grep -ioE '(close[sd]?|fix(e[sd])?|resolve[sd]?)[[:space:]]+#[0-9]+' \
    | grep -oE '[0-9]+' || true)
  # Source 2: closingIssuesReferences (GitHub's resolved link set).
  if [ -n "$ref" ]; then
    refs_json=$("$GH_BIN" pr view "$ref" --json closingIssuesReferences \
      --jq '.closingIssuesReferences[].number' 2>/dev/null || true)
  else
    refs_json=$("$GH_BIN" pr view --json closingIssuesReferences \
      --jq '.closingIssuesReferences[].number' 2>/dev/null || true)
  fi
  ref_nums=$(printf '%s\n' "$refs_json" | grep -oE '[0-9]+' || true)
  # Union + dedup, integer-only (mandatory security + correctness filter).
  printf '%s\n%s\n' "$kw_nums" "$ref_nums" \
    | grep -E '^[0-9]+$' \
    | sort -un
  return 0
}

# Source the work-summary text for the completion comment (sanitised). First
# available wins: complete-summary-<run_index>.md → state.json facts/goal → PR
# title+body. Reads nothing from untrusted argv; output is sanitised via the
# library sanitise_body so leaked local paths never reach the comment.
_completion_summary_text() {
  local ref="${1:-}"
  local summ_file="$WORKSPACE_ROOT/.context/complete-summary-$RUN_INDEX.md"
  if [ -f "$summ_file" ]; then
    sanitise_body < "$summ_file"
    return 0
  fi
  # Fallback 1: state.json facts.goal (+ facts summary if present).
  local goal
  goal=$(jq -r '.facts.goal // empty' "$STATE_FILE" 2>/dev/null || true)
  if [ -n "$goal" ]; then
    printf '%s' "$goal" | sanitise_body
    return 0
  fi
  # Fallback 2: PR title + body.
  local pr_txt
  if [ -n "$ref" ]; then
    pr_txt=$("$GH_BIN" pr view "$ref" --json title,body \
      --jq '"\(.title)\n\n\(.body)"' 2>/dev/null || true)
  else
    pr_txt=$("$GH_BIN" pr view --json title,body \
      --jq '"\(.title)\n\n\(.body)"' 2>/dev/null || true)
  fi
  printf '%s' "$pr_txt" | sanitise_body
  return 0
}

# Build the completion comment body for one issue. $1=issue_n, $2=optional pr-ref.
# Layout: marker + heading + work-summary [+ visual-evidence block]. The block is
# appended only when requires_screenshots==true AND captures exist (build_block
# returns 0). Summary-only otherwise — NO broken refs, NO note spam. stdout only.
build_completion_body() {
  local issue_n="$1" ref="${2:-}"
  local marker summary req
  marker=$(_completion_marker "$issue_n")
  summary=$(_completion_summary_text "$ref")
  printf '%s\n' "$marker"
  printf '## Worktask completed\n\n'
  [ -n "$summary" ] && printf '%s\n' "$summary"
  # Append the visual-evidence block only when screenshots are on AND captures
  # exist. build_block returns non-zero (no output) when there are no captures.
  req=$(state_requires_screenshots)
  if [ "$req" != "false" ]; then
    local mf block _tier_tmp
    mf=$(manifest_path)
    _tier_tmp=$(mktemp 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/ave-tier-comp.$$")
    if block=$(HOST_TIER_FILE="$_tier_tmp" \
               build_block "$mf" "## Visual evidence (DV captures, run $RUN_INDEX)"); then
      printf '\n%s' "$block"
    fi
    rm -f "$_tier_tmp"
  fi
  return 0
}

# Build the per-issue completion audit metadata JSON.
#   $1=issue_n $2=result-reason $3=dedupe_key
_completion_meta() {
  jq -cn --arg w "$WORKTASK_ID" --argjson r "$RUN_INDEX" \
    --argjson issue "$1" --arg reason "$2" --arg dk "$3" \
    '{worktask_id:$w, run_index:$r, issue:$issue, reason:$reason, dedupe_key:$dk}'
}

# Post one completion comment per related issue. $1=optional pr-ref. Non-blocking.
post_completion() {
  local ref="${1:-}"
  local action="completion_summary_commented"

  # Gate 0: milestone mode → defer (parent milestone issue is canonical).
  if [ "${MILESTONE_MODE:-0}" = "1" ] || \
     { [ -f "$STATE_FILE" ] && [ -n "$(jq -r '.metadata.milestone // empty' "$STATE_FILE" 2>/dev/null)" ]; }; then
    audit_av "$action" "deferred" \
      "$(_completion_meta 0 milestone_mode "$WORKTASK_ID:$RUN_INDEX:completion:all")"
    return 0
  fi

  # Gate 1: resolve related issues. Empty → audit no_related_issues, exit 0.
  local issues; issues=$(resolve_related_issues "$ref")
  if [ -z "$issues" ]; then
    audit_av "$action" "skipped" \
      "$(_completion_meta 0 no_related_issues "$WORKTASK_ID:$RUN_INDEX:completion:none")"
    return 0
  fi

  # One comment per issue. Integers only (resolver-validated). Non-blocking.
  local n marker dk body
  while IFS= read -r n; do
    [ -z "$n" ] && continue
    dk="$WORKTASK_ID:$RUN_INDEX:completion:$n"
    marker=$(_completion_marker "$n")
    # Gate 2: idempotency — per-issue marker already present → skip.
    if pl_issue_has_marker "$n" "$marker"; then
      audit_av "$action" "skipped" "$(_completion_meta "$n" already_published "$dk")"
      continue
    fi
    body=$(build_completion_body "$n" "$ref")
    # Gate 3: post via stdin (--body-file -); never interpolate body into argv.
    if printf '%s' "$body" | "$GH_BIN" issue comment "$n" --body-file - >/dev/null 2>&1; then
      audit_av "$action" "ok" "$(_completion_meta "$n" commented "$dk")"
    else
      audit_av "$action" "deferred" "$(_completion_meta "$n" gh_error "$dk")"
    fi
  done <<EOF
$issues
EOF
  return 0
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
  _ok()   { echo "attach-visual-evidence: $1 PASS"; pass=$((pass+1)); }
  _fail() { echo "attach-visual-evidence: $1 FAIL${2:+ — $2}"; fail=$((fail+1)); }

  # GH mock: records calls, simulates `issue view` (marker presence via file) and
  # `issue comment`. Marker store = $GH_MARKER_DIR/<target> (per-issue). The mock also answers
  # `pr view` for the completion resolver/summary:
  #   $GH_PR_BODY    → PR body for keyword scan + title/body fallback
  #   $GH_PR_REFS    → space-separated issue numbers for closingIssuesReferences
  #   $GH_PR_TITLE   → PR title (title,body fallback)
  #   $GH_FAIL_ISSUES→ space-separated issue numbers whose `issue comment` fails
  _mk_gh() { # $1=dir
    cat > "$1/bin/gh" <<'MOCK'
#!/usr/bin/env bash
# Per-target marker store path. target = the issue ref/number ($3).
_store() {
  # Per-issue marker file under $GH_MARKER_DIR. With the dir unset there is no
  # per-target store, so sink to /dev/null rather than composing /dev/null/<target>,
  # which is ENOTDIR and would make every read and write in the mock fail.
  if [ -z "${GH_MARKER_DIR:-}" ]; then
    printf '/dev/null'
    return 0
  fi
  printf '%s/%s' "$GH_MARKER_DIR" "$(printf '%s' "${1:-_}" | tr '/:' '__')"
}
case "$1 $2" in
  "pr view")
    # Determine which --json field was asked for.
    if printf '%s' "$*" | grep -q 'closingIssuesReferences'; then
      for n in ${GH_PR_REFS:-}; do printf '%s\n' "$n"; done
    elif printf '%s' "$*" | grep -q 'title,body'; then
      printf '%s\n\n%s\n' "${GH_PR_TITLE:-}" "${GH_PR_BODY:-}"
    else
      # --json body
      printf '%s\n' "${GH_PR_BODY:-}"
    fi
    exit 0 ;;
  "issue view")
    # --json comments --jq ... : echo stored comment bodies for this target.
    s=$(_store "$3"); [ -f "$s" ] && cat "$s"
    exit 0 ;;
  "issue comment")
    # Simulated failure for selected issues (f12).
    for f in ${GH_FAIL_ISSUES:-}; do [ "$f" = "$3" ] && exit 1; done
    body=$(cat); s=$(_store "$3"); printf '%s\n' "$body" >> "$s"
    echo "https://github.com/o/r/issues/$3#comment-1"; exit 0 ;;
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
  local mdir4="$d4/markers"; mkdir -p "$mdir4"
  ( PATH="$d4/bin:$PATH" STATE_FILE="$d4/.context/state.json" WORKSPACE_ROOT="$d4" \
    GH_BIN=gh GH_MARKER_DIR="$mdir4" ASSET_HOST_MODE=raw ASSET_OWNER_REPO=o/r ASSET_REF=main DRY_RUN=1 \
    bash "$self" --post issue >/dev/null 2>&1 )
  if grep -q '"action":"visual_evidence_issue_commented"' "$d4/.context/logs/audit.jsonl" 2>/dev/null && \
     grep -q '"result":"ok"' "$d4/.context/logs/audit.jsonl" 2>/dev/null && \
     grep -rqF "<!-- visual-evidence:wid-test:0 -->" "$mdir4"; then
    _ok "f4-post-issue-first"
  else
    _fail "f4-post-issue-first" "$(tail -1 "$d4/.context/logs/audit.jsonl" 2>/dev/null)"
  fi

  # ---- f5: --post issue second run, marker present → skipped/already_published
  ( PATH="$d4/bin:$PATH" STATE_FILE="$d4/.context/state.json" WORKSPACE_ROOT="$d4" \
    GH_BIN=gh GH_MARKER_DIR="$mdir4" ASSET_HOST_MODE=raw ASSET_OWNER_REPO=o/r ASSET_REF=main DRY_RUN=1 \
    bash "$self" --post issue >/dev/null 2>&1 )
  local marker_count; marker_count=$(cat "$mdir4"/* 2>/dev/null | grep -cF "<!-- visual-evidence:wid-test:0 -->")
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

  # ---- f8: resolve_related_issues — keyword-only / refs-only / union+dedup ----
  # Drive the resolver directly via declare -f with a gh mock on PATH. All
  # offline (GH_PR_BODY / GH_PR_REFS mocks).
  local d8; d8=$(_mk_sandbox); mkdir -p "$d8/bin"; _mk_gh "$d8"
  _resolve() { # $1=body $2=refs ; echoes resolver output (sorted unique ints)
    PATH="$d8/bin:$PATH" GH_BIN=gh GH_PR_BODY="$1" GH_PR_REFS="$2" \
      WORKTASK_ID=wid-test RUN_INDEX=0 \
      bash -c '
        GH_BIN=gh
        '"$(declare -f resolve_related_issues)"'
        resolve_related_issues ""
      '
  }
  local r_kw r_refs r_union f8_ok=1
  r_kw=$(_resolve "Closes #10"$'\n'"Fixes #12" "")
  [ "$(printf '%s' "$r_kw" | tr '\n' ' ')" = "10 12" ] || f8_ok=0
  r_refs=$(_resolve "no keywords here" "12 15")
  [ "$(printf '%s' "$r_refs" | tr '\n' ' ')" = "12 15" ] || f8_ok=0
  r_union=$(_resolve "Closes #10" "12 10")
  [ "$(printf '%s' "$r_union" | tr '\n' ' ')" = "10 12" ] || f8_ok=0
  if [ "$f8_ok" = "1" ]; then
    _ok "f8-resolve-union-dedup"
  else
    _fail "f8-resolve-union-dedup" "kw='$(printf '%s' "$r_kw" | tr '\n' ',')' refs='$(printf '%s' "$r_refs" | tr '\n' ',')' union='$(printf '%s' "$r_union" | tr '\n' ',')'"
  fi
  rm -rf "$d8"

  # ---- f9: --post completion first run → one comment per issue + ok rows ----
  local d9; d9=$(_mk_sandbox); _manifest_with_captures "$d9"
  mkdir -p "$d9/bin" "$d9/markers"; _mk_gh "$d9"
  ( PATH="$d9/bin:$PATH" STATE_FILE="$d9/.context/state.json" WORKSPACE_ROOT="$d9" \
    GH_BIN=gh GH_MARKER_DIR="$d9/markers" GH_PR_BODY="Closes #10"$'\n'"Fixes #12" GH_PR_REFS="" \
    ASSET_HOST_MODE=raw ASSET_OWNER_REPO=o/r ASSET_REF=main DRY_RUN=1 \
    bash "$self" --post completion >/dev/null 2>&1 )
  local f9_ok=1
  [ -f "$d9/markers/10" ] && grep -qF "<!-- completion-summary:wid-test:0:10 -->" "$d9/markers/10" || f9_ok=0
  [ -f "$d9/markers/12" ] && grep -qF "<!-- completion-summary:wid-test:0:12 -->" "$d9/markers/12" || f9_ok=0
  local ok_rows; ok_rows=$(grep -c '"action":"completion_summary_commented".*"result":"ok"' "$d9/.context/logs/audit.jsonl" 2>/dev/null || echo 0)
  [ "${ok_rows:-0}" -eq 2 ] || f9_ok=0
  if [ "$f9_ok" = "1" ]; then
    _ok "f9-completion-first-run"
  else
    _fail "f9-completion-first-run" "ok_rows=$ok_rows $(tail -2 "$d9/.context/logs/audit.jsonl" 2>/dev/null | tr '\n' '~')"
  fi

  # ---- f10: --post completion second run → idempotent, no duplicate ----
  ( PATH="$d9/bin:$PATH" STATE_FILE="$d9/.context/state.json" WORKSPACE_ROOT="$d9" \
    GH_BIN=gh GH_MARKER_DIR="$d9/markers" GH_PR_BODY="Closes #10"$'\n'"Fixes #12" GH_PR_REFS="" \
    ASSET_HOST_MODE=raw ASSET_OWNER_REPO=o/r ASSET_REF=main DRY_RUN=1 \
    bash "$self" --post completion >/dev/null 2>&1 )
  local f10_ok=1 m10 m12 already
  m10=$(grep -cF "<!-- completion-summary:wid-test:0:10 -->" "$d9/markers/10")
  m12=$(grep -cF "<!-- completion-summary:wid-test:0:12 -->" "$d9/markers/12")
  [ "$m10" -eq 1 ] && [ "$m12" -eq 1 ] || f10_ok=0   # still exactly one each
  already=$(grep -c '"reason":"already_published"' "$d9/.context/logs/audit.jsonl" 2>/dev/null || echo 0)
  [ "${already:-0}" -ge 2 ] || f10_ok=0
  if [ "$f10_ok" = "1" ]; then
    _ok "f10-completion-idempotent"
  else
    _fail "f10-completion-idempotent" "m10=$m10 m12=$m12 already=$already"
  fi
  rm -rf "$d9"

  # ---- f11: requires_screenshots=false → summary-only comment, no image refs ----
  local d11; d11=$(_mk_sandbox)
  jq '.metadata.requires_screenshots=false' "$d11/.context/state.json" > "$d11/.context/state.json.t" \
    && mv "$d11/.context/state.json.t" "$d11/.context/state.json"
  mkdir -p "$d11/bin" "$d11/markers"; _mk_gh "$d11"
  ( PATH="$d11/bin:$PATH" STATE_FILE="$d11/.context/state.json" WORKSPACE_ROOT="$d11" \
    GH_BIN=gh GH_MARKER_DIR="$d11/markers" GH_PR_BODY="Closes #10" GH_PR_REFS="" DRY_RUN=1 \
    bash "$self" --post completion >/dev/null 2>&1 )
  local f11_ok=1
  [ -f "$d11/markers/10" ] || f11_ok=0
  # Summary present (heading), but NO image embeds and NO hosting note spam.
  grep -qF "## Worktask completed" "$d11/markers/10" || f11_ok=0
  grep -qE '!\[' "$d11/markers/10" && f11_ok=0
  grep -qi 'inline hosting unavailable' "$d11/markers/10" && f11_ok=0
  grep -qF "## Visual evidence" "$d11/markers/10" && f11_ok=0
  if [ "$f11_ok" = "1" ]; then
    _ok "f11-completion-summary-only"
  else
    _fail "f11-completion-summary-only" "$(cat "$d11/markers/10" 2>/dev/null | tr '\n' '~')"
  fi
  rm -rf "$d11"

  # ---- f12: gh failure on one issue → continue to others, exit 0 ----
  local d12; d12=$(_mk_sandbox); _manifest_with_captures "$d12"
  mkdir -p "$d12/bin" "$d12/markers"; _mk_gh "$d12"
  ( PATH="$d12/bin:$PATH" STATE_FILE="$d12/.context/state.json" WORKSPACE_ROOT="$d12" \
    GH_BIN=gh GH_MARKER_DIR="$d12/markers" GH_PR_BODY="Closes #10"$'\n'"Fixes #12" GH_PR_REFS="" \
    GH_FAIL_ISSUES="12" \
    ASSET_HOST_MODE=raw ASSET_OWNER_REPO=o/r ASSET_REF=main DRY_RUN=1 \
    bash "$self" --post completion >/dev/null 2>&1 )
  local f12_rc=$?
  local f12_ok=1
  [ "$f12_rc" -eq 0 ] || f12_ok=0                          # non-blocking exit 0
  [ -f "$d12/markers/10" ] || f12_ok=0                     # issue #10 succeeded
  grep -q '"issue":10,"reason":"commented"' "$d12/.context/logs/audit.jsonl" 2>/dev/null || f12_ok=0
  grep -q '"issue":12,"reason":"gh_error"' "$d12/.context/logs/audit.jsonl" 2>/dev/null || f12_ok=0
  if [ "$f12_ok" = "1" ]; then
    _ok "f12-completion-gh-failure-continues"
  else
    _fail "f12-completion-gh-failure-continues" "rc=$f12_rc $(grep completion_summary "$d12/.context/logs/audit.jsonl" 2>/dev/null | tr '\n' '~')"
  fi
  rm -rf "$d12"

  # ---- f13: --emit pr twice reuses the first emission; --force re-hosts
  local d13; d13=$(_mk_sandbox); _manifest_with_captures "$d13"
  local e13a e13b e13c
  e13a=$(STATE_FILE="$d13/.context/state.json" WORKSPACE_ROOT="$d13" \
         ASSET_HOST_MODE=raw ASSET_OWNER_REPO=o/r ASSET_REF=main DRY_RUN=1 \
         bash "$self" --emit pr 2>/dev/null)
  e13b=$(STATE_FILE="$d13/.context/state.json" WORKSPACE_ROOT="$d13" \
         ASSET_HOST_MODE=raw ASSET_OWNER_REPO=o/r ASSET_REF=main DRY_RUN=1 \
         bash "$self" --emit pr 2>/dev/null)
  e13c=$(STATE_FILE="$d13/.context/state.json" WORKSPACE_ROOT="$d13" \
         ASSET_HOST_MODE=raw ASSET_OWNER_REPO=o/r ASSET_REF=main DRY_RUN=1 \
         bash "$self" --emit pr --force 2>/dev/null)
  local f13_ok=1
  [ -n "$e13a" ] || f13_ok=0
  [ "$e13a" = "$e13b" ] || f13_ok=0                                  # same URLs replayed
  [ "$e13a" = "$e13c" ] || f13_ok=0                                  # --force still emits
  [ -s "$d13/.context/logs/visual-evidence-pr-wid-test-0.md" ] || f13_ok=0
  grep -q '"result":"reused"' "$d13/.context/logs/audit.jsonl" 2>/dev/null || f13_ok=0
  [ "$(grep -c '"result":"reused"' "$d13/.context/logs/audit.jsonl" 2>/dev/null)" = "1" ] || f13_ok=0
  if [ "$f13_ok" = "1" ]; then
    _ok "f13-emit-pr-idempotent"
  else
    _fail "f13-emit-pr-idempotent" "$(grep visual_evidence_pr_emitted "$d13/.context/logs/audit.jsonl" 2>/dev/null | tr '\n' '~')"
  fi
  rm -rf "$d13"

  echo "attach-visual-evidence: self-test summary — pass=$pass fail=$fail"
  [ "$fail" -eq 0 ]
}

# ---------- entrypoint ------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  run_self_tests || exit 2
  exit 0
fi

# Read-only schema check. Handled here, before the tier library and state load, so the
# gate can call it in a tree with no state.json and so nothing about the publishing
# modes' exit-0 contract is reachable from this path.
if [ "${1:-}" = "--validate-manifest" ]; then
  validate_manifest "${2:-}"
  exit $?
fi

usage() {
  echo "usage: $0 {--emit pr [--force] | --post issue | --post completion [<pr-ref>] | --validate-manifest <path> | --self-test}" >&2
}

# Argv is validated BEFORE the library/state load so a caller error reports the
# caller error — a missing state.json must not mask a bad or absent mode.
MODE="${1:-}"; TARGET="${2:-}"
FORCE=0
case "$MODE" in
  --emit)
    [ "$TARGET" = "pr" ] || { echo "usage: $0 --emit pr [--force]" >&2; exit 1; }
    case "${3:-}" in
      --force) FORCE=1 ;;
      "") ;;
      *) echo "usage: $0 --emit pr [--force]" >&2; exit 1 ;;
    esac ;;
  --post)
    case "$TARGET" in
      issue|completion) ;;
      *) echo "usage: $0 --post {issue | completion [<pr-ref>]}" >&2; exit 1 ;;
    esac ;;
  *)
    usage
    exit 1 ;;
esac

# Source the tier library (after self-test branch so tests fork fresh processes).
if [ -f "$_LIB" ]; then
  # shellcheck disable=SC1090
  PUBLISH_LIB_ONLY=1 . "$_LIB"
else
  echo "attach-visual-evidence: tier library not found: $_LIB" >&2
  exit 1
fi

load_context

case "$MODE" in
  --emit) emit_pr ;;
  --post)
    case "$TARGET" in
      issue) post_issue ;;
      completion) post_completion "${3:-}" ;;
    esac ;;
esac
exit 0

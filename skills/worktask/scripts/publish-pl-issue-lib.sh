#!/usr/bin/env bash
# publish-pl-issue-lib.sh — sanitiser, plan-extraction, state, and label helpers
# shared by publish-pl-issue.sh.
#
# SOURCED, never executed. Every function here reads the caller's globals
# (STATE_FILE, WORKSPACE_ROOT, ISSUE_ANCHOR, GH_BIN, …) at call time, so this
# file is not standalone and must be sourced AFTER the defaults/env block.
#
# The sanitiser is a published contract surface: fn-preflight-cmds.sh and
# attach-visual-evidence.sh reach `sanitise_body` by sourcing publish-pl-issue.sh
# under PUBLISH_LIB_ONLY=1, which loads this file on the way. Changing a rule here
# changes what those callers may publish.

# ---------- shared host-path pattern and scrub ------------------------------
# A missing path-scrub.sh stops the caller: nothing else removes a glued host path.
_PLI_PATH_SCRUB="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../shared/scripts" 2> /dev/null && pwd -P)/path-scrub.sh"
if [ -r "$_PLI_PATH_SCRUB" ]; then
  # shellcheck disable=SC1090
  . "$_PLI_PATH_SCRUB"
else
  printf >&2 'publish-pl-issue: path-scrub.sh unreachable at %s — plugin install broken\n' \
    "$_PLI_PATH_SCRUB"
  exit 1
fi

# ---------- three-pass sanitiser -------------------------------------------
# Pass 1: drop whole lines containing forbidden tokens (L1..L10).
# Pass 2: drop filename-shaped tokens unless allow-list rules A1..A6 fire.
# Pass 3: corpflow_path_scrub. It never drops a line, so the strip-ratio guard in
#         publish-pl-issue.sh is unaffected.
sanitise_body() {
  # Reads body from stdin, writes sanitised body to stdout.
  # An empty ERE would make L2/L3b match every line.
  if [ -z "${CORPFLOW_HOST_PATH_ERE:-}" ] || [ -z "${CORPFLOW_DRIVE_PATH_ERE:-}" ] \
    || ! command -v corpflow_path_scrub > /dev/null 2>&1; then
    printf >&2 'sanitise_body: path-scrub.sh is not loaded — refusing to sanitise\n'
    return 1
  fi
  # Force C locale so awk byte-handles UTF-8 (em-dashes, smart quotes) without
  # tripping the "towc: multibyte conversion failure" warning + line drop.
  CORPFLOW_HOST_PATH_ERE="$CORPFLOW_HOST_PATH_ERE" \
    CORPFLOW_DRIVE_PATH_ERE="$CORPFLOW_DRIVE_PATH_ERE" \
    LC_ALL=C awk '
    BEGIN {
      in_fence = 0
      host_re = "(^|[[:space:]])" ENVIRON["CORPFLOW_HOST_PATH_ERE"]
      drive_re = "(^|[[:space:]])" ENVIRON["CORPFLOW_DRIVE_PATH_ERE"]
    }
    {
      line = $0
      # Pass-1 predicates match on a backtick-neutralised COPY. The rules below
      # anchor on (^|[[:space:]]), and a backtick is neither -- so wrapping a
      # path in a code span used to defeat every one of them while pass 2 (A1/A2)
      # then copied code spans through verbatim. That combination published
      # `.context/` and `/Users/...` paths into PR and issue bodies. Substituting
      # a SPACE (not deleting) preserves each anchor s intent: `.context/ now
      # matches, foo.context/ still does not. Emit "line", never "probe".
      probe = line; gsub(/`/, " ", probe)
      # ---- Pass 1 line-strip --------------------------------------------
      if (probe ~ /(^|[[:space:]])\.context\//) next                 # L1
      # Same ERE as pr-body-lint.sh P1, so the sanitiser and its read-back agree.
      if (probe ~ host_re) next                                      # L2,L3
      # Windows drive-letter paths carry no leading slash, so L2/L3 cannot see them.
      if (probe ~ drive_re) next                                     # L3b
      if (probe ~ /(^|[[:space:]])~\//) next                         # L4
      if (line ~ /conductor\/workspaces\/[A-Za-z0-9_-]+/) next      # L5
      if (line ~ /(^|[[:space:]])(workspace_path|plan_file|run_index|artifact_path)[[:space:]]*[:=]/) next  # L6
      if (line ~ /(planning|architecture|coordinating|coordination|developing|development|reviewing|review|qa|testing|documenting|documentation|releasing|release|finalizing|finalization|stakeholding|retrospective|incident|ethics-review)-[0-9]+(-[a-z0-9]+(-[a-z0-9]+)*)?\.md/) next  # L7,L8; the optional -<stream> tail catches per-stream DV names
      if (probe ~ /(^|[[:space:]])(\.\/|\.\.\/)[A-Za-z0-9_.\/-]+/) next   # L9
      # L10: drop whole line when a plugin-qualified identifier is the leading
      # non-bullet token (e.g. "* Routed to corpflow:developer ...",
      # "Breakdown using corpflow:estimation-methodology:"). Strict prefix
      # allow-list keeps this from false-positive on http:// / git:// / etc.
      # The prefix list MUST mirror skills/shared/compatible-plugins.md
      # (Registry plugins + Support plugins — equivalently the plugin set of
      # skills/shared/routing-matrix.md default targets) and stay identical at every
      # occurrence in this file. A missing prefix leaks the agent identifiers
      # of that plugin into the published issue.
      if (line ~ /^[[:space:]]*([-*][[:space:]]+)?(Routed to|Breakdown using|Implemented by|Reviewed by|Handled by|Uses|Using|Delegated to)[[:space:]]+(corpflow|apple-developer|system-developer|android-developer|frontend-developer|backend-developer|ai-engineer|debugging-toolkit|security-scanning|skill-creator|conductor|claude-in-chrome):[a-z][a-z0-9-]*/) next

      # ---- Pass 2 token-strip (with allow-list) -------------------------
      # Track fenced code block state (A1).
      if (line ~ /^[[:space:]]*```/) {
        in_fence = (in_fence == 1) ? 0 : 1
        print line
        next
      }
      if (in_fence == 1) { print line; next }

      # A4: narrative bullet labels — pass entire line.
      if (line ~ /^[[:space:]]*[-*][[:space:]]+(class|type|protocol|struct|enum|function|fn|func|method)[[:space:]:]/) {
        print line; next
      }

      # A3: strip "symbol:" prefix but keep token body.
      gsub(/(^|[[:space:]])symbol:/, " ", line)

      # A2: inline-code passthrough — collect backtick spans first.
      # Build output character-by-character, skipping deny tokens outside spans.
      out = ""
      n = length(line)
      i = 1
      while (i <= n) {
        ch = substr(line, i, 1)
        if (ch == "`") {
          # passthrough until matching backtick
          j = index(substr(line, i+1), "`")
          if (j > 0) {
            out = out substr(line, i, j + 1)
            i = i + j + 1
            continue
          }
        }
        # Look ahead for filename token starting at i.
        rest = substr(line, i)
        if (match(rest, /^[A-Z][A-Za-z0-9_]+\.(md|json|jsonl|swift|ts|py|yml|yaml|sh|bash|go|rs|kt|java|rb|cpp|c|h|hpp|m|mm)/) && substr(rest, RLENGTH + 1, 1) !~ /[A-Za-z0-9_]/) {
          # A5: extension is in deny-list → strip.
          i = i + RLENGTH
          continue
        }
        # A6: plugin-qualified identifier token (corpflow:foo, apple-developer:bar,
        # etc.). Narrow known-prefix allow-list to avoid false positives on
        # http:, git:, file:, etc. Backtick spans already passed through above.
        # Prefix list MUST mirror skills/shared/compatible-plugins.md and L275.
        if (match(rest, /^(corpflow|apple-developer|system-developer|android-developer|frontend-developer|backend-developer|ai-engineer|debugging-toolkit|security-scanning|skill-creator|conductor|claude-in-chrome):[a-z][a-z0-9-]*/)) {
          i = i + RLENGTH
          continue
        }
        out = out ch
        i = i + 1
      }
      print out
    }
  ' | corpflow_path_scrub
}

# ---------- title-cap helpers ------------------------------------------------
# Caps each line at $1 codepoints including the `…`, cut on the last whitespace
# boundary with trailing `,;:-` trimmed; no boundary hard-cuts to $1-1. jq, not
# `cut -c`, because it counts codepoints; `+` quantifiers only for jq 1.6.
title_cap_word_boundary() {
  local limit="$1"
  jq -Rr --argjson n "$limit" '
    def wb_cap($n):
      if length <= $n then .
      else
        (.[0:$n] | sub("[^[:space:]]+$"; "") | sub("[[:space:],;:-]+$"; "")) as $w
        | if ($w | length) > 0 then $w + "…" else .[0:$n-1] + "…" end
      end;
    wb_cap($n)
  '
}

# Reproduces the pre-word-boundary title cut byte-for-byte (`cut -c1-100`), so
# resolve_context_issue_search can still probe for an issue published under the
# old scheme. The mid-word cut is the point here, not a bug to fix.
title_legacy_cut() {
  head -1 | cut -c1-100 | sanitise_body | tr -d '\n'
}

# ---------- plan extraction -------------------------------------------------
extract_anchor() {
  # $1=plan_file, $2=anchor name (without ##); returns anchor body lines.
  local plan="$1" anchor="$2"
  awk -v hdr="## $anchor" '
    BEGIN { in_block = 0 }
    /^## / {
      if (in_block == 1) exit
      if (tolower($0) == tolower(hdr)) { in_block = 1; next }
    }
    { if (in_block == 1) print }
  ' "$plan"
}

# Scalar YAML frontmatter field from a plan file. Only the LEADING `---` … `---`
# fence counts — a `---` thematic break further down the body is not frontmatter and
# is never read. Splits on the FIRST colon so a value may contain further colons.
# A folded/multi-line value contributes only its first line, which is all a title can
# carry anyway (the caller's `head -1` would drop the rest regardless).
extract_frontmatter_field() {
  local plan="$1" key="$2" v
  v=$(awk -v key="$key" '
    NR == 1 && $0 != "---" { exit }
    NR == 1 { in_fm = 1; next }
    in_fm && $0 == "---" { exit }
    # Top-level keys only. The PL template nests everything under `handoff:`, and an
    # indented `title:`/`issue:` there belongs to that block, not to the document.
    in_fm && /^[ \t]/ { next }
    in_fm {
      idx = index($0, ":")
      if (idx == 0) next
      k = substr($0, 1, idx - 1)
      gsub(/[ \t]+$/, "", k)
      if (tolower(k) != tolower(key)) next
      val = substr($0, idx + 1)
      gsub(/^[ \t]+|[ \t]+$/, "", val)
      print val
      exit
    }
  ' "$plan" 2>/dev/null) || v=""
  # One layer of surrounding quotes is stripped HERE rather than in awk, which would
  # need nested-quote escaping for no benefit.
  case "$v" in
    \"*\") v="${v#\"}"; v="${v%\"}" ;;
    \'*\') v="${v#\'}"; v="${v%\'}" ;;
  esac
  printf '%s' "$v"
}

# First `# ` heading of a plan, frontmatter skipped (a `#`-prefixed frontmatter
# comment must not win over the document's real H1).
extract_first_h1() {
  local plan="$1"
  awk '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { in_fm = 0; next }
    in_fm { next }
    /^# / { sub(/^#[ \t]+/, ""); gsub(/[ \t]+$/, ""); print; exit }
  ' "$plan" 2>/dev/null
}

# First sentence of a block read on stdin — the first prose line, truncated at its
# first sentence terminator. Headings, quotes, table rows and list bullets are
# skipped: a requirements bullet is a fragment, not a title. The terminator must be
# followed by whitespace or end-of-line so a version like "3.5s" is not a sentence end.
first_sentence() {
  awk '
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*[#>|]/ { next }
    /^[[:space:]]*[-*+][[:space:]]/ { next }
    {
      line = $0
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line == "") next
      if (match(line, /[.!?]([[:space:]]|$)/)) line = substr(line, 1, RSTART)
      print line
      exit
    }
  '
}
# ---------- workspace.json discovery ----------------------------------------
find_workspace_json() {
  if [ -n "$WORKSPACE_ROOT" ] && [ -f "$WORKSPACE_ROOT/workspace.json" ]; then
    printf '%s\n' "$WORKSPACE_ROOT/workspace.json"; return 0
  fi
  if [ -f "$PWD/workspace.json" ]; then
    printf '%s\n' "$PWD/workspace.json"; return 0
  fi
  return 1
}

# ---------- milestone-mode detector -----------------------------------------
# Returns 0 (true) if the worktask is running under a batch orchestrator (/megatask)
# or inside a megatask per-issue workspace. Detection signals (highest priority first):
#   1. MILESTONE_MODE=1 env override (/megatask's per-issue prompt, tests).
#   2. state.json:metadata.milestone non-empty.
#   3. state.json:tasks.PL0.metadata.megatask_group or .milestone non-empty — the keys
#      /megatask's per-issue stamp carries, so the ledger answers even when the env is lost.
#   4. workspace.json present at $WORKSPACE_ROOT or $PWD.
is_milestone_mode() {
  [ "${MILESTONE_MODE:-0}" = "1" ] && return 0
  if [ -f "$STATE_FILE" ]; then
    local m
    m=$(jq -r '.metadata.milestone // ""' "$STATE_FILE" 2>/dev/null)
    [ -n "$m" ] && [ "$m" != "null" ] && return 0
    m=$(jq -r '.tasks.PL0.metadata // {} | .megatask_group // .milestone // ""' "$STATE_FILE" 2>/dev/null)
    [ -n "$m" ] && [ "$m" != "null" ] && return 0
  fi
  find_workspace_json >/dev/null 2>&1 && return 0
  return 1
}

# ---------- atomic JSON write ------------------------------------------------
# _atomic_json <target> — reads the finished document from stdin and replaces <target>
# with it through tmp → fsync → mv. rc 1 when the replacement did not land.
#
# The emptiness check is what makes it safe to feed from a pipeline: a jq that dies
# part-way leaves a truncated or empty temp file, and the four hand-rolled copies this
# replaces would leave that file behind on disk beside the ledger. Nothing partial is
# ever renamed over the target.
_atomic_json() {
  local target="$1" tmp="${1}.tmp.$$"
  cat > "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  [ -s "$tmp" ] || { rm -f "$tmp" 2>/dev/null; return 1; }
  sync "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$target" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
}

# ---------- atomic state.json write -----------------------------------------
write_state_url() {
  # $1=url. Atomically sets state.json:metadata.github_issue_url.
  local url="$1"
  jq --arg url "$url" '.metadata = (.metadata // {}) | .metadata.github_issue_url = $url' \
    "$STATE_FILE" | _atomic_json "$STATE_FILE" || return 1
}

# ---------- run-independent GitHub-issue anchor -----------------------------
# The .context/gh-issue.json anchor binds this context to its canonical issue
# across worktask runs (state.json cannot: it is re-seeded, metadata wiped, on
# every fresh /worktask — so a second run would lose github_issue_url and open a
# duplicate). write_context_issue stamps created/last-commented to the CURRENT run;
# a later run (run_index greater than created_run_index) comments instead of creating.
write_context_issue() {
  # $1=url $2=number. Atomic (tmp → fsync → mv), mirroring write_state_url. Non-fatal.
  local url="$1" number="$2"
  [ -z "$url" ] && return 0
  [ -n "$ISSUE_ANCHOR" ] || return 0
  jq -cn --arg url "$url" --argjson num "${number:-0}" \
     --arg wid "${WORKTASK_ID:-unknown}" --argjson ri "${RUN_INDEX:-0}" \
     --arg ts "$(date -u +%FT%TZ)" \
     '{version:1, url:$url, number:$num, created_run_index:$ri, created_worktask_id:$wid, created_at:$ts, last_commented_run_index:$ri}' \
     2>/dev/null | _atomic_json "$ISSUE_ANCHOR" || return 1
}

bump_anchor_commented() {
  # $1=run_index. Record a follow-up comment for this run (anchor-source path).
  local ri="$1"
  [ -n "$ISSUE_ANCHOR" ] && [ -f "$ISSUE_ANCHOR" ] || return 0
  jq --argjson ri "${ri:-0}" '.last_commented_run_index = $ri' "$ISSUE_ANCHOR" 2>/dev/null \
    | _atomic_json "$ISSUE_ANCHOR" || return 1
}

# Return 0 if the issue already carries $2 among its comment bodies (network guard
# for comment idempotency). Two consumers reach it through the PUBLISH_LIB_ONLY
# source: publish-pl-issue.sh and attach-visual-evidence.sh, which kept a
# byte-identical private copy until the copy was deleted in favour of this one.
pl_issue_has_marker() {
  local url="$1" marker="$2" body
  body=$("$GH_BIN" issue view "$url" --json comments --jq '.comments[].body' 2>/dev/null || true)
  printf '%s' "$body" | grep -qF "$marker"
}

# Resolve the canonical issue for this .context WITHOUT touching GitHub.
# Priority: (1) .context/gh-issue.json anchor, (2) state.json:metadata.github_issue_url
# (only present within the same run). On hit sets RESOLVED_ISSUE_{URL,NUMBER,
# CREATED_RUN,SOURCE} and returns 0; otherwise resets them and returns 1.
resolve_context_issue_local() {
  # shellcheck disable=SC2034  # read by the dedup guards in publish-pl-issue.sh
  RESOLVED_ISSUE_URL=""; RESOLVED_ISSUE_NUMBER=""; RESOLVED_ISSUE_CREATED_RUN=""; RESOLVED_ISSUE_SOURCE=""
  if [ -n "$ISSUE_ANCHOR" ] && [ -f "$ISSUE_ANCHOR" ] && jq -e . "$ISSUE_ANCHOR" >/dev/null 2>&1; then
    local a_url
    a_url=$(jq -r '.url // ""' "$ISSUE_ANCHOR" 2>/dev/null)
    if [ -n "$a_url" ]; then
      RESOLVED_ISSUE_URL="$a_url"
      RESOLVED_ISSUE_NUMBER=$(jq -r '.number // ""' "$ISSUE_ANCHOR" 2>/dev/null)
      RESOLVED_ISSUE_CREATED_RUN=$(jq -r '.created_run_index // 0' "$ISSUE_ANCHOR" 2>/dev/null)
      RESOLVED_ISSUE_SOURCE="anchor"
      return 0
    fi
  fi
  local s_url
  s_url=$(jq -r '.metadata.github_issue_url // ""' "$STATE_FILE" 2>/dev/null)
  if [ -n "$s_url" ]; then
    RESOLVED_ISSUE_URL="$s_url"
    RESOLVED_ISSUE_NUMBER=$(printf '%s' "$s_url" | grep -oE '[0-9]+$' || true)
    RESOLVED_ISSUE_CREATED_RUN="$RUN_INDEX"
    RESOLVED_ISSUE_SOURCE="state"
    return 0
  fi
  return 1
}

# GitHub-side recovery: find an OPEN issue whose title EXACTLY matches $TITLE
# (case-insensitive, trimmed). Accepts a single hit only — an ambiguous / multi-hit
# result is ignored so an unrelated same-worded issue never captures a fresh context.
# Needs $TITLE, so it runs AFTER the title is built. Sets RESOLVED_ISSUE_* on hit.
# Falls back to $TITLE_LEGACY (the pre-word-boundary cut, same ticket-prefix applied)
# when it differs, so an issue published under the old fixed-100 title is still found.
resolve_context_issue_search() {
  resolve_context_issue_search_for "$TITLE" && return 0
  local legacy="${TITLE_LEGACY:-}"
  [ -n "$legacy" ] || return 1
  local t_lc l_lc
  t_lc=$(printf '%s' "$TITLE" | tr '[:upper:]' '[:lower:]')
  l_lc=$(printf '%s' "$legacy" | tr '[:upper:]' '[:lower:]')
  [ "$t_lc" != "$l_lc" ] || return 1
  resolve_context_issue_search_for "$legacy"
}

resolve_context_issue_search_for() {
  local probe="$1"
  [ "$GH_ISSUE_SEARCH" = "1" ] || return 1
  [ "$DRY_RUN" != "1" ] || return 1
  command -v "$GH_BIN" >/dev/null 2>&1 || return 1
  local want; want=$(printf '%s' "$probe" | tr '[:upper:]' '[:lower:]' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  [ -n "$want" ] || return 1
  local hits; hits=$("$GH_BIN" issue list --state open --search "$probe in:title" --json number,title,url --limit 20 2>/dev/null || true)
  [ -n "$hits" ] || return 1
  local matched n
  matched=$(printf '%s' "$hits" | jq -c --arg t "$want" '[ .[] | select((.title|ascii_downcase|gsub("^\\s+|\\s+$";"")) == $t) ]' 2>/dev/null || echo '[]')
  n=$(printf '%s' "$matched" | jq 'length' 2>/dev/null || echo 0)
  # shellcheck disable=SC2034  # read by the dedup guards in publish-pl-issue.sh
  if [ "$n" = "1" ]; then
    RESOLVED_ISSUE_URL=$(printf '%s' "$matched" | jq -r '.[0].url')
    RESOLVED_ISSUE_NUMBER=$(printf '%s' "$matched" | jq -r '.[0].number')
    RESOLVED_ISSUE_CREATED_RUN="-1"   # predates this context's runs → always comment
    RESOLVED_ISSUE_SOURCE="search"
    return 0
  fi
  return 1
}

# ---------- label auto-provisioning -----------------------------------------
# Color/description registry for canonical worktask labels (AC-1).
# worktask (blue), planning-approved (green), complexity:<tier>
# (severity gradient), ticket:<prefix> (purple). Unknown labels fall back to
# a neutral grey + generic description.
label_color() {
  case "$1" in
    worktask)             printf '0366d6' ;;  # blue
    planning-approved)    printf '0e8a16' ;;  # green
    complexity:low)       printf 'c2e0c6' ;;  # pale green
    complexity:moderate)  printf 'fbca04' ;;  # amber
    complexity:medium)    printf 'fbca04' ;;  # amber
    complexity:high)      printf 'd93f0b' ;;  # deep orange
    complexity:critical)  printf 'b60205' ;;  # red
    ticket:*)             printf '5319e7' ;;  # purple
    *)                    printf 'cccccc' ;;
  esac
}

label_description() {
  case "$1" in
    worktask)             printf 'corpflow worktask run' ;;
    planning-approved)    printf 'PL stage plan approved by human' ;;
    complexity:*)         printf 'PL complexity tier' ;;
    ticket:*)             printf 'External tracker reference' ;;
    *)                    printf '' ;;
  esac
}

# DROPPED_LABELS is populated by ensure_labels(); read by issue-create branch.
DROPPED_LABELS=""

ensure_labels() {
  # $@ = list of label names to ensure. For each, if it does not already exist
  # in the repo (per `gh label list`), attempt to create it. On create failure,
  # append the label name to DROPPED_LABELS (space-separated). Idempotent: a
  # second invocation with the same labels no-ops cleanly.
  command -v "$GH_BIN" >/dev/null 2>&1 || return 0
  local existing
  existing=$("$GH_BIN" label list --limit 200 --json name --jq '.[].name' 2>/dev/null || true)
  local lbl color desc rc
  for lbl in "$@"; do
    [ -z "$lbl" ] && continue
    if printf '%s\n' "$existing" | grep -Fxq "$lbl"; then
      continue
    fi
    color=$(label_color "$lbl")
    desc=$(label_description "$lbl")
    if [ -n "$desc" ]; then
      "$GH_BIN" label create "$lbl" --color "$color" --description "$desc" >/dev/null 2>&1
    else
      "$GH_BIN" label create "$lbl" --color "$color" >/dev/null 2>&1
    fi
    rc=$?
    if [ "$rc" -ne 0 ]; then
      DROPPED_LABELS="${DROPPED_LABELS}${DROPPED_LABELS:+ }${lbl}"
    fi
  done
}

# ---------- gh failure classification ---------------------------------------
# Map gh stderr blobs to a canonical audit reason (AC-3). Order matters:
# label_create_failed and explicit HTTP codes are checked before the broad
# network_error catch — which is reserved for transport-failure stderr.
classify_gh_failure() {
  local out="$1"
  # Label-create failure (helper-specific token "label_create_failed" is what
  # the issue-create branch passes when DROPPED_LABELS is non-empty AND
  # gh itself failed; otherwise we sniff stderr).
  if printf '%s' "$out" | grep -qiE 'could not add label|label .* not found|label_create_failed'; then
    printf 'label_create_failed'
    return 0
  fi
  if printf '%s' "$out" | grep -qiE 'HTTP 401|authentication required|bad credentials|auth(entication)? token'; then
    printf 'auth_missing'
    return 0
  fi
  if printf '%s' "$out" | grep -qiE 'HTTP 403|permission denied|forbidden|rate.limit'; then
    printf 'permission_denied'
    return 0
  fi
  if printf '%s' "$out" | grep -qiE 'HTTP 404|repository.*not found|could not resolve to a repository|no such repository'; then
    printf 'repo_not_found'
    return 0
  fi
  if printf '%s' "$out" | grep -qiE 'timed out|timeout|deadline exceeded'; then
    printf 'gh_timeout'
    return 0
  fi
  if printf '%s' "$out" | grep -qiE 'could not resolve host|connection refused|network is unreachable|no route to host'; then
    printf 'network_error'
    return 0
  fi
  if printf '%s' "$out" | grep -qiE 'HTTP [45][0-9]{2}|graphql error|api\.github\.com'; then
    printf 'gh_api_error'
    return 0
  fi
  # Default — gh failed but stderr did not match any known pattern. Preserve
  # backward compat: fixtures 01-05 + any caller without a recognisable error
  # token still bucket to gh_api_error (a real upstream failure, not transport).
  printf 'gh_api_error'
  return 0
}

# ---------- external-ticket extraction --------------------------------------
# Returns the matched ^[A-Z][A-Z0-9]+-[0-9]+ token from $1, or empty on no
# match. Used by both the live issue-create path and self-test.
extract_external_ticket() {
  local src="$1"
  printf '%s' "$src" | grep -oE '^[A-Z][A-Z0-9]+-[0-9]+' | head -1
}

# Persist external ticket prefix to state.json:metadata.external_ticket.
write_state_external_ticket() {
  local tkt="$1"
  [ -z "$tkt" ] && return 0
  jq --arg t "$tkt" '.metadata = (.metadata // {}) | .metadata.external_ticket = $t' \
    "$STATE_FILE" | _atomic_json "$STATE_FILE" || return 1
}

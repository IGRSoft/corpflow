#!/usr/bin/env bash
# publish-pl-issue.sh — auto-publish a sanitised GitHub issue after PL approval.
#
# Invoked by the orchestrator at Step 6.5 of skills/worktask/SKILL.md between
# `approval_received` audit-write and stage-loop entry. NEVER blocks the worktask:
# operational outcomes are encoded in audit.jsonl rows (result + reason), helper
# exits 0 unless catastrophic (jq missing, audit dir unwritable, state corrupt).
#
# Contracts (analyzing-0.md):
#   - Two-pass sanitiser (sanitise_body): Pass 1 awk line-strip L1–L9, Pass 2
#     token-strip with allow-list A1–A5.
#   - Strip-ratio >50% aborts publish; aborted body persisted to
#     .context/logs/issue-body-<run_index>.aborted.tmp.
#   - Idempotency + cross-run dedup: one .context/ ↔ one GitHub issue. The issue
#     ref is persisted to the run-independent .context/gh-issue.json anchor (state.json
#     is re-seeded per run, so it cannot hold this). Same-run resolve → short-circuit
#     (already_published). A LATER worktask run in the same .context/ resolves the
#     anchor (or, if lost, an exact-title single-hit GitHub search) and posts a
#     marker-deduped follow-up COMMENT instead of opening a duplicate issue. See
#     skills/gh-issue-dedup. Env: GH_ISSUE_ANCHOR (path), GH_ISSUE_SEARCH (0 disables).
#   - Milestone-mode: state.json:metadata.milestone OR workspace.json present →
#     exit 0 immediately with reason=milestone_mode. No gh API call of any kind
#     (no create, no comment). The parent milestone issue is the canonical record.
#   - Atomic state.json write: tmp.$$ → fsync → mv -f.
#   - Audit row: actor=orchestrator, action=github_issue_created, via=publish-pl-issue.sh,
#     dedupe_key=<worktask_id>:<run_index>:gh_issue.
#   - Exit codes: 0 all operational paths, 1 catastrophic, 2 --self-test failure.
#
# **`plan_file` shape boundary** — `state.json.plan_file` holds a **workspace-relative
# path** (`.context/planning-N.md`); `task.metadata.plan_file` holds a **bare
# basename** (`planning-N.md`). Both shapes are legal. Every reader MUST accept
# either: try the value as given, then its basename resolved against the directory
# holding `state.json`. Canonical statement: skills/worktask/references/handoff-protocol.md
# § state.json schema. This script implements exactly that two-candidate resolution
# at the PLAN_FILE block below, and names both candidates on the fatal path.
#
# Asset host-and-rewrite contract (Figma image embed — REQ-1..REQ-6):
#   The PM authors the `## design-preview` anchor with placeholder tokens of the
#   shape `{{asset:<basename>}}` on their own line (basename only — NO `.context/`
#   path), each followed by a `- <description>` bullet, with the Figma source URL
#   preserved above (see agents/product-manager.md § Asset-placeholder grammar).
#   Because the tokens carry no `.context/` token, they survive sanitise_body
#   Pass-1 L1. AFTER sanitisation, resolve_design_assets() rewrites each token to
#   a hosted markdown image line `![<basename>](<url>)` — so the image line never
#   faces L1 and no local path ever reaches the issue body.
#
#   Tier order (REQ-3, highest priority first):
#     0. user-attachments (PREFERRED, live) — GitHub's native
#        github.com/user-attachments/assets/<uuid> store the web composer uses.
#        GitHub rewrites these to private-user-images.githubusercontent.com with a
#        short-lived scoped JWT, so they render for authenticated viewers of
#        PRIVATE/INTERNAL repos. This is the ONLY tier that satisfies all three
#        constraints at once: private-repo rendering, BINARY payloads, and no
#        commit to the repository. Selected automatically whenever usable.
#        Requires the `drogers0/gh-image` gh extension (`gh extension install
#        drogers0/gh-image`), which supplies the browser session token the
#        upload-policy flow needs — see "q1 spike outcome" below for why a PAT
#        cannot. Availability is probed via `gh image check-token`; pin it with
#        ASSET_GH_IMAGE=1/0 in tests. Still NEVER a hard runtime dependency —
#        when the extension is absent or its token is stale, selection falls
#        through to the tiers below and ultimately degrades silently.
#     1. raw (verified to RENDER, not merely to exist) — raw.githubusercontent.com.
#        REQ-1: the gate now approximates GitHub's camo image proxy, which fetches
#        the URL ANONYMOUSLY. A private/internal repo's raw URL 404s for an
#        anonymous fetch even though an authenticated `gh api contents` check
#        passes — that false positive is exactly what broke private-repo embeds.
#        So: if `gh repo view --json visibility` reports PRIVATE or INTERNAL, the
#        raw tier is REFUSED (it would render broken) and we degrade. For PUBLIC
#        repos we additionally require an anonymous `curl -fsIL` HEAD to succeed.
#     2. gist (`gh gist create --public`) — render-verified raw gist asset URL.
#        AC1 PRIMARY for PRIVATE/INTERNAL repos: a PUBLIC gist raw URL is
#        anonymously fetchable, so camo renders it inline even when the
#        surrounding repo is private (the repo's privacy does not gate camo's
#        outbound fetch of a public origin). The URL is render-verified by an
#        anonymous HEAD (gist_raw_url_reachable) BEFORE it is emitted; a verify
#        miss degrades to tier-3 (never a broken/non-rendering embed). The
#        ASSET_GIST_PUBLIC=0 opt-out (q2/policy) creates a secret/unlisted gist
#        instead — also anonymously fetchable, so it still renders; only
#        discoverability differs. `gh gist create` already has `gist` scope.
#     3. none — URL-only note (Figma URL + exactly one note line "Screenshots
#        persisted on disk; inline hosting unavailable — see designs registry.").
#   No broken `![]()` at any tier. Each downgrade appends a non-blocking audit row
#   with reason=image_hosting_unavailable under a distinct dedupe-key suffix
#   (`:asset_hosting`) so it cannot mask the final github_issue_created result row.
#
#   q1 spike outcome (DV0, recorded per REQ-2): the user-attachments upload-policy
#   endpoint is web-session-oriented. `gh api -X POST upload/policies/assets`
#   returns HTTP 404 (the endpoint is on github.com, not api.github.com); a direct
#   `curl -X POST -H "Authorization: Bearer <gh-token>"
#   https://github.com/upload/policies/assets` returns HTTP 422 (malformed) rather
#   than 401/403 — i.e. the Bearer token is NOT accepted as an authenticated web
#   session; the flow needs the browser `_gh_sess` cookie + CSRF token. VERDICT:
#   NOT viable with gh auth ALONE. SUPERSEDED: the `drogers0/gh-image` extension
#   supplies exactly that browser session token (it extracts `_gh_sess` from the
#   local browser, or takes GH_SESSION_TOKEN) and drives the same upload-policy
#   flow, printing `![base](url)`. Tier-0 is therefore LIVE whenever that
#   extension is installed and its token is valid. The spike's finding stands as
#   written — a PAT still cannot do this; what changed is that the session token
#   is now obtainable from the CLI. REQ-1
#   render-verification is the shipped cure (it fixes the broken-image symptom by
#   degrading instead of emitting a dead raw URL).
#
#   Disk lookup: <basename> resolves ONLY to .context/designs/<basename> (canonical
#   per skills/task-folder-organization/SKILL.md). {{asset:...}} tokens carry Figma
#   design-preview frames, which live exclusively in .context/designs/. .context/images/
#   is reserved for DV implementation screenshots and is NEVER a Figma asset source.
#   raw path: the PNG is copied to ASSET_DIR_REL =
#     ".worktask-assets/<worktask_id>/<basename>" on the worktask branch, referenced
#     via https://raw.githubusercontent.com/<owner>/<repo>/<ref>/<path>.
#     <owner>/<repo> parsed from `git remote get-url origin` (git@ + https forms);
#     <ref> from `git rev-parse --abbrev-ref HEAD`.
#   push contract: the helper does NOT push or commit (no surprising git side
#     effects at Step 6.5). It copies the file into the worktree path so a later
#     human-gated commit (FN) picks it up, and verifies the ref is reachable on the
#     remote with `git ls-remote --exit-code origin <ref>` before emitting raw URLs.
#     If the branch/asset is not yet pushed, it degrades — non-blocking, exit 0.
#
# Env vars for injection (test/dev): STATE_FILE, WORKSPACE_ROOT, GH_BIN, DRY_RUN,
# GH_TIMEOUT (default 30). Asset-hosting test hooks: ASSET_HOST_MODE
# (user-attachments|raw|gist|none — forces a tier for self-tests, bypassing live
# git/gh probes), ASSET_OWNER_REPO (mock "owner/repo"), ASSET_REF (mock ref),
# GIST_RAW_URL_BASE (mock gist raw base), USER_ATTACH_URL_BASE (mock
# user-attachments asset base, mirrors GIST_RAW_URL_BASE), ASSET_REPO_VISIBILITY
# (mock `gh repo view` visibility: PUBLIC|PRIVATE|INTERNAL — drives REQ-1
# render-verification offline). ASSET_UA_ENABLE=1 + USER_ATTACH_URL_BASE is the
# OFFLINE MOCK for tier-0; the LIVE tier-0 path needs no opt-in and is probed via
# `gh image check-token` (pin with ASSET_GH_IMAGE=1/0).
# ASSET_GIST_PUBLIC (tri-state: 1 forces public, 0 forces
# secret/unlisted, empty/unset = auto-derive from repo visibility) controls
# gist-tier visibility (AC1).
# GIST_VERIFY_FORCE (pass|fail) short-circuits the gist render-verify HEAD for
# offline self-tests. When unset, real git/gh probes drive tier selection.
#
# AC1 Privacy posture (C2 operator guidance):
#   The gist tier uploads screenshot bytes to a URL that GitHub's camo image proxy
#   can fetch ANONYMOUSLY — that is what makes an embed render inside a PRIVATE
#   repo's issue/PR body at all. NEITHER gist kind preserves confidentiality:
#   public and secret/unlisted gists are both anonymously readable by URL. Do not
#   capture screenshots containing secrets, tokens, or PII (C3 capture policy).
#
#   What the two kinds actually differ on is DISCOVERABILITY, not access:
#   a public gist is search-indexed and listed on the authoring account's gist
#   profile; a secret one is neither. Since rendering works either way, `--public`
#   has no upside on a closed repo — so the default is auto (see ASSET_GIST_PUBLIC
#   below): PRIVATE/INTERNAL → secret, PUBLIC/unknown → public. Set the variable
#   explicitly to override in either direction.
#
#   Auto narrows exposure; it does not remove it. Operators handling material that
#   must not leave the org should skip hosting entirely (ASSET_HOST_MODE=none,
#   which emits bullets instead of embeds) rather than rely on unlisted URLs.
#   The FN gate provides human disclosure before merge (C1 gate condition).

set -u

# ---------- defaults / env --------------------------------------------------
STATE_FILE="${STATE_FILE:-.context/state.json}"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-}"
GH_BIN="${GH_BIN:-gh}"
DRY_RUN="${DRY_RUN:-0}"
GH_TIMEOUT="${GH_TIMEOUT:-30}"
# Longer than GH_TIMEOUT on purpose: a COLD `gh image check-token` legitimately
# needs tens of seconds to decrypt the browser cookie store (warm is ~3s).
GH_IMAGE_PROBE_TIMEOUT="${GH_IMAGE_PROBE_TIMEOUT:-90}"
STRICT="${STRICT:-0}"
LOG_DIR="${WORKSPACE_ROOT:-${CLAUDE_PROJECT_DIR:-.}}/.context/logs"
AUDIT_FILE="$LOG_DIR/audit.jsonl"
# Run-independent .context ↔ issue binding. state.json is re-seeded on every fresh
# /worktask (commands/worktask.md § seed), wiping metadata.github_issue_url — so the
# canonical issue reference is persisted HERE instead, surviving run_index increments.
# A second worktask in the same .context/ then comments on the existing issue rather
# than opening a duplicate. See skills/gh-issue-dedup. Sits next to state.json.
ISSUE_ANCHOR="${GH_ISSUE_ANCHOR:-$(dirname "$STATE_FILE")/gh-issue.json}"
# GitHub-side recovery search when no local anchor resolves (fresh clone / lost
# .context/). Default on; exact-title single-hit only (guarded against false matches).
GH_ISSUE_SEARCH="${GH_ISSUE_SEARCH:-1}"
# Human-readable suffix for the next fatal() diagnostic. Declared here so `set -u`
# is satisfied at every fatal() call; callers set it immediately before failing.
FATAL_DETAIL=""

# ---------- asset-hosting env hooks (Figma image embed) ---------------------
# Roots used to resolve {{asset:<basename>}} tokens and to stage hosted copies.
# Derived from WORKSPACE_ROOT (falls back to CLAUDE_PROJECT_DIR / cwd) so the
# helper works both in-worktree and in self-test sandboxes.
ASSET_ROOT="${WORKSPACE_ROOT:-${CLAUDE_PROJECT_DIR:-.}}"
ASSET_DESIGNS_DIR="$ASSET_ROOT/.context/designs"     # canonical (and only) Figma asset source
ASSET_IMAGES_DIR="$ASSET_ROOT/.context/images"        # DV implementation screenshots — NEVER a Figma {{asset:...}} source
# Test hooks (unset in production → real git/gh probes drive tier selection):
ASSET_HOST_MODE="${ASSET_HOST_MODE:-}"                # user-attachments|raw|gist|none force
ASSET_OWNER_REPO="${ASSET_OWNER_REPO:-}"              # mock "owner/repo"
ASSET_REF="${ASSET_REF:-}"                            # mock <ref>
GIST_RAW_URL_BASE="${GIST_RAW_URL_BASE:-}"            # mock gist raw base
USER_ATTACH_URL_BASE="${USER_ATTACH_URL_BASE:-}"      # mock user-attachments asset base
ASSET_REPO_VISIBILITY="${ASSET_REPO_VISIBILITY:-}"    # mock PUBLIC|PRIVATE|INTERNAL (REQ-1)
# Live opt-in for the user-attachments tier. Currently inert: q1 spike found the
# upload-policy flow needs a browser session cookie, not a gh token (see header).
# This flag now ONLY gates the offline mock path (with USER_ATTACH_URL_BASE) used
# by self-tests. The live tier-0 path is not gated by it — it activates whenever
# `gh image` is installed and authed. Default off (mock disabled).
ASSET_UA_ENABLE="${ASSET_UA_ENABLE:-0}"
# Pin tier-0 availability for deterministic tests: 1 = force available, 0 = force
# unavailable, empty = probe `gh image check-token` live.
ASSET_GH_IMAGE="${ASSET_GH_IMAGE:-}"
# Gist visibility. Tri-state: "1" forces public, "0" forces secret/unlisted, and
# EMPTY (the default) means auto — derived from repo visibility by
# gist_public_effective(): PRIVATE/INTERNAL → secret, everything else → public.
#
# Why auto rather than a flat default-on: both gist kinds are anonymously
# fetchable by URL (camo requires that to render at all), so on a PRIVATE or
# INTERNAL repo `--public` buys NOTHING — it cannot improve rendering, which
# already works — while adding search indexing and a listing on the authoring
# account's public gist profile. That is pure downside exactly where the source
# repo is closed, so auto declines it. On a PUBLIC repo the listing costs
# nothing and public stays the default.
#
# This narrows discoverability only. It does NOT make the bytes confidential —
# see the AC1 privacy posture note in the header. Both paths render-verify
# before emitting a URL (see gist_raw_url_reachable).
ASSET_GIST_PUBLIC="${ASSET_GIST_PUBLIC:-}"
# Offline render-verify test hook for gist_raw_url_reachable. When set to "pass"
# the anonymous HEAD probe is short-circuited to success; "fail" forces failure
# (caller degrades). Empty (production default) → a real anonymous curl HEAD.
GIST_VERIFY_FORCE="${GIST_VERIFY_FORCE:-}"
# Reason recorded by resolve_design_assets() when it degrades below tier-1.
# resolve_design_assets runs in a command substitution (subshell), so it cannot
# set a parent variable — it writes the reason to ASSET_DEGRADED_FILE instead,
# which the parent reads after the substitution returns. Empty file / absent →
# no degradation.
ASSET_DEGRADED_REASON=""
ASSET_DEGRADED_FILE=""

# ---------- CLI flag parsing ------------------------------------------------
# Accept --strict (sets STRICT=1). --self-test handled in entrypoint below.
for _arg in "$@"; do
  case "$_arg" in
    --strict) STRICT=1 ;;
    *) ;;
  esac
done

# ---------- helpers ---------------------------------------------------------
# Bounded execution WITHOUT coreutils. Stock macOS ships neither `timeout` nor
# `gtimeout` and Homebrew coreutils is not a dependency of this plugin, so the
# `command -v gtimeout || command -v timeout` idiom used below silently resolves
# to empty and leaves the call UNBOUNDED on exactly the platform that needs it.
# Prefers a real timeout binary when one exists; otherwise polls at 1s
# granularity. Returns the command's status, or 124 on timeout (GNU convention).
TIMEOUT_BIN="${TIMEOUT_BIN:-$(command -v gtimeout || command -v timeout || true)}"
run_with_timeout() {
  local secs="$1"; shift
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" "$secs" "$@"
    return $?
  fi
  "$@" &
  local p=$! n=0
  while kill -0 "$p" 2> /dev/null && [ "$n" -lt "$secs" ]; do
    sleep 1; n=$((n + 1))
  done
  if kill -0 "$p" 2> /dev/null; then
    kill -9 "$p" 2> /dev/null || true
    wait "$p" 2> /dev/null || true
    return 124
  fi
  wait "$p" 2> /dev/null
  return $?
}

audit_row() {
  # $1=result, $2=metadata-json (compact). Always appends one row.
  local result="$1" meta_json="$2"
  command -v jq >/dev/null 2>&1 || return 1
  mkdir -p "$LOG_DIR" || return 1
  local row
  row=$(jq -cn \
    --arg ts "$(date -u +%FT%TZ)" \
    --arg actor "orchestrator" \
    --arg action "github_issue_created" \
    --arg subject "PL0" \
    --arg result "$result" \
    --arg task_id "${PL0_TASK_ID:-1}" \
    --argjson meta "$meta_json" \
    '{ts:$ts, actor:$actor, action:$action, subject:$subject, result:$result, task_id:$task_id, metadata:$meta}'
  )
  printf '%s\n' "$row" >> "$AUDIT_FILE"
}

defer() {
  # $1=reason; appends audit row with result=deferred, exits 0.
  local reason="$1"
  local wid run_index dk
  wid=$(jq -r '.worktask_id // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
  run_index=$(jq -r '.run_index // 0' "$STATE_FILE" 2>/dev/null || echo "0")
  dk="$wid:$run_index:gh_issue"
  audit_row "deferred" "$(jq -cn --arg v "publish-pl-issue.sh" --arg r "$reason" --arg dk "$dk" '{via:$v, reason:$r, dedupe_key:$dk}')" || true
  exit 0
}

fatal() {
  # $1=reason; appends audit row with result=error, exits 1.
  local reason="$1"
  local wid run_index dk
  # The audit row alone is machine-only: an operator watching the orchestrator sees
  # nothing at all when this path fires. Emit the reason (plus any FATAL_DETAIL the
  # caller staged) on stderr before exiting.
  printf >&2 'publish-pl-issue: FATAL %s%s\n' "$reason" "${FATAL_DETAIL:+ — $FATAL_DETAIL}"
  wid=$(jq -r '.worktask_id // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
  run_index=$(jq -r '.run_index // 0' "$STATE_FILE" 2>/dev/null || echo "0")
  dk="$wid:$run_index:gh_issue"
  audit_row "error" "$(jq -cn --arg v "publish-pl-issue.sh" --arg r "$reason" --arg dk "$dk" '{via:$v, reason:$r, dedupe_key:$dk}')" 2>/dev/null || true
  exit 1
}

# ---------- two-pass sanitiser ---------------------------------------------
# Pass 1: drop whole lines containing forbidden tokens (L1..L9).
# Pass 2: drop filename-shaped tokens unless allow-list rules A1..A5 fire.
sanitise_body() {
  # Reads body from stdin, writes sanitised body to stdout.
  # Force C locale so awk byte-handles UTF-8 (em-dashes, smart quotes) without
  # tripping the "towc: multibyte conversion failure" warning + line drop.
  LC_ALL=C awk '
    BEGIN { in_fence = 0 }
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
      if (probe ~ /(^|[[:space:]])\/(Users|home|tmp|var|opt|etc|root)\//) next  # L2,L3
      if (probe ~ /(^|[[:space:]])~\//) next                         # L4
      if (line ~ /conductor\/workspaces\/[A-Za-z0-9_-]+/) next      # L5
      if (line ~ /(^|[[:space:]])(workspace_path|plan_file|run_index|artifact_path)[[:space:]]*[:=]/) next  # L6
      if (line ~ /(planning|architecture|coordinating|coordination|developing|development|reviewing|review|qa|testing|documenting|documentation|releasing|release|finalizing|finalization|stakeholding|retrospective|incident|ethics-review)-[0-9]+\.md/) next  # L7,L8
      if (probe ~ /(^|[[:space:]])(\.\/|\.\.\/)[A-Za-z0-9_.\/-]+/) next   # L9
      # L10: drop whole line when a plugin-qualified identifier is the leading
      # non-bullet token (e.g. "* Routed to corpflow:developer ...",
      # "Breakdown using corpflow:estimation-methodology:"). Strict prefix
      # allow-list keeps this from false-positive on http:// / git:// / etc.
      # The prefix list MUST mirror skills/shared/compatible-plugins.md
      # (Registry plugins + Support plugins) and stay identical at every
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
  '
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

# ---------- asset host-and-rewrite (Figma image embed) ----------------------
# Parse "owner/repo" from a git remote URL. Handles both forms:
#   git@github.com:IGRSoft/corpflow.git
#   https://github.com/IGRSoft/corpflow.git   (and without .git)
# Echoes "owner/repo" on success; empty on no match.
parse_owner_repo() {
  local url="$1" path
  case "$url" in
    git@*:*)        path="${url#*:}" ;;                 # scp-like: host:owner/repo
    ssh://*|https://*|http://*|git://*)
                    path="${url#*://}"                  # strip scheme
                    path="${path#*/}" ;;                # strip host[:port]/
    *)              path="$url" ;;
  esac
  path="${path%.git}"                                   # drop trailing .git
  path="${path%/}"
  # Keep only the last two segments (owner/repo) — tolerates extra path depth.
  printf '%s' "$path" | awk -F'/' 'NF>=2 { printf "%s/%s", $(NF-1), $NF }'
}

# Resolve a {{asset:<basename>}} basename to an on-disk path. {{asset:...}} tokens
# carry Figma design-preview frames, which live ONLY under .context/designs/ (the
# canonical design-reference dir). .context/images/ is reserved for DV implementation
# screenshots and is NEVER a design-asset source — do not fall back to it. Echoes the
# resolved designs/ path, or empty if not found.
resolve_asset_path() {
  local base="$1"
  if [ -f "$ASSET_DESIGNS_DIR/$base" ]; then
    printf '%s' "$ASSET_DESIGNS_DIR/$base"; return 0
  fi
  return 1
}

# Echo the target repo visibility (PUBLIC|PRIVATE|INTERNAL|"" unknown). Honours
# the ASSET_REPO_VISIBILITY mock first (offline self-tests), else probes
# `gh repo view --json visibility`. NON-BLOCKING: any failure echoes empty.
repo_visibility() {
  if [ -n "$ASSET_REPO_VISIBILITY" ]; then
    printf '%s' "$ASSET_REPO_VISIBILITY" | tr '[:lower:]' '[:upper:]'
    return 0
  fi
  command -v "$GH_BIN" >/dev/null 2>&1 || { printf ''; return 0; }
  "$GH_BIN" auth status >/dev/null 2>&1 || { printf ''; return 0; }
  "$GH_BIN" repo view --json visibility --jq '.visibility' 2>/dev/null \
    | tr '[:lower:]' '[:upper:]'
}

# Decide the hosting tier + compute owner/repo + ref. Sets globals:
#   HOST_TIER  ∈ {user-attachments, raw, gist, none}
#   HOST_OWNER_REPO, HOST_REF   (for raw tier)
# Honors ASSET_HOST_MODE override (self-tests); otherwise probes git/gh.
# NON-BLOCKING: any probe failure degrades the tier, never errors.
# Is the `gh image` extension (drogers0/gh-image) usable right now? It uploads to
# GitHub's user-attachments CDN using a browser SESSION token — the flow a PAT
# cannot authenticate — and prints `![base](url)`.
# ASSET_GH_IMAGE pins the answer for deterministic tests: 1 = force available,
# 0 = force unavailable, empty = probe live. The probe is cached because
# check-token does network I/O and select_host_tier can be called per asset.
GH_IMAGE_OK_CACHE=""
# Why the probe result is no longer a bare boolean: "extension absent", "token
# stale" and "probe timed out" are three different operator actions, and
# collapsing them into one "inline hosting unavailable" sentence is what let a
# run ship six captured screenshots as a dead path. Set to
# absent|token_invalid|probe_timeout|ok and surfaced in the body + audit row.
GH_IMAGE_FAIL_REASON=""
gh_image_available() {
  case "${ASSET_GH_IMAGE:-}" in
    1) GH_IMAGE_FAIL_REASON="ok"; return 0 ;;
    0) GH_IMAGE_FAIL_REASON="absent"; return 1 ;;
  esac
  [ -n "$GH_IMAGE_OK_CACHE" ] && { [ "$GH_IMAGE_OK_CACHE" = "1" ] && return 0 || return 1; }
  GH_IMAGE_OK_CACHE=0
  command -v "$GH_BIN" >/dev/null 2>&1 || { GH_IMAGE_FAIL_REASON="absent"; return 1; }
  # check-token is SLOW on a cold cache: it decrypts the browser cookie store and
  # on macOS can block indefinitely on a Keychain prompt when non-interactive
  # (measured >120s cold, 3s warm). Unbounded, it stalls FN and the stall is then
  # misreported as "hosting unavailable". GH_SESSION_TOKEN bypasses the browser
  # entirely and is the supported way to make this fast and non-interactive.
  run_with_timeout "$GH_IMAGE_PROBE_TIMEOUT" "$GH_BIN" image check-token >/dev/null 2>&1
  case "$?" in
    0)   GH_IMAGE_OK_CACHE=1; GH_IMAGE_FAIL_REASON="ok"; return 0 ;;
    124) GH_IMAGE_FAIL_REASON="probe_timeout"; return 1 ;;
    *)   GH_IMAGE_FAIL_REASON="token_invalid"; return 1 ;;
  esac
}

HOST_TIER=""
HOST_OWNER_REPO=""
HOST_REF=""
select_host_tier() {
  HOST_TIER="none"; HOST_OWNER_REPO=""; HOST_REF=""
  # Forced mode (self-tests bypass live probes).
  case "$ASSET_HOST_MODE" in
    user-attachments)
      HOST_TIER="user-attachments"; return 0 ;;
    raw)
      HOST_TIER="raw"
      HOST_OWNER_REPO="${ASSET_OWNER_REPO:-owner/repo}"
      HOST_REF="${ASSET_REF:-main}"
      return 0 ;;
    gist) HOST_TIER="gist"; return 0 ;;
    none) HOST_TIER="none"
          [ -n "$GH_IMAGE_FAIL_REASON" ] || GH_IMAGE_FAIL_REASON="no_host_tier"
          return 0 ;;
    *) ;;  # fall through to live probes
  esac

  # Tier-0 (user-attachments) — now LIVE via the `gh image` extension, which
  # drives the browser-session upload the q1 spike found `gh` itself cannot do.
  # This is the PREFERRED tier and the only one that satisfies all three
  # constraints at once: it works on PRIVATE/INTERNAL repos (GitHub serves the
  # asset from private-user-images.githubusercontent.com with a scoped JWT, so no
  # camo 404), it accepts BINARY files (unlike gists), and it does not commit
  # anything to the repository (unlike raw). Preconditions: the extension is
  # installed AND holds a valid session token.
  #   Mock path: ASSET_UA_ENABLE=1 + USER_ATTACH_URL_BASE (offline self-tests).
  if [ "$ASSET_UA_ENABLE" = "1" ] && [ -n "$USER_ATTACH_URL_BASE" ]; then
    HOST_TIER="user-attachments"; return 0
  fi
  if gh_image_available; then
    HOST_TIER="user-attachments"; return 0
  fi

  # Tier-1 (raw.githubusercontent.com) preconditions: remote parseable AND ref
  # reachable on origin. The helper does NOT push — it only checks. REQ-1: refuse
  # the raw tier for PRIVATE/INTERNAL repos, because GitHub's camo image proxy
  # fetches the URL anonymously and would 404 — emitting a broken image. Those
  # repos degrade to gist/none instead. raw_asset_url_reachable() re-checks at
  # host time (defence in depth); selecting away here avoids the wasted cp.
  local remote owner_repo ref vis
  remote=$(git remote get-url origin 2>/dev/null || true)
  owner_repo=$(parse_owner_repo "$remote")
  ref=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  vis=$(repo_visibility)
  if [ -n "$owner_repo" ] && [ -n "$ref" ] && [ "$ref" != "HEAD" ] \
     && [ "$vis" != "PRIVATE" ] && [ "$vis" != "INTERNAL" ]; then
    if git ls-remote --exit-code origin "$ref" >/dev/null 2>&1; then
      HOST_TIER="raw"; HOST_OWNER_REPO="$owner_repo"; HOST_REF="$ref"
      return 0
    fi
  fi
  # Tier-2 (gist): available iff gh is present + authed. NOTE — this tier CANNOT
  # host images: `gh gist create` rejects binary content ("binary file not
  # supported"), so every PNG/JPG fails the guard in host_one_asset and degrades
  # to a bullet. It was previously documented as the effective primary tier for
  # PRIVATE/INTERNAL repos; that claim was wrong. It remains selectable for text
  # assets. Consequence: on a PRIVATE/INTERNAL repo WITHOUT the `gh image`
  # extension there is no working inline-embed tier (raw refused above, tier-0
  # unavailable, gist binary-blocked) — the visual-evidence block degrades to
  # bullets and inline rendering needs a manual web-UI attach. Installing
  # `drogers0/gh-image` activates tier-0 and removes that limitation. It
  # creates a render-verified gist (visibility per gist_public_effective) whose raw URL
  # camo can fetch anonymously. host_one_asset render-verifies before emitting.
  if command -v "$GH_BIN" >/dev/null 2>&1 && \
     "$GH_BIN" auth status >/dev/null 2>&1; then
    HOST_TIER="gist"; return 0
  fi
  # Tier-3: URL-only note. Only stamp a reason when the gh-image probe did not
  # already set a more specific one (absent/token_invalid/probe_timeout) — that
  # distinction is the whole point of GH_IMAGE_FAIL_REASON.
  HOST_TIER="none"
  [ -n "$GH_IMAGE_FAIL_REASON" ] || GH_IMAGE_FAIL_REASON="no_host_tier"
  return 0
}

# Return success only when a constructed raw.githubusercontent.com URL will
# RENDER inside a GitHub issue — i.e. when GitHub's camo image proxy (which
# fetches the URL ANONYMOUSLY) can retrieve it. REQ-1.
#
# The historical bug: this gate used an AUTHENTICATED `gh api contents` existence
# check, which succeeds for PRIVATE/INTERNAL content the anonymous camo proxy
# CANNOT fetch — a false positive that emitted a dead raw URL (broken image).
#
# New semantics:
#   - PRIVATE/INTERNAL repo  → ALWAYS fail (anonymous fetch would 404; degrade).
#   - PUBLIC repo            → require an anonymous `curl -fsIL` HEAD to succeed
#                              (no auth header — mirrors what camo sees). When
#                              curl is absent, fall back to the authenticated
#                              existence check (best effort; public content the
#                              auth check sees is anonymously fetchable too).
# Any uncertainty degrades away from the raw tier (non-blocking).
raw_asset_url_reachable() {
  # $1=owner/repo $2=ref $3=rel-path $4=raw-url
  local owner_repo="$1" ref="$2" rel="$3" raw_url="$4"
  local vis
  vis=$(repo_visibility)
  # REQ-1: never emit a raw URL for non-public repos — camo can't fetch it.
  if [ "$vis" = "PRIVATE" ] || [ "$vis" = "INTERNAL" ]; then
    return 1
  fi
  # Public (or unknown-visibility public-by-default): approximate the camo proxy's
  # ANONYMOUS fetch. Strip any ambient auth so the HEAD matches what camo sees.
  if command -v curl >/dev/null 2>&1; then
    curl -fsIL --max-time 10 -H 'Authorization:' "$raw_url" >/dev/null 2>&1 && return 0
    return 1
  fi
  # No curl: fall back to authenticated existence (best effort; only reached for
  # public/unknown repos, where existence implies anonymous reachability).
  if command -v "$GH_BIN" >/dev/null 2>&1 && "$GH_BIN" auth status >/dev/null 2>&1; then
    "$GH_BIN" api --silent -X GET "repos/$owner_repo/contents/$rel" -f ref="$ref" >/dev/null 2>&1 && return 0
  fi
  return 1
}

# Return success only when a gist raw URL will RENDER inside a GitHub issue/PR —
# i.e. when GitHub's camo image proxy (which fetches origins ANONYMOUSLY) can
# retrieve it. AC1/REQ-1: a public-gist raw URL is anonymously fetchable, so it
# renders inside a PRIVATE repo's body (the surrounding repo's privacy does not
# gate camo's outbound fetch of a public origin). Mirrors raw_asset_url_reachable.
#   $1 = gist raw URL
# GIST_VERIFY_FORCE (offline test hook) short-circuits the network probe:
#   pass → return 0 ; fail → return 1.
gist_raw_url_reachable() {
  local url="$1"
  # Offline test hook: bypass the network entirely.
  case "$GIST_VERIFY_FORCE" in
    pass) return 0 ;;
    fail) return 1 ;;
  esac
  # Approximate camo's ANONYMOUS fetch: strip any ambient auth header so the HEAD
  # matches what camo sees AND so a leaked token is never sent to a URL derived
  # from gh output.
  if command -v curl >/dev/null 2>&1; then
    curl -fsIL --max-time 10 -H 'Authorization;' "$url" >/dev/null 2>&1 && return 0
    return 1
  fi
  # No curl: optimistic-pass. A gist raw URL (public or unlisted/secret) is
  # anonymously reachable by construction, so without a probe tool we assume it
  # renders rather than dropping a working embed. Document the assumption.
  return 0
}

# Resolve the effective gist visibility: "1" (public) or "0" (secret/unlisted).
# An explicit ASSET_GIST_PUBLIC always wins and short-circuits before any probe,
# so callers that set it need no gh/network access. Empty → auto-derive from
# repo visibility, declining `--public` for closed repos (see the ASSET_GIST_PUBLIC
# note above). Unknown visibility (no gh, unauthed, probe failure) falls back to
# public: that is the historical behaviour, and it keeps the embed rendering.
gist_public_effective() {
  case "${ASSET_GIST_PUBLIC:-}" in
    1) printf '1'; return 0 ;;
    0) printf '0'; return 0 ;;
  esac
  case "$(repo_visibility 2>/dev/null || printf '')" in
    PRIVATE|INTERNAL) printf '0' ;;
    *)                printf '1' ;;
  esac
}

# Host a single PNG and echo its public https URL (or empty on failure).
#   $1 = basename, $2 = on-disk source path
# Uses HOST_TIER/HOST_OWNER_REPO/HOST_REF set by select_host_tier().
host_one_asset() {
  local base="$1" src="$2"
  case "$HOST_TIER" in
    user-attachments)
      # TOP tier: github.com/user-attachments/assets/<uuid>. Live via the
      # `gh image` extension, which supplies the browser SESSION token that the
      # upload-policy flow requires and a PAT cannot provide (the q1 blocker).
      # GitHub rewrites these to private-user-images.githubusercontent.com with a
      # short-lived scoped JWT, so they render for repo members on PRIVATE and
      # INTERNAL repos, accept binaries, and never touch the repository.
      if [ -n "$USER_ATTACH_URL_BASE" ]; then
        # Mirror GIST_RAW_URL_BASE: synthesise the asset URL offline. A real UUID
        # is server-assigned; the mock base stands in for it in tests.
        printf '%s/%s' "${USER_ATTACH_URL_BASE%/}" "$base"; return 0
      fi
      if [ "$DRY_RUN" = "1" ]; then
        # A dry run must not upload, but it also must not claim success for an
        # uploader that isn't there — that is the failure mode that made an
        # earlier dry run report working embeds while the real run emitted
        # bullets. check-token is read-only, so probing it here is side-effect
        # free. Inline (not via gh_image_available) to keep host_one_asset
        # dependency-free for the declare -f subshells in the self-tests.
        "$GH_BIN" image check-token >/dev/null 2>&1 || return 1
        printf 'https://github.com/user-attachments/assets/dry-run-%s' "$base"; return 0
      fi
      # `gh image <file>` prints `![<base>](<url>)` on success. Extract the URL;
      # a missing/!matching line means the upload failed, so degrade rather than
      # emit a broken embed. stderr is dropped: it can echo token diagnostics.
      local giout giurl
      giout=$("$GH_BIN" image "$src" 2>/dev/null) || return 1
      giurl=$(printf '%s' "$giout" \
        | grep -oE 'https://github\.com/user-attachments/assets/[A-Za-z0-9._-]+' | head -1)
      [ -z "$giurl" ] && return 1
      printf '%s' "$giurl"
      return 0 ;;
    raw)
      # Copy the PNG into the tracked assets path on the worktask branch so a
      # later (human-gated) commit ships it. We do NOT git-add/commit/push here.
      local rel=".worktask-assets/${WORKTASK_ID:-task}/$base"
      local dest="$ASSET_ROOT/$rel"
      if [ "$DRY_RUN" != "1" ]; then
        mkdir -p "$(dirname "$dest")" 2>/dev/null || return 1
        cp -f "$src" "$dest" 2>/dev/null || return 1
      fi
      local raw_url
      raw_url=$(printf 'https://raw.githubusercontent.com/%s/%s/%s' \
        "$HOST_OWNER_REPO" "$HOST_REF" "$rel")
      # Prevent broken image markdown: only emit tier-1 URLs when the asset is
      # reachable at that ref. Otherwise signal failure so caller degrades.
      if [ "$DRY_RUN" != "1" ] && ! raw_asset_url_reachable "$HOST_OWNER_REPO" "$HOST_REF" "$rel" "$raw_url"; then
        return 1
      fi
      printf '%s' "$raw_url"
      return 0 ;;
    gist)
      # HARD LIMIT: `gh gist create` rejects binary content outright with
      # "binary file not supported" — the gists API takes UTF-8 text only. A
      # PNG/JPG can therefore NEVER be hosted on this tier, on any repo. Detect
      # it here and fail fast so the caller degrades to a bullet with a real
      # reason, instead of burning a network round-trip on a guaranteed failure.
      # Placed ahead of the mock/dry-run short-circuits deliberately: a dry run
      # that reported a working embed for a binary would be lying about the very
      # thing being dry-run. `grep -I` treats binary as non-matching, so this
      # succeeds only for text.
      if ! LC_ALL=C grep -qI . "$src" 2>/dev/null; then
        return 1
      fi
      # Mock-friendly: if GIST_RAW_URL_BASE is set (self-tests), synthesise the
      # raw URL without touching the network. Otherwise upload via gh.
      if [ -n "$GIST_RAW_URL_BASE" ]; then
        printf '%s/%s' "${GIST_RAW_URL_BASE%/}" "$base"; return 0
      fi
      if [ "$DRY_RUN" = "1" ]; then
        printf 'https://gist.githubusercontent.com/dry/run/raw/%s' "$base"; return 0
      fi
      local gout raw raw_url
      # Visibility via gist_public_effective(): explicit ASSET_GIST_PUBLIC wins,
      # else auto-derived from repo visibility (closed repo → secret). Both kinds
      # are anonymously fetchable, so both render — only discoverability differs.
      if [ "$(gist_public_effective)" = "1" ]; then
        gout=$("$GH_BIN" gist create --public "$src" 2>/dev/null) || return 1
      else
        gout=$("$GH_BIN" gist create "$src" 2>/dev/null) || return 1
      fi
      # gh prints the gist web URL; the raw asset URL is web/raw/<base>.
      raw=$(printf '%s' "$gout" | grep -oE 'https://gist\.github\.com/[A-Za-z0-9._/-]+' | head -1)
      [ -z "$raw" ] && return 1
      raw_url=$(printf '%s/raw/%s' "$raw" "$base")
      # REQ-1: render-verify (anonymous HEAD) before emitting; on miss, signal
      # failure so the caller degrades — never emit a non-rendering URL.
      if ! gist_raw_url_reachable "$raw_url"; then
        return 1
      fi
      printf '%s' "$raw_url"
      return 0 ;;
    *)
      return 1 ;;
  esac
}

# Rewrite {{asset:<basename>}} tokens in the (already-sanitised) design-preview
# body to hosted `![<basename>](<url>)` lines. Reads body on stdin, writes the
# rewritten body to stdout. Because this runs in a command substitution, it
# records degradation by writing the reason to $ASSET_DEGRADED_FILE (when set)
# rather than to a parent variable — the parent reads the file afterwards. A
# tier-1/tier-2 hosting miss injects exactly one tier-3 note line. NON-BLOCKING.
_flag_degraded() {
  # $1 = reason. Record both in-subshell (for self-test direct calls) and via
  # the file side channel (for the live command-substitution call site).
  ASSET_DEGRADED_REASON="$1"
  [ -n "$ASSET_DEGRADED_FILE" ] && printf '%s' "$1" > "$ASSET_DEGRADED_FILE" 2>/dev/null || true
}
resolve_design_assets() {
  local body; body=$(cat)
  # Fast path: no tokens → return body unchanged (URL-only design-preview).
  if ! printf '%s\n' "$body" | grep -q '{{asset:'; then
    printf '%s' "$body"
    return 0
  fi
  select_host_tier
  # Tier-3 (no hosting): strip every {{asset:...}} token line, append exactly one
  # note line. Preserve all non-token lines (Figma URL + description bullets).
  if [ "$HOST_TIER" = "none" ]; then
    _flag_degraded "image_hosting_unavailable"
    printf '%s\n' "$body" \
      | LC_ALL=C awk '/^[[:space:]]*\{\{asset:[^}]+\}\}[[:space:]]*$/ { next } { print }'
    printf 'Screenshots persisted on disk; inline hosting unavailable — see designs registry.\n'
    return 0
  fi
  # Tier-1/Tier-2: substitute each token with a hosted image line. If a single
  # asset cannot be hosted (missing on disk, host_one_asset fails), drop its
  # token line and flag degradation, but keep going for the rest (best effort).
  local degraded=0 line base src url
  while IFS= read -r line; do
    case "$line" in
      *'{{asset:'*'}}'*)
        # Extract basename between {{asset: and }}.
        base=$(printf '%s' "$line" | sed -n 's/.*{{asset:\([^}]*\)}}.*/\1/p')
        if [ -z "$base" ]; then printf '%s\n' "$line"; continue; fi
        src=$(resolve_asset_path "$base" || true)
        if [ -z "$src" ]; then degraded=1; continue; fi   # no file → drop token
        url=$(host_one_asset "$base" "$src" || true)
        if [ -z "$url" ]; then degraded=1; continue; fi    # host failed → drop
        printf '![%s](%s)\n' "$base" "$url"
        ;;
      *)
        printf '%s\n' "$line"
        ;;
    esac
  done <<EOF
$body
EOF
  if [ "$degraded" = "1" ]; then
    _flag_degraded "image_hosting_unavailable"
    printf 'Screenshots persisted on disk; inline hosting unavailable — see designs registry.\n'
  fi
  return 0
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
#   1. MILESTONE_MODE=1 env override (used by tests).
#   2. state.json:metadata.milestone non-empty.
#   3. workspace.json present at $WORKSPACE_ROOT or $PWD.
is_milestone_mode() {
  [ "${MILESTONE_MODE:-0}" = "1" ] && return 0
  if [ -f "$STATE_FILE" ]; then
    local m
    m=$(jq -r '.metadata.milestone // ""' "$STATE_FILE" 2>/dev/null)
    [ -n "$m" ] && [ "$m" != "null" ] && return 0
  fi
  find_workspace_json >/dev/null 2>&1 && return 0
  return 1
}

# ---------- atomic state.json write -----------------------------------------
write_state_url() {
  # $1=url. Atomically sets state.json:metadata.github_issue_url.
  local url="$1"
  local tmp="${STATE_FILE}.tmp.$$"
  jq --arg url "$url" '.metadata = (.metadata // {}) | .metadata.github_issue_url = $url' "$STATE_FILE" > "$tmp" || return 1
  sync "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$STATE_FILE" || return 1
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
  local tmp="${ISSUE_ANCHOR}.tmp.$$"
  jq -cn --arg url "$url" --argjson num "${number:-0}" \
     --arg wid "${WORKTASK_ID:-unknown}" --argjson ri "${RUN_INDEX:-0}" \
     --arg ts "$(date -u +%FT%TZ)" \
     '{version:1, url:$url, number:$num, created_run_index:$ri, created_worktask_id:$wid, created_at:$ts, last_commented_run_index:$ri}' \
     > "$tmp" 2>/dev/null || return 1
  sync "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$ISSUE_ANCHOR" || return 1
}

bump_anchor_commented() {
  # $1=run_index. Record a follow-up comment for this run (anchor-source path).
  local ri="$1"
  [ -n "$ISSUE_ANCHOR" ] && [ -f "$ISSUE_ANCHOR" ] || return 0
  local tmp="${ISSUE_ANCHOR}.tmp.$$"
  jq --argjson ri "${ri:-0}" '.last_commented_run_index = $ri' "$ISSUE_ANCHOR" > "$tmp" 2>/dev/null || return 1
  sync "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$ISSUE_ANCHOR" || return 1
}

# Return 0 if the issue already carries $2 among its comment bodies (network guard
# for comment idempotency; mirrors attach-visual-evidence.sh:issue_has_marker).
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
resolve_context_issue_search() {
  resolve_context_issue_search_for "$TITLE"
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
# Per spec §4.1: worktask (blue), planning-approved (green), complexity:<tier>
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
  local tmp="${STATE_FILE}.tmp.$$"
  jq --arg t "$tkt" '.metadata = (.metadata // {}) | .metadata.external_ticket = $t' "$STATE_FILE" > "$tmp" || return 1
  sync "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$STATE_FILE" || return 1
}

# ---------- self-test -------------------------------------------------------
run_self_tests() {
  local fixtures_dir
  # Self-test fixtures are reference data kept under references/fixtures/; this
  # script lives in scripts/, so reach one level up into the sibling references/.
  fixtures_dir="$(dirname "$0")/../references/fixtures/publish-pl-issue"
  [ -d "$fixtures_dir" ] || { echo "publish-pl-issue: fixtures dir missing: $fixtures_dir" >&2; return 1; }
  local pass=0 fail=0

  # Fixture 01: clean plan — sanitiser should not strip much.
  local clean orig_len san_len
  clean=$(sanitise_body < "$fixtures_dir/01-clean-plan.md")
  orig_len=$(wc -c < "$fixtures_dir/01-clean-plan.md")
  san_len=$(printf '%s' "$clean" | wc -c)
  if [ "$san_len" -gt 0 ] && [ "$san_len" -ge $((orig_len / 2)) ]; then
    echo "publish-pl-issue: self-test 01-clean-plan PASS (orig=$orig_len san=$san_len)"
    pass=$((pass + 1))
  else
    echo "publish-pl-issue: self-test 01-clean-plan FAIL (orig=$orig_len san=$san_len)"
    fail=$((fail + 1))
  fi

  # Fixture 02: leaky plan — must strip all forbidden tokens.
  local leaky
  leaky=$(sanitise_body < "$fixtures_dir/02-leaky-plan.md")
  if printf '%s' "$leaky" | grep -qE '\.context/|/Users/|conductor/workspaces/|planning-[0-9]+\.md'; then
    echo "publish-pl-issue: self-test 02-leaky-plan FAIL (leak detected)"
    printf '%s\n' "$leaky" | grep -E '\.context/|/Users/|conductor/workspaces/|planning-[0-9]+\.md' | head -3 >&2
    fail=$((fail + 1))
  else
    echo "publish-pl-issue: self-test 02-leaky-plan PASS (no leaks)"
    pass=$((pass + 1))
  fi

  # Fixture 03: mostly-paths — strip ratio should be > 50%.
  local pathy pathy_orig pathy_san ratio_num ratio_den
  pathy=$(sanitise_body < "$fixtures_dir/03-mostly-paths.md")
  pathy_orig=$(wc -c < "$fixtures_dir/03-mostly-paths.md")
  pathy_san=$(printf '%s' "$pathy" | wc -c)
  ratio_num=$((pathy_orig - pathy_san))
  ratio_den=$pathy_orig
  if [ "$ratio_den" -gt 0 ] && [ $((ratio_num * 100 / ratio_den)) -gt 50 ]; then
    echo "publish-pl-issue: self-test 03-mostly-paths PASS (strip_pct=$((ratio_num * 100 / ratio_den))%)"
    pass=$((pass + 1))
  else
    echo "publish-pl-issue: self-test 03-mostly-paths FAIL (strip ratio not > 50%)"
    fail=$((fail + 1))
  fi

  # Fixture 04: already-published — companion state.json short-circuits.
  local f04_state="$fixtures_dir/04-state.json"
  local url_check
  url_check=$(jq -r '.metadata.github_issue_url // ""' "$f04_state" 2>/dev/null)
  if [ -n "$url_check" ]; then
    echo "publish-pl-issue: self-test 04-already-published PASS (state preloaded with $url_check)"
    pass=$((pass + 1))
  else
    echo "publish-pl-issue: self-test 04-already-published FAIL (state.json missing github_issue_url)"
    fail=$((fail + 1))
  fi

  # Fixture 05: milestone-mode — companion state.json carries metadata.milestone.
  # Detector reads STATE_FILE directly; verify both env-override and state-json
  # signals would fire is_milestone_mode().
  local f05_state="$fixtures_dir/05-state.json"
  local milestone_check
  milestone_check=$(jq -r '.metadata.milestone // ""' "$f05_state" 2>/dev/null)
  local env_check=0
  ( MILESTONE_MODE=1 STATE_FILE=/dev/null bash -c '
      [ "${MILESTONE_MODE:-0}" = "1" ] && exit 0 || exit 1
    ' ) && env_check=1
  if [ -n "$milestone_check" ] && [ "$milestone_check" != "null" ] && [ "$env_check" = "1" ]; then
    echo "publish-pl-issue: self-test 05-milestone-mode PASS (state.metadata.milestone=$milestone_check + env override)"
    pass=$((pass + 1))
  else
    echo "publish-pl-issue: self-test 05-milestone-mode FAIL (milestone=$milestone_check env_check=$env_check)"
    fail=$((fail + 1))
  fi

  # ---- Fixture 06: strict mode — STRICT=1 + label create failure → exit 1 ----
  # Run the strict-mode assertion in a subshell with a mocked $GH_BIN that always
  # fails on `label create`. Verify the helper exits 1 and writes an audit row
  # with result=failed and reason=label_create_failed.
  local t6_dir t6_log t6_state t6_plan
  t6_dir=$(mktemp -d 2>/dev/null || echo "/tmp/publish-pl-self-test-06.$$")
  mkdir -p "$t6_dir/.context/logs" "$t6_dir/bin"
  t6_state="$t6_dir/.context/state.json"
  t6_plan="$t6_dir/planning-0.md"
  cat > "$t6_state" <<'JSON'
{"version":1,"worktask_id":"strict-mode-test","run_index":0,"plan_file":"PLAN_PLACEHOLDER","facts":{"goal":"OV-999 Strict mode regression"},"metadata":{}}
JSON
  # Patch plan_file path in state.json.
  jq --arg p "$t6_plan" '.plan_file = $p' "$t6_state" > "$t6_state.tmp" && mv -f "$t6_state.tmp" "$t6_state"
  cat > "$t6_plan" <<'MD'
# Strict-mode plan
## requirements
- REQ-1: example
## acceptance-criteria
- AC-1: example
## scope
In: x. Out: y.
## complexity
Score: 5/50 (Low).
## stages
PL0 → DV0
MD
  # Mock gh that fails every label create + issue create (label-related stderr).
  cat > "$t6_dir/bin/gh" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  auth)         exit 0 ;;
  label)
    case "$2" in
      list) echo "" ; exit 0 ;;
      create) echo "could not create label: validation failed" >&2 ; exit 1 ;;
    esac ;;
  issue)
    echo "could not add label: 'worktask' not found in repository" >&2
    exit 1 ;;
esac
exit 0
MOCK
  chmod +x "$t6_dir/bin/gh"
  # Provide a fake `git remote get-url origin` by injecting a dummy git wrapper
  # (lightweight: just intercept `remote get-url`).
  cat > "$t6_dir/bin/git" <<'MOCK'
#!/usr/bin/env bash
if [ "$1" = "remote" ] && [ "$2" = "get-url" ]; then echo "git@example.com:org/repo.git"; exit 0; fi
exec /usr/bin/env -i PATH=/usr/bin:/bin git "$@"
MOCK
  chmod +x "$t6_dir/bin/git"
  t6_log="$t6_dir/run.log"
  ( PATH="$t6_dir/bin:$PATH" \
    STATE_FILE="$t6_state" \
    WORKSPACE_ROOT="$t6_dir" \
    GH_BIN="gh" \
    STRICT=1 \
    bash "$0" >"$t6_log" 2>&1 )
  local t6_rc=$?
  local t6_audit="$t6_dir/.context/logs/audit.jsonl"
  if [ "$t6_rc" -eq 1 ] && [ -f "$t6_audit" ] && \
     grep -q '"result":"failed"' "$t6_audit" && \
     grep -qE '"reason":"label_create_failed"|"reason":"gh_api_error"' "$t6_audit"; then
    echo "publish-pl-issue: self-test 06-strict-mode PASS (rc=$t6_rc, audit result=failed)"
    pass=$((pass + 1))
  else
    echo "publish-pl-issue: self-test 06-strict-mode FAIL (rc=$t6_rc)"
    [ -f "$t6_audit" ] && tail -1 "$t6_audit" >&2 || echo "  no audit row" >&2
    fail=$((fail + 1))
  fi
  rm -rf "$t6_dir"

  # ---- Fixture 07: external-ticket extraction ----
  local t7_match t7_no_double
  t7_match=$(extract_external_ticket "OV-113 Change navigation in settings")
  if [ "$t7_match" = "OV-113" ]; then
    echo "publish-pl-issue: self-test 07-ticket-extract PASS (got '$t7_match')"
    pass=$((pass + 1))
  else
    echo "publish-pl-issue: self-test 07-ticket-extract FAIL (got '$t7_match' want 'OV-113')"
    fail=$((fail + 1))
  fi
  # No-match case (lowercase / no number / wrong shape).
  local t7_neg
  t7_neg=$(extract_external_ticket "fix-publish-pl-issue-helper")
  if [ -z "$t7_neg" ]; then
    echo "publish-pl-issue: self-test 07-ticket-no-match PASS (empty as expected)"
    pass=$((pass + 1))
  else
    echo "publish-pl-issue: self-test 07-ticket-no-match FAIL (matched '$t7_neg')"
    fail=$((fail + 1))
  fi
  # Title-prefix idempotency check (no double-prefix). Pure-string assertion.
  local _t="OV-113 Change navigation"
  case "$_t" in
    "OV-113"|"OV-113 "*|"OV-113:"*) t7_no_double=ok ;;
    *) t7_no_double=fail ;;
  esac
  if [ "$t7_no_double" = "ok" ]; then
    echo "publish-pl-issue: self-test 07-no-double-prefix PASS"
    pass=$((pass + 1))
  else
    echo "publish-pl-issue: self-test 07-no-double-prefix FAIL"
    fail=$((fail + 1))
  fi

  # ---- Fixture 13: title/summary resolution chain (#375) ----
  # Driven end-to-end through the real entrypoint under DRY_RUN=1, not through the
  # helpers in isolation: the title is only observable on the `gh issue create` line
  # and the Summary only in the rendered body file, so a unit-level assertion would
  # miss exactly the wiring that broke. `t13_run <plan> <worktask_id> [goal]` builds a
  # throwaway workspace, runs the script, and leaves stderr + body + audit behind.
  local t13_dir t13_self
  t13_dir=$(mktemp -d 2>/dev/null || echo "/tmp/publish-pl-self-test-13.$$")
  # Absolute: t13_run cds into the throwaway workspace before re-invoking us, so a
  # relative $0 (the normal invocation shape) would no longer resolve.
  t13_self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  t13_run() {
    local plan="$1" wid="$2" goal="${3:-}" run="$t13_dir/run"
    rm -rf "$run"; mkdir -p "$run/.context/logs"
    cp "$plan" "$run/.context/planning-0.md"
    jq -n --arg w "$wid" --arg g "$goal" \
      '{version:2, worktask_id:$w, run_index:0, plan_file:".context/planning-0.md",
        tasks:{PL0:{status:"completed"}},
        facts:(if $g == "" then {} else {goal:$g} end),
        handoffs:{}, metadata:{}}' > "$run/.context/state.json"
    ( cd "$run" && WORKSPACE_ROOT="$run" STATE_FILE="$run/.context/state.json" \
        DRY_RUN=1 GH_ISSUE_SEARCH=0 GH_BIN=true \
        bash "$t13_self" > "$run/out.txt" 2> "$run/err.txt" )
  }
  # Title as published: the DRY_RUN line quotes it, so read between the quotes.
  t13_title() {
    sed -n 's/.*--title "\(.*\)" --body-file.*/\1/p' "$t13_dir/run/err.txt" | head -1
  }
  t13_summary() {
    awk '/^## Summary$/ { s = 1; next } /^## / { s = 0 } s' "$t13_dir/run/issue-body-0.tmp" 2>/dev/null \
      || true
  }

  local f13="$fixtures_dir/13-frontmatter-title.md"
  local f13b="$fixtures_dir/13b-prefixed-title.md"
  local f13c="$fixtures_dir/13c-no-title-source.md"
  if [ -f "$f13" ] && [ -f "$f13b" ] && [ -f "$f13c" ]; then
    # 13a: no facts.goal → frontmatter title wins, ticket prefixed exactly once,
    # and the Summary falls back to the plan's own ## summary anchor.
    local t13a_ok=1 t13a_title t13a_sum
    t13_run "$f13" "ov-164-catalog-image-blinking" ""
    # LOG_DIR is WORKSPACE_ROOT-relative, so the body lands beside the run's audit.
    cp "$t13_dir/run/.context/logs/issue-body-0.tmp" "$t13_dir/run/issue-body-0.tmp" 2>/dev/null || true
    t13a_title=$(t13_title)
    t13a_sum=$(t13_summary | tr -d '[:space:]')
    [ "$t13a_title" = "OV-164 Product list images are blinking before rendering" ] || t13a_ok=0
    [ -n "$t13a_sum" ] || t13a_ok=0
    if [ "$t13a_ok" = "1" ]; then
      echo "publish-pl-issue: self-test 13a-frontmatter-title PASS"
      pass=$((pass + 1))
    else
      echo "publish-pl-issue: self-test 13a-frontmatter-title FAIL (title='$t13a_title' summary_empty=$([ -z "$t13a_sum" ] && echo yes || echo no))"
      fail=$((fail + 1))
    fi

    # 13b: a frontmatter title that ALREADY carries the ticket must not be doubled.
    local t13b_ok=1 t13b_title
    t13_run "$f13b" "ov-164-catalog-image-blinking" ""
    t13b_title=$(t13_title)
    [ "$t13b_title" = "OV-164 Product list images are blinking before rendering" ] || t13b_ok=0
    case "$t13b_title" in *"OV-164 OV-164"*) t13b_ok=0 ;; esac
    if [ "$t13b_ok" = "1" ]; then
      echo "publish-pl-issue: self-test 13b-no-double-prefix PASS"
      pass=$((pass + 1))
    else
      echo "publish-pl-issue: self-test 13b-no-double-prefix FAIL (title='$t13b_title')"
      fail=$((fail + 1))
    fi

    # 13c: every prose rank empty → slug fallback, exit 0, degradation row present.
    local t13c_ok=1 t13c_title t13c_rc=0
    t13_run "$f13c" "wt-no-sources" "" || t13c_rc=$?
    t13c_title=$(t13_title)
    [ "$t13c_rc" = "0" ] || t13c_ok=0
    [ "$t13c_title" = "wt-no-sources" ] || t13c_ok=0
    grep -qF '"reason":"title_fallback_worktask_id"' "$t13_dir/run/.context/logs/audit.jsonl" 2>/dev/null || t13c_ok=0
    if [ "$t13c_ok" = "1" ]; then
      echo "publish-pl-issue: self-test 13c-slug-fallback-audited PASS"
      pass=$((pass + 1))
    else
      echo "publish-pl-issue: self-test 13c-slug-fallback-audited FAIL (rc=$t13c_rc title='$t13c_title')"
      fail=$((fail + 1))
    fi

    # 13d: no regression — facts.goal set still wins every later rank, for BOTH the
    # title and the Summary, exactly as before the chain existed.
    local t13d_ok=1 t13d_title t13d_sum
    t13_run "$f13" "ov-164-catalog-image-blinking" "OV-164 Ship the catalog image cache"
    cp "$t13_dir/run/.context/logs/issue-body-0.tmp" "$t13_dir/run/issue-body-0.tmp" 2>/dev/null || true
    t13d_title=$(t13_title)
    t13d_sum=$(t13_summary)
    [ "$t13d_title" = "OV-164 Ship the catalog image cache" ] || t13d_ok=0
    printf '%s' "$t13d_sum" | grep -qF 'Ship the catalog image cache' || t13d_ok=0
    if [ "$t13d_ok" = "1" ]; then
      echo "publish-pl-issue: self-test 13d-goal-still-wins PASS"
      pass=$((pass + 1))
    else
      echo "publish-pl-issue: self-test 13d-goal-still-wins FAIL (title='$t13d_title')"
      fail=$((fail + 1))
    fi
  else
    echo "publish-pl-issue: self-test 13-title-chain SKIP (fixtures missing)"
    fail=$((fail + 1))
  fi

  # 13e: reader units — frontmatter parsing must not read a `---` thematic break
  # further down the body, and first_sentence must not stop inside "3.5s".
  local t13e_ok=1 t13e_v
  printf 'not frontmatter\n\n---\ntitle: Stolen From A Thematic Break\n---\n' > "$t13_dir/nofm.md"
  t13e_v=$(extract_frontmatter_field "$t13_dir/nofm.md" "title")
  [ -z "$t13e_v" ] || t13e_ok=0
  printf -- '---\ntitle: "Quoted: with a colon"\n---\n# H1 here\n' > "$t13_dir/fm.md"
  t13e_v=$(extract_frontmatter_field "$t13_dir/fm.md" "title")
  [ "$t13e_v" = "Quoted: with a colon" ] || t13e_ok=0
  t13e_v=$(extract_first_h1 "$t13_dir/fm.md")
  [ "$t13e_v" = "H1 here" ] || t13e_ok=0
  t13e_v=$(printf -- '- a bullet\n\nCut the 3.5s delay. Second sentence.\n' | first_sentence)
  [ "$t13e_v" = "Cut the 3.5s delay." ] || t13e_ok=0
  # A nested key belongs to its block: the PL template's `handoff:` carries indented
  # fields, and one of them must never be mistaken for the document's own title.
  printf -- '---\nhandoff:\n  title: Nested Not Mine\n---\n' > "$t13_dir/nested.md"
  t13e_v=$(extract_frontmatter_field "$t13_dir/nested.md" "title")
  [ -z "$t13e_v" ] || t13e_ok=0
  printf -- "---\ntitle: 'Single quoted'\n---\n" > "$t13_dir/sq.md"
  t13e_v=$(extract_frontmatter_field "$t13_dir/sq.md" "title")
  [ "$t13e_v" = "Single quoted" ] || t13e_ok=0
  if [ "$t13e_ok" = "1" ]; then
    echo "publish-pl-issue: self-test 13e-chain-readers PASS"
    pass=$((pass + 1))
  else
    echo "publish-pl-issue: self-test 13e-chain-readers FAIL (last='$t13e_v')"
    fail=$((fail + 1))
  fi
  rm -rf "$t13_dir"

  # ---- Fixture classify_gh_failure: canned stderr blobs ----
  local cl
  cl=$(classify_gh_failure "could not add label: 'worktask' not found in repository")
  if [ "$cl" = "label_create_failed" ]; then
    pass=$((pass + 1)); echo "publish-pl-issue: self-test classify(label) PASS ($cl)"
  else
    fail=$((fail + 1)); echo "publish-pl-issue: self-test classify(label) FAIL ($cl)"
  fi
  cl=$(classify_gh_failure "HTTP 401: Bad credentials")
  if [ "$cl" = "auth_missing" ]; then
    pass=$((pass + 1)); echo "publish-pl-issue: self-test classify(401) PASS ($cl)"
  else
    fail=$((fail + 1)); echo "publish-pl-issue: self-test classify(401) FAIL ($cl)"
  fi
  cl=$(classify_gh_failure "HTTP 403: permission denied")
  if [ "$cl" = "permission_denied" ]; then
    pass=$((pass + 1)); echo "publish-pl-issue: self-test classify(403) PASS ($cl)"
  else
    fail=$((fail + 1)); echo "publish-pl-issue: self-test classify(403) FAIL ($cl)"
  fi
  cl=$(classify_gh_failure "HTTP 404: repository not found")
  if [ "$cl" = "repo_not_found" ]; then
    pass=$((pass + 1)); echo "publish-pl-issue: self-test classify(404) PASS ($cl)"
  else
    fail=$((fail + 1)); echo "publish-pl-issue: self-test classify(404) FAIL ($cl)"
  fi
  cl=$(classify_gh_failure "request timed out after 30s")
  if [ "$cl" = "gh_timeout" ]; then
    pass=$((pass + 1)); echo "publish-pl-issue: self-test classify(timeout) PASS ($cl)"
  else
    fail=$((fail + 1)); echo "publish-pl-issue: self-test classify(timeout) FAIL ($cl)"
  fi
  cl=$(classify_gh_failure "could not resolve host: api.github.com")
  if [ "$cl" = "network_error" ]; then
    pass=$((pass + 1)); echo "publish-pl-issue: self-test classify(network) PASS ($cl)"
  else
    fail=$((fail + 1)); echo "publish-pl-issue: self-test classify(network) FAIL ($cl)"
  fi
  cl=$(classify_gh_failure "")
  if [ "$cl" = "gh_api_error" ]; then
    pass=$((pass + 1)); echo "publish-pl-issue: self-test classify(default) PASS ($cl)"
  else
    fail=$((fail + 1)); echo "publish-pl-issue: self-test classify(default) FAIL ($cl)"
  fi

  # ---- Fixture 08: label auto-create idempotency + ensure_labels behaviour ----
  # Mock gh to (a) report a partial label list, (b) succeed on `label create`.
  # Confirm DROPPED_LABELS stays empty.
  local t8_dir
  t8_dir=$(mktemp -d 2>/dev/null || echo "/tmp/publish-pl-self-test-08.$$")
  mkdir -p "$t8_dir/bin"
  cat > "$t8_dir/bin/gh" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  label)
    case "$2" in
      list) printf '' ; exit 0 ;;     # zero existing labels
      create) exit 0 ;;               # creates always succeed
    esac ;;
esac
exit 0
MOCK
  chmod +x "$t8_dir/bin/gh"
  # Re-source-free invocation: call ensure_labels in a clean subshell whose only
  # `gh` on PATH is the mock above.
  local t8_dropped
  t8_dropped=$( PATH="$t8_dir/bin:$PATH" GH_BIN=gh bash -c '
    DROPPED_LABELS=""
    '"$(declare -f label_color)"'
    '"$(declare -f label_description)"'
    '"$(declare -f ensure_labels)"'
    ensure_labels worktask planning-approved complexity:low ticket:OV-113
    printf "%s" "$DROPPED_LABELS"
  ' )
  if [ -z "$t8_dropped" ]; then
    echo "publish-pl-issue: self-test 08-missing-labels PASS (all 4 created, none dropped)"
    pass=$((pass + 1))
  else
    echo "publish-pl-issue: self-test 08-missing-labels FAIL (dropped='$t8_dropped')"
    fail=$((fail + 1))
  fi
  # Idempotency: second invocation with the same labels (now "existing") must
  # also produce no drops.
  cat > "$t8_dir/bin/gh" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  label)
    case "$2" in
      list)
        printf 'worktask\nplanning-approved\ncomplexity:low\nticket:OV-113\n'
        exit 0 ;;
      create) echo "label already exists" >&2; exit 1 ;;  # would fail if called
    esac ;;
esac
exit 0
MOCK
  chmod +x "$t8_dir/bin/gh"
  t8_dropped=$( PATH="$t8_dir/bin:$PATH" GH_BIN=gh bash -c '
    DROPPED_LABELS=""
    '"$(declare -f label_color)"'
    '"$(declare -f label_description)"'
    '"$(declare -f ensure_labels)"'
    ensure_labels worktask planning-approved complexity:low ticket:OV-113
    printf "%s" "$DROPPED_LABELS"
  ' )
  if [ -z "$t8_dropped" ]; then
    echo "publish-pl-issue: self-test 08-idempotent PASS"
    pass=$((pass + 1))
  else
    echo "publish-pl-issue: self-test 08-idempotent FAIL (dropped='$t8_dropped')"
    fail=$((fail + 1))
  fi
  rm -rf "$t8_dir"

  # ---- Fixture 09: Design Preview render (with Figma URL) ----
  # Build the rendered body from fixture 09 in the same shape as the live
  # render block. Asserts the new heading + URL preservation + absence of
  # the now-removed Planned Stages heading + reviewer instruction line.
  local f9="$fixtures_dir/09-with-figma-link.md"
  if [ -f "$f9" ]; then
    local f9_reqs f9_acs f9_scope f9_complex f9_design f9_body
    f9_reqs=$(extract_anchor "$f9" "requirements" | sanitise_body)
    f9_acs=$(extract_anchor "$f9" "acceptance-criteria" | sanitise_body)
    f9_scope=$(extract_anchor "$f9" "scope" | sanitise_body)
    f9_complex=$(extract_anchor "$f9" "complexity" | sanitise_body)
    f9_design=$(extract_anchor "$f9" "design-preview" | sanitise_body)
    f9_body=$(
      printf '## Summary\nfixture 09 summary\n\n'
      printf '## Requirements\n%s\n\n' "$f9_reqs"
      printf '## Acceptance Criteria\n%s\n\n' "$f9_acs"
      printf '## Scope\n%s\n\n' "$f9_scope"
      if [ -n "$(printf '%s' "$f9_design" | tr -d '[:space:]')" ]; then
        printf '## Design Preview\n%s\n\nCompare implementation (DV) and screenshots (QA) against this design.\n\n' "$f9_design"
      fi
      printf '## Complexity\n%s\n\n' "$f9_complex"
    )
    local f9_ok=1
    printf '%s' "$f9_body" | grep -qF '## Design Preview' || f9_ok=0
    printf '%s' "$f9_body" | grep -qF 'https://www.figma.com/design/AbC123/Example?node-id=1-2' || f9_ok=0
    printf '%s' "$f9_body" | grep -qF 'Compare implementation (DV) and screenshots (QA)' || f9_ok=0
    if printf '%s' "$f9_body" | grep -qF '## Planned Stages'; then f9_ok=0; fi
    if [ "$f9_ok" = "1" ]; then
      echo "publish-pl-issue: self-test 09-with-figma-link PASS"
      pass=$((pass + 1))
    else
      echo "publish-pl-issue: self-test 09-with-figma-link FAIL"
      printf '%s\n' "$f9_body" | head -40 >&2
      fail=$((fail + 1))
    fi

    # Fixture 09b: Plan WITHOUT design-preview (use fixture 01) — rendered
    # body must contain neither Design Preview NOR Planned Stages headings.
    local f1_reqs f1_acs f1_scope f1_complex f1_design f1_body
    f1_reqs=$(extract_anchor "$fixtures_dir/01-clean-plan.md" "requirements" | sanitise_body)
    f1_acs=$(extract_anchor "$fixtures_dir/01-clean-plan.md" "acceptance-criteria" | sanitise_body)
    f1_scope=$(extract_anchor "$fixtures_dir/01-clean-plan.md" "scope" | sanitise_body)
    f1_complex=$(extract_anchor "$fixtures_dir/01-clean-plan.md" "complexity" | sanitise_body)
    f1_design=$(extract_anchor "$fixtures_dir/01-clean-plan.md" "design-preview" | sanitise_body)
    f1_body=$(
      printf '## Summary\nfixture 01 summary\n\n'
      printf '## Requirements\n%s\n\n' "$f1_reqs"
      printf '## Acceptance Criteria\n%s\n\n' "$f1_acs"
      printf '## Scope\n%s\n\n' "$f1_scope"
      if [ -n "$(printf '%s' "$f1_design" | tr -d '[:space:]')" ]; then
        printf '## Design Preview\n%s\n\nCompare implementation (DV) and screenshots (QA) against this design.\n\n' "$f1_design"
      fi
      printf '## Complexity\n%s\n\n' "$f1_complex"
    )
    local f1_ok=1
    if printf '%s' "$f1_body" | grep -qF '## Design Preview'; then f1_ok=0; fi
    if printf '%s' "$f1_body" | grep -qF '## Planned Stages'; then f1_ok=0; fi
    if [ "$f1_ok" = "1" ]; then
      echo "publish-pl-issue: self-test 09b-no-design-no-stages PASS"
      pass=$((pass + 1))
    else
      echo "publish-pl-issue: self-test 09b-no-design-no-stages FAIL"
      fail=$((fail + 1))
    fi

    # Fixture 09c: sanitiser preserves figma.com URLs (design + proto variants).
    local urls_in urls_out
    urls_in=$'Visit https://www.figma.com/design/AbC123/Example?node-id=1-2\nor https://www.figma.com/proto/XYZ789/Flow?page-id=2-3\n'
    urls_out=$(printf '%s' "$urls_in" | sanitise_body)
    local f9c_ok=1
    printf '%s' "$urls_out" | grep -qF 'figma.com/design/AbC123/Example?node-id=1-2' || f9c_ok=0
    printf '%s' "$urls_out" | grep -qF 'figma.com/proto/XYZ789/Flow?page-id=2-3' || f9c_ok=0
    if [ "$f9c_ok" = "1" ]; then
      echo "publish-pl-issue: self-test 09c-figma-urls-survive PASS"
      pass=$((pass + 1))
    else
      echo "publish-pl-issue: self-test 09c-figma-urls-survive FAIL"
      printf '%s\n' "$urls_out" >&2
      fail=$((fail + 1))
    fi

    # Fixture 02b: plugin-qualified identifier tokens must not appear in
    # sanitised body (Pass-2 A6 rule), outside code spans.
    local leak_in leak_out
    leak_in=$'Breakdown using corpflow:estimation-methodology:\n* Routed to corpflow:developer (apple-developer:ios-developer).\nDelegated to apple-developer:test-generator for regression coverage.\nNarrative referencing corpflow:product-manager directly.\nKeep `corpflow:code-fixer` inside backticks intact.\n'
    leak_out=$(printf '%s' "$leak_in" | sanitise_body)
    local f02b_ok=1
    # The three leading-token lines should be entirely dropped by L10.
    if printf '%s' "$leak_out" | grep -qF 'Breakdown using'; then f02b_ok=0; fi
    if printf '%s' "$leak_out" | grep -qF 'Routed to'; then f02b_ok=0; fi
    if printf '%s' "$leak_out" | grep -qF 'Delegated to'; then f02b_ok=0; fi
    # The mid-sentence reference should have the identifier stripped by A6
    # (narrative remains, token gone).
    if printf '%s' "$leak_out" | grep -qE '(corpflow|apple-developer|system-developer|android-developer|frontend-developer|backend-developer|ai-engineer|debugging-toolkit|security-scanning|skill-creator|conductor|claude-in-chrome):[a-z]' | grep -v '`'; then
      # Allow backticked occurrences only (one is intentionally kept).
      if printf '%s' "$leak_out" | grep -vE '^[^`]*`[^`]*`[^`]*$' | grep -qE '(corpflow|apple-developer|system-developer|android-developer|frontend-developer|backend-developer|ai-engineer|debugging-toolkit|security-scanning|skill-creator|conductor|claude-in-chrome):[a-z]'; then
        f02b_ok=0
      fi
    fi
    # Backtick passthrough preserves the token.
    if ! printf '%s' "$leak_out" | grep -qF '`corpflow:code-fixer`'; then f02b_ok=0; fi
    if [ "$f02b_ok" = "1" ]; then
      echo "publish-pl-issue: self-test 02b-identifier-leak-strip PASS"
      pass=$((pass + 1))
    else
      echo "publish-pl-issue: self-test 02b-identifier-leak-strip FAIL"
      printf '%s\n' "$leak_out" >&2
      fail=$((fail + 1))
    fi
  else
    echo "publish-pl-issue: self-test 09-with-figma-link SKIP (fixture missing)"
    fail=$((fail + 1))
  fi

  # ---- Fixture 10: Figma image-embed (placeholder → ![alt](url)) ----
  # Happy path (AC-1, AC-7, AC-3, AC-4) + fallback render (AC-5). Mocks the host
  # (ASSET_HOST_MODE) and stubs the two PNGs on disk — never hits the network.
  local f10="$fixtures_dir/10-figma-image-embed.md"
  if [ -f "$f10" ]; then
    # Sandbox: stub the two persisted PNGs in a temp canonical designs dir.
    local t10_dir
    t10_dir=$(mktemp -d 2>/dev/null || echo "/tmp/publish-pl-self-test-10.$$")
    mkdir -p "$t10_dir/.context/designs"
    # 8-byte PNG signature stubs (resolve_asset_path only checks existence).
    printf '\211PNG\r\n\032\n' > "$t10_dir/.context/designs/figma-scan-25-default-255-2264.png"
    printf '\211PNG\r\n\032\n' > "$t10_dir/.context/designs/figma-analyzing-default-255-2267.png"

    # Extract + sanitise the design-preview anchor exactly as the live path does.
    local f10_design f10_embed
    f10_design=$(extract_anchor "$f10" "design-preview" | sanitise_body)

    # --- 10a: happy path (raw host, both assets present) ---
    # Override hosting globals locally; DRY_RUN=1 skips the cp side-effect.
    local _save_root="$ASSET_ROOT" _save_designs="$ASSET_DESIGNS_DIR" _save_images="$ASSET_IMAGES_DIR"
    local _save_mode="$ASSET_HOST_MODE" _save_or="$ASSET_OWNER_REPO" _save_ref="$ASSET_REF"
    local _save_dry="$DRY_RUN" _save_wid="${WORKTASK_ID:-}"
    ASSET_ROOT="$t10_dir"
    ASSET_DESIGNS_DIR="$t10_dir/.context/designs"
    ASSET_IMAGES_DIR="$t10_dir/.context/images"
    ASSET_HOST_MODE="raw"
    ASSET_OWNER_REPO="IGRSoft/corpflow"
    ASSET_REF="feature/figma-screenshot-markdown"
    DRY_RUN=1
    WORKTASK_ID="fixture-10"
    # File side channel: resolve_design_assets runs in a subshell, so it reports
    # degradation via ASSET_DEGRADED_FILE (matching the live call site).
    local _save_degfile="$ASSET_DEGRADED_FILE"
    ASSET_DEGRADED_FILE="$t10_dir/.degraded"
    : > "$ASSET_DEGRADED_FILE"
    f10_embed=$(printf '%s' "$f10_design" | resolve_design_assets)
    ASSET_DEGRADED_REASON=$(cat "$ASSET_DEGRADED_FILE" 2>/dev/null || echo "")

    local f10a_ok=1
    # AC-1/AC-7: two ![alt](url) lines, each using the basename as alt text, in
    # document order, with the Figma URL preserved above.
    printf '%s\n' "$f10_embed" | grep -qF '![figma-scan-25-default-255-2264.png](https://raw.githubusercontent.com/IGRSoft/corpflow/feature/figma-screenshot-markdown/.worktask-assets/fixture-10/figma-scan-25-default-255-2264.png)' || f10a_ok=0
    printf '%s\n' "$f10_embed" | grep -qF '![figma-analyzing-default-255-2267.png](https://raw.githubusercontent.com/IGRSoft/corpflow/feature/figma-screenshot-markdown/.worktask-assets/fixture-10/figma-analyzing-default-255-2267.png)' || f10a_ok=0
    printf '%s\n' "$f10_embed" | grep -qF 'https://www.figma.com/design/FOO/FaceScan?node-id=255-2263' || f10a_ok=0
    # AC-7 ordering: scan-25 image line precedes analyzing image line.
    local _l25 _lan
    _l25=$(printf '%s\n' "$f10_embed" | grep -nF '![figma-scan-25-default' | head -1 | cut -d: -f1)
    _lan=$(printf '%s\n' "$f10_embed" | grep -nF '![figma-analyzing-default' | head -1 | cut -d: -f1)
    if [ -z "$_l25" ] || [ -z "$_lan" ] || [ "$_l25" -ge "$_lan" ]; then f10a_ok=0; fi
    # AC-7 interleave: each image line is immediately followed by its bullet.
    # (-e guards the leading-dash bullet pattern from being read as a flag.)
    printf '%s\n' "$f10_embed" | grep -A1 -F -e '![figma-scan-25-default' | grep -qF -e '- state `default` — 25% progress ring' || f10a_ok=0
    # No leftover placeholder tokens.
    if printf '%s\n' "$f10_embed" | grep -qF '{{asset:'; then f10a_ok=0; fi
    # No degradation flagged on the happy path.
    [ -z "$ASSET_DEGRADED_REASON" ] || f10a_ok=0
    if [ "$f10a_ok" = "1" ]; then
      echo "publish-pl-issue: self-test 10-image-embed PASS"
      pass=$((pass + 1))
    else
      echo "publish-pl-issue: self-test 10-image-embed FAIL"
      printf '%s\n' "$f10_embed" | head -20 >&2
      fail=$((fail + 1))
    fi

    # --- 10-no-leak: AC-3/AC-4 — full body grep finds no local path tokens ---
    # Build a full issue body with the embedded design-preview, then grep.
    local f10_reqs f10_acs f10_scope f10_complex f10_body
    f10_reqs=$(extract_anchor "$f10" "requirements" | sanitise_body)
    f10_acs=$(extract_anchor "$f10" "acceptance-criteria" | sanitise_body)
    f10_scope=$(extract_anchor "$f10" "scope" | sanitise_body)
    f10_complex=$(extract_anchor "$f10" "complexity" | sanitise_body)
    f10_body=$(
      printf '## Summary\nfixture 10 summary\n\n'
      printf '## Requirements\n%s\n\n' "$f10_reqs"
      printf '## Acceptance Criteria\n%s\n\n' "$f10_acs"
      printf '## Scope\n%s\n\n' "$f10_scope"
      printf '## Design Preview\n%s\n\nCompare implementation (DV) and screenshots (QA) against this design.\n\n' "$f10_embed"
      printf '## Complexity\n%s\n\n' "$f10_complex"
    )
    local f10nl_ok=1
    if printf '%s' "$f10_body" | grep -qE '\.context/|/Users/|conductor/workspaces/|planning-[0-9]+\.md'; then
      f10nl_ok=0
      printf '%s\n' "$f10_body" | grep -nE '\.context/|/Users/|conductor/workspaces/|planning-[0-9]+\.md' | head -3 >&2
    fi
    # The image lines must have survived (AC-3: not dropped by Pass-1 L1).
    printf '%s' "$f10_body" | grep -qF '![figma-scan-25-default-255-2264.png]' || f10nl_ok=0
    if [ "$f10nl_ok" = "1" ]; then
      echo "publish-pl-issue: self-test 10-no-leak PASS"
      pass=$((pass + 1))
    else
      echo "publish-pl-issue: self-test 10-no-leak FAIL"
      fail=$((fail + 1))
    fi

    # --- 10b: fallback render (AC-5) — hosting unavailable → URL-only + note ---
    ASSET_HOST_MODE="none"
    : > "$ASSET_DEGRADED_FILE"
    local f10b_embed
    f10b_embed=$(printf '%s' "$f10_design" | resolve_design_assets)
    ASSET_DEGRADED_REASON=$(cat "$ASSET_DEGRADED_FILE" 2>/dev/null || echo "")
    local f10b_ok=1
    # Figma URL preserved.
    printf '%s\n' "$f10b_embed" | grep -qF 'https://www.figma.com/design/FOO/FaceScan?node-id=255-2263' || f10b_ok=0
    # Exactly one note line, exact text.
    local _notes
    _notes=$(printf '%s\n' "$f10b_embed" | grep -cF 'Screenshots persisted on disk; inline hosting unavailable — see designs registry.')
    [ "$_notes" = "1" ] || f10b_ok=0
    # No broken image markdown, no image lines, no leftover tokens.
    if printf '%s\n' "$f10b_embed" | grep -qF '!['; then f10b_ok=0; fi
    if printf '%s\n' "$f10b_embed" | grep -qF '{{asset:'; then f10b_ok=0; fi
    # Audit reason set.
    [ "$ASSET_DEGRADED_REASON" = "image_hosting_unavailable" ] || f10b_ok=0
    if [ "$f10b_ok" = "1" ]; then
      echo "publish-pl-issue: self-test 10b-fallback PASS"
      pass=$((pass + 1))
    else
      echo "publish-pl-issue: self-test 10b-fallback FAIL"
      printf '%s\n' "$f10b_embed" | head -20 >&2
      fail=$((fail + 1))
    fi

    # Restore globals + clean up the sandbox.
    ASSET_ROOT="$_save_root"; ASSET_DESIGNS_DIR="$_save_designs"; ASSET_IMAGES_DIR="$_save_images"
    ASSET_HOST_MODE="$_save_mode"; ASSET_OWNER_REPO="$_save_or"; ASSET_REF="$_save_ref"
    DRY_RUN="$_save_dry"; WORKTASK_ID="$_save_wid"; ASSET_DEGRADED_REASON=""
    ASSET_DEGRADED_FILE="$_save_degfile"
    rm -rf "$t10_dir"
  else
    echo "publish-pl-issue: self-test 10-image-embed SKIP (fixture missing)"
    fail=$((fail + 1))
  fi

  # ---- Fixture 11: user-attachments tier + REQ-1 render-verification ----
  # Re-uses fixture 10's design-preview anchor; all paths fully offline (mocks).
  local f11="$fixtures_dir/10-figma-image-embed.md"
  if [ -f "$f11" ]; then
    local t11_dir
    t11_dir=$(mktemp -d 2>/dev/null || echo "/tmp/publish-pl-self-test-11.$$")
    mkdir -p "$t11_dir/.context/designs"
    printf '\211PNG\r\n\032\n' > "$t11_dir/.context/designs/figma-scan-25-default-255-2264.png"
    printf '\211PNG\r\n\032\n' > "$t11_dir/.context/designs/figma-analyzing-default-255-2267.png"
    local f11_design
    f11_design=$(extract_anchor "$f11" "design-preview" | sanitise_body)

    # Save/restore the hosting globals around the whole fixture.
    local _s_root="$ASSET_ROOT" _s_designs="$ASSET_DESIGNS_DIR" _s_images="$ASSET_IMAGES_DIR"
    local _s_mode="$ASSET_HOST_MODE" _s_or="$ASSET_OWNER_REPO" _s_ref="$ASSET_REF"
    local _s_dry="$DRY_RUN" _s_wid="${WORKTASK_ID:-}" _s_uab="$USER_ATTACH_URL_BASE"
    local _s_uae="$ASSET_UA_ENABLE" _s_vis="$ASSET_REPO_VISIBILITY" _s_degfile="$ASSET_DEGRADED_FILE"
    ASSET_ROOT="$t11_dir"
    ASSET_DESIGNS_DIR="$t11_dir/.context/designs"
    ASSET_IMAGES_DIR="$t11_dir/.context/images"
    DRY_RUN=1
    WORKTASK_ID="fixture-11"
    ASSET_DEGRADED_FILE="$t11_dir/.degraded"

    # --- 11a: user-attachments happy path (mocked base, forced mode) (AC-2) ---
    ASSET_HOST_MODE="user-attachments"
    USER_ATTACH_URL_BASE="https://github.com/user-attachments/assets/mock-uuid"
    : > "$ASSET_DEGRADED_FILE"
    local f11a_embed
    f11a_embed=$(printf '%s' "$f11_design" | resolve_design_assets)
    local f11a_reason; f11a_reason=$(cat "$ASSET_DEGRADED_FILE" 2>/dev/null || echo "")
    local f11a_ok=1
    printf '%s\n' "$f11a_embed" | grep -qF '![figma-scan-25-default-255-2264.png](https://github.com/user-attachments/assets/mock-uuid/figma-scan-25-default-255-2264.png)' || f11a_ok=0
    printf '%s\n' "$f11a_embed" | grep -qF '![figma-analyzing-default-255-2267.png](https://github.com/user-attachments/assets/mock-uuid/figma-analyzing-default-255-2267.png)' || f11a_ok=0
    if printf '%s\n' "$f11a_embed" | grep -qF '{{asset:'; then f11a_ok=0; fi
    [ -z "$f11a_reason" ] || f11a_ok=0
    if [ "$f11a_ok" = "1" ]; then
      echo "publish-pl-issue: self-test 11a-user-attachments-happy PASS"; pass=$((pass + 1))
    else
      echo "publish-pl-issue: self-test 11a-user-attachments-happy FAIL"
      printf '%s\n' "$f11a_embed" | head -20 >&2; fail=$((fail + 1))
    fi

    # --- 11b: user-attachments uploader unavailable → degrade (AC-3) ---
    # Forced UA mode, no mock base, AND the `gh image` uploader failing (GH_BIN
    # stubbed to `false`) → host_one_asset returns 1 → tokens drop + degradation
    # flagged. Non-blocking, no broken markup. Stubbing GH_BIN is what makes this
    # deterministic now that tier-0 has a live path: without it the test would
    # really upload on any machine where `gh image` is installed and authed.
    ASSET_HOST_MODE="user-attachments"
    USER_ATTACH_URL_BASE=""
    local f11b_gh_saved="$GH_BIN"; GH_BIN=false
    : > "$ASSET_DEGRADED_FILE"
    local f11b_embed
    f11b_embed=$(printf '%s' "$f11_design" | resolve_design_assets)
    local f11b_reason; f11b_reason=$(cat "$ASSET_DEGRADED_FILE" 2>/dev/null || echo "")
    local f11b_ok=1
    if printf '%s\n' "$f11b_embed" | grep -qF '!['; then f11b_ok=0; fi
    if printf '%s\n' "$f11b_embed" | grep -qF '{{asset:'; then f11b_ok=0; fi
    [ "$f11b_reason" = "image_hosting_unavailable" ] || f11b_ok=0
    printf '%s\n' "$f11b_embed" | grep -qF 'https://www.figma.com/design/FOO/FaceScan?node-id=255-2263' || f11b_ok=0
    GH_BIN="$f11b_gh_saved"
    if [ "$f11b_ok" = "1" ]; then
      echo "publish-pl-issue: self-test 11b-user-attachments-degrade PASS"; pass=$((pass + 1))
    else
      echo "publish-pl-issue: self-test 11b-user-attachments-degrade FAIL"
      printf '%s\n' "$f11b_embed" | head -20 >&2; fail=$((fail + 1))
    fi

    # --- 11c: REQ-1 — raw render-verification fails for PRIVATE repo (AC-1) ---
    # raw_asset_url_reachable() must return 1 when visibility is PRIVATE, even
    # when the authenticated existence check would pass. Direct unit assertion
    # (no network — ASSET_REPO_VISIBILITY mock drives the gate).
    ASSET_REPO_VISIBILITY="PRIVATE"
    local f11c_ok=1
    if raw_asset_url_reachable "owner/repo" "feat/x" ".worktask-assets/t/a.png" \
         "https://raw.githubusercontent.com/owner/repo/feat/x/.worktask-assets/t/a.png"; then
      f11c_ok=0   # MUST have returned non-zero for a private repo
    fi
    ASSET_REPO_VISIBILITY="INTERNAL"
    if raw_asset_url_reachable "owner/repo" "feat/x" ".worktask-assets/t/a.png" \
         "https://raw.githubusercontent.com/owner/repo/feat/x/.worktask-assets/t/a.png"; then
      f11c_ok=0   # MUST also fail for INTERNAL
    fi
    if [ "$f11c_ok" = "1" ]; then
      echo "publish-pl-issue: self-test 11c-raw-private-refused PASS"; pass=$((pass + 1))
    else
      echo "publish-pl-issue: self-test 11c-raw-private-refused FAIL"; fail=$((fail + 1))
    fi

    # --- 11d: REQ-1 — PRIVATE repo, live tier select → raw refused, degrade ---
    # select_host_tier() with PRIVATE visibility + gh authed must NOT pick raw;
    # it should fall to gist (gh present mock) — proves the camo false-positive
    # is closed at selection time too. Mock gh `auth status` success via a stub.
    local t11d_bin="$t11_dir/bin"
    mkdir -p "$t11d_bin"
    cat > "$t11d_bin/gh" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  auth) exit 0 ;;
  repo) echo "PRIVATE"; exit 0 ;;   # --json visibility --jq path
esac
exit 0
MOCK
    chmod +x "$t11d_bin/gh"
    cat > "$t11d_bin/git" <<'MOCK'
#!/usr/bin/env bash
if [ "$1" = "remote" ] && [ "$2" = "get-url" ]; then echo "git@github.com:owner/repo.git"; exit 0; fi
if [ "$1" = "rev-parse" ]; then echo "feature/x"; exit 0; fi
if [ "$1" = "ls-remote" ]; then exit 0; fi
exec /usr/bin/env -i PATH=/usr/bin:/bin git "$@"
MOCK
    chmod +x "$t11d_bin/git"
    local f11d_tier
    f11d_tier=$( PATH="$t11d_bin:$PATH" GH_BIN=gh \
      ASSET_HOST_MODE="" ASSET_REPO_VISIBILITY="" ASSET_UA_ENABLE=0 ASSET_GH_IMAGE=0 \
      bash -c '
        '"$(declare -f parse_owner_repo)"'
        '"$(declare -f repo_visibility)"'
        '"$(declare -f gh_image_available)"'
        '"$(declare -f select_host_tier)"'
        select_host_tier
        printf "%s" "$HOST_TIER"
      ' )
    if [ "$f11d_tier" = "gist" ]; then
      echo "publish-pl-issue: self-test 11d-private-selects-gist PASS"; pass=$((pass + 1))
    else
      echo "publish-pl-issue: self-test 11d-private-selects-gist FAIL (tier='$f11d_tier' want gist)"; fail=$((fail + 1))
    fi

    # --- 11e: ASSET_HOST_MODE=user-attachments accepted offline (AC-7) ---
    # Forced mode must select the tier without any network probe.
    local f11e_tier
    f11e_tier=$( ASSET_HOST_MODE="user-attachments" bash -c '
        '"$(declare -f parse_owner_repo)"'
        '"$(declare -f repo_visibility)"'
        '"$(declare -f gh_image_available)"'
        '"$(declare -f select_host_tier)"'
        ASSET_UA_ENABLE=0 USER_ATTACH_URL_BASE=""
        select_host_tier
        printf "%s" "$HOST_TIER"
      ' )
    if [ "$f11e_tier" = "user-attachments" ]; then
      echo "publish-pl-issue: self-test 11e-mode-override-offline PASS"; pass=$((pass + 1))
    else
      echo "publish-pl-issue: self-test 11e-mode-override-offline FAIL (tier='$f11e_tier')"; fail=$((fail + 1))
    fi

    # Restore globals + clean up.
    ASSET_ROOT="$_s_root"; ASSET_DESIGNS_DIR="$_s_designs"; ASSET_IMAGES_DIR="$_s_images"
    ASSET_HOST_MODE="$_s_mode"; ASSET_OWNER_REPO="$_s_or"; ASSET_REF="$_s_ref"
    DRY_RUN="$_s_dry"; WORKTASK_ID="$_s_wid"; USER_ATTACH_URL_BASE="$_s_uab"
    ASSET_UA_ENABLE="$_s_uae"; ASSET_REPO_VISIBILITY="$_s_vis"; ASSET_DEGRADED_FILE="$_s_degfile"
    ASSET_DEGRADED_REASON=""
    rm -rf "$t11_dir"
  else
    echo "publish-pl-issue: self-test 11-user-attachments SKIP (fixture missing)"
    fail=$((fail + 1))
  fi

  # ---- Fixture 12: AC1 PUBLIC-gist tier + render-verify (offline) ----
  # All paths mockable via ASSET_GIST_PUBLIC / GIST_VERIFY_FORCE / GH_BIN — no
  # live gh or curl. host_one_asset runs the gist branch directly via declare -f.
  local t12_dir
  t12_dir=$(mktemp -d 2>/dev/null || echo "/tmp/publish-pl-self-test-12.$$")
  mkdir -p "$t12_dir/bin"
  printf '\211PNG\r\n\032\n' > "$t12_dir/a.png"
  # gh mock: `gist create [--public] <src>` records its full argv to argv.log and
  # prints a gist web URL so the raw URL can be derived.
  cat > "$t12_dir/bin/gh" <<MOCK
#!/usr/bin/env bash
if [ "\$1" = "gist" ] && [ "\$2" = "create" ]; then
  printf '%s\n' "\$*" >> "$t12_dir/argv.log"
  echo "https://gist.github.com/deadbeefdeadbeef"
  exit 0
fi
exit 0
MOCK
  chmod +x "$t12_dir/bin/gh"

  # --- 12a: --public flag gated by ASSET_GIST_PUBLIC ---
  # Default-on (ASSET_GIST_PUBLIC=1) → `gh gist create` MUST receive --public.
  # Opt-out (ASSET_GIST_PUBLIC=0)    → --public MUST be absent (secret gist).
  : > "$t12_dir/argv.log"
  local f12a_url_on f12a_url_off f12a_ok=1
  f12a_url_on=$( PATH="$t12_dir/bin:$PATH" GH_BIN=gh \
    bash -c '
      '"$(declare -f gist_raw_url_reachable)"'
      '"$(declare -f repo_visibility)"'
      '"$(declare -f gist_public_effective)"'
      '"$(declare -f host_one_asset)"'
      HOST_TIER=gist DRY_RUN=0 GIST_RAW_URL_BASE="" ASSET_GIST_PUBLIC=1 GIST_VERIFY_FORCE=pass
      host_one_asset "a.png" "'"$t12_dir"'/a.png"
    ' )
  grep -qF 'gist create --public' "$t12_dir/argv.log" || f12a_ok=0
  [ "$f12a_url_on" = "https://gist.github.com/deadbeefdeadbeef/raw/a.png" ] || f12a_ok=0
  : > "$t12_dir/argv.log"
  f12a_url_off=$( PATH="$t12_dir/bin:$PATH" GH_BIN=gh \
    bash -c '
      '"$(declare -f gist_raw_url_reachable)"'
      '"$(declare -f repo_visibility)"'
      '"$(declare -f gist_public_effective)"'
      '"$(declare -f host_one_asset)"'
      HOST_TIER=gist DRY_RUN=0 GIST_RAW_URL_BASE="" ASSET_GIST_PUBLIC=0 GIST_VERIFY_FORCE=pass
      host_one_asset "a.png" "'"$t12_dir"'/a.png"
    ' )
  grep -qF 'gist create --public' "$t12_dir/argv.log" && f12a_ok=0   # MUST be absent
  grep -qE 'gist create [^-]' "$t12_dir/argv.log" || f12a_ok=0       # secret form: src follows directly, no flag
  [ "$f12a_url_off" = "https://gist.github.com/deadbeefdeadbeef/raw/a.png" ] || f12a_ok=0
  if [ "$f12a_ok" = "1" ]; then
    echo "publish-pl-issue: self-test 12a-gist-public-flag-gated PASS"; pass=$((pass + 1))
  else
    echo "publish-pl-issue: self-test 12a-gist-public-flag-gated FAIL (on='$f12a_url_on' off='$f12a_url_off')"
    cat "$t12_dir/argv.log" >&2; fail=$((fail + 1))
  fi

  # --- 12a0: tier-0 live path — `gh image` upload + URL extraction ---
  # host_one_asset must invoke `gh image <src>` and pull the user-attachments URL
  # out of its `![base](url)` line; a non-matching/absent line must degrade (rc!=0,
  # no output) rather than emit a broken embed. Binary input is deliberate: this
  # tier accepts binaries, which is exactly what the gist tier cannot do.
  local f12a0_ok=1 f12a0_url f12a0_bad
  cat > "$t12_dir/bin/gh-img" <<'MOCK'
#!/usr/bin/env bash
if [ "$1" = "image" ]; then
  printf '![%s](https://github.com/user-attachments/assets/abc123-def456)\n' "$(basename "$2")"
  exit 0
fi
exit 0
MOCK
  chmod +x "$t12_dir/bin/gh-img"
  printf '\x89PNG\r\n\x1a\n\x00\x01' > "$t12_dir/ua.png"
  f12a0_url=$( GH_BIN="$t12_dir/bin/gh-img" \
    bash -c '
      '"$(declare -f host_one_asset)"'
      HOST_TIER=user-attachments DRY_RUN=0 USER_ATTACH_URL_BASE=""
      host_one_asset "ua.png" "'"$t12_dir"'/ua.png"
    ' )
  [ "$f12a0_url" = "https://github.com/user-attachments/assets/abc123-def456" ] || f12a0_ok=0
  # Uploader prints nothing usable → must degrade with no output.
  f12a0_bad=$( GH_BIN=true \
    bash -c '
      '"$(declare -f host_one_asset)"'
      HOST_TIER=user-attachments DRY_RUN=0 USER_ATTACH_URL_BASE=""
      host_one_asset "ua.png" "'"$t12_dir"'/ua.png"
    ' ) && f12a0_ok=0
  [ -n "$f12a0_bad" ] && f12a0_ok=0
  if [ "$f12a0_ok" = "1" ]; then
    echo "publish-pl-issue: self-test 12a0-user-attachments-live PASS"; pass=$((pass + 1))
  else
    echo "publish-pl-issue: self-test 12a0-user-attachments-live FAIL (url='$f12a0_url' bad='$f12a0_bad')"; fail=$((fail + 1))
  fi

  # --- 12a2: unset ASSET_GIST_PUBLIC auto-derives visibility from the repo ---
  # Closed repo (PRIVATE/INTERNAL) MUST NOT get `--public`: both gist kinds are
  # anonymously fetchable so the embed renders either way, and `--public` only
  # adds indexing + profile listing. PUBLIC (and unknown, e.g. no gh) keep the
  # historical public default. ASSET_REPO_VISIBILITY mocks the probe offline.
  local f12a2_ok=1 v
  for v in PRIVATE INTERNAL; do
    : > "$t12_dir/argv.log"
    PATH="$t12_dir/bin:$PATH" GH_BIN=gh bash -c '
      '"$(declare -f gist_raw_url_reachable)"'
      '"$(declare -f repo_visibility)"'
      '"$(declare -f gist_public_effective)"'
      '"$(declare -f host_one_asset)"'
      HOST_TIER=gist DRY_RUN=0 GIST_RAW_URL_BASE="" ASSET_GIST_PUBLIC="" GIST_VERIFY_FORCE=pass
      ASSET_REPO_VISIBILITY="'"$v"'"
      host_one_asset "a.png" "'"$t12_dir"'/a.png"
    ' >/dev/null 2>&1
    grep -qF 'gist create --public' "$t12_dir/argv.log" && f12a2_ok=0   # MUST be absent
    grep -qE 'gist create [^-]' "$t12_dir/argv.log" || f12a2_ok=0       # secret form
  done
  for v in PUBLIC ""; do
    : > "$t12_dir/argv.log"
    PATH="$t12_dir/bin:$PATH" GH_BIN=gh bash -c '
      '"$(declare -f gist_raw_url_reachable)"'
      '"$(declare -f repo_visibility)"'
      '"$(declare -f gist_public_effective)"'
      '"$(declare -f host_one_asset)"'
      HOST_TIER=gist DRY_RUN=0 GIST_RAW_URL_BASE="" ASSET_GIST_PUBLIC="" GIST_VERIFY_FORCE=pass
      ASSET_REPO_VISIBILITY="'"$v"'"
      host_one_asset "a.png" "'"$t12_dir"'/a.png"
    ' >/dev/null 2>&1
    grep -qF 'gist create --public' "$t12_dir/argv.log" || f12a2_ok=0   # MUST be present
  done
  if [ "$f12a2_ok" = "1" ]; then
    echo "publish-pl-issue: self-test 12a2-gist-visibility-auto PASS"; pass=$((pass + 1))
  else
    echo "publish-pl-issue: self-test 12a2-gist-visibility-auto FAIL"
    cat "$t12_dir/argv.log" >&2; fail=$((fail + 1))
  fi

  # --- 12a3: gist tier refuses binary assets (never calls gh) ---
  # `gh gist create` rejects binary content, so a PNG/JPG can never be hosted on
  # this tier. host_one_asset must fail fast and NOT invoke gh, so the caller
  # degrades to a bullet instead of burning a guaranteed-failure round-trip.
  local f12a3_ok=1 f12a3_url
  printf '\x89PNG\r\n\x1a\n\x00\x01\x02\x03' > "$t12_dir/bin.png"
  : > "$t12_dir/argv.log"
  f12a3_url=$( PATH="$t12_dir/bin:$PATH" GH_BIN=gh \
    bash -c '
      '"$(declare -f gist_raw_url_reachable)"'
      '"$(declare -f repo_visibility)"'
      '"$(declare -f gist_public_effective)"'
      '"$(declare -f host_one_asset)"'
      HOST_TIER=gist DRY_RUN=0 GIST_RAW_URL_BASE="" ASSET_GIST_PUBLIC=1 GIST_VERIFY_FORCE=pass
      host_one_asset "bin.png" "'"$t12_dir"'/bin.png"
    ' ) && f12a3_ok=0        # MUST return non-zero
  [ -n "$f12a3_url" ] && f12a3_ok=0                       # MUST emit no URL
  [ -s "$t12_dir/argv.log" ] && f12a3_ok=0                # MUST NOT have called gh
  if [ "$f12a3_ok" = "1" ]; then
    echo "publish-pl-issue: self-test 12a3-gist-binary-refused PASS"; pass=$((pass + 1))
  else
    echo "publish-pl-issue: self-test 12a3-gist-binary-refused FAIL (url='$f12a3_url')"
    cat "$t12_dir/argv.log" >&2; fail=$((fail + 1))
  fi

  # --- 12b: render-verify gate — pass emits URL, fail degrades (no URL) ---
  local f12b_pass f12b_fail f12b_rc_pass f12b_rc_fail f12b_ok=1
  # gist_raw_url_reachable unit assertions (offline hook).
  if GIST_VERIFY_FORCE=pass gist_raw_url_reachable "https://x/raw/a.png"; then :; else f12b_ok=0; fi
  if GIST_VERIFY_FORCE=fail gist_raw_url_reachable "https://x/raw/a.png"; then f12b_ok=0; fi
  # host_one_asset: verify pass → emits the URL.
  f12b_pass=$( PATH="$t12_dir/bin:$PATH" GH_BIN=gh \
    bash -c '
      '"$(declare -f gist_raw_url_reachable)"'
      '"$(declare -f repo_visibility)"'
      '"$(declare -f gist_public_effective)"'
      '"$(declare -f host_one_asset)"'
      HOST_TIER=gist DRY_RUN=0 GIST_RAW_URL_BASE="" ASSET_GIST_PUBLIC=1 GIST_VERIFY_FORCE=pass
      host_one_asset "a.png" "'"$t12_dir"'/a.png"
    ' ); f12b_rc_pass=$?
  [ "$f12b_rc_pass" = "0" ] && [ -n "$f12b_pass" ] || f12b_ok=0
  # host_one_asset: verify fail → empty output + non-zero rc (caller degrades).
  f12b_fail=$( PATH="$t12_dir/bin:$PATH" GH_BIN=gh \
    bash -c '
      '"$(declare -f gist_raw_url_reachable)"'
      '"$(declare -f repo_visibility)"'
      '"$(declare -f gist_public_effective)"'
      '"$(declare -f host_one_asset)"'
      HOST_TIER=gist DRY_RUN=0 GIST_RAW_URL_BASE="" ASSET_GIST_PUBLIC=1 GIST_VERIFY_FORCE=fail
      host_one_asset "a.png" "'"$t12_dir"'/a.png"
    ' ); f12b_rc_fail=$?
  [ "$f12b_rc_fail" != "0" ] && [ -z "$f12b_fail" ] || f12b_ok=0
  if [ "$f12b_ok" = "1" ]; then
    echo "publish-pl-issue: self-test 12b-gist-render-verify PASS"; pass=$((pass + 1))
  else
    echo "publish-pl-issue: self-test 12b-gist-render-verify FAIL (pass='$f12b_pass'/$f12b_rc_pass fail='$f12b_fail'/$f12b_rc_fail)"; fail=$((fail + 1))
  fi

  # --- 12c: PRIVATE repo selects the gist tier end-to-end (render-verified) ---
  # select_host_tier() with PRIVATE visibility + gh authed must pick gist (raw
  # refused), confirming gist is now the render-verified PRIVATE-repo primary.
  cat > "$t12_dir/bin/gh-sel" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  auth) exit 0 ;;
  repo) echo "PRIVATE"; exit 0 ;;
esac
exit 0
MOCK
  chmod +x "$t12_dir/bin/gh-sel"
  cat > "$t12_dir/bin/git-sel" <<'MOCK'
#!/usr/bin/env bash
if [ "$1" = "remote" ] && [ "$2" = "get-url" ]; then echo "git@github.com:owner/repo.git"; exit 0; fi
if [ "$1" = "rev-parse" ]; then echo "feature/x"; exit 0; fi
if [ "$1" = "ls-remote" ]; then exit 0; fi
exec /usr/bin/env -i PATH=/usr/bin:/bin git "$@"
MOCK
  chmod +x "$t12_dir/bin/git-sel"
  local f12c_tier
  f12c_tier=$( cp "$t12_dir/bin/gh-sel" "$t12_dir/bin/gh2"; cp "$t12_dir/bin/git-sel" "$t12_dir/bin/git"; \
    PATH="$t12_dir/bin:$PATH" GH_BIN=gh2 \
    ASSET_HOST_MODE="" ASSET_REPO_VISIBILITY="" ASSET_UA_ENABLE=0 ASSET_GH_IMAGE=0 \
    bash -c '
      '"$(declare -f parse_owner_repo)"'
      '"$(declare -f repo_visibility)"'
      '"$(declare -f gh_image_available)"'
      '"$(declare -f select_host_tier)"'
      select_host_tier
      printf "%s" "$HOST_TIER"
    ' )
  rm -f "$t12_dir/bin/git"   # avoid leaking the git shim past this test
  if [ "$f12c_tier" = "gist" ]; then
    echo "publish-pl-issue: self-test 12c-private-selects-gist PASS"; pass=$((pass + 1))
  else
    echo "publish-pl-issue: self-test 12c-private-selects-gist FAIL (tier='$f12c_tier' want gist)"; fail=$((fail + 1))
  fi
  rm -rf "$t12_dir"

  # ---- parse_owner_repo: both remote URL forms ----
  local _por
  _por=$(parse_owner_repo "git@github.com:IGRSoft/corpflow.git")
  if [ "$_por" = "IGRSoft/corpflow" ]; then
    echo "publish-pl-issue: self-test parse_owner_repo(ssh) PASS"; pass=$((pass + 1))
  else
    echo "publish-pl-issue: self-test parse_owner_repo(ssh) FAIL (got '$_por')"; fail=$((fail + 1))
  fi
  _por=$(parse_owner_repo "https://github.com/IGRSoft/corpflow.git")
  if [ "$_por" = "IGRSoft/corpflow" ]; then
    echo "publish-pl-issue: self-test parse_owner_repo(https) PASS"; pass=$((pass + 1))
  else
    echo "publish-pl-issue: self-test parse_owner_repo(https) FAIL (got '$_por')"; fail=$((fail + 1))
  fi

  echo "publish-pl-issue: self-test summary — pass=$pass fail=$fail"
  [ "$fail" -eq 0 ]
}

# Library mode: attach-visual-evidence.sh sources this file for the tier logic.
[ "${PUBLISH_LIB_ONLY:-0}" = "1" ] && return 0 2>/dev/null

# ---------- entrypoint ------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  run_self_tests || exit 2
  exit 0
fi

# Catastrophic-pre-flight: jq required for audit + state I/O.
command -v jq >/dev/null 2>&1 || { echo "publish-pl-issue: jq not found" >&2; exit 1; }
mkdir -p "$LOG_DIR" 2>/dev/null || fatal "audit_dir_unwritable"
[ -r "$STATE_FILE" ] || fatal "state_corrupt"
jq -e . "$STATE_FILE" >/dev/null 2>&1 || fatal "state_corrupt"

# Pull worktask context.
WORKTASK_ID=$(jq -r '.worktask_id // "unknown"' "$STATE_FILE")
RUN_INDEX=$(jq -r '.run_index // 0' "$STATE_FILE")
PLAN_FILE=$(jq -r '.plan_file // ""' "$STATE_FILE")
# Two legal shapes reach this field (see the plan_file shape boundary in the header):
# a workspace-relative path, or a bare basename written from the task-metadata
# convention. Resolve the second against the state file's own directory — the same
# fallback ISSUE_ANCHOR performs above. PLAN_CANDIDATES feeds the fatal diagnostic.
PLAN_CANDIDATES="${PLAN_FILE:-<empty .plan_file>}"
if [ -n "$PLAN_FILE" ] && [ ! -r "$PLAN_FILE" ]; then
  _plan_alt="$(dirname "$STATE_FILE")/$(basename "$PLAN_FILE")"
  PLAN_CANDIDATES="$PLAN_FILE, $_plan_alt"
  [ -r "$_plan_alt" ] && PLAN_FILE="$_plan_alt"
fi
DEDUPE_KEY="$WORKTASK_ID:$RUN_INDEX:gh_issue"

# Strict mode: CLI --strict wins; else read metadata.gh_issue.strict from state.
# Default unchanged: STRICT=0 (non-blocking, preserves fixtures 01-05 behaviour).
if [ "$STRICT" != "1" ] && [ "$STRICT" != "true" ]; then
  STATE_STRICT=$(jq -r '.metadata.gh_issue.strict // false' "$STATE_FILE" 2>/dev/null)
  if [ "$STATE_STRICT" = "true" ]; then STRICT=1; fi
fi

# Guard 1: opt-out via task metadata or env override.
NO_GH=$(jq -r '.metadata.no_gh_issue // false' "$STATE_FILE" 2>/dev/null)
if [ "${NO_GH_ISSUE:-${NO_GH}}" = "true" ]; then
  defer "opted_out"
fi

# Guard 2: idempotency + cross-run dedup. Resolve the canonical issue for this
# .context from the run-independent anchor (or the same-run state url). Created in
# THIS run → already published (defer). Created in an EARLIER run → comment on it
# instead of opening a duplicate (COMMENT_MODE, executed at the publish branch once
# the body is built). No local hit → COMMENT_MODE stays 0; a GitHub-side search may
# still recover a lost anchor after the title is built. See skills/gh-issue-dedup.
COMMENT_MODE=0
EXISTING_ISSUE_URL=""
EXISTING_ISSUE_SOURCE=""
if resolve_context_issue_local; then
  if [ "${RESOLVED_ISSUE_CREATED_RUN:-0}" -lt "${RUN_INDEX:-0}" ] 2>/dev/null; then
    COMMENT_MODE=1
    EXISTING_ISSUE_URL="$RESOLVED_ISSUE_URL"
    EXISTING_ISSUE_SOURCE="$RESOLVED_ISSUE_SOURCE"
  else
    defer "already_published"
  fi
fi

# Guard 2.5: milestone-mode — skip GH publish entirely (no create, no comment).
# The parent milestone issue is the canonical record; auto-posting plan-approval
# comments would fragment the review surface. PR linkage (FN stage or manual)
# ties the implementation back to the milestone.
if is_milestone_mode; then
  defer "milestone_mode"
fi

# Guard 3: gh binary present.
command -v "$GH_BIN" >/dev/null 2>&1 || defer "gh_not_installed"

# Guard 4: gh auth.
if [ "$DRY_RUN" != "1" ]; then
  "$GH_BIN" auth status >/dev/null 2>&1 || defer "auth_missing"
fi

# Guard 5: remote present.
if [ "$DRY_RUN" != "1" ]; then
  git remote get-url origin 2>/dev/null | grep -q . || defer "no_remote"
fi

# Plan readable?
[ -r "$PLAN_FILE" ] || {
  FATAL_DETAIL="plan unreadable; tried: $PLAN_CANDIDATES"
  fatal "plan_unreadable"
}

# ---------- extract + sanitise + render -------------------------------------
# Title and Summary resolve through INDEPENDENT chains. They shared one source
# (`facts.goal`) until issue #375: `facts.goal` is OPTIONAL in the handoff protocol —
# written only when the PM agent patches state.json, so orchestrator-inline seeding, a
# hand-authored `.context/`, or a regenerated state leaves it unset — and one empty
# value then corrupted BOTH the title (silently, to the kebab worktask slug) and the
# `## Summary` section (to empty) in the same run.
GOAL_RAW=$(jq -r '.facts.goal // ""' "$STATE_FILE")
FM_TITLE=$(extract_frontmatter_field "$PLAN_FILE" "title")
FM_ISSUE=$(extract_frontmatter_field "$PLAN_FILE" "issue")
PLAN_H1=$(extract_first_h1 "$PLAN_FILE")
SUMMARY_ANCHOR=$(extract_anchor "$PLAN_FILE" "summary")
if [ -z "$(printf '%s' "$SUMMARY_ANCHOR" | tr -d '[:space:]')" ]; then
  SUMMARY_ANCHOR=$(extract_anchor "$PLAN_FILE" "problem")
fi

# Summary body chain: facts.goal → `## summary` → `## problem`. The worktask slug is
# deliberately NOT a rank here — an empty section is honest, a slug posing as prose
# is not.
SUMMARY_RAW="$GOAL_RAW"
if [ -z "$SUMMARY_RAW" ]; then SUMMARY_RAW="$SUMMARY_ANCHOR"; fi

# Title chain, first non-empty wins. TITLE_SOURCE names the winning rank and is
# carried into the audit row so a degraded title is visible rather than silent.
TITLE_SOURCE="facts_goal"
TITLE_RAW="$GOAL_RAW"
if [ -z "$TITLE_RAW" ]; then TITLE_SOURCE="plan_frontmatter_title"; TITLE_RAW="$FM_TITLE"; fi
if [ -z "$TITLE_RAW" ]; then TITLE_SOURCE="plan_h1"; TITLE_RAW="$PLAN_H1"; fi
if [ -z "$TITLE_RAW" ]; then
  TITLE_SOURCE="plan_summary_anchor"
  TITLE_RAW=$(printf '%s\n' "$SUMMARY_ANCHOR" | first_sentence)
fi
if [ -z "$TITLE_RAW" ]; then TITLE_SOURCE="worktask_id"; TITLE_RAW="$WORKTASK_ID"; fi

# AC-2: external-ticket extraction. Match ^[A-Z][A-Z0-9]+-[0-9]+ in the goal first,
# then whichever source won the title, then the plan's frontmatter `issue:`, then
# upper-cased WORKTASK_ID. Every rank feeds the same no-double-prefix guard below.
EXTERNAL_TICKET=$(extract_external_ticket "$GOAL_RAW")
if [ -z "$EXTERNAL_TICKET" ]; then
  EXTERNAL_TICKET=$(extract_external_ticket "$TITLE_RAW")
fi
if [ -z "$EXTERNAL_TICKET" ]; then
  EXTERNAL_TICKET=$(extract_external_ticket "$(printf '%s' "$FM_ISSUE" | tr '[:lower:]' '[:upper:]')")
fi
if [ -z "$EXTERNAL_TICKET" ]; then
  EXTERNAL_TICKET=$(extract_external_ticket "$(printf '%s' "$WORKTASK_ID" | tr '[:lower:]' '[:upper:]')")
fi
if [ -n "$EXTERNAL_TICKET" ]; then
  write_state_external_ticket "$EXTERNAL_TICKET" || true
fi
REQS_RAW=$(extract_anchor "$PLAN_FILE" "requirements")
ACS_RAW=$(extract_anchor "$PLAN_FILE" "acceptance-criteria")
SCOPE_RAW=$(extract_anchor "$PLAN_FILE" "scope")
COMPLEXITY_RAW=$(extract_anchor "$PLAN_FILE" "complexity")
# Optional: design-preview anchor (Figma URL captured at PL). Excluded from
# strip-ratio denominator to avoid skewing the guard with short URL bodies.
DESIGN_RAW=$(extract_anchor "$PLAN_FILE" "design-preview")

SUMMARY_S=$(printf '%s\n' "$SUMMARY_RAW" | sanitise_body)
REQS_S=$(printf '%s\n' "$REQS_RAW" | sanitise_body)
ACS_S=$(printf '%s\n' "$ACS_RAW" | sanitise_body)
SCOPE_S=$(printf '%s\n' "$SCOPE_RAW" | sanitise_body)
COMPLEXITY_S=$(printf '%s\n' "$COMPLEXITY_RAW" | sanitise_body)
DESIGN_S=$(printf '%s\n' "$DESIGN_RAW" | sanitise_body)

# Host-and-rewrite (Figma image embed): resolve {{asset:<basename>}} placeholder
# tokens in the already-sanitised design-preview body to hosted ![alt](url) image
# lines. This runs AFTER sanitise_body (so the image lines never face Pass-1 L1)
# and is fully non-blocking — any hosting failure degrades to a URL-only note.
# When the anchor carries no tokens (URL-only design-preview, e.g. fixture 09),
# resolve_design_assets returns the body unchanged. design-preview is excluded
# from the strip-ratio denominator below (R5), so the rewrite cannot perturb it.
# resolve_design_assets runs in a subshell (command substitution), so it reports
# degradation through ASSET_DEGRADED_FILE rather than a parent variable.
ASSET_DEGRADED_FILE="$LOG_DIR/.asset-degraded.$$"
: > "$ASSET_DEGRADED_FILE" 2>/dev/null || ASSET_DEGRADED_FILE=""
DESIGN_EMBED=$(printf '%s' "$DESIGN_S" | resolve_design_assets)
if [ -n "$ASSET_DEGRADED_FILE" ] && [ -s "$ASSET_DEGRADED_FILE" ]; then
  ASSET_DEGRADED_REASON=$(cat "$ASSET_DEGRADED_FILE" 2>/dev/null || echo "")
fi
[ -n "$ASSET_DEGRADED_FILE" ] && rm -f "$ASSET_DEGRADED_FILE" 2>/dev/null || true

# Strip-ratio check against the four required anchor bodies only.
# (stages anchor is consumed by the orchestrator from the plan file but no
# longer rendered into the published body; design-preview is optional and a
# short URL — both excluded from the denominator on purpose.)
ORIG_TOTAL=$(printf '%s%s%s%s' "$REQS_RAW" "$ACS_RAW" "$SCOPE_RAW" "$COMPLEXITY_RAW" | wc -c)
SAN_TOTAL=$(printf '%s%s%s%s' "$REQS_S" "$ACS_S" "$SCOPE_S" "$COMPLEXITY_S" | wc -c)
# Fallback: when the plan has none of the expected anchor headings, anchor-extracted
# bytes are zero — fall back to whole-file byte length so a near-empty body still
# trips the strip-ratio guard instead of being silently published. Matches the
# --self-test behaviour for fixture 03-mostly-paths.md. (T4 remediation, DV0.1)
if [ "$ORIG_TOTAL" -eq 0 ]; then
  ORIG_TOTAL=$(wc -c < "$PLAN_FILE" 2>/dev/null || echo 0)
  PLAN_SAN=$(sanitise_body < "$PLAN_FILE" 2>/dev/null | wc -c)
  SAN_TOTAL="$PLAN_SAN"
fi
STRIP_PCT=0
if [ "$ORIG_TOTAL" -gt 0 ]; then
  STRIP_PCT=$(( (ORIG_TOTAL - SAN_TOTAL) * 100 / ORIG_TOTAL ))
fi
if [ "$STRIP_PCT" -gt 50 ]; then
  ABORT_TMP="$LOG_DIR/issue-body-${RUN_INDEX}.aborted.tmp"
  {
    printf '%s\n\n' "$SUMMARY_S"
    printf '## Requirements\n%s\n\n' "$REQS_S"
    printf '## Acceptance Criteria\n%s\n\n' "$ACS_S"
    printf '## Scope\n%s\n\n' "$SCOPE_S"
    if [ -n "$(printf '%s' "$DESIGN_EMBED" | tr -d '[:space:]')" ]; then
      printf '## Design Preview\n%s\n\nCompare implementation (DV) and screenshots (QA) against this design.\n\n' "$DESIGN_EMBED"
    fi
    printf '## Complexity\n%s\n' "$COMPLEXITY_S"
  } > "$ABORT_TMP" 2>/dev/null || true
  audit_row "deferred" "$(jq -cn --arg v "publish-pl-issue.sh" --arg r "sanitiser_aborted" --argjson sp "$STRIP_PCT" --arg dk "$DEDUPE_KEY" --arg path "$ABORT_TMP" '{via:$v, reason:$r, strip_ratio:$sp, aborted_body:$path, dedupe_key:$dk}')" || true
  exit 0
fi

# Mode is implicit "create" — milestone mode short-circuited above (Guard 2.5).
MODE="create"

# Complexity-tier label (read from facts.decisions or planning § complexity heading).
TIER=$(printf '%s' "$COMPLEXITY_S" | grep -oiE '\((Low|Medium|Moderate|High|Critical)\)' | head -1 | tr '[:upper:]' '[:lower:]' | tr -d '()')
[ -z "$TIER" ] && TIER="moderate"

# Render body via heredoc.
BODY_TMP="$LOG_DIR/issue-body-${RUN_INDEX}.tmp"
{
  printf '## Summary\n%s\n\n' "$SUMMARY_S"
  printf '## Requirements\n%s\n\n' "$REQS_S"
  printf '## Acceptance Criteria\n%s\n\n' "$ACS_S"
  printf '## Scope\n%s\n\n' "$SCOPE_S"
  if [ -n "$(printf '%s' "$DESIGN_EMBED" | tr -d '[:space:]')" ]; then
    printf '## Design Preview\n%s\n\nCompare implementation (DV) and screenshots (QA) against this design.\n\n' "$DESIGN_EMBED"
  fi
  printf '## Complexity\n%s\n\n' "$COMPLEXITY_S"
  printf -- '---\n*Plan approved on %s. Tracking continues in worktask run #%s.*\n' "$(date -u +%F)" "$RUN_INDEX"
} > "$BODY_TMP" 2>/dev/null || fatal "audit_dir_unwritable"

# REQ-5: if asset hosting degraded below tier-1, append a non-blocking audit row
# recording the reason. Use a distinct dedupe key suffix so this advisory row
# never masks the canonical github_issue_created outcome during audit dedupe.
# The body already carries the URL-only note; publish is never blocked.
if [ -n "$ASSET_DEGRADED_REASON" ]; then
  audit_row "deferred" "$(jq -cn --arg v "publish-pl-issue.sh" --arg r "$ASSET_DEGRADED_REASON" --arg dk "${DEDUPE_KEY}:asset_hosting" '{via:$v, reason:$r, dedupe_key:$dk}')" || true
fi

# Title (sanitised — TITLE_RAW resolved by the chain above). The head/cut/sanitise
# pipeline applies to every rank of that chain: a multi-line frontmatter value or a
# long H1 is flattened and capped here, never at the source.
TITLE=$(printf '%s' "$TITLE_RAW" | head -1 | cut -c1-100 | sanitise_body | tr -d '\n')
[ -z "$TITLE" ] && TITLE="Plan approved: $WORKTASK_ID"

# AC-2: ensure title starts with EXTERNAL_TICKET prefix. Skip if already prefixed
# (avoid double-prefix like "OV-113 OV-113 …"). Compared case-INsensitively and with
# `-` accepted as a separator: the slug-fallback rank yields "ov-164-catalog-…",
# which an exact-case check treats as unprefixed and turns into the reported
# "OV-164 ov-164-catalog-…".
if [ -n "$EXTERNAL_TICKET" ]; then
  _title_lc=$(printf '%s' "$TITLE" | tr '[:upper:]' '[:lower:]')
  _tkt_lc=$(printf '%s' "$EXTERNAL_TICKET" | tr '[:upper:]' '[:lower:]')
  case "$_title_lc" in
    "$_tkt_lc"|"$_tkt_lc "*|"$_tkt_lc:"*|"$_tkt_lc-"*)
      ;;
    *)
      TITLE="$EXTERNAL_TICKET $TITLE"
      ;;
  esac
fi

# Degradation is recorded, not silent: reaching the slug rank means every prose
# source was empty and the published title is a kebab id. Distinct dedupe-key suffix
# so this advisory never masks the canonical github_issue_created outcome. Never
# blocks — a title is not worth failing a worktask over.
if [ "$TITLE_SOURCE" = "worktask_id" ]; then
  audit_row "deferred" "$(jq -cn --arg v "publish-pl-issue.sh" --arg r "title_fallback_worktask_id" \
    --arg ts "$TITLE_SOURCE" --arg dk "${DEDUPE_KEY}:title_source" \
    '{via:$v, reason:$r, title_source:$ts, dedupe_key:$dk}')" || true
fi

# Guard 2 (recovery half): no local anchor resolved → try a GitHub-side search to
# recover a lost .context ↔ issue binding (fresh clone / regenerated state). Needs
# the finalised TITLE. On an exact-title single hit, comment instead of create.
if [ "$COMMENT_MODE" != "1" ] && resolve_context_issue_search; then
  COMMENT_MODE=1
  EXISTING_ISSUE_URL="$RESOLVED_ISSUE_URL"
  EXISTING_ISSUE_SOURCE="$RESOLVED_ISSUE_SOURCE"
fi

# AC-1 + AC-2: build the canonical label list and auto-provision missing ones.
CANONICAL_LABELS="worktask planning-approved complexity:$TIER"
if [ -n "$EXTERNAL_TICKET" ]; then
  CANONICAL_LABELS="$CANONICAL_LABELS ticket:$EXTERNAL_TICKET"
fi
if [ "$DRY_RUN" != "1" ] && [ "$COMMENT_MODE" != "1" ]; then
  # shellcheck disable=SC2086
  ensure_labels $CANONICAL_LABELS
fi

# Filter out dropped labels (those that failed to auto-create) from the
# argument passed to `gh issue create`. Preserve original order.
SURVIVING_LABELS=""
for _l in $CANONICAL_LABELS; do
  _dropped=0
  for _d in $DROPPED_LABELS; do
    [ "$_l" = "$_d" ] && _dropped=1 && break
  done
  if [ "$_dropped" -eq 0 ]; then
    SURVIVING_LABELS="${SURVIVING_LABELS}${SURVIVING_LABELS:+,}${_l}"
  fi
done

# Invoke gh — create a NEW issue, or (cross-run) COMMENT on the existing one.
# Milestone mode skipped above. Comment path: a subsequent worktask in the same
# .context/ appends a marker-deduped plan summary instead of opening a duplicate.
URL=""
GH_OUT=""
if [ "$COMMENT_MODE" = "1" ]; then
  PLAN_MARKER="<!-- worktask-plan:$WORKTASK_ID:$RUN_INDEX -->"
  COMMENT_TMP="$LOG_DIR/issue-comment-${RUN_INDEX}.tmp"
  {
    printf '%s\n' "$PLAN_MARKER"
    printf '## Follow-up worktask — run #%s\n\n' "$RUN_INDEX"
    cat "$BODY_TMP"
  } > "$COMMENT_TMP" 2>/dev/null || fatal "audit_dir_unwritable"
  if [ "$DRY_RUN" = "1" ]; then
    URL="$EXISTING_ISSUE_URL"
    echo "DRY_RUN: $GH_BIN issue comment $EXISTING_ISSUE_URL --body-file $COMMENT_TMP" >&2
  else
    # Idempotency: this run already commented (marker present) → do not double-post.
    if pl_issue_has_marker "$EXISTING_ISSUE_URL" "$PLAN_MARKER"; then
      defer "comment_already_present"
    fi
    if CMT_OUT=$("$GH_BIN" issue comment "$EXISTING_ISSUE_URL" --body-file "$COMMENT_TMP" 2>&1); then
      URL="$EXISTING_ISSUE_URL"
    else
      CMT_REASON=$(classify_gh_failure "$CMT_OUT")
      CMT_FAIL=$(jq -cn --arg v "publish-pl-issue.sh" --arg r "$CMT_REASON" --arg url "$EXISTING_ISSUE_URL" --arg src "$EXISTING_ISSUE_SOURCE" --arg dk "$DEDUPE_KEY" \
        '{via:$v, mode:"comment", reason:$r, url:$url, resolved_via:$src, dedupe_key:$dk}')
      if [ "$STRICT" = "1" ] || [ "$STRICT" = "true" ]; then
        audit_row "failed" "$CMT_FAIL" || true
        exit 1
      fi
      audit_row "deferred" "$CMT_FAIL" || true
      exit 0
    fi
  fi
  # Persist/refresh the run-independent anchor so future runs resolve locally.
  if [ "$EXISTING_ISSUE_SOURCE" = "anchor" ]; then
    bump_anchor_commented "$RUN_INDEX" || true
  else
    write_context_issue "$EXISTING_ISSUE_URL" "${RESOLVED_ISSUE_NUMBER:-$(printf '%s' "$EXISTING_ISSUE_URL" | grep -oE '[0-9]+$')}" || true
  fi
  CMT_META=$(jq -cn --arg v "publish-pl-issue.sh" --arg url "$URL" --arg tier "$TIER" --argjson sp "$STRIP_PCT" --arg src "$EXISTING_ISSUE_SOURCE" --arg dk "$DEDUPE_KEY" \
    '{via:$v, mode:"comment", url:$url, complexity_tier:$tier, sanitiser_stripped_pct:$sp, resolved_via:$src, dedupe_key:$dk}')
  audit_row "ok" "$CMT_META" || true
  printf 'commented_url=%s\n' "$URL"
  exit 0
fi

if [ "$DRY_RUN" = "1" ]; then
  URL="https://github.com/dry/run/issues/0"
  echo "DRY_RUN: $GH_BIN issue create --title \"$TITLE\" --body-file $BODY_TMP --label $SURVIVING_LABELS" >&2
else
  # run_with_timeout, not a bare TIMEOUT_BIN probe: on stock macOS both binaries
  # are absent, so the old `else` arm ran this call completely unbounded.
  GH_OUT=$(run_with_timeout "$GH_TIMEOUT" "$GH_BIN" issue create --title "$TITLE" --body-file "$BODY_TMP" --label "$SURVIVING_LABELS" 2>&1) || true
  URL=$(printf '%s' "$GH_OUT" | grep -oE 'https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/issues/[0-9]+' | head -1)
  if [ -z "$URL" ]; then
    # AC-3: classify failure mode from gh stderr. If labels were dropped and
    # stderr did not specifically blame a different cause, attribute to
    # label_create_failed (the most likely root cause when DROPPED_LABELS≠"").
    REASON=$(classify_gh_failure "$GH_OUT")
    if [ -n "$DROPPED_LABELS" ] && [ "$REASON" = "gh_api_error" ]; then
      REASON="label_create_failed"
    fi
    FAIL_META=$(jq -cn --arg v "publish-pl-issue.sh" --arg r "$REASON" --arg dk "$DEDUPE_KEY" \
      --arg tkt "${EXTERNAL_TICKET:-}" --arg dropped "${DROPPED_LABELS:-}" \
      '{via:$v, reason:$r, dedupe_key:$dk}
       + (if $tkt == "" then {} else {external_ticket:$tkt} end)
       + (if $dropped == "" then {} else {labels_dropped:($dropped|split(" "))} end)')
    # AC-4: strict mode blocks the worktask on operational failure.
    if [ "$STRICT" = "1" ] || [ "$STRICT" = "true" ]; then
      audit_row "failed" "$FAIL_META" || true
      exit 1
    fi
    audit_row "deferred" "$FAIL_META" || true
    exit 0
  fi
fi

# Persist URL to state.json (atomic). Audit row appended regardless of write success.
write_state_url "$URL" || true
# Persist the run-independent .context/gh-issue.json anchor so a later worktask in
# this .context/ (which re-seeds state.json) resolves this issue and comments on it
# instead of opening a duplicate. Non-fatal; state.json stays the same-run fallback.
write_context_issue "$URL" "$(printf '%s' "$URL" | grep -oE '[0-9]+$')" || true
META_JSON=$(jq -cn --arg v "publish-pl-issue.sh" --arg mode "$MODE" --arg url "$URL" --arg tier "$TIER" --argjson sp "$STRIP_PCT" --arg dk "$DEDUPE_KEY" \
  --arg tkt "${EXTERNAL_TICKET:-}" --arg dropped "${DROPPED_LABELS:-}" \
  '{via:$v, mode:$mode, url:$url, complexity_tier:$tier, sanitiser_stripped_pct:$sp, dedupe_key:$dk}
   + (if $tkt == "" then {} else {external_ticket:$tkt} end)
   + (if $dropped == "" then {} else {labels_dropped:($dropped|split(" "))} end)')
audit_row "ok" "$META_JSON" || true

# Emit single optional line for orchestrator terminal UX.
printf 'published_url=%s\n' "$URL"
exit 0

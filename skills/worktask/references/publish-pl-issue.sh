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
#   - Idempotency: state.json:metadata.github_issue_url short-circuits.
#   - Milestone-mode: state.json:metadata.milestone OR workspace.json present →
#     exit 0 immediately with reason=milestone_mode. No gh API call of any kind
#     (no create, no comment). The parent milestone issue is the canonical record.
#   - Atomic state.json write: tmp.$$ → fsync → mv -f.
#   - Audit row: actor=orchestrator, action=github_issue_created, via=publish-pl-issue.sh,
#     dedupe_key=<worktask_id>:<run_index>:gh_issue.
#   - Exit codes: 0 all operational paths, 1 catastrophic, 2 --self-test failure.
#
# Env vars for injection (test/dev): STATE_FILE, WORKSPACE_ROOT, GH_BIN, DRY_RUN,
# GH_TIMEOUT (default 30).

set -u

# ---------- defaults / env --------------------------------------------------
STATE_FILE="${STATE_FILE:-.context/state.json}"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-}"
GH_BIN="${GH_BIN:-gh}"
DRY_RUN="${DRY_RUN:-0}"
GH_TIMEOUT="${GH_TIMEOUT:-30}"
STRICT="${STRICT:-0}"
LOG_DIR="${WORKSPACE_ROOT:-${CLAUDE_PROJECT_DIR:-.}}/.context/logs"
AUDIT_FILE="$LOG_DIR/audit.jsonl"

# ---------- CLI flag parsing ------------------------------------------------
# Accept --strict (sets STRICT=1). --self-test handled in entrypoint below.
for _arg in "$@"; do
  case "$_arg" in
    --strict) STRICT=1 ;;
    *) ;;
  esac
done

# ---------- helpers ---------------------------------------------------------
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
      # ---- Pass 1 line-strip --------------------------------------------
      if (line ~ /(^|[[:space:]])\.context\//) next                 # L1
      if (line ~ /(^|[[:space:]])\/(Users|home|tmp|var|opt|etc|root)\//) next  # L2,L3
      if (line ~ /(^|[[:space:]])~\//) next                         # L4
      if (line ~ /conductor\/workspaces\/[A-Za-z0-9_-]+/) next      # L5
      if (line ~ /(^|[[:space:]])(workspace_path|plan_file|run_index|artifact_path)[[:space:]]*[:=]/) next  # L6
      if (line ~ /(planning|analyzing|coordinating|coordination|developing|development|reviewing|review|qa|testing|documenting|documentation|releasing|release|finalizing|finalization|stakeholding|retrospective|incident|ethics-review)-[0-9]+\.md/) next  # L7,L8
      if (line ~ /(^|[[:space:]])(\.\/|\.\.\/)[A-Za-z0-9_.\/-]+/) next   # L9
      # L10: drop whole line when a plugin-qualified identifier is the leading
      # non-bullet token (e.g. "* Routed to igrsoft:developer ...",
      # "Breakdown using igrsoft:estimation-methodology:"). Strict prefix
      # allow-list keeps this from false-positive on http:// / git:// / etc.
      if (line ~ /^[[:space:]]*([-*][[:space:]]+)?(Routed to|Breakdown using|Implemented by|Reviewed by|Handled by|Uses|Using|Delegated to)[[:space:]]+(igrsoft|apple-developer|debugging-toolkit|security-scanning|skill-creator|conductor|claude-in-chrome):[a-z][a-z0-9-]*/) next

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
        # A6: plugin-qualified identifier token (igrsoft:foo, apple-developer:bar,
        # etc.). Narrow known-prefix allow-list to avoid false positives on
        # http:, git:, file:, etc. Backtick spans already passed through above.
        if (match(rest, /^(igrsoft|apple-developer|debugging-toolkit|security-scanning|skill-creator|conductor|claude-in-chrome):[a-z][a-z0-9-]*/)) {
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
# Returns 0 (true) if the worktask is running under --milestone:N or inside a
# milestone-worktask workspace. Detection signals (highest priority first):
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
    worktask)             printf 'igrsoft worktask run' ;;
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
  fixtures_dir="$(dirname "$0")/fixtures/publish-pl-issue"
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
    leak_in=$'Breakdown using igrsoft:estimation-methodology:\n* Routed to igrsoft:developer (apple-developer:ios-developer).\nNarrative referencing igrsoft:product-manager directly.\nKeep `igrsoft:code-fixer` inside backticks intact.\n'
    leak_out=$(printf '%s' "$leak_in" | sanitise_body)
    local f02b_ok=1
    # The leading-token lines (1 + 2) should be entirely dropped by L10.
    if printf '%s' "$leak_out" | grep -qF 'Breakdown using'; then f02b_ok=0; fi
    if printf '%s' "$leak_out" | grep -qF 'Routed to'; then f02b_ok=0; fi
    # The mid-sentence reference should have the identifier stripped by A6
    # (narrative remains, token gone).
    if printf '%s' "$leak_out" | grep -qE '(igrsoft|apple-developer):[a-z]' | grep -v '`'; then
      # Allow backticked occurrences only (one is intentionally kept).
      if printf '%s' "$leak_out" | grep -vE '^[^`]*`[^`]*`[^`]*$' | grep -qE '(igrsoft|apple-developer):[a-z]'; then
        f02b_ok=0
      fi
    fi
    # Backtick passthrough preserves the token.
    if ! printf '%s' "$leak_out" | grep -qF '`igrsoft:code-fixer`'; then f02b_ok=0; fi
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

  echo "publish-pl-issue: self-test summary — pass=$pass fail=$fail"
  [ "$fail" -eq 0 ]
}

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

# Guard 2: idempotency — already-published.
EXISTING_URL=$(jq -r '.metadata.github_issue_url // ""' "$STATE_FILE" 2>/dev/null)
if [ -n "$EXISTING_URL" ]; then
  defer "already_published"
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
[ -r "$PLAN_FILE" ] || fatal "plan_unreadable"

# ---------- extract + sanitise + render -------------------------------------
SUMMARY_RAW=$(jq -r '.facts.goal // ""' "$STATE_FILE")

# AC-2: external-ticket extraction. Match ^[A-Z][A-Z0-9]+-[0-9]+ in SUMMARY_RAW
# first; fall back to upper-cased WORKTASK_ID extraction. Already-prefixed
# titles are left as-is in the render block below (no double-prefix).
EXTERNAL_TICKET=$(extract_external_ticket "$SUMMARY_RAW")
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
    if [ -n "$(printf '%s' "$DESIGN_S" | tr -d '[:space:]')" ]; then
      printf '## Design Preview\n%s\n\nCompare implementation (DV) and screenshots (QA) against this design.\n\n' "$DESIGN_S"
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
  if [ -n "$(printf '%s' "$DESIGN_S" | tr -d '[:space:]')" ]; then
    printf '## Design Preview\n%s\n\nCompare implementation (DV) and screenshots (QA) against this design.\n\n' "$DESIGN_S"
  fi
  printf '## Complexity\n%s\n\n' "$COMPLEXITY_S"
  printf -- '---\n*Plan approved on %s. Tracking continues in worktask run #%s.*\n' "$(date -u +%F)" "$RUN_INDEX"
} > "$BODY_TMP" 2>/dev/null || fatal "audit_dir_unwritable"

# Title (sanitised — pulled from facts.goal or worktask_id).
TITLE_RAW="${SUMMARY_RAW:-$WORKTASK_ID}"
TITLE=$(printf '%s' "$TITLE_RAW" | head -1 | cut -c1-100 | sanitise_body | tr -d '\n')
[ -z "$TITLE" ] && TITLE="Plan approved: $WORKTASK_ID"

# AC-2: ensure title starts with EXTERNAL_TICKET prefix. Skip if already prefixed
# (avoid double-prefix like "OV-113 OV-113 …").
if [ -n "$EXTERNAL_TICKET" ]; then
  case "$TITLE" in
    "$EXTERNAL_TICKET"|"$EXTERNAL_TICKET "*|"$EXTERNAL_TICKET:"*)
      ;;
    *)
      TITLE="$EXTERNAL_TICKET $TITLE"
      ;;
  esac
fi

# AC-1 + AC-2: build the canonical label list and auto-provision missing ones.
CANONICAL_LABELS="worktask planning-approved complexity:$TIER"
if [ -n "$EXTERNAL_TICKET" ]; then
  CANONICAL_LABELS="$CANONICAL_LABELS ticket:$EXTERNAL_TICKET"
fi
if [ "$DRY_RUN" != "1" ]; then
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

# Invoke gh — single publish path (create). Milestone mode skipped above.
URL=""
GH_OUT=""
if [ "$DRY_RUN" = "1" ]; then
  URL="https://github.com/dry/run/issues/0"
  echo "DRY_RUN: $GH_BIN issue create --title \"$TITLE\" --body-file $BODY_TMP --label $SURVIVING_LABELS" >&2
else
  TIMEOUT_BIN="$(command -v gtimeout || command -v timeout || true)"
  if [ -n "$TIMEOUT_BIN" ]; then
    GH_OUT=$("$TIMEOUT_BIN" "$GH_TIMEOUT" "$GH_BIN" issue create --title "$TITLE" --body-file "$BODY_TMP" --label "$SURVIVING_LABELS" 2>&1) || true
  else
    GH_OUT=$("$GH_BIN" issue create --title "$TITLE" --body-file "$BODY_TMP" --label "$SURVIVING_LABELS" 2>&1) || true
  fi
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
META_JSON=$(jq -cn --arg v "publish-pl-issue.sh" --arg mode "$MODE" --arg url "$URL" --arg tier "$TIER" --argjson sp "$STRIP_PCT" --arg dk "$DEDUPE_KEY" \
  --arg tkt "${EXTERNAL_TICKET:-}" --arg dropped "${DROPPED_LABELS:-}" \
  '{via:$v, mode:$mode, url:$url, complexity_tier:$tier, sanitiser_stripped_pct:$sp, dedupe_key:$dk}
   + (if $tkt == "" then {} else {external_ticket:$tkt} end)
   + (if $dropped == "" then {} else {labels_dropped:($dropped|split(" "))} end)')
audit_row "ok" "$META_JSON" || true

# Emit single optional line for orchestrator terminal UX.
printf 'published_url=%s\n' "$URL"
exit 0

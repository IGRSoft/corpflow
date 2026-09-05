#!/usr/bin/env bash
# attach-visual-evidence-selftest.sh — the `--self-test` harness for attach-visual-evidence.sh.
#
# SOURCED, never executed: attach-visual-evidence.sh loads this file only on the `--self-test`
# path, so the production path never pays for it. Sourcing leaves the caller's
# `$0` and every function it has already defined in scope — this file reads the
# caller's helpers and is not standalone.
#
# Contract: defines `run_self_tests`, returning 0 when every case passes.

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

#!/usr/bin/env bats
# Contract tests for skills/worktask/scripts/attach-visual-evidence.sh.
# Contracts (from header + body):
#   - --emit pr: requires_screenshots=false => empty stdout, audit reason=requires_screenshots_false
#   - --emit pr: requires_screenshots=true + no manifest/captures => empty stdout, audit reason=no_captures
#   - --emit pr: requires_screenshots=true + markdown-table manifest + co-located PNG + gist mock
#               => stdout contains "## Visual evidence" + "![dv-01 ...](<gist-url>)"
#   - missing/corrupt state.json => exit 1 (catastrophic)
#   - invalid usage (no mode, bad mode) => exit 1 + usage line
#   - --self-test => "fail=0", exit 0
bats_require_minimum_version 1.5.0
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/attach-visual-evidence.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context/logs"
  # state.json with requires_screenshots=false for skip tests
  cat > "$WD/state-false.json" <<'EOS'
{"version":1,"worktask_id":"t","run_index":0,"metadata":{"requires_screenshots":false},"facts":{"goal":"test"}}
EOS
  # state.json with requires_screenshots=true for capture tests
  cat > "$WD/state-true.json" <<'EOS'
{"version":1,"worktask_id":"t","run_index":0,"metadata":{"requires_screenshots":true},"facts":{"goal":"test"}}
EOS
  # markdown-table manifest + co-located PNG (img_dir = dirname(MANIFEST_FILE))
  printf '\x89PNG\r\n\x1a\n' > "$WD/dv-01-test.png"
  cat > "$WD/screenshots.md" <<'EOS'
| # | slug | path | bytes | tool | adapter | caption | ts | ref |
|---|------|------|-------|------|---------|---------|----|----|
| 01 | test | dv-01-test.png | 100 | apple | sim | Login screen | 2026-01-01 | DV |
EOS
}

@test "happy: --emit pr with requires_screenshots=false produces empty stdout (exit 0)" {
  run env STATE_FILE="$WD/state-false.json" WORKSPACE_ROOT="$WD" \
    bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_success
  # empty stdout — skip gate fires before any gh call
  assert_output ""
  # audit row records the skip
  run jq -r '.metadata.reason' <(tail -1 "$WD/.context/logs/audit.jsonl")
  assert_output "requires_screenshots_false"
}

@test "happy: --emit pr with captures + gist mock renders a Visual evidence block" {
  # Requires a markdown-table manifest and a co-located PNG.
  # GIST_VERIFY_FORCE=pass bypasses the anonymous HEAD probe.
  run env STATE_FILE="$WD/state-true.json" WORKSPACE_ROOT="$WD" \
    MANIFEST_FILE="$WD/screenshots.md" \
    ASSET_HOST_MODE=gist GIST_RAW_URL_BASE="https://mock.gist/raw" \
    GIST_VERIFY_FORCE=pass \
    bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_success
  assert_output --partial "## Visual evidence"
  assert_output --partial "![dv-01 Login screen](https://mock.gist/raw/dv-01-test.png)"
  assert_output --partial "Manifest:"
}

# A second --emit for the same run previously re-hosted every asset, orphaning the
# first set on GitHub. The --post modes dedupe against a marker they can read back
# off the issue; --emit has no remote to consult, so the emission cache is the marker.
@test "idempotency: a second --emit pr replays the first emission, --force re-hosts" {
  _emit() {
    env STATE_FILE="$WD/state-true.json" WORKSPACE_ROOT="$WD" \
      MANIFEST_FILE="$WD/screenshots.md" \
      ASSET_HOST_MODE=gist GIST_RAW_URL_BASE="https://mock.gist/raw" \
      GIST_VERIFY_FORCE=pass \
      bash "$PLUGIN_ROOT/$SCRIPT" --emit pr "$@"
  }
  first=$(_emit)
  second=$(_emit)
  forced=$(_emit --force)

  [ -n "$first" ]
  [ "$first" = "$second" ]
  [ "$first" = "$forced" ]
  [ -s "$WD/.context/logs/visual-evidence-pr-t-0.md" ]
  # Exactly one replay row: the first run emitted, the third was forced.
  run grep -c '"result":"reused"' "$WD/.context/logs/audit.jsonl"
  assert_output "1"
}

@test "gist verify: the reachability probe rejecting degrades the embed (real fail arm)" {
  # Carried from DV3. Reaching gist_raw_url_reachable's REJECT arm needs
  # GIST_RAW_URL_BASE="" — publish-pl-issue.sh:808 synthesises and returns early
  # whenever it is set, which is why every other gist test here leaves
  # GIST_VERIFY_FORCE inert — plus a mocked `gh gist create` for the upload.
  stub_cmd gh --stdout 'https://gist.github.com/abc123'
  run env STATE_FILE="$WD/state-true.json" WORKSPACE_ROOT="$WD" \
    MANIFEST_FILE="$WD/screenshots.md" \
    ASSET_HOST_MODE=gist GIST_RAW_URL_BASE="" \
    GIST_VERIFY_FORCE=fail PATH="$STUB_PATH" \
    bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_success
  # REQ-1: a URL that failed render-verification must never reach the PR body.
  refute_output --partial "https://gist.github.com/abc123/raw/dv-01-test.png"
}

@test "gist verify: the same wiring with the probe passing does emit the embed" {
  # Falsification arm for the test above: identical except the verdict, so the
  # missing embed there is attributable to the probe rather than a broken mock.
  stub_cmd gh --stdout 'https://gist.github.com/abc123'
  run env STATE_FILE="$WD/state-true.json" WORKSPACE_ROOT="$WD" \
    MANIFEST_FILE="$WD/screenshots.md" \
    ASSET_HOST_MODE=gist GIST_RAW_URL_BASE="" \
    GIST_VERIFY_FORCE=pass PATH="$STUB_PATH" \
    bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_success
  assert_output --partial "https://gist.github.com/abc123/raw/dv-01-test.png"
}

@test "edge: --emit pr with true flag but no manifest/captures → empty stdout, audit no_captures" {
  # No MANIFEST_FILE set → manifest_path resolves to a non-existent path → no_captures.
  run env STATE_FILE="$WD/state-true.json" WORKSPACE_ROOT="$WD" \
    bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_success
  assert_output ""
  run jq -r '.metadata.reason' <(tail -1 "$WD/.context/logs/audit.jsonl")
  assert_output "no_captures"
}

@test "failure: missing state.json is catastrophic (exit 1)" {
  run env STATE_FILE="$WD/state-missing.json" WORKSPACE_ROOT="$WD" \
    bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_failure 1
  assert_output --partial "state unreadable"
}

@test "failure: no mode argument prints usage and exits 1" {
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_failure 1
  assert_output --partial "usage:"
}

@test "contract: --self-test passes (smoke, NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "fail=0"
}

# ---------------------------------------------------------------------------
# The manifest reference must carry NO local path. `.context/` is gitignored and
# per-workspace, so it means nothing to a reviewer -- and as a code span it was
# the one shape that slipped past the sanitiser's pass-1 anchors.
# ---------------------------------------------------------------------------

@test "contract: the emitted manifest reference contains no local path" {
  run env STATE_FILE="$WD/state-true.json" WORKSPACE_ROOT="$WD" \
    MANIFEST_FILE="$WD/screenshots.md" \
    ASSET_HOST_MODE=gist GIST_RAW_URL_BASE="https://mock.gist/raw" \
    GIST_VERIFY_FORCE=pass \
    bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_success
  assert_output --partial "Manifest:"
  refute_output --partial ".context/"
}

@test "contract: the emitted block survives the sanitiser intact" {
  # Regression guard for the interaction that produced the bug: the block is
  # written by one script and stripped by another, and neither test knew about
  # the other. If a local path ever returns here, the sanitiser deletes the whole
  # line and "see manifest" ends up naming nothing.
  run env STATE_FILE="$WD/state-true.json" WORKSPACE_ROOT="$WD" \
    MANIFEST_FILE="$WD/screenshots.md" \
    ASSET_HOST_MODE=gist GIST_RAW_URL_BASE="https://mock.gist/raw" \
    GIST_VERIFY_FORCE=pass \
    bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_success
  sanitised=$(printf '%s\n' "$output" | (
    PUBLISH_LIB_ONLY=1 . "$PLUGIN_ROOT/skills/worktask/scripts/publish-pl-issue.sh" \
      > /dev/null 2>&1
    sanitise_body
  ))
  [[ "$sanitised" == *"Manifest:"* ]]
}

# ---------------------------------------------------------------------------
# D4 -- captures exist but did not reach the reader. Trigger is
# hostable_rows > 0 && embed_count < hostable_rows, counting embeddable (png)
# rows only.
# ---------------------------------------------------------------------------

# Write a manifest of N png rows plus their co-located files.
_mk_manifest() {
  local n="$1" i
  {
    printf '| # | slug | path | bytes | tool | adapter | caption | ts | ref |\n'
    printf '|---|------|------|-------|------|---------|---------|----|----|\n'
    for i in $(seq -f '%02g' 1 "$n"); do
      printf '| %s | s%s | dv-%s-t.png | 100 | apple | sim | Cap %s | 2026-01-01 | DV |\n' \
        "$i" "$i" "$i" "$i"
      printf '\x89PNG\r\n\x1a\n' > "$WD/dv-$i-t.png"
    done
  } > "$WD/screenshots.md"
}

_degraded_row() {
  jq -c 'select(.action=="visual_evidence_degraded")|.metadata' \
    "$WD/.context/logs/audit.jsonl" 2> /dev/null || true
}

@test "D4: captures on disk with hosting unavailable emits a degraded audit row" {
  _mk_manifest 2
  run env STATE_FILE="$WD/state-true.json" WORKSPACE_ROOT="$WD" \
    MANIFEST_FILE="$WD/screenshots.md" ASSET_HOST_MODE=none \
    bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_success
  run _degraded_row
  assert_output --partial '"captured":2'
  assert_output --partial '"embedded":0'
}

@test "D4: the degradation is announced on stderr with an actionable reason" {
  _mk_manifest 2
  run --separate-stderr env STATE_FILE="$WD/state-true.json" WORKSPACE_ROOT="$WD" \
    MANIFEST_FILE="$WD/screenshots.md" ASSET_HOST_MODE=none \
    bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_success
  [[ "$stderr" == *"NOTICE"* ]]
  [[ "$stderr" == *"reason="* ]]
}

@test "D4: visual_evidence_pr_emitted is still written alongside the degraded row" {
  # fn-preflight.sh gates on this row's PRESENCE; replacing it would block every
  # screenshot-requiring worktask.
  _mk_manifest 2
  run env STATE_FILE="$WD/state-true.json" WORKSPACE_ROOT="$WD" \
    MANIFEST_FILE="$WD/screenshots.md" ASSET_HOST_MODE=none \
    bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_success
  run jq -rc 'select(.action=="visual_evidence_pr_emitted")|.result' \
    "$WD/.context/logs/audit.jsonl"
  assert_output --partial "ok"
}

@test "D4: partial loss fires too — 6 captures against the 5-embed cap" {
  # The OV-161 shape. A "== 0" trigger would miss this entirely.
  _mk_manifest 6
  run env STATE_FILE="$WD/state-true.json" WORKSPACE_ROOT="$WD" \
    MANIFEST_FILE="$WD/screenshots.md" \
    ASSET_HOST_MODE=gist GIST_RAW_URL_BASE="https://mock.gist/raw" \
    GIST_VERIFY_FORCE=pass \
    bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_success
  run _degraded_row
  assert_output --partial '"captured":6'
  assert_output --partial '"embedded":5'
}

@test "D4: a fully embedded run emits NO degraded row" {
  _mk_manifest 2
  run env STATE_FILE="$WD/state-true.json" WORKSPACE_ROOT="$WD" \
    MANIFEST_FILE="$WD/screenshots.md" \
    ASSET_HOST_MODE=gist GIST_RAW_URL_BASE="https://mock.gist/raw" \
    GIST_VERIFY_FORCE=pass \
    bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_success
  run _degraded_row
  assert_output ""
}

@test "D4: placeholder rows alone do NOT fire it (never embeddable by design)" {
  {
    printf '| # | slug | path | bytes | tool | adapter | caption | ts | ref |\n'
    printf '|---|------|------|-------|------|---------|---------|----|----|\n'
    printf '| 01 | a | dv-01-a.txt | 10 | apple | sim | placeholder | 2026-01-01 | DV |\n'
  } > "$WD/screenshots.md"
  run env STATE_FILE="$WD/state-true.json" WORKSPACE_ROOT="$WD" \
    MANIFEST_FILE="$WD/screenshots.md" ASSET_HOST_MODE=none \
    bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_success
  run _degraded_row
  assert_output ""
}

@test "D4: an out-of-budget link-only row does NOT fire it" {
  _mk_manifest 1
  {
    printf '\n## Out-of-budget files (link-only)\n'
    printf -- '- huge.png: 99999999 bytes\n'
  } >> "$WD/screenshots.md"
  run env STATE_FILE="$WD/state-true.json" WORKSPACE_ROOT="$WD" \
    MANIFEST_FILE="$WD/screenshots.md" \
    ASSET_HOST_MODE=gist GIST_RAW_URL_BASE="https://mock.gist/raw" \
    GIST_VERIFY_FORCE=pass \
    bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_success
  run _degraded_row
  assert_output ""
}

# --- the render-verify probe is UNREACHABLE under the mock base --------------
# Every gist test in this file sets GIST_RAW_URL_BASE and then sets
# GIST_VERIFY_FORCE=pass, with a comment claiming the latter "bypasses the
# anonymous HEAD probe". It does not: publish-pl-issue.sh:808-809 returns the
# synthesised URL early whenever GIST_RAW_URL_BASE is non-empty, which is BEFORE
# the gist_raw_url_reachable call at :829. GIST_VERIFY_FORCE is inert in this
# configuration, so the `fail) return 1` arm has no coverage here in either
# direction. The script's own self-tests reach it by setting GIST_RAW_URL_BASE=""
# (:2029, :2041, :2104, :2118) and mocking the upload instead.
# Pinned as characterisation; real fail-arm coverage is routed to DV4.

@test "characterisation: GIST_VERIFY_FORCE is inert while GIST_RAW_URL_BASE is set" {
  _mk_manifest 1
  run env STATE_FILE="$WD/state-true.json" WORKSPACE_ROOT="$WD" \
    MANIFEST_FILE="$WD/screenshots.md" \
    ASSET_HOST_MODE=gist GIST_RAW_URL_BASE="https://mock.gist/raw" \
    GIST_VERIFY_FORCE=pass \
    bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_success
  local pass_out="$output"

  run env STATE_FILE="$WD/state-true.json" WORKSPACE_ROOT="$WD" \
    MANIFEST_FILE="$WD/screenshots.md" \
    ASSET_HOST_MODE=gist GIST_RAW_URL_BASE="https://mock.gist/raw" \
    GIST_VERIFY_FORCE=fail \
    bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_success

  # Identical under both hook values, and the embed survives even under `fail` —
  # the two facts that together prove the probe was never consulted. Moving the
  # verify ahead of the mock short-circuit turns this red, which is the signal.
  assert_output "$pass_out"
  assert_output --partial "](https://mock.gist/raw/dv-01"
  run _degraded_row
  assert_output ""
}

# --- --validate-manifest (REQ-8) ---------------------------------------------
# Read-only schema mode added so hooks/dv-screenshot-gate.sh can reject a malformed
# manifest at the stage that WRITES it. The publishing modes' exit-0 contract is
# separately re-asserted below: their stdout is spliced into the PR body.

@test "validate: a canonical manifest exits 0 with no diagnostic" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-manifest "$WD/screenshots.md"
  assert_success
  assert_output ""
}

@test "validate: a row with the wrong column count exits 1 naming the line" {
  cat > "$WD/bad.md" <<'EOS'
| # | path | caption |
|---|------|---------|
| 01 | dv-01-test.png | too few columns |
EOS
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-manifest "$WD/bad.md"
  assert_failure 1
  assert_output --partial "columns, expected 9"
  assert_output --partial "line 3"
}

@test "validate: a non-two-digit index exits 1" {
  cat > "$WD/bad2.md" <<'EOS'
| # | slug | path | bytes | tool | adapter | caption | ts | ref |
|---|------|------|-------|------|---------|---------|----|----|
| 1 | test | dv-01-test.png | 100 | apple | sim | Login | 2026-01-01 | DV |
EOS
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-manifest "$WD/bad2.md"
  assert_failure 1
  assert_output --partial "two-digit ordinal"
}

@test "validate: a missing manifest exits 2, distinct from a schema violation" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-manifest "$WD/nope.md"
  assert_failure 2
  assert_output --partial "manifest not found"
}

@test "validate: the mode writes nothing — the manifest is byte-identical afterwards" {
  cp "$WD/screenshots.md" "$WD/snap.md"
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-manifest "$WD/screenshots.md"
  assert_success
  run diff -q "$WD/screenshots.md" "$WD/snap.md"
  assert_success
}

@test "contract: --emit pr keeps its exit-0 contract for a manifest the validator rejects" {
  # The PR-body composer splices this stdout; a schema failure must NOT become a
  # non-zero exit here. Enforcement lives in the gate, never in the composer.
  cat > "$WD/bad3.md" <<'EOS'
| # | path |
|---|------|
| 1 | dv-01-test.png |
EOS
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-manifest "$WD/bad3.md"
  assert_failure 1

  run env STATE_FILE="$WD/state-true.json" WORKSPACE_ROOT="$WD" \
    MANIFEST_FILE="$WD/bad3.md" ASSET_HOST_MODE=none \
    bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_success
}

@test "validate: a table-free manifest exits 3 — no rows, policy left to the caller" {
  printf '# screenshots\n\nNo captures.\n' > "$WD/norows.md"
  run bash "$PLUGIN_ROOT/$SCRIPT" --validate-manifest "$WD/norows.md"
  assert_failure 3
  assert_output --partial "no canonical capture rows"
}

# --- embed cap vs hosting failure (R-4.3) ------------------------------------

# Two captures, both hostable, cap forced to one: the degradation is the cap, and
# hosting is healthy. Before this fix the audit row took its reason from the hosting
# probe alone, so a capped-but-healthy run reported a hosting reason on a good row.
mk_two_row_manifest() {
  printf '\x89PNG\r\n\x1a\n' > "$WD/dv-02-test.png"
  cat > "$WD/screenshots.md" <<'EOS'
| # | slug | path | bytes | tool | adapter | caption | ts | ref |
|---|------|------|-------|------|---------|---------|----|----|
| 01 | test | dv-01-test.png | 100 | apple | sim | Login screen | 2026-01-01 | DV |
| 02 | test | dv-02-test.png | 100 | apple | sim | Home screen | 2026-01-01 | DV |
EOS
}

@test "embed cap: a capped but healthy run states the cap in the body" {
  mk_two_row_manifest
  run env STATE_FILE="$WD/state-true.json" WORKSPACE_ROOT="$WD" \
    MANIFEST_FILE="$WD/screenshots.md" MAX_EMBED=1 \
    ASSET_HOST_MODE=gist GIST_RAW_URL_BASE="https://mock.gist/raw" \
    GIST_VERIFY_FORCE=pass \
    bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_success
  assert_output --partial "omitted (embed cap 1)"
  assert_output --partial "embed cap 1"
  assert_output --partial "hosting is healthy"
}

@test "embed cap: the audit row carries the distinct embed_cap reason, not a hosting reason" {
  mk_two_row_manifest
  run env STATE_FILE="$WD/state-true.json" WORKSPACE_ROOT="$WD" \
    MANIFEST_FILE="$WD/screenshots.md" MAX_EMBED=1 \
    ASSET_HOST_MODE=gist GIST_RAW_URL_BASE="https://mock.gist/raw" \
    GIST_VERIFY_FORCE=pass \
    bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_success
  run jq -rs '[.[] | select(.action == "visual_evidence_degraded")] | last | .metadata.reason' \
    "$WD/.context/logs/audit.jsonl"
  assert_output "embed_cap"
}

@test "embed cap: the operator note does not blame a missing session token" {
  mk_two_row_manifest
  run env STATE_FILE="$WD/state-true.json" WORKSPACE_ROOT="$WD" \
    MANIFEST_FILE="$WD/screenshots.md" MAX_EMBED=1 \
    ASSET_HOST_MODE=gist GIST_RAW_URL_BASE="https://mock.gist/raw" \
    GIST_VERIFY_FORCE=pass \
    bash "$PLUGIN_ROOT/$SCRIPT" --emit pr 2>&1
  assert_success
  refute_output --partial "Set GH_SESSION_TOKEN"
  assert_output --partial "not a hosting failure"
}

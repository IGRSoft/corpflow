#!/usr/bin/env bats
# Tests for hooks/anchor-preflight.sh (DV0c) — PostToolUse gate that runs
# cache-lint --anchor-lint only for canonical .context/<stage>-N.md artifacts.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="hooks/anchor-preflight.sh"

setup() {
  WD="$(mk_tmpworkdir)"
}

@test "happy: non-artifact write path is a no-op (exit 0, no lint invoked)" {
  # SKILL.md is not a worktask artifact -> the gating regex misses -> exit 0.
  run bash "$PLUGIN_ROOT/$SCRIPT" \
    < "${FIXTURES}/hooks/anchor-preflight-nonartifact.payload.json"
  assert_success
  [ -z "$output" ]
}

@test "edge: artifact-shaped path that does not exist on disk is a no-op" {
  # file_path matches the regex but the file is absent -> exit 0 (no lint).
  run bash "$PLUGIN_ROOT/$SCRIPT" \
    <<< '{"tool_input":{"file_path":".context/development-99.md"}}'
  assert_success
}

@test "edge: empty stdin and no env path -> no-op exit 0" {
  run bash "$PLUGIN_ROOT/$SCRIPT" < /dev/null
  assert_success
}

@test "failure: a real artifact missing its H2 anchor surfaces a non-zero lint" {
  # Build a .context/<stage>-N.md artifact with NO H2 anchor; the gate must
  # delegate to cache-lint --anchor-lint, which fails for the missing anchor.
  mkdir -p "$WD/.context"
  cat > "$WD/.context/development-0.md" <<'EOF'
---
handoff:
  stage: DV
  verdict: ok
  summary: "no anchor present"
---

# Development

Body without the required `## DV Handoff` H2 anchor.
EOF
  run env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "$PLUGIN_ROOT/$SCRIPT" \
    <<< "{\"tool_input\":{\"file_path\":\"$WD/.context/development-0.md\"}}"
  assert_failure
}

@test "failure: env unset -> self-located plugin root still lints (missing anchor)" {
  # Provider-agnostic fallback: with CLAUDE_PLUGIN_ROOT unset the hook derives
  # the plugin root from its own path and must still surface the lint failure
  # (pre-fix behavior was a silent exit 0).
  mkdir -p "$WD/.context"
  cat > "$WD/.context/development-0.md" <<'EOF'
---
handoff:
  stage: DV
  verdict: ok
  summary: "no anchor present"
---

# Development

Body without the required `## DV Handoff` H2 anchors.
EOF
  run env -u CLAUDE_PLUGIN_ROOT bash "$PLUGIN_ROOT/$SCRIPT" \
    <<< "{\"tool_input\":{\"file_path\":\"$WD/.context/development-0.md\"}}"
  assert_failure
}

@test "happy: env unset -> compliant artifact passes via self-located root" {
  # The self-location block must not trip `set -eu`, and a DV artifact carrying
  # the full anchor allow-list lints clean.
  mkdir -p "$WD/.context"
  cat > "$WD/.context/development-1.md" <<'EOF'
---
handoff:
  stage: DV
  verdict: ok
  summary: "all anchors present"
---

# Development

## files-changed

table

## tests-added

list

## deviations

none

## follow-ups

none

## elicitation-sweep

nothing to elicit
EOF
  run env -u CLAUDE_PLUGIN_ROOT bash "$PLUGIN_ROOT/$SCRIPT" \
    <<< "{\"tool_input\":{\"file_path\":\"$WD/.context/development-1.md\"}}"
  assert_success
}

@test "contract: explicit env override wins -> bogus root degrades to no-op exit 0" {
  # Strict env-first semantics: a set-but-bogus CLAUDE_PLUGIN_ROOT is honored
  # (never second-guessed by self-location), so the lint script is not found
  # and the hook no-ops. Same override contract apple-canvas.bats relies on.
  mkdir -p "$WD/.context"
  cat > "$WD/.context/development-2.md" <<'EOF'
---
handoff:
  stage: DV
  verdict: ok
  summary: "no anchor present"
---

# Development

Missing anchors, but lint is unreachable via the bogus override.
EOF
  run env CLAUDE_PLUGIN_ROOT="/nonexistent_plugin_root_$$" \
    bash "$PLUGIN_ROOT/$SCRIPT" \
    <<< "{\"tool_input\":{\"file_path\":\"$WD/.context/development-2.md\"}}"
  assert_success
}

@test "failure: a per-stream DV write is linted like development-N.md (missing anchor)" {
  mkdir -p "$WD/.context"
  printf -- '---\nhandoff:\n  stage: DV\n  verdict: ok\n  summary: "no anchor"\n---\n\n# Development\n' \
    > "$WD/.context/development-0-service.md"
  run env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/$SCRIPT" \
    <<< "{\"tool_input\":{\"file_path\":\"$WD/.context/development-0-service.md\"}}"
  assert_failure 2
}

@test "happy: an over-long stream slug is not an artifact name (no-op)" {
  mkdir -p "$WD/.context"
  long="$WD/.context/development-0-a2345678901234567890123456789012345678901.md"
  printf -- '---\nhandoff:\n  stage: DV\n---\n' > "$long"
  run env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/$SCRIPT" \
    <<< "{\"tool_input\":{\"file_path\":\"$long\"}}"
  assert_success
}

@test "contract: --self-test asserts the gating regex (smoke, NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "self-test OK"
}

# --- control-byte lint (bytes are printf-generated) ---------------------------

# mk_compliant_dv <path> — a DV artifact carrying the full anchor allow-list.
mk_compliant_dv() {
  printf -- '---\nhandoff:\n  stage: DV\n  verdict: ok\n  summary: "all anchors"\n---\n\n# Development\n' > "$1"
  printf '\n## %s\n\nbody\n' files-changed tests-added deviations follow-ups elicitation-sweep >> "$1"
}

payload() {
  printf '{"tool_input":{"file_path":"%s"}}' "$1"
}

@test "control bytes: a NUL in a compliant artifact exits non-zero naming path and offset" {
  mkdir -p "$WD/.context"
  mk_compliant_dv "$WD/.context/development-3.md"
  local off
  off=$(wc -c < "$WD/.context/development-3.md" | tr -d ' ')
  printf '\000\n' >> "$WD/.context/development-3.md"
  run env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/$SCRIPT" \
    <<< "$(payload "$WD/.context/development-3.md")"
  assert_failure 2
  assert_output --partial "control bytes in $WD/.context/development-3.md"
  assert_output --partial "$WD/.context/development-3.md:$off:0x00"
}

@test "control bytes: a NUL in a non-artifact text file exits non-zero" {
  printf 'spellings `\\0` raw \000\n' > "$WD/notes.md"
  run env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(payload "$WD/notes.md")"
  assert_failure 2
  assert_output --partial "$WD/notes.md:19:0x00"
}

@test "control bytes: a clean non-artifact write is a no-op" {
  printf 'clean\ttext\r\n' > "$WD/notes.md"
  run env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(payload "$WD/notes.md")"
  assert_success
  assert_output ""
}

@test "control bytes: a non-text extension is not linted" {
  printf 'png\000data' > "$WD/logo.png"
  run env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$(payload "$WD/logo.png")"
  assert_success
}

@test "control bytes: an artifact with a NUL and a missing anchor shows both diagnostics" {
  mkdir -p "$WD/.context"
  printf -- '---\nhandoff:\n  stage: DV\n  verdict: ok\n  summary: "no anchor"\n---\n\n# Development\n\nraw \001 byte\n' \
    > "$WD/.context/development-4.md"
  local anchor_line
  anchor_line="$(bash "$PLUGIN_ROOT/skills/worktask/scripts/cache-lint.sh" --anchor-lint "$WD/.context/development-4.md" 2>&1 | head -1 || true)"
  [ -n "$anchor_line" ] || fail "anchor lint printed nothing for a missing-anchor artifact"
  run env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/$SCRIPT" \
    <<< "$(payload "$WD/.context/development-4.md")"
  assert_failure 2
  assert_output --partial "control bytes in $WD/.context/development-4.md"
  assert_output --partial "$anchor_line"
}

@test "control bytes: an empty plugin root never sources skills/ from the cwd" {
  mkdir -p "$WD/hookcopy" "$WD/skills/worktask/scripts"
  cp "$PLUGIN_ROOT/$SCRIPT" "$WD/hookcopy/anchor-preflight.sh"
  printf 'cb_is_lintable() { return 0; }\ncb_scan_file() { echo PLANTED; return 1; }\n' \
    > "$WD/skills/worktask/scripts/control-byte-lib.sh"
  printf 'x\000\n' > "$WD/notes.md"
  cd "$WD"
  run env -u CLAUDE_PLUGIN_ROOT bash "$WD/hookcopy/anchor-preflight.sh" <<< "$(payload "$WD/notes.md")"
  assert_success
  refute_output --partial "PLANTED"
}

@test "control bytes: --self-test fails when the library is unreachable" {
  run env CLAUDE_PLUGIN_ROOT="/nonexistent_plugin_root_$$" bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_failure
  assert_output --partial "control-byte-lib.sh unreachable"
}

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

@test "contract: --self-test asserts the gating regex (smoke, NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "self-test OK"
}

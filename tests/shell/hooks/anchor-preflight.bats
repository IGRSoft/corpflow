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

# --- PreToolUse deny arm ------------------------------------------------------
# A JSON deny on stdout with exit 0 blocks the write; empty stdout with exit 0 allows it.

# pre_payload <tool> <file_path> <content-or-new_string> [old_string]
pre_payload() {
  if [ "$1" = Write ]; then
    jq -cn --arg p "$2" --arg c "$3" '{hook_event_name:"PreToolUse", tool_name:"Write", tool_input:{file_path:$p, content:$c}}'
  else
    jq -cn --arg p "$2" --arg n "$3" --arg o "${4:-}" '{hook_event_name:"PreToolUse", tool_name:"Edit", tool_input:{file_path:$p, new_string:$n, old_string:$o}}'
  fi
}

with_ledger() { mkdir -p "$WD/.context"; : > "$WD/.context/state.json"; }

run_pre() { run env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$1"; }

@test "pre: a Write adding an H2 outside the DV allow-list is denied, naming it and the allowed set" {
  with_ledger
  run_pre "$(pre_payload Write "$WD/.context/development-0.md" $'## files-changed\n\n## Approach\n')"
  assert_success
  local decision reason
  decision="$(jq -r '.hookSpecificOutput.permissionDecision' <<< "$output")"
  reason="$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<< "$output")"
  [ "$decision" = deny ] || fail "not denied: $output"
  [[ "$reason" == *"development-0.md (stage=DV) adds H2 outside the allow-list: ## Approach."* ]]
  [[ "$reason" == *"Allowed: ## files-changed, ## tests-added"* ]]
  [[ "$reason" == *"optional: ## verification-command, ## decisions"* ]]
}

@test "pre: a conforming Write, and one missing required H2s, are both allowed" {
  with_ledger
  run_pre "$(pre_payload Write "$WD/.context/development-0.md" $'## files-changed\n\n## verification-command\n')"
  assert_success
  assert_output ""
}

@test "pre: the same bad content to a non-artifact path is allowed" {
  with_ledger
  run_pre "$(pre_payload Write "$WD/.context/notes.md" $'## Approach\n')"
  assert_success
  assert_output ""
  run_pre "$(pre_payload Write "$WD/docs/development-0.md" $'## Approach\n')"
  assert_success
  assert_output ""
}

@test "pre: no state.json beside the artifact means no deny" {
  mkdir -p "$WD/.context"
  run_pre "$(pre_payload Write "$WD/.context/development-0.md" $'## Approach\n')"
  assert_success
  assert_output ""
}

@test "pre: a per-stream development file is never linted against the carrier set" {
  with_ledger
  run_pre "$(pre_payload Write "$WD/.context/development-0-backend.md" $'## commits\n')"
  assert_success
  assert_output ""
}

@test "pre: an Edit whose new_string adds a bad H2 is denied; keeping an existing one is not" {
  with_ledger
  run_pre "$(pre_payload Edit "$WD/.context/testing-2.md" $'## Notes\nbody' 'old body')"
  assert_success
  [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<< "$output")" = deny ]
  [[ "$output" == *"(stage=QA)"* ]]
  run_pre "$(pre_payload Edit "$WD/.context/testing-2.md" $'## Notes\nnew body' $'## Notes\nold body')"
  assert_success
  assert_output ""
}

@test "pre: a stage's title-case optional is allowed there and denied in another stage" {
  with_ledger
  run_pre "$(pre_payload Write "$WD/.context/testing-0.md" $'## Visual Evidence\n')"
  assert_output ""
  run_pre "$(pre_payload Write "$WD/.context/developer-review-0.md" $'## Visual Evidence\n')"
  [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<< "$output")" = deny ]
}

@test "pre: an unreachable plugin root fails open" {
  with_ledger
  run env CLAUDE_PLUGIN_ROOT="/nonexistent_plugin_root_$$" bash "$PLUGIN_ROOT/$SCRIPT" \
    <<< "$(pre_payload Write "$WD/.context/development-0.md" $'## Approach\n')"
  assert_success
  assert_output ""
}

@test "pre: the Pre arm never runs the PostToolUse control-byte scan or lint" {
  with_ledger
  printf 'x\000\n' > "$WD/.context/development-0.md"
  run_pre "$(pre_payload Write "$WD/.context/development-0.md" $'## files-changed\n')"
  assert_success
  assert_output ""
}

@test "manifest: anchor-preflight is registered under PreToolUse Write|Edit and PostToolUse" {
  run jq -r '.hooks.PreToolUse[] | select(any(.hooks[]; .command | test("anchor-preflight"))) | .matcher' \
    "$PLUGIN_ROOT/.claude-plugin/plugin.json"
  assert_success
  assert_output "Write|Edit"
  run jq -r '.hooks.PostToolUse[] | select(any(.hooks[]; .command | test("anchor-preflight"))) | .matcher' \
    "$PLUGIN_ROOT/.claude-plugin/plugin.json"
  assert_output "Write|Edit"
}

@test "manifest: each registration names its event in argv" {
  run jq -r '[.hooks.PreToolUse[].hooks[], .hooks.PostToolUse[].hooks[]]
    | map(select(.command | test("anchor-preflight")) | (.args // []) | join(" ")) | join(",")' \
    "$PLUGIN_ROOT/.claude-plugin/plugin.json"
  assert_success
  assert_output "--event pre,--event post"
}

# The Pre call fires before the write, so a Post lint of the on-disk file must never gate it.
@test "event: no jq + a legacy file-path env var + --event pre exits 0; without --event it exits 2" {
  with_ledger
  printf 'no anchors\n' > "$WD/.context/development-0.md"
  run_script_env --hide jq --env "CLAUDE_PLUGIN_ROOT=$PLUGIN_ROOT" \
    --env "CLAUDE_TOOL_INPUT_FILE_PATH=$WD/.context/development-0.md" -- "$SCRIPT" --event pre
  assert_success
  assert_output ""
  run_script_env --hide jq --env "CLAUDE_PLUGIN_ROOT=$PLUGIN_ROOT" \
    --env "CLAUDE_TOOL_INPUT_FILE_PATH=$WD/.context/development-0.md" -- "$SCRIPT"
  assert_failure 2
}

@test "event: --event post lints a PreToolUse-shaped payload as Post; an unknown event fails open" {
  mkdir -p "$WD/.context"
  printf 'no anchors\n' > "$WD/.context/development-0.md"
  local payload
  payload="$(jq -cn --arg p "$WD/.context/development-0.md" '{hook_event_name:"PreToolUse", tool_input:{file_path:$p}}')"
  run env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/$SCRIPT" --event post <<< "$payload"
  assert_failure 2
  run env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/$SCRIPT" --event bogus <<< "$payload"
  assert_success
  assert_output ""
}

# RK-A1: an Edit is judged on new_string alone, so a heading the file keeps inside a fence
# still reads as an H2 and is denied; the reason carries the H3 workaround.
@test "pre: an Edit fragment that lands inside a fence in the file is still denied" {
  with_ledger
  printf '## files-changed\n\n```md\nold\n```\n' > "$WD/.context/development-0.md"
  run env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/$SCRIPT" --event pre \
    <<< "$(pre_payload Edit "$WD/.context/development-0.md" $'## Example\nold' 'old')"
  assert_success
  [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<< "$output")" = deny ] || fail "not denied: $output"
  [[ "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<< "$output")" == *"## Example."*"Nest other headings as H3." ]]
}

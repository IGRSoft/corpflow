#!/usr/bin/env bats
# acceptance-check.sh: QA may pass only when every DV acceptance command was executed with
# exit 0. The R1 fixture replays the benchmark failure — a byte-exact board contract that DV
# listed and QA never ran — and must come out no-go.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

CHECK="skills/worktask/scripts/acceptance-check.sh"

setup() {
  cd "$PLUGIN_ROOT"
  DV="$BATS_TEST_TMPDIR/development-0.md"
  QA="$BATS_TEST_TMPDIR/testing-0.md"
  cat > "$DV" <<'MD'
## verification-command

swift test

## acceptance-commands

```bash
# board rows keep one leading and one trailing space
printf 'x\n' | .build/debug/tictactoe --moves 1 | cmp - expected/board-1.txt
.build/debug/tictactoe --moves 1,2 | cmp - expected/board-2.txt
```

## decisions

none
MD
}

qa_with() {
  { printf '## summary\n\nok\n\n## acceptance-commands\n\n'; printf '%s\n' "$@"; printf '\n## notes\n\n- exit=0 ignored outside the anchor\n'; } > "$QA"
}

@test "R1 replay: QA ran no acceptance command -> no-go" {
  printf '## summary\n\nswift test: 48 passed\n' > "$QA"
  run bash "$CHECK" --qa "$QA" --dv "$DV"
  [ "$status" -eq 1 ]
  assert_line --index 0 "acceptance: 0/2 executed, 0 failed"
  assert_line --partial "missing: .build/debug/tictactoe --moves 1,2 | cmp - expected/board-2.txt"
}

@test "every command executed with exit 0 -> pass" {
  qa_with "- exit=0 printf 'x\n' | .build/debug/tictactoe --moves 1 | cmp - expected/board-1.txt" \
          "- exit=0 \`.build/debug/tictactoe --moves 1,2 | cmp - expected/board-2.txt\`"
  run bash "$CHECK" --qa "$QA" --dv "$DV"
  [ "$status" -eq 0 ]
  assert_output "acceptance: 2/2 executed, 0 failed"
}

@test "an executed command that failed -> no-go" {
  qa_with "- exit=0 printf 'x\n' | .build/debug/tictactoe --moves 1 | cmp - expected/board-1.txt" \
          "- exit=1 .build/debug/tictactoe --moves 1,2 | cmp - expected/board-2.txt"
  run bash "$CHECK" --qa "$QA" --dv "$DV"
  [ "$status" -eq 1 ]
  assert_line --partial "failed: .build/debug/tictactoe --moves 1,2"
}

@test "rows outside the QA anchor do not count" {
  qa_with "- exit=0 printf 'x\n' | .build/debug/tictactoe --moves 1 | cmp - expected/board-1.txt"
  printf -- '- exit=0 .build/debug/tictactoe --moves 1,2 | cmp - expected/board-2.txt\n' >> "$QA"
  run bash "$CHECK" --qa "$QA" --dv "$DV"
  [ "$status" -eq 1 ]
  assert_line --index 0 "acceptance: 1/2 executed, 0 failed"
}

@test "no acceptance-commands in any DV artifact -> pass with 0/0" {
  printf '## decisions\n\nnone\n' > "$DV"
  printf '## summary\n\nok\n' > "$QA"
  run bash "$CHECK" --qa "$QA" --dv "$DV"
  [ "$status" -eq 0 ]
  assert_output "acceptance: 0/0 executed, 0 failed"
}

@test "commands union across DV artifacts, duplicates counted once" {
  DV2="$BATS_TEST_TMPDIR/development-1.md"
  cp "$DV" "$DV2"
  qa_with "- exit=0 printf 'x\n' | .build/debug/tictactoe --moves 1 | cmp - expected/board-1.txt"
  run bash "$CHECK" --qa "$QA" --dv "$DV" --dv "$DV2"
  [ "$status" -eq 1 ]
  assert_line --index 0 "acceptance: 1/2 executed, 0 failed"
}

@test "usage errors exit 2" {
  run bash "$CHECK" --dv "$DV"
  [ "$status" -eq 2 ]
  run bash "$CHECK" --qa "$QA"
  [ "$status" -eq 2 ]
  run bash "$CHECK" --qa /nonexistent --dv "$DV"
  [ "$status" -eq 2 ]
}

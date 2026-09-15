#!/usr/bin/env bats
# The four capture adapters inline _task_id_ok, _field_ok and _next_nn instead of sharing a lib;
# this suite keeps the copies identical and pins _next_nn's numbering rules once.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

ADAPTERS=(
  skills/dv-screenshot-capture/scripts/web-capture.sh
  skills/dv-screenshot-capture/scripts/android-capture.sh
  skills/dv-screenshot-capture/scripts/apple-canvas.sh
  skills/dv-screenshot-capture/scripts/cli-fallback.sh
)
LADDER_SCRIPTS=(
  "${ADAPTERS[@]}"
  skills/dv-screenshot-capture/scripts/size-budget.sh
  skills/dv-screenshot-capture/scripts/visual-diff.sh
)

fn_body() { # <script> <function>
  awk -v fn="$2" '$0 == fn "() {" { p = 1 } p { print } p && $0 == "}" { exit }' "$PLUGIN_ROOT/$1"
}

@test "each helper is present and byte-identical across the four adapters" {
  local fn first a body
  for fn in _task_id_ok _field_ok _next_nn; do
    first="$(fn_body "${ADAPTERS[0]}" "$fn")"
    [ -n "$first" ] || fail "$fn missing from ${ADAPTERS[0]}"
    for a in "${ADAPTERS[@]}"; do
      body="$(fn_body "$a" "$fn")"
      [ "$body" = "$first" ] || fail "$fn in $a differs from ${ADAPTERS[0]}"
    done
  done
}

@test "the task-id grammar literal is the contract's" {
  run fn_body "${ADAPTERS[0]}" _task_id_ok
  assert_output --partial "local re='^[A-Z]{2}[0-9]+\$'"
}

@test "every capture script resolves .context through the ladder, never a cwd-relative path" {
  local s
  for s in "${LADDER_SCRIPTS[@]}"; do
    grep -q 'corpflow_context_dir' "$PLUGIN_ROOT/$s" || fail "$s does not call corpflow_context_dir"
    if grep -nE '^[[:space:]]*(IMAGES_DIR|LOGS_DIR|ERRORS_DIR)="\.context|PROJECT_ROOT="\$\(pwd\)"' "$PLUGIN_ROOT/$s"; then
      fail "$s still builds a cwd-relative path"
    fi
  done
}

@test "_next_nn: per task, max not count, decimal 08/09, oversize and manifest rows, 99 cap" {
  local d
  d="$(mk_tmpworkdir)"
  fn_body "${ADAPTERS[0]}" _next_nn > "$d/fn.sh"
  # shellcheck source=/dev/null
  . "$d/fn.sh"
  mkdir -p "$d/img/oversize"

  assert_equal "$(_next_nn "$d/img" DV0)" '01'
  printf 'x' > "$d/img/dv-DV0-01-a.png"
  printf 'x' > "$d/img/dv-DV0-08-b.png"
  assert_equal "$(_next_nn "$d/img" DV0)" '09'
  assert_equal "$(_next_nn "$d/img" DV1)" '01'
  printf 'x' > "$d/img/oversize/dv-DV0-09-big.png"
  assert_equal "$(_next_nn "$d/img" DV0)" '10'
  printf '| 12 | row | dv-DV0-12-row.png |\n' > "$d/img/screenshots-DV0.md"
  assert_equal "$(_next_nn "$d/img" DV0)" '13'
  printf 'x' > "$d/img/dv-DV10-05-c.png"
  assert_equal "$(_next_nn "$d/img" DV1)" '01'
  printf 'x' > "$d/img/dv-DV2-99-last.png"
  run _next_nn "$d/img" DV2
  assert_failure 1
}

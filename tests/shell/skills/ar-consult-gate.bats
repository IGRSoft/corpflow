#!/usr/bin/env bats
# Pins agents/software-architector.md § Consult Gate (AR): the platform-architect consult opens
# at the first score of the estimation table's Moderate tier, and the open path dispatches on
# Sonnet with a capped return. Both sides are read from their defining files, never hardcoded.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

ARCH="agents/software-architector.md"
EST="skills/estimation-methodology/SKILL.md"
HANDOFF="skills/cross-plugin-handoff/SKILL.md"

# Body of one markdown section: from its heading to the next heading of any level.
section() {
  awk -v h="$2" 'index($0, h) == 1 { on = 1; next } on && /^#/ { exit } on { print }' "$1"
}

# Lower bound of the Moderate row in the stage-set table, e.g. "21".
moderate_floor() {
  awk -F'|' '$3 ~ /Moderate/ { gsub(/ /, "", $2); split($2, r, "–"); print r[1]; exit }' "$1"
}

gate_floor() {
  section "$1" "#### Consult Gate (AR)" | grep -oE '≥ ?[0-9]+' | head -1 | tr -dc '0-9'
}

@test "gate floor equals the Moderate tier floor" {
  cd "$PLUGIN_ROOT"
  want="$(moderate_floor "$EST")"
  got="$(gate_floor "$ARCH")"
  [ -n "$want" ] && [ "$got" = "$want" ]
}

@test "gate floor check fails on a planted Medium floor" {
  cd "$PLUGIN_ROOT"
  planted="$BATS_TEST_TMPDIR/arch.md"
  sed 's/Moderate+ (≥ 21/Medium+ (≥ 11/' "$ARCH" > "$planted"
  [ "$(gate_floor "$planted")" != "$(moderate_floor "$EST")" ]
}

@test "the old Low-only gate heading is gone" {
  cd "$PLUGIN_ROOT"
  ! grep -q "Low-Complexity Gate" "$ARCH"
}

@test "open gate dispatches on sonnet with a capped return" {
  cd "$PLUGIN_ROOT"
  section "$ARCH" "### Delegation Flow" | grep -q 'model: "sonnet"'
  section "$ARCH" "### Delegation Flow" | grep -q '≤300 tokens'
  grep -q 'model: "sonnet"' "$HANDOFF"
  grep -q 'max 300 tokens' "$HANDOFF"
}

@test "completion checklist keys on the gate, not the tier" {
  cd "$PLUGIN_ROOT"
  section "$ARCH" "## Completion Verification" | grep -q "Consult Gate (AR)"
}

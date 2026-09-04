#!/usr/bin/env bash
# detect-ui-change-selftest.sh — the `--self-test` harness for detect-ui-change.sh.
#
# SOURCED, never executed: detect-ui-change.sh loads this file only on the `--self-test`
# path, so the production path never pays for it. Sourcing leaves the caller's
# `$0` and every function it has already defined in scope — this file reads the
# caller's helpers and is not standalone.
#
# Contract: defines `run_self_tests`, returning 0 when every case passes.

# ---------- self-test -------------------------------------------------------
run_self_tests() {
  local pass=0 fail=0 td out
  td=$(mktemp -d 2>/dev/null || echo "/tmp/detect-ui-change.$$")
  mkdir -p "$td/.context/designs"

  _assert() { # $1=label $2=expected-bool $3=actual-json
    local got; got=$(printf '%s' "$3" | jq -r '.requires_screenshots' 2>/dev/null)
    if [ "$got" = "$2" ]; then
      echo "detect-ui-change: $1 PASS (requires_screenshots=$got)"; pass=$((pass+1))
    else
      echo "detect-ui-change: $1 FAIL (want=$2 got=$got json=$3)"; fail=$((fail+1))
    fi
  }

  # t1 — UI-scoped plan via S3 keyword → true.
  cat > "$td/ui.md" <<'MD'
---
ui_visual_check: false
---
# Plan
## requirements
- REQ-1: add a new SwiftUI view with custom layout and animation
## scope
In: Views/Settings. Out: backend.
MD
  out=$(DESIGNS_DIR="$td/.context/designs" bash "$0" "$td/ui.md" --platform apple)
  _assert "t1-keyword-S3" true "$out"

  # t2 — non-UI plan → false.
  cat > "$td/nonui.md" <<'MD'
---
ui_visual_check: false
---
# Plan
## requirements
- REQ-1: refactor the bash audit helper and tighten jq parsing
## scope
In: skills/worktask/references. Out: any UI.
MD
  out=$(DESIGNS_DIR="$td/.context/designs" bash "$0" "$td/nonui.md" --platform all)
  _assert "t2-non-ui" false "$out"

  # t3 — S1 invariant: ui_visual_check:true forces true even with no keywords.
  cat > "$td/s1.md" <<'MD'
---
ui_visual_check: true
---
# Plan
## requirements
- REQ-1: pure backend rewrite, no visuals
## scope
In: server. Out: client.
MD
  out=$(DESIGNS_DIR="$td/.context/designs" bash "$0" "$td/s1.md" --platform all)
  _assert "t3-S1-invariant" true "$out"
  if printf '%s' "$out" | jq -e '.signals | index("S1")' >/dev/null 2>&1; then
    echo "detect-ui-change: t3-S1-signal PASS"; pass=$((pass+1))
  else
    echo "detect-ui-change: t3-S1-signal FAIL (S1 not in signals: $out)"; fail=$((fail+1))
  fi

  # t4 — fail-safe: missing plan file → true.
  out=$(DESIGNS_DIR="$td/.context/designs" bash "$0" "$td/does-not-exist.md" --platform all)
  _assert "t4-fail-safe" true "$out"
  if printf '%s' "$out" | grep -q 'fail_safe_default'; then
    echo "detect-ui-change: t4-fail-safe-reason PASS"; pass=$((pass+1))
  else
    echo "detect-ui-change: t4-fail-safe-reason FAIL ($out)"; fail=$((fail+1))
  fi

  # t5 — S4 path-class match (platform apple + Views/ path) with no S3 keyword.
  cat > "$td/s4.md" <<'MD'
---
ui_visual_check: false
---
# Plan
## requirements
- REQ-1: relocate files under Views/Profile/ for tidiness
## scope
In: Views/Profile. Out: nothing visual described in words.
MD
  out=$(DESIGNS_DIR="$td/.context/designs" bash "$0" "$td/s4.md" --platform apple)
  _assert "t5-S4-pathclass" true "$out"

  # t6 — S2 design artifact present forces true on an otherwise non-UI plan.
  cp /dev/null "$td/.context/designs/figma-registry.md"
  out=$(DESIGNS_DIR="$td/.context/designs" bash "$0" "$td/nonui.md" --platform all)
  _assert "t6-S2-designs" true "$out"

  # t7 — S4 on Android: an Android UI path with no S3 keyword in the prose. This
  # is the case that used to return false and skip capture entirely.
  cat > "$td/android-path.md" <<'MD'
---
ui_visual_check: false
---
# Plan
## requirements
- REQ-1: move the profile package under app/src/main/java/com/acme/ui/Profile.kt
## scope
In: app/src/main/java/com/acme/ui/Profile.kt. Out: server.
MD
  out=$(DESIGNS_DIR="$td/.context/designs.absent" bash "$0" "$td/android-path.md" --platform android)
  _assert "t7-android-S4-pathclass" true "$out"

  # t8 — S3 on Android: Compose vocabulary with no path class named.
  cat > "$td/android-kw.md" <<'MD'
---
ui_visual_check: false
---
# Plan
## requirements
- REQ-1: add a Composable for the profile summary
## scope
In: profile feature. Out: networking.
MD
  out=$(DESIGNS_DIR="$td/.context/designs.absent" bash "$0" "$td/android-kw.md" --platform android)
  _assert "t8-android-S3-keyword" true "$out"

  rm -rf "$td"
  echo "detect-ui-change: self-test summary — pass=$pass fail=$fail"
  [ "$fail" -eq 0 ]
}

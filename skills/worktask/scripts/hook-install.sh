#!/usr/bin/env bash
# hook-install.sh — Idempotent installer for the state-merge.sh SubagentStop hook.
#
# Copies state-merge.sh from the plugin's hooks/ to the project's .claude/hooks/
# and verifies the plugin.json registration. Safe to re-run.
#
# An existing but non-executable destination is overwritten, so it is first saved to
# state-merge.sh.bak — a single slot rewritten on each overwrite, never accumulated.
#
# Usage:
#   hook-install.sh                 # install hook
#   hook-install.sh --self-test     # run self-test in a scratch dir
#   hook-install.sh --check         # verify installation without modifying
#
# Env:
#   CLAUDE_PLUGIN_ROOT — plugin install directory (auto-discovered if unset)

set -euo pipefail

# ---------- Plugin root discovery ----------
# Located from $(dirname "$0") like every sibling resolution this script already does.
# `[ -r ]` first, not a bare `.`: sourcing a missing file with the `.` builtin is a
# special-builtin error that exits a `set -e` shell immediately, bypassing an
# `if ! . …; then` guard entirely.
_CORPFLOW_BASE="$(dirname "$0")/../../shared/lib/corpflow-base.sh"
if [[ -r "$_CORPFLOW_BASE" ]]; then
  # shellcheck source=skills/shared/lib/corpflow-base.sh
  . "$_CORPFLOW_BASE"
else
  printf >&2 'hook-install.sh: corpflow-base.sh unreachable at %s — plugin install broken\n' \
    "$_CORPFLOW_BASE"
  exit 3
fi

# The env rung stays at the call sites, deliberately unvalidated: an explicit override
# must win whether or not the tree it names carries the marker, and the allowlist that
# pins which files may read the variable can only see it here.
_plugin_root() {
  if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
    echo "$CLAUDE_PLUGIN_ROOT"
    return 0
  fi
  corpflow_plugin_root
}

# ---------- Check mode ----------
check_installation() {
  local rc=0
  if [[ -x ".claude/hooks/state-merge.sh" ]]; then
    echo "check: .claude/hooks/state-merge.sh exists and is executable ✓"
  else
    echo "check: .claude/hooks/state-merge.sh MISSING or not executable" >&2
    rc=1
  fi

  local plugin_root
  if plugin_root=$(_plugin_root); then
    if grep -q 'state-merge\.sh' "$plugin_root/.claude-plugin/plugin.json" 2>/dev/null; then
      echo "check: plugin.json registers state-merge.sh SubagentStop hook ✓"
    else
      echo "check: plugin.json does NOT register state-merge.sh" >&2
      rc=1
    fi
  else
    echo "check: cannot locate plugin root (CLAUDE_PLUGIN_ROOT unset)" >&2
    rc=1
  fi
  return $rc
}

# ---------- Install ----------
install_hook() {
  local plugin_root
  if ! plugin_root=$(_plugin_root); then
    echo "install: ERROR — cannot locate plugin root. Set CLAUDE_PLUGIN_ROOT." >&2
    return 1
  fi

  local src="$plugin_root/hooks/state-merge.sh"
  local dst=".claude/hooks/state-merge.sh"

  if [[ ! -f "$src" ]]; then
    echo "install: ERROR — source not found: $src" >&2
    return 1
  fi

  if [[ -x "$dst" ]]; then
    echo "install: $dst already installed (idempotent — no-op)"
  else
    mkdir -p .claude/hooks
    # A non-executable $dst is typically a hand-customized copy or a partial write; the
    # .bak (not .sh) suffix keeps the rescue out of the `.claude/hooks/*.sh` live-hook globs.
    if [[ -e "$dst" ]]; then
      cp "$dst" "$dst.bak"
      echo "install: backed up existing $dst → $dst.bak"
    fi
    cp "$src" "$dst"
    chmod +x "$dst"
    echo "install: copied $src → $dst"
  fi

  if grep -q 'state-merge\.sh' "$plugin_root/.claude-plugin/plugin.json" 2>/dev/null; then
    echo "install: plugin.json hook registration verified ✓"
  else
    echo "install: WARNING — plugin.json does not register state-merge.sh. The hook will only work if invoked manually by the orchestrator (Step 6.5)." >&2
  fi
}

# ---------- Self-test ----------
self_test() {
  local self_path
  self_path="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  local td
  td=$(mktemp -d -t hook-install-XXXXXX)
  trap "rm -rf '$td'" EXIT

  mkdir -p "$td/plugin/hooks" "$td/plugin/.claude-plugin"
  cat > "$td/plugin/hooks/state-merge.sh" <<'HOOK'
#!/usr/bin/env bash
echo "state-merge stub"
HOOK
  chmod +x "$td/plugin/hooks/state-merge.sh"

  cat > "$td/plugin/.claude-plugin/plugin.json" <<'JSON'
{"name":"test","hooks":{"SubagentStop":[{"hooks":[{"type":"command","command":"state-merge.sh"}]}]}}
JSON

  local project="$td/project"
  mkdir -p "$project"
  cd "$project"

  # Test 1: fresh install
  CLAUDE_PLUGIN_ROOT="$td/plugin" "$self_path" 2>&1
  if [[ -x ".claude/hooks/state-merge.sh" ]]; then
    echo "self-test: fresh install: ok"
  else
    echo "self-test: fresh install: FAIL" >&2; exit 1
  fi

  # Test 2: idempotent re-run
  local out
  out=$(CLAUDE_PLUGIN_ROOT="$td/plugin" "$self_path" 2>&1)
  if echo "$out" | grep -q "idempotent"; then
    echo "self-test: idempotent re-run: ok"
  else
    echo "self-test: idempotent re-run: FAIL" >&2; exit 1
  fi

  # Test 3: check mode
  if CLAUDE_PLUGIN_ROOT="$td/plugin" "$self_path" --check >/dev/null 2>&1; then
    echo "self-test: check mode (installed): ok"
  else
    echo "self-test: check mode (installed): FAIL" >&2; exit 1
  fi

  # Test 4: check mode detects missing
  rm -f .claude/hooks/state-merge.sh
  if CLAUDE_PLUGIN_ROOT="$td/plugin" "$self_path" --check >/dev/null 2>&1; then
    echo "self-test: check mode (missing): FAIL (should have failed)" >&2; exit 1
  else
    echo "self-test: check mode (missing): ok"
  fi

  # Test 5: a non-executable dst is backed up, not silently destroyed
  if [[ -e ".claude/hooks/state-merge.sh.bak" ]]; then
    echo "self-test: backup on overwrite: FAIL (fresh install left a stray .bak)" >&2; exit 1
  fi
  printf 'CUSTOMIZED\n' > .claude/hooks/state-merge.sh
  chmod -x .claude/hooks/state-merge.sh
  CLAUDE_PLUGIN_ROOT="$td/plugin" "$self_path" >/dev/null 2>&1
  if [[ -f ".claude/hooks/state-merge.sh.bak" ]] \
     && [[ "$(cat .claude/hooks/state-merge.sh.bak)" == "CUSTOMIZED" ]]; then
    echo "self-test: backup on overwrite: ok"
  else
    echo "self-test: backup on overwrite: FAIL" >&2; exit 1
  fi

  echo "self-test: ALL PASS"
}

# ---------- main ----------
case "${1:-}" in
  --check)     check_installation ;;
  --self-test) self_test ;;
  -h|--help)
    sed -n 's/^# \{0,1\}//p' "$0" | sed -n '1,/^$/p'
    exit 0
    ;;
  *)           install_hook ;;
esac

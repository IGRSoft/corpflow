#!/usr/bin/env bash
# hook-install.sh — Idempotent installer for the state-merge.sh SubagentStop hook.
#
# Copies state-merge.sh from the plugin install directory to .claude/hooks/
# and verifies the plugin.json registration. Safe to re-run.
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
find_plugin_root() {
  if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
    echo "$CLAUDE_PLUGIN_ROOT"
    return 0
  fi
  local candidate
  for candidate in \
    "$(cd "$(dirname "$0")/../../.." 2>/dev/null && pwd)" \
    "$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)"; do
    if [[ -f "$candidate/.claude-plugin/plugin.json" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
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
  if plugin_root=$(find_plugin_root); then
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
  if ! plugin_root=$(find_plugin_root); then
    echo "install: ERROR — cannot locate plugin root. Set CLAUDE_PLUGIN_ROOT." >&2
    return 1
  fi

  local src="$plugin_root/.claude/hooks/state-merge.sh"
  local dst=".claude/hooks/state-merge.sh"

  if [[ ! -f "$src" ]]; then
    echo "install: ERROR — source not found: $src" >&2
    return 1
  fi

  if [[ -x "$dst" ]]; then
    echo "install: $dst already installed (idempotent — no-op)"
  else
    mkdir -p .claude/hooks
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

  mkdir -p "$td/plugin/.claude/hooks" "$td/plugin/.claude-plugin"
  cat > "$td/plugin/.claude/hooks/state-merge.sh" <<'HOOK'
#!/usr/bin/env bash
echo "state-merge stub"
HOOK
  chmod +x "$td/plugin/.claude/hooks/state-merge.sh"

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

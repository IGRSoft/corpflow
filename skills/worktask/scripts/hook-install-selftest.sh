#!/usr/bin/env bash
# hook-install-selftest.sh — the `--self-test` harness for hook-install.sh.
#
# SOURCED, never executed: hook-install.sh loads this file only on the `--self-test`
# path, so the production path never pays for it. Sourcing leaves the caller's
# `$0` and every function it has already defined in scope — this file reads the
# caller's helpers and is not standalone.
#
# Contract: defines `self_test`, returning 0 when every case passes.

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
  cd "$project" || exit 1

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

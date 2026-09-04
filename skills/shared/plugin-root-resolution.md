---
name: plugin-root-resolution
---

# Plugin-Root Resolution (provider-agnostic)

**Definition**: the directory containing `.claude-plugin/plugin.json` for the corpflow
plugin. Known layouts: the Claude Code cache
`~/.claude/plugins/cache/igrsoft/corpflow/<version>/` — **version-keyed, never hardcode
it**; a plain git clone, where it is the repository root; or wherever another harness
installed the plugin directory.

## Why `CLAUDE_PLUGIN_ROOT` alone is not enough

`CLAUDE_PLUGIN_ROOT` is a Claude Code-only mechanism with two distinct behaviors:

1. Claude Code **textually substitutes** the exact bare token (dollar-brace form) when it
   loads skill/command content and when it parses hook `command:` strings in
   `plugin.json` / agent frontmatter.
2. It is **exported as an environment variable only to hook subprocesses** — it is NOT
   set in the model's Bash tool environment.

So the token resolves only when Claude Code itself loads or launches the file. It is
literal and dead whenever a subagent `Read`s a plugin file from disk, when a snippet is
copy-pasted into another prompt, or when a non-Claude-Code harness consumes these skills.
Every path convention below must work in all three states: substituted, expanded-to-empty,
and literal prose.

## Resolution ladder

1. **`$CLAUDE_PLUGIN_ROOT` when actually set in the executing shell** — true for hook
   subprocesses and for tests that export it. An explicitly set value always wins (tests
   rely on this override contract).
2. **Skill base directory, minus `/skills/<name>`** — every agent-skills harness announces
   "Base directory for this skill: `<path>`" on load. For any corpflow skill that path is
   `<plugin-root>/skills/<name>`, so the root is two levels up.

### Rungs 3–4 and validation

3. **Read-path derivation** — a file you `Read` from disk gives you its absolute path: walk
   up to the nearest ancestor containing `.claude-plugin/plugin.json`.
4. **Claude Code cache last resort** (CC installs only):
   `ls -d ~/.claude/plugins/cache/igrsoft/corpflow/*/ 2>/dev/null | sort -V | tail -1`
   — may be stale if an older version is pinned, so validate before trusting.

**Always validate** a candidate: `[ -f "$PLUGIN_ROOT/.claude-plugin/plugin.json" ]`.

## Canonical executable-snippet shape (markdown)

Fenced snippets that call bundled helpers use this preamble, keeping their existing `-f`
guard and audit-deferral bodies unchanged:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"  # Claude Code substitutes this token when loading this file
# Empty? Substitute <plugin-root>: the dir containing .claude-plugin/plugin.json —
# two levels above this skill's base directory (see skills/shared/plugin-root-resolution.md).
[ -d "$PLUGIN_ROOT" ] || PLUGIN_ROOT="<plugin-root>"
HELPER="$PLUGIN_ROOT/skills/<skill>/scripts/<helper>.sh"
```

### Why this shape

Under Claude Code the first line is substituted at load time and the fallback is dead code.
Everywhere else the unset variable expands to empty, the `-d` test fails, and the executor
substitutes `<plugin-root>` via the ladder above (it knows either the skill base directory
or the path it read the file from). If the placeholder is pasted verbatim, the downstream
`-f` guard fails exactly like today's unresolved paths — graceful deferral, never a hard
error.

## Author rules

### Markdown token form

- **Markdown may contain the token only in its exact bare dollar-brace form** — never
  compose a longer path by appending a slash and segments after the closing brace, and
  never use the shell default-value (colon-dash) form inside the braces. Composition breaks
  the moment the token is not substituted; the default-value form forfeits load-time
  substitution and risks mangled output from partial matchers. Whitelisted exceptions, all
  Claude Code-native config parsed only by Claude Code: the `hooks` block of
  `.claude-plugin/plugin.json`, `hooks:` entries in agent frontmatter, and verbatim
  documentation of those entries (`skills/worktask/references/handoff-protocol.md`).

### Prose and shell-script paths

- **Prose instructions** write helper paths plugin-root-relative (e.g.
  `hooks/megatask-monitor.sh`) followed by: "(plugin root: `${CLAUDE_PLUGIN_ROOT}` if
  available, else resolve per `skills/shared/plugin-root-resolution.md`)".
- **Shell scripts** (never load-substituted, only executed) use env-first with a
  self-location fallback validated against the `.claude-plugin/plugin.json` marker. There is
  now **one** resolver, not a family of reference implementations: `corpflow_script_dir()`
  and `corpflow_plugin_root()` in `skills/shared/lib/corpflow-base.sh` (mirrored
  byte-identically into `hooks/lib/corpflow-base.sh` — see that file's `MIRRORED, NOT
  SHARED` header and the parity test `tests/shell/skills/corpflow-base.bats`). Source it and
  call `corpflow_plugin_root` rather than reimplementing the walk; the previous doc named
  three "reference implementations" that were three *different*, disagreeing
  implementations, and only 4 of 69 scripts in the repo actually followed this rule before
  the library existed.

### Tests

- **Tests** may set or unset the env var freely to exercise the override and fallback
  contracts (`tests/shell/worktask/hook-install.bats`,
  `tests/shell/dv-screenshot/apple-canvas.bats`,
  `tests/shell/hooks/anchor-preflight.bats`).

## Acceptance check (run before merging path changes)

`tests/shell/skills/plugin-root-refs.bats` codifies both greps:

- Token-plus-slash composition in `*.md` → only the whitelisted config/doc lines.
- Default-value (colon-dash) form of the token in `*.md` → zero occurrences.

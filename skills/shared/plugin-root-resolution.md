---
name: plugin-root-resolution
description: Canonical, provider-agnostic rule for resolving the igrsoft plugin root. Use when a skill, agent, command, or script must locate bundled helpers (hooks/, skills/*/scripts/) and CLAUDE_PLUGIN_ROOT may be unavailable.
---

# Plugin-Root Resolution (provider-agnostic)

**Definition**: the plugin root is the directory containing `.claude-plugin/plugin.json`
for the igrsoft plugin. Known layouts:

- Claude Code cache: `~/.claude/plugins/cache/igrsoft/igrsoft/<version>/` — **version-keyed;
  never hardcode** a versioned path.
- Plain git clone: the repository root.
- Any other harness: wherever it installed the plugin directory.

## Why `CLAUDE_PLUGIN_ROOT` alone is not enough

`CLAUDE_PLUGIN_ROOT` is a Claude Code-only mechanism with two distinct behaviors:

1. Claude Code **textually substitutes** the exact bare token (dollar-brace form) when it
   loads skill/command content and when it parses hook `command:` strings in
   `plugin.json` / agent frontmatter.
2. It is **exported as an environment variable only to hook subprocesses** — it is NOT
   set in the model's Bash tool environment.

So the token resolves only when Claude Code itself loads or launches the file. It is
literal (and dead) whenever a subagent `Read`s a plugin file from disk, when a snippet
is copy-pasted into another prompt, or when any non-Claude-Code harness consumes these
skills. Every path convention below must therefore work in all three states:
substituted, expanded-to-empty, and literal prose.

## Resolution ladder

Resolve the plugin root by trying, in order:

1. **`$CLAUDE_PLUGIN_ROOT` when actually set in the executing shell** — true for Claude
   Code hook subprocesses and for tests that export it. An explicitly set value always
   wins (tests rely on this override contract).
2. **Skill base directory, minus `/skills/<name>`** — every agent-skills harness
   (Claude Code included) announces "Base directory for this skill: `<path>`" when a
   skill loads. For any igrsoft skill that path is `<plugin-root>/skills/<name>`, so the
   plugin root is two directory levels up.

### Rungs 3–4 and validation

3. **Read-path derivation** — if you `Read` any plugin file from disk you know its
   absolute path: walk up to the nearest ancestor directory containing
   `.claude-plugin/plugin.json`.
4. **Claude Code cache last resort** (CC installs only):
   `ls -d ~/.claude/plugins/cache/igrsoft/igrsoft/*/ 2>/dev/null | sort -V | tail -1`
   — may be stale if an older version is pinned, so validate before trusting.

**Always validate** a candidate: `[ -f "$PLUGIN_ROOT/.claude-plugin/plugin.json" ]`.

## Canonical executable-snippet shape (markdown)

Fenced snippets in skills/commands that call bundled helpers use this preamble, keeping
their existing `-f` guard and audit-deferral bodies unchanged:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"  # Claude Code substitutes this token when loading this file
# Empty? Substitute <plugin-root>: the dir containing .claude-plugin/plugin.json —
# two levels above this skill's base directory (see skills/shared/plugin-root-resolution.md).
[ -d "$PLUGIN_ROOT" ] || PLUGIN_ROOT="<plugin-root>"
HELPER="$PLUGIN_ROOT/skills/<skill>/scripts/<helper>.sh"
```

### Why this shape

Under Claude Code the first line is substituted at load time and the
fallback is dead code; everywhere else the unset variable expands to empty, the `-d`
test fails, and the executor substitutes `<plugin-root>` using the ladder above (it
knows the skill base directory or the path it read the file from). If the placeholder
is pasted verbatim, the downstream `-f` guard fails exactly like today's unresolved
paths — graceful deferral, never a hard error.

## Author rules

### Markdown token form

- **Markdown may contain the token only in its exact bare dollar-brace form** — never
  compose a longer path by appending a slash and segments after the closing brace, and
  never use the shell default-value form (colon-dash) inside the braces. Composition
  breaks the moment the token is not substituted; the default-value form both forfeits
  Claude Code's load-time substitution and risks mangled output from partial matchers.
  Whitelisted exceptions (they are Claude Code-native config, parsed only by Claude
  Code): the `hooks` block of `.claude-plugin/plugin.json`, `hooks:` entries in agent
  frontmatter, and verbatim documentation of those entries
  (`skills/worktask/references/handoff-protocol.md`).

### Prose and shell-script paths

- **Prose instructions** write helper paths plugin-root-relative (e.g.
  `hooks/audit-dedup.sh --check-mode`) followed by:
  "(plugin root: `${CLAUDE_PLUGIN_ROOT}` if available, else resolve per
  `skills/shared/plugin-root-resolution.md`)".
- **Shell scripts** (never load-substituted, only executed) use env-first with a
  self-location fallback validated against the `.claude-plugin/plugin.json` marker.
  Reference implementations: `find_plugin_root()` in
  `skills/worktask/scripts/hook-install.sh` (gold standard),
  `skills/dv-screenshot-capture/scripts/apple-canvas.sh` (one-liner form),
  `hooks/anchor-preflight.sh` (hook variant).

### Tests

- **Tests** may set or unset the env var freely to exercise the override and fallback
  contracts (`tests/shell/worktask/hook-install.bats`,
  `tests/shell/dv-screenshot/apple-canvas.bats`,
  `tests/shell/hooks/anchor-preflight.bats`).

## Acceptance check (run before merging path changes)

`tests/shell/skills/plugin-root-refs.bats` codifies both greps:

- Token-plus-slash composition in `*.md` → only the whitelisted config/doc lines.
- Default-value (colon-dash) form of the token in `*.md` → zero occurrences.

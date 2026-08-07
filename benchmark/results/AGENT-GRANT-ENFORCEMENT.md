# Do agent frontmatter grants bind in headless dispatch?

**Status:** partially answered from stored evidence; the open half needs a live
probe that has not been run. Investigation only — nothing in the plugin changed
on the strength of this document.

**Source:** `results/runs/live/live-20260807T114444Z-a0cdb43.json` and the 14 stage
transcripts under `workdirs/live-20260807T114444Z-a0cdb43/captures/`. The WITH arm
dispatches `claude -p --agent company-workflow:<agent> --permission-mode
bypassPermissions --settings live/settings/benchmark-settings.json`, which is how
worktask stages run in production too.

## Why it matters

`CLAUDE.md` treats tool grants as a control: *"No build tooling at the
orchestrator — never re-add `mcp__XcodeBuildMCP__*` grants to a stage agent."*
Several agents narrow `Bash` deliberately; `agents/product-manager.md:9-14` spends
six comment lines justifying why its grant is `Bash(curl:*)` and `Bash(mkdir:*)`
rather than bare `Bash`. If those narrowings do not bind under the mode stages
actually run in, the reasoning is decorative.

## Method

Each capture's `system`/`init` event records the tool list the session was given.
Comparing that against the agent's declared `tools:`, and the transcript's actual
`tool_use` calls against both, answers the question directly. Nested calls carry
`parent_tool_use_id` and belong to a spawned subagent, not to the stage agent.

## Finding 1 — tool *sets* are enforced

| stage | agent | `Bash` in declared `tools:` | `Bash` in session tool list | own tools outside the grant |
|---|---|---|---|---|
| PL | product-manager | scoped only | yes | none |
| AR | software-architector | no | **no** | none |
| TL | team-lead | no | **no** | none |
| DV | developer | yes | yes | none |

Every WITH-arm stage used only tools it was granted. AR and TL were handed a
session with no `Bash` at all, matching their frontmatter. The WITHOUT arm, which
dispatches bare, got the full 189-tool set — the expected contrast.

**Correction.** An earlier pass of this analysis reported that
`software-architector` "ran 6 Bash calls with no Bash grant." That was wrong: all
six carry `parent_tool_use_id`, so they belong to the platform architect subagent
the stage spawned via `Task`, which has its own grants. Attributing a subagent's
calls to its parent produced a violation that does not exist. AR's own calls were
1 `Agent`, 1 `Glob`, 5 `Read`, 2 `Write` — entirely within its grant.

## Finding 2 — `Bash` command scoping is NOT enforced

`agents/product-manager.md` declares:

```
tools: Read, Glob, Grep, Write, Edit, Bash(curl:*), Bash(mkdir:*), …
```

The PL session's tool list contains plain `Bash`. Of the 17 Bash calls PL made,
**zero** match the allow-list:

```
bash  cat  find  for  grep  ls  python3  sed
```

including `find / -maxdepth 8 -path "*company-workflow*/skills/…"` and a
heredoc-fed `python3`. The scoping collapsed to unrestricted `Bash`.

The benchmark's own deny-list (`live/settings/benchmark-settings.json`) blocks
`Bash(curl:*)` — the one thing PM was actually granted — so under these settings
PM should have been able to run `mkdir` and nothing else.

## Finding 3 — `maxTurns` did not bind for DV

`agents/developer.md` declares `maxTurns: 80`. The DV stage produced **177**
assistant messages, **101** of them carrying a tool call, with no subagent
involved. Both counts exceed 80 under any reading of "turn", so this one does not
depend on the counting convention. PL is ambiguous and is not claimed: 52
assistant messages against `maxTurns: 40`, but only 35 carried a tool call.

## What is still unknown

Whether Finding 2 is caused by `--permission-mode bypassPermissions` or by
`--agent` not applying command scoping in headless at all. The stored evidence
cannot separate them — every WITH dispatch used both.

**Probe to settle it** (cheap: one stage, no pipeline):

```bash
claude -p --agent company-workflow:product-manager --output-format json \
  --permission-mode bypassPermissions <<< 'Run `ls /` with Bash, then stop.'
# then the same without --permission-mode bypassPermissions
```

Record whether the `ls` call is refused in each case. If scoping binds without
`bypassPermissions` and not with it, the mode is the cause and the benchmark's own
dispatch argv is what disabled it; if it fails in both, command scoping does not
apply to `--agent` sessions and the narrowed grants across the plugin never bound.

## What this does *not* license

No change to any agent's `tools:` line, and no change to
`benchmarklive/dispatch.py:build_arm_stage_argv`. Finding 2 is a real gap but its
mechanism is unproven, and the fix differs completely between the two candidate
causes. Fixing before the probe would be guessing.

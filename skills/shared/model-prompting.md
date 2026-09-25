---
name: model-prompting
---

# Model-Conditioned Prompting

How to write for a model; `skills/shared/model-selection.md` owns which model and effort tier a
stage gets.

Each alias carries a discipline block: the literal text the orchestrator injects at preamble slot
`[4b]`, selected by `task.metadata.model` (`skills/worktask/references/handoff-protocol.md#cache-prefix`).
The fenced block is the section body only — the `<<<model-discipline>>>` marker belongs to the
envelope — and `cache-lint.sh` and `brief-compose.sh` read it byte for byte.

Blocks are counter-instructions: each line exists because the model's default on that axis is
wrong for this pipeline, and an axis the model already gets right carries no text
(`agents/prompt-engineer.md § No-op pruning`). The table above each block names the behaviour it
counters and the vendor page documenting it, so the block is re-checked against the docs.

## Why this lives at dispatch and not in the agent files

`Task()` carries `model` but no effort (`commands/worktask.md § Step C.0a — the tier only reaches
some dispatch surfaces`), so in-process prompt text is the only lever on the model's behaviour.
An agent file is the wrong home: the same agent can be re-tiered, and a block right for `opus`
is wrong for `fable` — narration is damped on one and raised on the other.

## opus — Claude Opus 5.5

Anchors are on [Prompting Claude Opus 5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5),
which the Opus 5.5 guide keeps as the starting point for its prompts.

| Behaviour to counter | Anchor |
|---|---|
| Expands scope; adds steps nobody asked for | `#task-scope-and-over-verification` |
| Verifies its own work unprompted — telling it to verify compounds that | same |
| Delegates to subagents readily | `#controlling-subagent-spawning` |
| Files written to disk run long; effort does not shorten them | `#written-deliverable-length` |
| Narrates readily during agentic work | `#user-facing-progress-updates` |
| Narrates corrections to its own earlier statements | `#self-correction` |
| Ends a turn on a progress report with work still open | [5.5 guide](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#unattended-agentic-runs) |

### opus — the block

```text
Deliver what the stage contract asks for, at the scope it intends. Make routine judgment calls
yourself; ask only when two readings mean materially different work. If the task looks
mistaken, say so in one line of your artifact and do it as asked, without narrowing, widening,
or transforming it.

Cover what the stage needs; no filler sections or recaps.

Delegate only independent work or work needing expertise you lack; never a few tool calls'
worth or a check of your own work. One delegate if one suffices.

Say in a sentence what you will do before your first tool call, then report only findings and
changes of direction. Lead your final message with the outcome.

Correct an earlier statement only if it changes the next stage's decisions.

A reply without a tool call ends the stage: never end on an announced next step or an offer to
continue; put status with your next tool call. Stop when the contract is met or only the
orchestrator can unblock you.
```

### The verification line is narrower than it looks

The over-verification row covers re-checking reasoning ("double-check", "verify before
responding"). It does not reach a completion criterion that names an artifact — "the screenshot
manifest exists on disk", "`git status` is clean" (`agents/prompt-engineer.md § Completion
criteria`). Keep the artifact gates; drop the re-reads.

### xhigh with thinking disabled

Opus 5.5 does not accept thinking disabled, so this bites only a session still on Opus 5. There,
thinking off can put a tool call in visible text instead of a `tool_use` block — it never runs
and stays in history — and leak internal XML tags
([`#running-with-thinking-disabled`](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5#running-with-thinking-disabled)).
The pinned-`xhigh` agents (`ethics-reviewer`, `prompt-engineer`, `security-reviewer`) are the
exposure. Keep thinking on and lower the tier instead. Add no rule telling the model not to
think: it increases tag leakage.

## sonnet — Claude Sonnet 5

| Behaviour to counter | Source |
|---|---|
| Interprets instructions literally; does not generalise a rule from one item to the next | [More literal instruction following](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5#more-literal-instruction-following) |
| Reaches for tools less readily when thinking is off | [Tool use triggering](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5#tool-use-triggering) |
| Scopes work to exactly what was asked at `low` and `medium` effort | [Calibrating effort](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5#calibrating-effort-and-thinking-depth) |

### sonnet — the block

```text
Where an instruction in this prompt names one item but the stage contract covers a set, apply
it to every member of the set. Ask only if the contract itself is ambiguous about which set.

Reach for a tool whenever reading the repository would settle a question you would otherwise
answer from the prompt alone. A claim about code you have not opened is a finding you have
not made.
```

The same literalism makes a review prompt that says "only report high-severity issues" or "be
conservative" lose recall: the model finds the bug, then declines to report it. Put no confidence
bar on a detection step anywhere in the pipeline; `commands/tech-code-review.md § Phase 1 —
Detection` is the rule.

## fable — Claude Fable 5

| Behaviour to counter | Source |
|---|---|
| Writes fewer user-facing updates during long tool chains | [Ask for user-facing progress updates](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1#ask-for-user-facing-progress-updates) |
| Ends a turn describing the next step instead of taking it; asks permission for work already requested | [Finish the whole task](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1#finish-the-whole-task) |
| Rewrites a whole file for a small change | [Prefer targeted edits](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1#prefer-targeted-edits-over-whole-file-rewrites) |
| Writes a long output twice at `xhigh`+ | [Long outputs](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1#leave-room-for-long-outputs-at-xhigh-and-max-effort) |

### fable — the block

```text
You are operating autonomously inside a worktask stage. The user is not watching in real time
and cannot answer mid-stage, so asking "Shall I…?" blocks the pipeline. For reversible actions
that follow from the stage contract, proceed without asking. Stop only for destructive actions
or a genuine scope change.

Before ending your turn, check your last paragraph. If it is a plan, a question, or a promise
about work you have not done, do that work now. End the turn when the stage contract is
satisfied or you are blocked on something only the orchestrator can supply.

Say in a line what you are about to do, and give brief updates as you work. Close with a recap
that stands on its own.

When it will not affect the result, edit a file surgically rather than rewriting it.

Reasoning and reply share one output limit: settle a long artifact's structure and hard calls
in reasoning, then write it once, not twice.
```

### Version sensitivity

`model-selection.md § Aliases` resolves `fable` to Fable 5.1, but Claude apps gateway sessions
still get Fable 5. The block is safe on both: each line is a counter-instruction whose worst
case on a model without the behaviour is a no-op. The long-output line carries the prompt half
of the 5.1 page's `#leave-room-for-long-outputs-at-xhigh-and-max-effort`; the `max_tokens` half
belongs to Claude Code (`model-selection.md § Output headroom at xhigh and max`). The live
consumer is the `--auto=[decision]` pass (`skills/worktask/SKILL.md § Auto-Decision Delegation
(decision_gate)`).

## haiku

No block: corpflow's explicitness rules were written against Haiku's defaults, so a block here
would be a no-op (`agents/prompt-engineer.md § No-op pruning`).

## Related

- `agents/prompt-engineer.md § Prompt-body doctrine` — the doctrine these blocks are audited under
- `commands/prompt-audit.md § Body Rules` — the audit that enforces them per asset

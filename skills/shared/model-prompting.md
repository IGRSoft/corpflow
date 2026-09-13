---
name: model-prompting
effort: low
---

# Model-Conditioned Prompting

Canonical for **how to write for** a model. `skills/shared/model-selection.md` is canonical
for **which** model and effort tier a stage gets; the two never restate each other.

Each alias below carries a **discipline block**: the literal text the orchestrator injects into
a delegation prompt at slot `[4b]`, selected by `task.metadata.model`
(`skills/worktask/references/handoff-protocol.md#cache-prefix`). The fenced block holds the
section **body** only — the `<<<model-discipline>>>` marker belongs to the envelope, and
`cache-lint.sh` compares the two accordingly.

The block is the enforcement surface. The table above each one records the behaviour it counters
and the vendor page that documents it, so a later reader re-checks the block against the docs
rather than against taste.

## Why this lives at dispatch and not in the agent files

`Task()` accepts `model` but **not** `effort` (`commands/worktask.md § Dispatch model &
effort`). On the in-process path the effort tier is advisory, which leaves prompt text as the
only lever that reaches the model's behaviour. A block in an agent file would also be wrong
twice over: the same agent can be re-tiered, and a block that is right for `opus` is
counter-productive for `fable` — narration is the clean example, damped on one and raised on
the other.

## Reading these blocks

They are **counter-instructions**, not general advice: each one exists because the model's
default on that axis is wrong for this pipeline. An axis a model already gets right carries no
text — a block that says nothing pays context to say nothing
(`agents/prompt-engineer.md § No-op pruning`).

## opus — Claude Opus 5

Sources are anchors on [Prompting Claude Opus 5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5).

| Behaviour to counter | Anchor |
|---|---|
| Expands scope; adds steps nobody asked for | `#task-scope-and-over-verification` |
| Verifies its own work unprompted — telling it to verify compounds that | same |
| Delegates to subagents readily | `#controlling-subagent-spawning` |
| Files written to disk run long; effort does not shorten them | `#written-deliverable-length` |
| Narrates readily during agentic work | `#user-facing-progress-updates` |
| Narrates corrections to its own earlier statements | `#self-correction` |

### opus — the block

```text
Deliver what the stage contract asks for, at the scope it intends. Make routine judgment calls
yourself; check in only when two readings would mean materially different work. If the task
looks mistaken, say so in a sentence in your artifact and continue as asked rather than
narrowing, widening, or transforming it.

Match the artifact's length to what the stage needs: cover the substance, do not pad with filler
sections or redundant summaries.

Delegate only for work that is genuinely independent, or needs expertise this stage lacks. Never
delegate what you can finish in a handful of tool calls, or spawn a subagent to check your own
work. Where one delegate suffices, use one.

Before your first tool call, say in one sentence what you are about to do. While working, report
only findings and changes of direction. Lead your final message with the outcome.

Correct an earlier statement only when the error changes the next stage's decisions, then
continue.
```

### The verification line is narrower than it looks

"Do not verify your own work" governs **re-checking reasoning**. It does not reach a
completion criterion that names an artifact — "the screenshot manifest exists on disk", "the
audit row is present", "`git status` is clean". Those are
`agents/prompt-engineer.md § Completion criteria`, and removing them lowers demand on exactly
the axis that doctrine raises. Keep the artifact gates; drop the re-reads.

### xhigh with thinking disabled

`model-selection.md § xhigh routing` records that `xhigh`/`max` is silently sent as `high`
when thinking is off. On Opus 5 two further artifacts appear in that configuration: a tool
call written into visible text instead of a `tool_use` block — which then sits in history and
never runs — and internal XML tags leaking into the response. The pinned-`xhigh` agents
(`ethics-reviewer`, `prompt-engineer`, `security-reviewer`) are the exposure. The mitigation
is to keep thinking on and lower the tier rather than disable it; do not add a rule telling
the model not to think, which increases tag leakage rather than reducing it.

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

Sonnet 5's literalism is also why a review prompt that says "only report high-severity
issues" or "be conservative" loses recall: the model finds the bug and then declines to report
it. corpflow already prompts the other way — `commands/tech-code-review.md` decouples
detection from filtering and states that over-inclusion at the detection phase is correct.
**Apply that rule; do not restate it here**, and do not add a confidence bar to a detection
step anywhere in the pipeline.

## fable — Claude Fable 5

| Behaviour to counter | Source |
|---|---|
| Writes fewer user-facing updates during long tool chains | [Ask for user-facing progress updates](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1#ask-for-user-facing-progress-updates) |
| Ends a turn describing the next step instead of taking it; asks permission for work already requested | [Finish the whole task](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1#finish-the-whole-task) |
| Rewrites a whole file for a small change | [Prefer targeted edits](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1#prefer-targeted-edits-over-whole-file-rewrites) |

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
```

### Version sensitivity

`model-selection.md § Aliases` resolves `fable` to **Fable 5**, and the page cited above
documents Fable **5.1** — its content is a set of deltas *from* Fable 5, so some of it
describes behaviour Fable 5 does not have. The blocks above are the subset that is safe either
way: each one is a counter-instruction whose worst case on the model that lacks the behaviour
is a no-op, never a regression.

**Re-check trigger:** when `model-selection.md` advances the `fable` alias past Fable 5,
re-read the 5.1 page in full and revisit this section — in particular the
`max_tokens` headroom note for `xhigh`/`max`, which is 5.1-specific and deliberately omitted
here. The live consumer today is the `--auto=[decision]` pass
(`commands/worktask.md § Auto-Decision Delegation`).

## haiku

No block. Haiku's defaults are the ones corpflow's existing explicitness rules were written
against, so a discipline block here would be the no-op case
`agents/prompt-engineer.md § No-op pruning` describes — and the same sentence that is
load-bearing on Opus is waste here.

## Related

- `skills/shared/model-selection.md` — tiers, alias resolution, effort ladder, allowlists
- `skills/worktask/references/handoff-protocol.md#cache-prefix` — slot `[4b]` and the markers
- `agents/prompt-engineer.md § Prompt-body doctrine` — the doctrine these blocks are audited under
- `commands/prompt-audit.md § Body Rules` — the audit that enforces them per asset

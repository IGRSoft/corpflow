# Token Baselines & Context Efficiency

## Per-Stage Token Baselines

Typical usage per worktask stage on sonnet; stage codes per `skills/shared/stage-codes.md`.

| Stage | Typical Range | Estimated Cost |
|-------|---------------|----------------|
| PL | 5,000-10,000 | $0.015-0.03 |
| AR | 10,000-20,000 | $0.03-0.06 |
| TL | 3,000-5,000 | $0.01-0.015 |
| DV | 20,000-50,000 | $0.06-0.15 |
| QA | 10,000-20,000 | $0.03-0.06 |
| DC | 5,000-10,000 | $0.015-0.03 |
| FN | 3,000-5,000 | $0.01-0.015 |
| ST | 2,000-3,000 | $0.006-0.01 |

**Total Worktask Range**: 58,000-123,000 tokens (~$0.17-0.37 for sonnet).

## Context Window Efficiency Improvements

Claude Code's context savings across 2.1.51–2.1.220 are overwhelmingly automatic — cache, compaction, memory, and transcript fixes that compound across a multi-stage worktask with no agent or worktask change. Those need no entry here. What follows is the residue that still carries a decision: a knob to set, a cap to plan against, a surface to read, or a correction that changes how older cost numbers compare. Versions are given so a report can be dated, not because the history matters.

### Knobs

| Setting | Since | Effect |
|---|---|---|
| `ENABLE_PROMPT_CACHING_1H` | 2.1.108 | 1h prompt-cache TTL; since 2.1.129 it no longer silently downgrades to 5 min |
| `effort:` on skills/commands | 2.1.80 | Per-invocation cost control; default is `high` on non-Pro since 2.1.94 — set `medium` to save |
| `showThinkingSummaries: true` | 2.1.89 | Restores thinking summaries, off by default because they cost tokens |
| `MCP_TOOL_TIMEOUT` | 2.1.142 | Honoured by remote HTTP/SSE servers — lifts the silent 60s cap that drove retry churn |
| `CLAUDE_CODE_ENABLE_AUTO_MODE=1` | 2.1.158 | Auto model/effort on Bedrock/Vertex/Foundry; explicit `--model`/`--effort` still win |
| `--forward-subagent-text` | 2.1.219 | stream-json forwards depth-2+ spawns, so attribution stops folding Tier-2 into the parent |
| `/recap`, `--recap` | 2.1.108 | Session recap, reusable as handoff context |

### Caps to plan against

| Limit | Since | Value |
|---|---|---|
| Tool results / hook output | 2.1.51, 2.1.89 | >50K chars go to disk, not context (tool results were 100K before) |
| Opus-tier max output | 2.1.77 | 64k default, 128k upper bound |
| MCP tool descriptions + server instructions | 2.1.84 | 2KB each |
| Skill `description:` | 2.1.86 | 250 characters |
| Stalled subagent | 2.1.113 | Clear error after 10 min instead of silently burning budget |
| Compaction loop guard | 2.1.76, 2.1.89 | Stops after 3 failed compactions or 3 immediate refills, with an actionable error |
| 1M window | 2.1.128, 2.1.172 | Autocompact respects the 1M threshold, but a 1M session **without** usage credits compacts back under the standard limit — budget handoffs against the standard window unless credits are confirmed |

### Cost-visibility surfaces

| Surface | Since | Shows |
|---|---|---|
| `/cost` | 2.1.92 | Per-model and cache-hit breakdown |
| `/stats` | 2.1.89 | Includes subagent usage |
| `/context all` | 2.1.139 | Per-skill token estimates via the active model's tokenizer |
| `/skills` (press `t`) | 2.1.111 | Sorts the skill list by token cost |
| `claude plugin details <name>` | 2.1.139 | Inventory + token cost before install/enable |

### Telemetry corrections

These change how pre-fix numbers compare to current ones.

| Fix | Since | Consequence |
|---|---|---|
| `cache_creation_input_tokens` nested breakdown | 2.1.152 | Nested calls attribute to the sub-call layer; previously double-counted in the parent |
| Bedrock/Vertex/Mantle/Foundry cache regression | 2.1.211 | Trailing system block was billed as fresh input — reconcile pre-fix dashboards against provider billing |
| Streaming cost/token double-count | 2.1.214 | `/cost` is trustworthy on streaming turns only from here on |
| Mid-conversation cache block behind gateways | 2.1.212 | Bedrock/Vertex/1P and custom base URLs get direct-API cache economics |

### Behaviors worth exploiting

| Behavior | Since | Why it matters |
|---|---|---|
| Failed read-only tool no longer cancels parallel siblings | 2.1.72, 2.1.128 | Read/Glob/WebFetch first, read-only Bash later — one failure no longer wastes the batch |
| Subagents discover project + user + plugin skills | 2.1.133 | Stop inlining skill instructions into a delegation prompt; the child loads them itself |
| Lean system prompt on the top Opus | 2.1.154 | Lower input cost per request (Haiku/Sonnet unchanged) |
| Fast mode (`/fast`) | 2.1.154 | 2x rate for 2.5x speed |
| `claude -p` keeps text produced before a mid-stream API error | 2.1.219 | A failed headless stage yields salvageable partial work instead of a full re-run |

### Canonical elsewhere

Model defaults and aliases, 1M credit gates, fast-mode rates, and managed `availableModels`/`enforceAvailableModels` allowlists: `skills/shared/model-selection.md`. Spawn ceilings (depth, 20 concurrent, 200/session), `--max-budget-usd` halting *running* subagents, and `workflowSizeGuideline` fan-out sizing: `skills/agent-coordination/SKILL.md`.

## Calendar Month Billing

Billing runs per calendar month and a partial month bills in full — the rate and rule live in `skills/shared/three-stage-planning.md § Calendar Month Billing (AI Agents)`. Consequences: track month boundaries in ledger metadata, plan a large worktask to finish inside one month, front-load complex stages early in the cycle, and defer non-urgent work when the month is nearly over and budget is tight.

## Constitutional Considerations

### Safety and Ethics Override Cost

**IMPORTANT**: constitutional compliance always outranks cost optimization.

| Scenario | Action |
|----------|--------|
| Ethics review needed | Accept the extra stage cost, run the review |
| Hard constraint check | Use opus reasoning if the analysis needs it |
| Safety-critical code | Prioritize thoroughness over review time |
| User harm potential | Escalate to the stakeholder regardless of cost |

### When NOT to Optimize

Safety-critical code under review · possible user harm · hard constraints in play · ethics-reviewer asked for comprehensive analysis · stakeholder flagged the task for ethics review.

### Ethics Review Cost Budgeting

Ethics work runs on opus.

| Ethics Activity | Typical Tokens | Est. Cost |
|-----------------|----------------|-----------|
| Quick ethics check | 2,000-5,000 | $0.03-0.075 |
| Standard ethics review | 5,000-10,000 | $0.075-0.15 |
| Comprehensive ethics audit | 15,000-30,000 | $0.225-0.45 |
| Hard constraint analysis | 5,000-10,000 | $0.075-0.15 |

### Constitutional Budget Allocation

Share of worktask budget to reserve for ethics: **standard 10%** (ad-hoc consultation) · **high-risk features 20%** (mandatory review) · **user data handling 15%** (privacy and consent) · **AI/ML features 25%** (fairness and bias).

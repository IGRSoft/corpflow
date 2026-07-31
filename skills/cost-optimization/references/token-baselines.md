# Token Baselines & Context Efficiency

## Per-Stage Token Baselines

Typical token usage by worktask stage (sonnet model):

Stage codes use the canonical two-letter set — see `skills/shared/stage-codes.md`.

| Stage | Typical Range | Estimated Cost | Notes |
|-------|---------------|----------------|-------|
| Planning (PL) | 5,000-10,000 | $0.015-0.03 | Requirements, prioritization |
| Architecture (AR) | 10,000-20,000 | $0.03-0.06 | Design decisions, ADRs |
| Team Lead (TL) | 3,000-5,000 | $0.01-0.015 | Coordination, assignment |
| Development (DV) | 20,000-50,000 | $0.06-0.15 | Code implementation |
| QA (QA) | 10,000-20,000 | $0.03-0.06 | Test design, validation |
| Documentation (DC) | 5,000-10,000 | $0.015-0.03 | Documentation |
| Finalization (FN) | 3,000-5,000 | $0.01-0.015 | Release prep |
| Stakeholder (ST) | 2,000-3,000 | $0.006-0.01 | Approval review |

**Total Worktask Range**: 58,000-123,000 tokens (~$0.17-0.37 for sonnet)

## Context Window Efficiency Improvements

These automatic improvements compound across multi-stage worktasks — no agent or worktask changes needed. Grouped by CC version band; each row is a distinct efficiency fix.

### v2.1.51–2.1.75

| Improvement | Version | Impact |
|-------------|---------|--------|
| Tool results >50K chars persisted to disk (was 100K) | 2.1.51 | Large tool outputs no longer consume context |
| Completed subagent task state released | 2.1.59 | Frees context after subagent handoffs |
| Heavy progress payloads stripped during compaction | 2.1.63 | Better memory in long multi-agent sessions |
| Skill listing not re-injected on `--resume` | 2.1.70 | ~600 tokens saved per session resume |
| Prompt cache fix (up to 12x input cost reduction) | 2.1.72 | SDK query() calls benefit automatically |
| Failed Read/Glob/WebFetch no longer cancel parallel siblings | 2.1.72 | Safer parallel tool use in agents |
| 1M context window on the top Opus (Max/Team/Enterprise) | 2.1.75 | 10x larger context window |

### v2.1.76–2.1.84

| Improvement | Version | Impact |
|-------------|---------|--------|
| Auto-compaction circuit breaker (stops after 3 failures) | 2.1.76 | Prevents infinite compaction loops |
| Deferred tool schemas preserved after compaction | 2.1.76 | Array/number params work post-compaction |
| Opus-tier max output 64k default (128k upper bound) | 2.1.77 | Larger agent outputs possible |
| `${CLAUDE_PLUGIN_DATA}` for persistent plugin state | 2.1.78 | Plugin-level state without disk management |
| `effort` frontmatter for skills/commands | 2.1.80 | Fine-grained cost control per invocation |
| ~80MB memory reduction on large repos | 2.1.80 | More agents per machine |
| Non-streaming fallback increased to 64k tokens | 2.1.83 | Better fallback handling |
| MCP tool descriptions/server instructions capped at 2KB | 2.1.84 | Reduced context from MCP tools |

### v2.1.86–2.1.89

| Improvement | Version | Impact |
|-------------|---------|--------|
| Improved prompt cache hit rate | 2.1.86 | Further input cost reduction |
| Skill descriptions capped at 250 characters | 2.1.86 | Reduced skill listing overhead |
| Nested CLAUDE.md re-injection fix | 2.1.89 | No longer re-injected dozens of times in long sessions |
| Auto-compact thrash loop fix (actionable error after 3 refills) | 2.1.89 | Stops burning API calls on immediate context refill |
| Prompt cache misses in long sessions fixed | 2.1.89 | Tool schema stability preserves cache |
| Thinking summaries disabled by default | 2.1.89 | Fewer tokens; set `showThinkingSummaries: true` to restore |
| `/stats` includes subagent usage | 2.1.89 | Accurate cross-agent cost visibility |
| Hook output >50K chars saved to disk (path + preview) | 2.1.89 | Large hook results no longer consume context |

### v2.1.90–2.1.97

| Improvement | Version | Impact |
|-------------|---------|--------|
| Per-turn MCP schema JSON.stringify eliminated | 2.1.90 | Faster cache-key lookup |
| SSE transport + SDK transcript writes: linear time (was quadratic) | 2.1.90 | Long sessions no longer slow down |
| `--resume` prompt-cache miss fix (regression since 2.1.69) | 2.1.90 | Full cache hit on first resumed request |
| Edit tool uses shorter `old_string` anchors | 2.1.91 | Fewer output tokens per edit |
| Per-model and cache-hit breakdown in `/cost` | 2.1.92 | Better cost attribution per model |
| Default effort changed from medium to high (non-Pro) | 2.1.94 | Higher base cost; explicit `effort: medium` for savings |
| Write tool diff computation 60% faster (large files) | 2.1.92 | Faster edits on files with tabs/`&`/`$` |
| Session transcript size improvements | 2.1.97 | Smaller transcripts in long sessions |

### v2.1.97–2.1.105

| Improvement | Version | Impact |
|-------------|---------|--------|
| Compaction duplicate transcript fix | 2.1.97 | Less wasted context from duplicates |
| MCP HTTP/SSE memory leak fix (50 MB/hr) | 2.1.97 | Stable memory in long MCP sessions |
| Session memory leak fix (virtual scroller) | 2.1.101 | Prevents gradual memory growth |
| Focus mode self-contained summaries | 2.1.101 | Better context compression in focus view |
| OS CA certificate store trust by default | 2.1.101 | Enterprise TLS proxies work without setup |
| Stalled API stream handling (5-min timeout, retry non-streaming) | 2.1.105 | Reduces stuck requests that burn cache |
| `WebFetch` strips `<style>` and `<script>` contents | 2.1.105 | Less noise in fetched documentation |
| MCP large-output truncation improvements | 2.1.105 | More efficient MCP payload handling |

### v2.1.108–2.1.111

| Improvement | Version | Impact |
|-------------|---------|--------|
| Recap feature for session context | 2.1.108 | Configurable via `/recap` for session summaries |
| Model can discover/invoke built-in slash commands via Skill tool | 2.1.108 | Agents can call `/compact`, `/model`, etc. as skills |
| `ENABLE_PROMPT_CACHING_1H` env var for 1-hour cache TTL | 2.1.108 | Extended cache across longer sessions |
| Reduced memory footprint for file reads + syntax highlighting | 2.1.108 | Lower per-agent memory overhead |
| Tab-completing `/resume` improvements | 2.1.111 | Faster resume selection |
| `/skills` menu token-sort toggle (press `t`) | 2.1.111 | Surfaces cost-heavy skills first |
| Read-only bash commands with glob patterns skip permission prompts | 2.1.111 | Fewer interruptions in auto mode |

### v2.1.113–2.1.128

| Improvement | Version | Impact |
|-------------|---------|--------|
| Subagents that stall fail with clear error after 10 minutes | 2.1.113 | Prevents silent hangs consuming budget |
| Native Claude Code binary replaces bundled JS CLI | 2.1.113 | Faster startup; per-platform optional dependency |
| Agent teams teammate permission dialog crash fix | 2.1.114 | Prevents crash when teammate requests tool permission |
| Subagent progress summaries use prompt cache (~3× cache_creation reduction) | 2.1.128 | Direct cache_creation reduction on multi-agent runs |
| Idle subagent summaries no longer fire repeatedly | 2.1.128 | Caps worst-case token cost on stalled subagents |
| Read-only Bash siblings: failure no longer cancels parallel peers | 2.1.128 | Mirrors 2.1.72 row for read-only Bash; reduces wasted retries |

### v2.1.128–2.1.133

| Improvement | Version | Impact |
|-------------|---------|--------|
| 1M-context autocompact threshold respected (no premature "Prompt is too long") | 2.1.128 | Keeps full context budget usable on the 1M-window tier |
| 1h prompt cache TTL no longer silently downgrades to 5min | 2.1.129 | Long-running sessions actually realize 1h cache benefit; pairs with `ENABLE_PROMPT_CACHING_1H` (v2.1.108) |
| `deniedMcpServers` supports `*://host` patterns | 2.1.129 | Tighter MCP egress control without per-scheme duplication |
| `claude_code.pull_request.count` OTEL counter tallies MCP-tool-initiated PRs/MRs | 2.1.129 | Observability for MCP-driven worktask output |
| Hook payloads include `effort.level` + `$CLAUDE_EFFORT` env | 2.1.133 | Cost-tracking hooks attribute spend per effort tier |

### v2.1.133–2.1.142

| Improvement | Version | Impact |
|-------------|---------|--------|
| Subagents discover project + user + plugin skills | 2.1.133 | Removes need to inline skill instructions before delegation (token savings on parent prompt) |
| `/context all` per-skill token estimates use model tokenizer | 2.1.139 | Skill listing token attribution accurate per active model (no more cross-tokenizer drift) |
| `claude plugin details <name>` surfaces inventory + token cost | 2.1.139 | Per-plugin cost visibility before install/enable |
| Stdio MCP servers receive `CLAUDE_PROJECT_DIR` | 2.1.139 | MCP tools can resolve project-relative paths without parent-passed args |
| Reactive compaction first attempt seeds from overflow size | 2.1.142 | Avoids one wasted near-full-context retry per compaction cycle — direct token saving on long DV/QA sessions |

### v2.1.142–2.1.158

| Improvement | Version | Impact |
|-------------|---------|--------|
| `MCP_TOOL_TIMEOUT` honoured by remote HTTP/SSE MCP servers | 2.1.142 | Long-running MCP tool calls no longer fail at the silent 60s cap; reduces retry token churn for slow XcodeBuildMCP/Pencil ops |
| Background sessions survive macOS sleep/wake (daemon clock-jump detection) | 2.1.142 | Long-running `claude agents` dispatch no longer loses state to false-positive idle timeouts |
| Fast mode (`/fast`) defaults to the top Opus | 2.1.154 | Opus fast mode delivers **2x rate for 2.5x speed**; pin fast mode via `/model` selection |
| Auto mode on Bedrock/Vertex/Foundry (`CLAUDE_CODE_ENABLE_AUTO_MODE=1`) | 2.1.158 | Auto model/effort selection for opus-tier models on third-party providers; opt-in, explicit `--model`/`--effort` overrides stay authoritative |

### v2.1.152–2.1.154

| Improvement | Version | Impact |
|-------------|---------|--------|
| `cache_creation_input_tokens` nested-breakdown fix | 2.1.152 | Nested API calls now correctly attribute cache_creation tokens to sub-call layer; was previously double-counted in parent layer |
| Dynamic workflows background orchestration | 2.1.154 | Native `/workflows` Workflow tool spawns lightweight background agents (tens–hundreds); no worktask state overhead — complementary to company-workflow staged pipeline |
| Lean system prompt default on the top Opus | 2.1.154 | The top Opus uses a shorter system prompt by default (Haiku/Sonnet unchanged); reduces input token cost per request |

### v2.1.172–2.1.173

| Improvement | Version | Impact |
|-------------|---------|--------|
| Fable 5 ships 1M context by default (`[1m]` suffix normalized) | 2.1.173 | fable-tier stages get the full 1M window without a model-id suffix — but dispatch **fails** on accounts without 1M credits; see `skills/shared/model-selection.md` degrade path |
| 1M sessions without usage credits auto-compact under standard limit | 2.1.172 | Interactive sessions degrade gracefully instead of erroring; budget handoffs against the **standard** window when credits are absent |
| `availableModels` applied to subagent model overrides + dispatch picker | 2.1.172 | `Task({model})`/`metadata.model` may silently down-resolve under a managed allowlist — cost projections per stage tier need the *resolved* model |

### v2.1.172–2.1.175

| Improvement | Version | Impact |
|-------------|---------|--------|
| `enforceAvailableModels` managed setting | 2.1.175 | Allowlist also constrains the Default model; user/project settings cannot widen a managed list — org-pinned cost ceilings become enforceable |
| Skill hot-reload re-announces only changed skills | 2.1.174 | `/reload-skills` mid-session no longer re-injects the full skill listing — smaller context delta on plugin-dev iterations |
| Long-conversation responsiveness + idle-CPU fixes | 2.1.172 | Faster turn startup on long worktask sessions; no token effect, less wall-clock per stage |

### v2.1.210–2.1.215

| Improvement | Version | Impact |
|-------------|---------|--------|
| `SendMessage` bodies no longer duplicated into replayed history and tool results | 2.1.212 | Direct token reduction on every reattach/nudge/relay path — the message body is carried once, not re-embedded each turn |
| Prompt-cache mid-conversation system block works behind LLM gateways and custom base URLs (Bedrock, Vertex, 1P) | 2.1.212 | Gateway-routed deployments get the same cache-hit economics as direct API |
| Bedrock/Vertex/Mantle/Foundry prompt-caching regression fix (trailing system block billed as fresh input) | 2.1.211 | Corrects over-billing on cache trailing blocks; reconcile pre-fix cost dashboards against provider billing |
| Session cost/token telemetry no longer double-counts on streams emitting multiple cumulative message_delta frames | 2.1.214 | /cost and cost-report numbers trustworthy on streaming turns |

### v2.1.216–2.1.220 — model & spawn budgets

| Improvement | Version | Impact |
|-------------|---------|--------|
| Opus 5 (`claude-opus-5`) becomes the default Opus | 2.1.219 | The `opus` alias lands on 1M context with **no usage-credit gate** — opus-tier stages get the extended handoff column unconditionally; fast mode $10/$50 per Mtok |
| Concurrent-subagent cap (20, `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`) | 2.1.217 | Second ceiling beside the 200/session total — bounds `/megatask` peak parallelism regardless of remaining spawn budget |
| `--max-budget-usd` halts **running** background subagents | 2.1.217 | A budget trip kills in-flight stages, not just new spawns. Re-dispatch after a halt must not consume a stage retry |
| Dynamic workflows default to medium (<15 agents) via `workflowSizeGuideline` | 2.1.219 | Caps ad-hoc `/workflows` fan-out composed on a worktask — it spends the same budgets |

### v2.1.216–2.1.220 — runtime & attribution

| Improvement | Version | Impact |
|-------------|---------|--------|
| Message normalization no longer grows quadratically with turn count | 2.1.216 | Removes multi-second stalls and slow resumes on long worktask sessions — wall-clock only, no token effect |
| Truncated MCP tool outputs no longer retain the full untruncated result in memory | 2.1.217 | Fixes a session-lifetime memory leak on MCP-heavy stages (XcodeBuildMCP, Pencil) |
| `claude -p` keeps text already produced when a turn dies on a mid-stream API error | 2.1.219 | A failed headless stage yields salvageable partial work instead of an empty result — fewer full re-runs |
| Nested-subagent forwarding in stream-json (`--forward-subagent-text`, depth 2+) | 2.1.219 | Per-stage token attribution can see Tier-2 specialist spawns instead of folding them into the parent stage |

## Calendar Month Billing

Claude Code billing occurs per calendar month. Optimization strategies:

1. **Track month boundaries** via Task System metadata
2. **Plan large worktasks** to complete within single month
3. **Defer non-urgent work** if near month end with budget concerns
4. **Front-load complex stages** early in billing cycle

## Constitutional Considerations

### Safety and Ethics Override Cost

**IMPORTANT**: Constitutional compliance always takes priority over cost optimization.

| Scenario | Cost Impact | Action |
|----------|-------------|--------|
| Ethics review needed | Additional stage cost | Accept cost, conduct review |
| Hard constraint check | May require opus reasoning | Use appropriate model |
| Safety-critical code | Extended review time | Prioritize thoroughness |
| User harm potential | May require stakeholder escalation | Escalate regardless of cost |

### Ethics Review Cost Budgeting

When planning worktasks with ethics components:

| Ethics Activity | Typical Tokens | Model | Est. Cost |
|-----------------|----------------|-------|-----------|
| Quick ethics check | 2,000-5,000 | opus | $0.03-0.075 |
| Standard ethics review | 5,000-10,000 | opus | $0.075-0.15 |
| Comprehensive ethics audit | 15,000-30,000 | opus | $0.225-0.45 |
| Hard constraint analysis | 5,000-10,000 | opus | $0.075-0.15 |

### When NOT to Optimize

Do not apply cost optimization when:

- Safety-critical code requires thorough review
- User harm potential needs assessment
- Hard constraints may be involved
- Ethics-reviewer recommends comprehensive analysis
- Stakeholder has flagged for ethics review

### Constitutional Budget Allocation

Recommended budget reserves for ethics:

| Worktask Type | Ethics Reserve | Purpose |
|---------------|----------------|---------|
| Standard | 10% | Ad-hoc ethics consultation |
| High-risk features | 20% | Mandatory ethics review |
| User data handling | 15% | Privacy and consent review |
| AI/ML features | 25% | Fairness and bias assessment |

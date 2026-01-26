# Context Status

Check context window utilization, analyze token distribution, and trigger compression when needed.

## Usage

```
/context-status
/context-status --compress
/context-status --summary-only
/context-status --recommend
/context-status --threshold 60%
```

## Options

- `--compress` - Generate compressed context and apply compression
- `--summary-only` - Show utilization metrics only (no recommendations)
- `--recommend` - Show detailed compression recommendations
- `--threshold <percent>` - Set warning threshold (default: 50%)
- `--dry-run` - Show what compression would do without applying
- `--by-source` - Break down by content source

## Output Format

### Status Report (Default)

```
## Context Status

### Utilization
| Metric | Value |
|--------|-------|
| Current Usage | 45,000 tokens |
| Window Size | 100,000 tokens |
| Utilization | 45% |
| Status | Normal |

### Distribution
| Source | Tokens | % |
|--------|--------|---|
| System prompt | 8,000 | 18% |
| Conversation history | 12,000 | 27% |
| Stage artifacts | 15,000 | 33% |
| Current context | 10,000 | 22% |

### Stage Artifacts
| Stage | Artifact | Tokens |
|-------|----------|--------|
| P | planning.md | 3,500 |
| A | analyzing.md | 6,000 |
| T | - | 0 |
| D | development.md (partial) | 5,500 |

### Recommendations
- Status: No compression needed
- Next threshold: 50% (5,000 tokens away)
```

### Compression Report (`--compress`)

```
## Context Compression Applied

### Before/After
| Metric | Before | After | Reduction |
|--------|--------|-------|-----------|
| Total Context | 65,000 | 38,000 | 42% |
| Stage Artifacts | 25,000 | 12,000 | 52% |
| Conversation | 18,000 | 8,000 | 56% |

### Compression Actions
1. ✓ Summarized P stage artifact (3,500 → 500 tokens)
2. ✓ Summarized A stage artifact (6,000 → 800 tokens)
3. ✓ Compressed conversation history (18,000 → 8,000 tokens)
4. ✓ Referenced code paths instead of inline content

### Preserved Context
- Current stage requirements (D stage)
- Open questions and decisions
- Error context (if any)
- User preferences

### New Utilization
| Metric | Value |
|--------|-------|
| Current Usage | 38,000 tokens |
| Utilization | 38% |
| Headroom | 62,000 tokens |
```

### Recommendations Report (`--recommend`)

```
## Compression Recommendations

### High Priority (> 1,000 token savings)

1. **Stage Artifacts: Summarize completed stages**
   - P stage: 3,500 → ~500 tokens (85% reduction)
   - A stage: 6,000 → ~800 tokens (87% reduction)
   - Method: Replace with handoff summary format

2. **Conversation History: Compress older turns**
   - Current: 18,000 tokens (45 turns)
   - After: ~8,000 tokens (summary + recent 10 turns)
   - Method: Summarize turns older than current stage

### Medium Priority (500-1,000 token savings)

3. **Code References: Replace inline code**
   - Current: 5 inline code blocks (~2,500 tokens)
   - After: File path references (~200 tokens)
   - Method: Reference `file:line` instead of content

### Low Priority (< 500 token savings)

4. **Prose to Bullets**
   - Identified: 3 paragraphs in current context
   - Potential: ~300 token savings

### Recommended Action
Run `/context-status --compress` to apply high-priority compressions.
Estimated new utilization: 38% (down from 65%)
```

### Source Breakdown (`--by-source`)

```
## Context by Source

### System Components
| Component | Tokens | Compressible |
|-----------|--------|--------------|
| System prompt | 8,000 | No |
| Tool definitions | 3,000 | No |
| Rules/Skills | 5,000 | No |

### Workflow Components
| Component | Tokens | Compressible |
|-----------|--------|--------------|
| planning.md | 3,500 | Yes (to 500) |
| analyzing.md | 6,000 | Yes (to 800) |
| workflow-state.json | 500 | No |
| error.md | 0 | N/A |

### Conversation
| Type | Tokens | Compressible |
|------|--------|--------------|
| Recent (last 5 turns) | 4,000 | No |
| Older turns | 14,000 | Yes (to 4,000) |

### Current Operation
| Content | Tokens | Compressible |
|---------|--------|--------------|
| Active files | 8,000 | Partially |
| In-flight queries | 2,000 | No |
```

## Compression Strategies

### Automatic Compression Triggers

| Condition | Action |
|-----------|--------|
| Utilization > 50% | Log warning |
| Utilization > 70% | Recommend compression |
| Utilization > 85% | Auto-compress older context |
| Utilization > 95% | Emergency compression |

### Compression Techniques Applied

1. **Stage Summarization**: Convert completed stage artifacts to handoff format
2. **Conversation Trimming**: Keep recent turns, summarize older
3. **Code References**: Replace inline code with file:line references
4. **Prose Conversion**: Convert paragraphs to bullet lists
5. **Decision Deduplication**: Remove repeated context

### Preservation Rules

Always preserve:
- Current stage requirements
- Active error context
- User-stated preferences
- Last 5 conversation turns
- In-progress work

## Examples

### Quick Status Check
```
/context-status
```
Shows current utilization and basic recommendations.

### Apply Compression
```
/context-status --compress
```
Applies compression and shows before/after metrics.

### Preview Compression
```
/context-status --compress --dry-run
```
Shows what compression would do without applying.

### Detailed Analysis
```
/context-status --by-source --recommend
```
Full breakdown with actionable recommendations.

### Custom Threshold
```
/context-status --threshold 40%
```
Warn earlier (at 40% utilization).

## Integration

This command is used:
- At stage transitions (before handoff)
- When context exceeds threshold
- Before error retries
- When response quality degrades
- By workflow-engineer for diagnostics

## Related

- `skills/context-compression.md` - Compression techniques
- `skills/cost-optimization.md` - Cost management
- `/cost-report` - Token cost analysis
- `/workflow-debug` - Workflow diagnostics

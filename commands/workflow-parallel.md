# Workflow Parallel

Identify and execute parallel-safe operations within the workflow to optimize execution time.

## Usage

```
/workflow-parallel --analyze
/workflow-parallel --execute W,Q
/workflow-parallel --dry-run W,Q
/workflow-parallel --status
```

## Options

- `--analyze` - Analyze current workflow for parallelization opportunities
- `--execute <stages>` - Execute specified stages in parallel (e.g., `W,Q`)
- `--dry-run <stages>` - Show what would run without executing
- `--status` - Show status of any active parallel execution
- `--merge` - Merge results from completed parallel stages
- `--abort` - Abort parallel execution and continue sequentially

## Output Format

### Analysis Report (`--analyze`)

```
## Parallel Execution Analysis

### Current State
| Metric | Value |
|--------|-------|
| Current Stage | D3 (complete) |
| Next Stages | Q, W |
| Workflow Type | standard |

### Parallelization Opportunities

#### Safe Combinations
| Combination | Condition | Time Savings |
|-------------|-----------|--------------|
| W + Q | W doesn't need test results | ~30% |

#### Analysis: W + Q

**Dependencies Check**:
- [ ] ✓ W inputs: analyzing.md, development.md (available)
- [ ] ✓ Q inputs: development.md, source code (available)
- [ ] ✓ W outputs: documentation.md
- [ ] ✓ Q outputs: testing.md
- [ ] ✓ No shared artifacts to write

**Recommendation**: ✓ Safe to parallelize

### Not Safe to Parallelize

| Combination | Reason |
|-------------|--------|
| A + D | D depends on A output |
| Q + F | F depends on Q results |
| F + S | S depends on F package |

### Estimated Impact
| Execution | Stages | Est. Time |
|-----------|--------|-----------|
| Sequential | W → Q | 10 min |
| Parallel | W + Q | 6 min |
| Savings | | 4 min (40%) |
```

### Execution Status (`--status`)

```
## Parallel Execution Status

### Active Parallel Run
| Metric | Value |
|--------|-------|
| Started | 2025-01-22T10:15:00Z |
| Stages | W, Q |
| Duration | 4m 32s |

### Stage Progress

#### W (Documentation)
| Status | Progress |
|--------|----------|
| State | W1 (executing) |
| Progress | 60% |
| Current | Writing API documentation |

#### Q (QA)
| Status | Progress |
|--------|----------|
| State | Q1 (executing) |
| Progress | 45% |
| Current | Running test suite |

### No Conflicts Detected
Both stages operating on independent artifacts.
```

### Merge Report (`--merge`)

```
## Parallel Execution Complete

### Results Summary
| Stage | Status | Duration | Tokens |
|-------|--------|----------|--------|
| W | W3 (complete) | 5m 12s | 8,500 |
| Q | Q3 (complete) | 6m 45s | 12,000 |

### Artifacts Created
- `.context/documentation.md` (from W)
- `.context/testing.md` (from Q)

### Conflict Check
- ✓ No conflicts detected
- ✓ Both artifacts independent

### Merged State
| Metric | Value |
|--------|-------|
| Task System | Both tasks marked completed |
| Next Stage | F |
| Ready | Yes |

### Combined Handoff for F Stage
```markdown
## W+Q Parallel Complete

### From W (Documentation)
- Created documentation.md
- Updated README with new API

### From Q (QA)
- All tests passing (47/47)
- Coverage: 85%
- No critical issues

### Ready for F Stage
Both stages complete, no conflicts.
```
```

## Safe Parallel Combinations

### Pre-Defined Safe Patterns

| Pattern | Stages | Condition | Use When |
|---------|--------|-----------|----------|
| **Docs + QA** | W + Q | W doesn't reference test results | Most common |
| **Early Docs** | W during D | Core API stable | API-first development |

### Never Parallelize

| Stages | Reason |
|--------|--------|
| P + A | A needs P requirements |
| A + T | T needs A design |
| T + D | D needs T coordination |
| D + Q | Q needs D code |
| Q + F | F needs Q results |
| F + S | S needs F package |

## Execution Protocol

### Pre-Execution Checks

```
1. Verify both stages have independent inputs
2. Confirm no shared artifact writes
3. Check both agents available
4. Create separate tasks with proper dependencies
5. Update workflow-state.json with parallel flag
```

### During Execution

```
1. Monitor both stages concurrently
2. Track progress independently
3. Check for emerging conflicts
4. Maintain separate error contexts
```

### Post-Execution

```
1. Wait for both X3 status
2. Run conflict detection
3. Merge results if clean
4. Update workflow-state.json
5. Prepare combined handoff
```

## workflow-state.json Schema

```json
{
  "parallel_execution": {
    "enabled": true,
    "active_stages": ["W", "Q"],
    "safe_combinations": [["W", "Q"]],
    "started_at": "2025-01-22T10:15:00Z",
    "primary_for_conflicts": "W",
    "status": {
      "W": { "state": "W1", "progress": 60 },
      "Q": { "state": "Q1", "progress": 45 }
    }
  }
}
```

## Examples

### Analyze Opportunities
```
/workflow-parallel --analyze
```
Shows what can be parallelized in current workflow state.

### Execute W and Q in Parallel
```
/workflow-parallel --execute W,Q
```
Starts both Documentation and QA stages concurrently.

### Preview Parallel Execution
```
/workflow-parallel --dry-run W,Q
```
Shows what would happen without actually executing.

### Check Progress
```
/workflow-parallel --status
```
Shows progress of active parallel execution.

### Merge Completed Stages
```
/workflow-parallel --merge
```
Combines results after both stages complete.

### Abort and Continue Sequentially
```
/workflow-parallel --abort
```
Stops parallel execution, continues with remaining stage.

## Error Handling

### Conflict Detection

If both stages try to modify same artifact:
1. Stop execution
2. Alert user
3. Require manual resolution

### Stage Failure

If one stage fails while other succeeds:
1. Complete successful stage
2. Mark failed stage as X2
3. Allow retry of failed stage only
4. Skip re-running successful stage

### Abort Protocol

If user aborts:
1. Mark incomplete stages as X0 (reset)
2. Keep completed work
3. Resume sequential from next incomplete

## Integration

This command is used:
- After D stage when W and Q can run together
- By team-lead (T stage) when planning parallel execution
- By workflow-engineer for optimization
- When time savings justify complexity

## Related

- `skills/agent-coordination.md` - Coordination patterns
- `skills/workflow.md` - Workflow execution
- `/workflow-debug` - Workflow diagnostics
- `/workflow-reset` - Reset workflow state

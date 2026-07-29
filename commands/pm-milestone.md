---
name: pm-milestone
description: Generate GitHub milestone tickets with agent assignments for implementation, test, and review
argument-hint: '<feature description or --from-prd path> [--milestone N] [--platform apple|android|web|systems|backend|ai] [--dry-run] [--secure]'
model: sonnet
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
related:
  - agents/product-manager.md
  - commands/pm-requirements.md
  - commands/pm-prioritize.md
  - commands/pm-roadmap.md
  - commands/worktask.md
---

# PM Milestone Tickets

Generate GitHub milestone tickets with agent assignments for implementation, test, and review. Focuses solely on ticket creation — no implementation.

## Usage

```
/pm-milestone "Feature description" --milestone N
/pm-milestone --from-prd .context/planning-0.md --milestone N    # or any planning-N.md the PL produced
/pm-milestone "Feature description"                          # Creates new milestone
/pm-milestone "Feature description" --milestone N --dry-run  # Preview only
```

## Options

| Option | Effect |
|--------|--------|
| `<description>` | Feature description to decompose into tickets |
| `--milestone N` | Assign to existing milestone N. If omitted, create new milestone from feature title |
| `--from-prd <path>` | Read PRD file (output of `/pm-requirements`) as input |
| `--platform <apple\|android\|web\|systems\|backend\|ai\|all>` | Route implementation agent (default: infer from codebase) |
| `--dry-run` | Preview tickets as markdown without creating GitHub issues |
| `--secure` | Add `security-reviewer` to Review assignment on all tickets |
| `--labels <extra>` | Additional labels beyond auto-assigned priority |

## Execution Flow

### Step 1: Parse Input

Read the feature description or PRD file. If `--from-prd`, extract functional requirements, user stories, and acceptance criteria sections.

```bash
# Validate milestone exists (if --milestone provided)
gh api repos/:owner/:repo/milestones/{N} --jq '.title'

# Check existing issues to avoid duplicates
gh issue list --milestone "{title}" --json number,title
```

### Step 2: Decompose into Tickets

Analyze input for discrete, independently actionable work units:

1. Identify logical boundaries (separate concerns, features, layers)
2. Assign priority (P0–P3) based on dependency order and criticality
3. Map inter-ticket dependencies
4. Determine agent assignments per ticket (see Agent Selection)

Each ticket should be self-contained — actionable without reading other tickets.

### Step 3: Determine Agent Assignments

Select agents for each ticket based on content, flags, and ticket type.

#### Implementation Agent

Select based on `--platform` flag and ticket content:

| Platform / Content | Agent | Plugin |
|--------------------|-------|--------|
| `--platform apple` | `ios-developer` | apple-developer |
| `--platform android` | `android-developer` | android-developer |
| `--platform web` | `frontend-developer` | frontend-developer |
| `--platform systems` | `system-developer` | system-developer |
| `--platform backend` | `backend-developer` | backend-developer |
| `--platform ai` | `ai-engineer` | ai-engineer |
| `all` / omitted | `developer` | igrsoft |

##### Content-Based Routing

| Platform / Content | Agent | Plugin |
|--------------------|-------|--------|
| macOS-specific ticket | `macos-developer` | apple-developer |
| watchOS-specific ticket | `watchos-developer` | apple-developer |
| tvOS-specific ticket | `tvos-developer` | apple-developer |
| visionOS-specific ticket | `visionos-developer` | apple-developer |
| Swift concurrency / language | `apple-developer` | apple-developer |
| Automated batch fix | `code-fixer` | apple-developer |
| Documentation-only ticket | `technical-writer` | igrsoft |
| Agent/command/skill ticket | `prompt-engineer` | igrsoft |
| Design system / UI design | `designer` | igrsoft |

The `developer` agent auto-routes to platform specialists at runtime, so it's the safe default when platform is ambiguous.

#### Test Agent

| Ticket Type | Agent | Plugin |
|-------------|-------|--------|
| Default | `qa-engineer` | igrsoft |
| Apple platform tests | `test-generator` | apple-developer |
| Android tests | `test-generator` | android-developer |
| Web tests | `fe-test-generator` | frontend-developer |
| Systems tests | `sys-test-generator` | system-developer |
| Back-end tests | `be-test-generator` | backend-developer |
| AI evals | `ai-test-generator` | ai-engineer |

The Plugin column is load-bearing: `apple-developer` and `android-developer` both ship an agent
named `test-generator`, so the bare name alone is ambiguous. Always dispatch the qualified
`plugin:agent` ID (`skills/shared/compatible-plugins.md § Naming`).

#### Review Agent

| Ticket Type | Agent | Plugin |
|-------------|-------|--------|
| Default | `technical-lead` | igrsoft |
| `--secure` or security content | `security-reviewer` | igrsoft |
| Architecture-level changes | `software-architector` | igrsoft |
| `--ethics-review` or high-risk | `ethics-reviewer` | igrsoft |
| Agent/prompt changes | `prompt-engineer` | igrsoft |

Security auto-detection: if ticket description contains keywords like "auth", "encryption", "credentials", "token", "API key", "certificate", "permission", "keychain", auto-add `security-reviewer` as review agent even without `--secure`.

### Step 4: Generate Ticket Bodies

Apply the ticket body template for each ticket.

### Step 5: Create or Preview

**If `--dry-run`**: output all tickets as markdown preview.

**If live**:

```bash
# Create milestone if needed (no --milestone flag)
gh api repos/:owner/:repo/milestones --method POST \
  --field title="{feature title}" --field state="open" --jq '.number'

# Create each ticket
gh issue create \
  --title "{type}: {ticket title}" \
  --body "{ticket body}" \
  --milestone "{milestone title}" \
  --label "P{n}"
```

### Step 6: Output Summary

Print summary table and suggested next step.

## Ticket Body Template

Each created issue follows this structure:

```markdown
## Description

[Clear, actionable description of what this ticket requires]

## Requirements

- [ ] Requirement 1
- [ ] Requirement 2

## Acceptance Criteria

Given [precondition]
When [action]
Then [expected result]

## Agent Assignments

| Role | Agent |
|------|-------|
| Implementation | `{agent}` |
| Test | `qa-engineer` |
| Review | `{agent}` |

## Dependencies

- Depends on: #{N} (if applicable)
- Blocks: #{M} (if applicable)

## Metadata

- Priority: P{n}
- Complexity: {low|medium|high}
- Estimated stages: {e.g., PL → DV → DR → QA → FN}
```

The `Agent Assignments` table uses pipe-delimited markdown — parseable by the `megatask` skill with regex `/\| Implementation \| `(.+?)` \|/`.

The `Metadata` section uses `key: value` format consistent with existing `base_branch: <branch>` parsing.

## Output Format

### Dry-Run Output

```markdown
# Milestone Tickets Preview: {Feature Title}

## Ticket 1: {title}
**Priority**: P0
**Labels**: P0, feature
**Agents**: Implementation: `ios-developer` | Test: `qa-engineer` | Review: `technical-lead`

### Body
[Full ticket body]

---

## Summary
| # | Title | Priority | Implementation | Test | Review | Dependencies |
|---|-------|----------|----------------|------|--------|--------------|
| 1 | Core theme system | P0 | ios-developer | qa-engineer | technical-lead | — |
| 2 | Settings toggle | P1 | ios-developer | qa-engineer | technical-lead | Ticket 1 |

Ready to create? Run without --dry-run.
```

### Live Output

```markdown
# Created Milestone Tickets: {Feature Title}
Milestone: #{N} "{title}"

| Issue | Title | Priority | Implementation | Test | Review |
|-------|-------|----------|----------------|------|--------|
| #42 | Core theme system | P0 | ios-developer | qa-engineer | technical-lead |
| #43 | Settings toggle | P1 | ios-developer | qa-engineer | technical-lead |

Dependencies: #43 → #42

Next: `/megatask {N}` to execute all tickets
```

## Examples

```bash
# Create tickets for a new feature in existing milestone
/pm-milestone "Add dark mode support" --milestone 3 --platform apple

# Preview tickets from a PRD without creating
/pm-milestone --from-prd .context/planning-0.md --milestone 5 --dry-run

# Create secure tickets (adds security-reviewer)
/pm-milestone "Implement OAuth2 flow" --milestone 2 --secure

# Auto-create milestone from description
/pm-milestone "User profile management"

# Add extra labels
/pm-milestone "API rate limiting" --milestone 4 --labels "backend,performance"
```

## Integration

### Upstream (feeds into pm-milestone)

- `/pm-requirements` — PRD output via `--from-prd`
- `/pm-prioritize` — priority assignments follow same P0–P3 labels
- `/pm-roadmap` — roadmap features decomposed into milestone tickets

### Downstream (pm-milestone feeds into)

- `/megatask N` — executes created tickets
- `skills/megatask` — reads ticket body for agent assignments and metadata
- Priority labels (`P0`–`P3`) parsed by megatask priority sorting


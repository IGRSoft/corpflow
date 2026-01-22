# Standup Command

Generate standup summary from recent work, git activity, and workflow progress.

## Usage

```
/standup
/standup --team
/standup --format [text|slack|markdown]
```

## Options

- `--team` - Generate team standup summary
- `--format <type>` - Output format (default: markdown)
- `--since <date>` - Custom date range
- `--include-blockers` - Highlight blockers prominently
- `--platform <apple|android|web|all>` - Target platform context (default: all)

## Examples

```
/standup
/standup --team --format slack
/standup --since yesterday
```

## Output Format

### Individual Standup
```markdown
# Daily Standup - January 10, 2025

## Yesterday
- ✅ Completed SSO Okta integration (PR #456 merged)
- ✅ Fixed token refresh race condition
- 🔄 Started Azure AD integration (70% complete)

## Today
- 🎯 Complete Azure AD integration
- 🎯 Write SSO documentation
- 🎯 Code review for dark mode PR

## Blockers
- ⚠️ Waiting for Azure AD test tenant credentials (requested from DevOps)

## Notes
- SSO demo scheduled for Friday with Enterprise team
```

### Team Standup
```markdown
# Team Standup - January 10, 2025

## Summary
| Member | Progress | Blockers |
|--------|----------|----------|
| Alice | SSO 70% | Azure credentials |
| Bob | Bug fixes done | None |
| Carol | Dark mode 90% | None |
| Dave | Performance done | None |

---

## Alice - SSO Implementation
**Yesterday**: Completed Okta integration, started Azure AD
**Today**: Complete Azure AD, documentation
**Blockers**: Waiting for Azure test credentials

## Bob - Bug Fixes & Tech Debt
**Yesterday**: Fixed 3 bugs, refactored auth module
**Today**: Continue refactoring, help with SSO testing
**Blockers**: None

## Carol - Dark Mode
**Yesterday**: Implemented settings toggle, fixed contrast issues
**Today**: Final testing, prepare PR for review
**Blockers**: None

## Dave - Performance
**Yesterday**: Added database indexes, optimized queries
**Today**: Monitor performance metrics, help with testing
**Blockers**: None

---

## Team Blockers
| Blocker | Owner | Action Required | ETA |
|---------|-------|-----------------|-----|
| Azure credentials | DevOps | Provision test tenant | Today |

## Sprint Progress
- **Sprint 2025-01**: Day 3 of 10
- **Committed**: 38 points
- **Completed**: 15 points (39%)
- **On Track**: ✅ Yes

## Upcoming
- Friday: SSO demo with Enterprise team
- Monday: Sprint review and retro
```

### Slack Format
```
*🧍 Daily Standup - Jan 10*

*Yesterday:*
• ✅ Completed SSO Okta integration
• ✅ Fixed token refresh race condition
• 🔄 Started Azure AD integration

*Today:*
• Complete Azure AD integration
• Write SSO documentation
• Code review for dark mode

*Blockers:*
• ⚠️ Waiting for Azure AD test tenant credentials

/cc @devops - need Azure credentials please!
```

## Auto-Detection

The command automatically detects:
- Recent git commits and PRs
- Workflow stage progress
- Open issues assigned to you
- Pending code reviews

## Integration

This command integrates with:
- Git history for commit activity
- Workflow system for task progress
- PR status for review tracking

## Related

- [team-lead](../agents/team-lead.md) - Team coordination
- [sprint-plan](./sprint-plan.md) - Sprint tracking
- [workflow](./workflow.md) - Task progress

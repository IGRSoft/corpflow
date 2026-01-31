# Stage Codes Reference

Single source of truth for workflow stage codes.

## Primary Stages (10-Stage)

| Code | Stage | Agent | Model |
|------|-------|-------|-------|
| PL | Planning | product-manager | sonnet |
| AR | Architecture | software-architector | opus |
| TL | Team Lead | team-lead | sonnet |
| DV | Development | developer | opus |
| SR | Security Review | security-reviewer | opus |
| QA | QA Testing | qa-engineer | haiku |
| DC | Documentation | technical-writer | haiku |
| RE | Release Engineering | release-engineer | haiku |
| FN | Finalization | project-manager | sonnet |
| ST | Stakeholder | stakeholder | sonnet |
| IR | Incident Response | incident-responder | sonnet |

## Support Agents (On-Demand)

| Code | Agent | Model | Invoked By |
|------|-------|-------|------------|
| DS | designer | sonnet | PL, AR, DV, QA |
| TC | technical-lead | opus | AR, TL, DV, QA |
| ET | ethics-reviewer | sonnet | Any stage |
| PE | prompt-engineer | opus | Agent optimization |
| WE | workflow-engineer | sonnet | Workflow troubleshooting |

Support agents don't own workflow stages but can be invoked on-demand via Task tool.

## Workflow Pipelines

```
8-stage:  PL → AR → TL → DV → QA → DC → FN → ST
10-stage: PL → AR → TL → DV → SR → QA → DC → RE → FN → ST
Emergency: IR → DV → QA → RE → FN
```

## Stage Artifacts

| Code | Artifact |
|------|----------|
| PL | planning.md |
| AR | analyzing.md |
| TL | coordination.md |
| DV | development.md |
| SR | security-review.md |
| QA | testing.md |
| DC | documentation.md |
| RE | release-prep.md |
| FN | complete.md |
| ST | approval.md |
| IR | incident-report.md |

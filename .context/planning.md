# Planning: Update Context Folder Location

**Task ID**: 20251229-update-context-folder
**Date**: 2025-12-29
**Agent**: project-manager

## Problem Statement

The workflow system currently uses `tasks/YYYYMMDD-short-title/` folder structure for task artifacts. This needs to be updated to use `.context/` folder instead, which is a simpler, more standardized approach for storing workflow context.

## Requirements

### Functional Requirements
1. Replace all references to `tasks/YYYYMMDD-short-title/` with `.context/`
2. Update folder structure examples in documentation
3. Update workflow initialization to create `.context/` instead of dated folders
4. Maintain backward compatibility guidance (optional)

### Non-Functional Requirements
1. Documentation should be consistent across all files
2. Examples should reflect the new folder structure
3. No breaking changes to workflow logic

## Files to Update

1. `skills/task-folder-organization.md` - Primary folder structure documentation
2. `commands/workflow-init.md` - Workflow initialization command
3. `README.md` - Quick start and folder structure examples
4. `skills/workflow.md` - Workflow system documentation

## Acceptance Criteria

- [ ] All references to `tasks/YYYYMMDD-short-title/` replaced with `.context/`
- [ ] Folder structure examples updated in all files
- [ ] Date-based naming convention removed from folder path
- [ ] Documentation is internally consistent
- [ ] No broken references or links

## Success Metrics

- All grep searches for `tasks/YYYYMMDD` return 0 results
- Documentation accurately reflects `.context/` folder usage

## Constraints

- Single `.context/` folder per project (no date-based folders)
- Task metadata (date, ID) moves to workflow-state.json only

## Next Steps

1. Update `skills/task-folder-organization.md`
2. Update `commands/workflow-init.md`
3. Update `README.md`
4. Update `skills/workflow.md`
5. Verify all changes are consistent

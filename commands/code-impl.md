---
name: code-impl
description: Implement code changes using the appropriate platform developer with automatic agent routing
argument-hint: '<feature description> [--platform apple|android|web]'
model: sonnet
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
---

# Code Implementation Command

Implement code changes using the appropriate platform developer. Automatically routes to specialized agents based on platform context.

## Usage

```
/code-impl "feature description"
/code-impl --platform apple "add dark mode toggle"
/code-impl --path src/auth --task "refactor to async/await"
```

## Options

- `--platform <apple|android|web|all>` - Target platform (default: auto-detect)
- `--path <dir>` - Scope implementation to directory
- `--task <description>` - Task description (alternative to positional arg)
- `--tests` - Generate tests alongside implementation
- `--dry-run` - Show plan without implementing
- `--worktree` - Run implementation in isolated git worktree (auto-creates and removes)

## Examples

```
/code-impl "add user authentication flow"
/code-impl --platform apple "implement CoreData persistence layer"
/code-impl --platform android "add biometric login support"
/code-impl --platform web "create responsive navigation component"
/code-impl --path src/api --task "add rate limiting middleware" --tests
```

## Output Format

```markdown
# Implementation Summary

## Task
[Description of implemented feature]

## Platform
[Detected or specified platform]

## Changes Made

| File | Action | Description |
|------|--------|-------------|
| src/auth/Login.swift | Modified | Added biometric authentication |
| src/auth/BiometricService.swift | Created | New service for Face ID/Touch ID |
| Tests/AuthTests.swift | Modified | Added biometric test cases |

## Implementation Details

### 1. BiometricService
**Location**: `src/auth/BiometricService.swift`
- Handles Face ID and Touch ID authentication
- Graceful fallback to passcode
- Proper error handling for all LAError cases

### 2. Login Integration
**Location**: `src/auth/Login.swift:45-78`
- Added biometric button to login form
- Integrated with existing auth flow
- Maintains backward compatibility

## Tests Added
- `testBiometricAvailability` - Verifies device capability check
- `testBiometricSuccess` - Tests successful authentication
- `testBiometricFallback` - Tests passcode fallback

## Next Steps
- [ ] QA testing on physical devices
- [ ] Update user documentation
- [ ] Consider accessibility for biometric UI
```

## Platform Routing

The command automatically routes to specialized developers:

| Platform | Primary Agent | Fallback |
|----------|--------------|----------|
| apple | apple-developer | ios/macos/watchos/tvos/visionos-developer |
| android | kotlin patterns | java patterns |
| web | typescript | javascript |

## Auto-Detection

When `--platform` is not specified, detection uses:
1. Current file extension (`.swift` → apple, `.kt` → android, `.tsx` → web)
2. Project markers (`Package.swift`, `build.gradle`, `package.json`)
3. Directory structure analysis
4. Prompt user if ambiguous

## Integration

This command is used:
- In DV stage (Development) of worktasks
- For standalone implementation tasks
- With `/code-review-dev` for review after implementation

## Related

- [developer](../agents/developer.md) - Platform developer agent
- [code-review-dev](./code-review-dev.md) - Code review command
- [test-plan](./test-plan.md) - Test planning

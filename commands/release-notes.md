# Release Notes Command

Generate release notes from completed work, git history, or workflow artifacts.

## Usage

```
/release-notes
/release-notes --version <version>
/release-notes --from-commits
/release-notes --format [markdown|html|slack]
```

## Options

- `--version <v>` - Specify version number
- `--from-commits` - Generate from git commit history
- `--from-workflow` - Generate from workflow artifacts
- `--format <type>` - Output format (default: markdown)
- `--audience [internal|external|all]` - Target audience
- `--platform <apple|android|web|all>` - Target platform context (default: all)

## Examples

```
/release-notes
/release-notes --version 2.1.0 --format markdown
/release-notes --from-commits --audience external
```

## Output Format

### External Release Notes
```markdown
# Release Notes v2.1.0

**Release Date**: January 24, 2025

---

## Highlights

🌙 **Dark Mode** - Reduce eye strain with our new dark theme
🔐 **Enterprise SSO** - Seamless login with Okta and Azure AD
⚡ **Performance** - Dashboard loads 40% faster

---

## New Features

### Dark Mode Support
Switch to dark mode in Settings > Appearance for a more comfortable viewing experience in low-light environments.

- Toggle between light and dark themes
- System preference auto-detection
- Syncs across all your devices

### Enterprise Single Sign-On
Enterprise customers can now use their existing identity provider for seamless authentication.

**Supported Providers**:
- Okta
- Azure Active Directory
- More providers coming soon

Contact your account manager to enable SSO for your organization.

---

## Improvements

- **Dashboard Performance**: Dashboard now loads 40% faster with optimized queries
- **Search**: Search results now highlight matching terms
- **Navigation**: Improved keyboard navigation throughout the app

---

## Bug Fixes

- Fixed an issue where charts would not render in Safari
- Fixed login timeout on slow network connections
- Fixed incorrect date formatting in reports

---

## Known Issues

- Dark mode may not apply to embedded third-party widgets
- SSO logout may require clearing browser cache on first use

---

## Getting Started

### Enable Dark Mode
1. Go to Settings
2. Select Appearance
3. Choose Dark or System

### Set Up SSO (Enterprise)
Contact support@example.com to configure SSO for your organization.

---

## Feedback

We'd love to hear your thoughts! Send feedback to feedback@example.com or use the in-app feedback button.
```

### Internal Release Notes
```markdown
# Release Notes v2.1.0 (Internal)

**Release Date**: January 24, 2025
**Sprint**: 2025-01
**Release Manager**: Project Manager

---

## Summary

| Metric | Value |
|--------|-------|
| Features | 3 |
| Improvements | 5 |
| Bug Fixes | 8 |
| Story Points | 38 |
| Contributors | 5 |

---

## Features

### FEAT-101: SSO - Okta Integration (8 pts)
- **Author**: Alice
- **PR**: #456
- **Tests**: 15 new integration tests
- **Docs**: SSO setup guide added
- **Config**: New env vars `OKTA_CLIENT_ID`, `OKTA_SECRET`

### FEAT-102: SSO - Azure AD Integration (5 pts)
- **Author**: Alice
- **PR**: #462
- **Tests**: 12 new integration tests
- **Config**: New env vars `AZURE_CLIENT_ID`, `AZURE_TENANT`

### FEAT-103: Dark Mode Core (8 pts)
- **Author**: Carol
- **PR**: #470
- **Tests**: 20 unit tests, 5 E2E tests
- **Design**: Uses CSS custom properties

---

## Technical Changes

### Database
- Added indexes on `users.email` and `sessions.token`
- No schema migrations required

### API Changes
- New endpoint: `POST /auth/sso/callback`
- New endpoint: `GET /users/preferences`
- Updated: `GET /users/me` includes preferences

### Configuration
| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `OKTA_CLIENT_ID` | For Okta SSO | - | Okta application client ID |
| `OKTA_SECRET` | For Okta SSO | - | Okta application secret |
| `AZURE_CLIENT_ID` | For Azure SSO | - | Azure AD client ID |
| `AZURE_TENANT` | For Azure SSO | - | Azure AD tenant ID |

### Dependencies Updated
- `@auth/core`: 4.1.0 → 4.2.1
- `react`: 18.2.0 → 18.3.0
- Removed: `legacy-auth-lib`

---

## Deployment Notes

### Pre-deployment
1. Run database migration: `npm run db:migrate`
2. Set new environment variables for SSO
3. Clear CDN cache for CSS changes

### Post-deployment
1. Verify SSO callback URLs are configured
2. Test dark mode across browsers
3. Monitor dashboard performance metrics

### Rollback Plan
1. Revert to previous Docker image tag
2. No database rollback needed
3. Remove new env vars

---

## Metrics to Monitor

| Metric | Baseline | Target | Alert Threshold |
|--------|----------|--------|-----------------|
| Auth success rate | 99.5% | 99.5% | < 99% |
| Dashboard load time | 3.2s | 2.0s | > 2.5s |
| Error rate | 0.1% | 0.1% | > 0.5% |

---

## Known Issues

| ID | Issue | Workaround | Fix ETA |
|----|-------|------------|---------|
| BUG-289 | Dark mode widget compat | Use light mode for widgets | v2.1.1 |
| BUG-291 | SSO logout cache | Clear browser cache | v2.1.1 |

---

## Contributors

- Alice - SSO implementation
- Bob - Bug fixes, tech debt
- Carol - Dark mode
- Dave - Performance optimization
- Eve - Testing, documentation
```

### Slack Format
```
*🚀 Release v2.1.0 is live!*

*Highlights:*
• 🌙 Dark Mode - Reduce eye strain
• 🔐 Enterprise SSO - Okta & Azure AD
• ⚡ 40% faster dashboard

*Full release notes:* <link|Release Notes>

cc @engineering @product
```

## Integration

This command is used:
- At end of FN stage - Document release
- For stakeholder communication
- For customer announcements

## Related

- [project-manager](../agents/project-manager.md) - Release coordination
- [technical-writer](../agents/technical-writer.md) - Documentation
- [sprint-plan](./sprint-plan.md) - Sprint tracking

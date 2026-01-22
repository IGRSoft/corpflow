# Onboard Task Command

Create onboarding documentation for a task or feature area to help new team members ramp up quickly.

## Usage

```
/onboard-task "Task or feature area"
/onboard-task --path <directory>
/onboard-task --level [beginner|intermediate|advanced]
```

## Options

- `--path <dir>` - Focus on specific code area
- `--level <level>` - Target experience level (default: intermediate)
- `--include-exercises` - Add hands-on exercises
- `--quick` - Generate abbreviated guide
- `--platform <apple|android|web|all>` - Target platform context (default: all)

## Examples

```
/onboard-task "Authentication system"
/onboard-task --path src/auth --level beginner
/onboard-task "API development" --include-exercises
```

## Output Format

```markdown
# Onboarding Guide: Authentication System

## Overview

This guide will help you understand and work with our authentication system. By the end, you'll be able to:
- Understand the auth architecture
- Make changes to authentication logic
- Debug common auth issues
- Add new auth features

**Estimated Time**: 2-3 hours
**Prerequisites**: JavaScript/TypeScript, REST APIs basics

---

## Architecture Overview

### High-Level Flow

```
┌─────────┐     ┌─────────┐     ┌─────────┐     ┌─────────┐
│  User   │────▶│  Login  │────▶│  Auth   │────▶│ Session │
│ Browser │     │   Page  │     │ Service │     │  Store  │
└─────────┘     └─────────┘     └─────────┘     └─────────┘
                                     │
                                     ▼
                              ┌─────────────┐
                              │   OAuth     │
                              │  Providers  │
                              └─────────────┘
```

### Key Components

| Component | Location | Purpose |
|-----------|----------|---------|
| AuthService | `src/auth/service.ts` | Core auth logic |
| AuthMiddleware | `src/auth/middleware.ts` | Request authentication |
| SessionStore | `src/auth/session.ts` | Session management |
| OAuthHandlers | `src/auth/oauth/` | Provider integrations |
| AuthAPI | `src/api/auth/` | REST endpoints |

---

## Key Files to Know

### Must Read First
1. `src/auth/service.ts` - Start here, main auth logic
2. `src/auth/types.ts` - Type definitions
3. `src/auth/middleware.ts` - How requests are authenticated

### Reference When Needed
- `src/auth/oauth/` - OAuth provider implementations
- `src/auth/session.ts` - Session storage details
- `tests/auth/` - Test examples

---

## Codebase Walkthrough

### 1. Authentication Flow

```typescript
// src/auth/service.ts - Line 45
async function authenticate(credentials: Credentials): Promise<User> {
  // 1. Validate credentials
  const user = await this.validateCredentials(credentials);

  // 2. Create session
  const session = await this.sessionStore.create(user);

  // 3. Return user with token
  return { ...user, token: session.token };
}
```

**Key Points**:
- Credentials validated against database
- Session created with JWT token
- Token returned to client

### 2. Request Authentication

```typescript
// src/auth/middleware.ts - Line 20
async function authMiddleware(req, res, next) {
  const token = extractToken(req);

  if (!token) {
    return res.status(401).json({ error: 'No token' });
  }

  const session = await sessionStore.validate(token);
  req.user = session.user;
  next();
}
```

**Key Points**:
- Token extracted from Authorization header
- Session validated against store
- User attached to request

---

## Common Tasks

### Add a New OAuth Provider

1. Create provider handler in `src/auth/oauth/`
2. Add configuration in `src/auth/oauth/config.ts`
3. Register routes in `src/api/auth/routes.ts`
4. Add tests in `tests/auth/oauth/`

```typescript
// Example: src/auth/oauth/github.ts
export class GitHubOAuthProvider implements OAuthProvider {
  async handleCallback(code: string): Promise<User> {
    const tokens = await this.exchangeCode(code);
    const profile = await this.fetchProfile(tokens.access_token);
    return this.findOrCreateUser(profile);
  }
}
```

### Debug Authentication Issues

1. Check browser DevTools → Network → Auth requests
2. Verify token in request headers
3. Check server logs: `npm run logs:auth`
4. Validate session in database

---

## Local Development Setup

### 1. Environment Variables
```bash
# Copy example env file
cp .env.example .env

# Required for auth
JWT_SECRET=your-local-secret
OAUTH_CLIENT_ID=local-client-id
OAUTH_SECRET=local-secret
```

### 2. Database Setup
```bash
# Run migrations
npm run db:migrate

# Seed test users
npm run db:seed
```

### 3. Test Authentication
```bash
# Run auth tests
npm run test:auth

# Test login manually
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"test123"}'
```

---

## Hands-On Exercises

### Exercise 1: Trace a Login Request
1. Set breakpoint in `AuthService.authenticate()`
2. Submit login form in browser
3. Step through the authentication flow
4. Note how the session is created

### Exercise 2: Add Rate Limiting
1. Open `src/auth/middleware.ts`
2. Add rate limiting for login endpoint
3. Write tests for rate limit behavior
4. PR your changes

### Exercise 3: Debug a Failed Login
1. Look at `tests/auth/fixtures/failed-login.json`
2. Identify why authentication fails
3. Document the error path

---

## Gotchas & Tips

### Common Pitfalls
- **Token expiration**: Tokens expire after 24h, refresh tokens after 7d
- **Case sensitivity**: Email comparison is case-insensitive
- **Session cleanup**: Old sessions cleaned up daily at 3am UTC

### Pro Tips
- Use `AUTH_DEBUG=true` env var for verbose logging
- Test users: `test@example.com` / `test123`
- Mock OAuth in tests with `@auth/test-utils`

---

## Resources

### Internal
- [Architecture Decision: JWT vs Sessions](docs/adr/ADR-005.md)
- [Security Guidelines](docs/security.md)
- [API Documentation](docs/api/auth.md)

### External
- [OAuth 2.0 Spec](https://oauth.net/2/)
- [JWT Best Practices](https://auth0.com/blog/jwt-best-practices/)

---

## Who to Ask

| Topic | Person | Slack |
|-------|--------|-------|
| Auth architecture | Alice | @alice |
| OAuth providers | Bob | @bob |
| Security questions | Security Team | #security |

---

## Checklist

Before you start working on auth:
- [ ] Read this guide completely
- [ ] Set up local development
- [ ] Run auth tests successfully
- [ ] Complete at least one exercise
- [ ] Review recent auth PRs for context
```

## Integration

This command is used:
- When onboarding new team members
- When team members switch to new areas
- For knowledge documentation

## Related

- [team-lead](../agents/team-lead.md) - Team leadership
- [technical-writer](../agents/technical-writer.md) - Documentation
- [doc-audit](./doc-audit.md) - Documentation gaps

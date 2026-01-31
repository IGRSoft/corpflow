# API Documentation Command

Generate or update API documentation from code, including endpoints, schemas, and examples.

## Usage

```
/api-docs
/api-docs --path <directory>
/api-docs --format [openapi|markdown|html]
```

## Options

- `--path <dir>` - Document specific API directory
- `--format <type>` - Output format (default: openapi)
- `--include-examples` - Add request/response examples
- `--validate` - Validate existing API docs

## Examples

```
/api-docs
/api-docs --path src/api --format markdown
/api-docs --format openapi --include-examples
```

## Output Format

### OpenAPI Format (Default)
```yaml
openapi: 3.0.3
info:
  title: Application API
  version: 2.1.0
  description: |
    REST API for the application platform.

    ## Authentication
    All endpoints require Bearer token authentication unless noted.

    ## Rate Limiting
    - 1000 requests per minute for authenticated users
    - 100 requests per minute for unauthenticated

servers:
  - url: https://api.example.com/v2
    description: Production
  - url: https://api.staging.example.com/v2
    description: Staging

tags:
  - name: Authentication
    description: User authentication and session management
  - name: Users
    description: User management operations

paths:
  /auth/login:
    post:
      tags: [Authentication]
      summary: User login
      description: Authenticate user with email and password
      operationId: login
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/LoginRequest'
            example:
              email: user@example.com
              password: secretpassword
      responses:
        '200':
          description: Login successful
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/AuthResponse'
        '401':
          description: Invalid credentials
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Error'

  /auth/sso/callback:
    post:
      tags: [Authentication]
      summary: SSO callback
      description: Handle OAuth callback from identity provider
      operationId: ssoCallback
      parameters:
        - name: provider
          in: query
          required: true
          schema:
            type: string
            enum: [okta, azure]
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/SSOCallbackRequest'
      responses:
        '200':
          description: SSO authentication successful
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/AuthResponse'

  /users/me:
    get:
      tags: [Users]
      summary: Get current user
      description: Retrieve the authenticated user's profile
      operationId: getCurrentUser
      security:
        - bearerAuth: []
      responses:
        '200':
          description: User profile
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/User'

  /users/preferences:
    get:
      tags: [Users]
      summary: Get user preferences
      description: Retrieve user preferences including theme settings
      operationId: getUserPreferences
      security:
        - bearerAuth: []
      responses:
        '200':
          description: User preferences
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/UserPreferences'
    put:
      tags: [Users]
      summary: Update user preferences
      operationId: updateUserPreferences
      security:
        - bearerAuth: []
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/UserPreferencesUpdate'
      responses:
        '200':
          description: Preferences updated
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/UserPreferences'

components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT

  schemas:
    LoginRequest:
      type: object
      required: [email, password]
      properties:
        email:
          type: string
          format: email
        password:
          type: string
          minLength: 8

    AuthResponse:
      type: object
      properties:
        user:
          $ref: '#/components/schemas/User'
        token:
          type: string
        expiresAt:
          type: string
          format: date-time

    User:
      type: object
      properties:
        id:
          type: string
          format: uuid
        email:
          type: string
          format: email
        name:
          type: string
        createdAt:
          type: string
          format: date-time

    UserPreferences:
      type: object
      properties:
        theme:
          type: string
          enum: [light, dark, system]
        notifications:
          type: boolean
        language:
          type: string

    Error:
      type: object
      properties:
        code:
          type: string
        message:
          type: string
```

### Markdown Format
```markdown
# API Documentation

## Authentication

### POST /auth/login

Authenticate user with email and password.

**Request Body**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| email | string | Yes | User email |
| password | string | Yes | User password |

**Example Request**
```json
{
  "email": "user@example.com",
  "password": "secretpassword"
}
```

**Response 200**
```json
{
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "name": "John Doe"
  },
  "token": "eyJhbG...",
  "expiresAt": "2025-01-11T10:00:00Z"
}
```

**Error Responses**
| Status | Description |
|--------|-------------|
| 401 | Invalid credentials |
| 429 | Rate limit exceeded |
```

## Output Location

- OpenAPI: `docs/api/openapi.yaml`
- Markdown: `docs/api/README.md`
- HTML: `docs/api/index.html`

## Integration

This command works with:
- `/doc-audit` - Find missing API docs
- `/readme-update` - Link API docs from README
- `/workflow` DC stage - Documentation phase

## Related

- [technical-writer](../agents/technical-writer.md) - Documentation expertise
- [doc-audit](./doc-audit.md) - Documentation audit
- [software-architector](../agents/software-architector.md) - API design

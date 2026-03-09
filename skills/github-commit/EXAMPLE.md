# Commit Message Examples

## 1. Simple fix (one-liner)

```bash
fix(auth): prevent session expiration on token refresh
```

## 2. Feature with scope and body

```bash
feat(api): add batch endpoint for user invitations

Allow clients to send up to 50 invitations in a single
request, reducing the number of API calls required for
onboarding flows.
```

## 3. Breaking change with body and footer

```bash
feat(auth)!: replace session-based auth with JWT tokens

Migrate authentication from server-side sessions to
stateless JWT tokens. This removes the dependency on
Redis for session storage and simplifies horizontal
scaling.

All existing sessions will be invalidated after deploy.
Clients must update to use the new /auth/token endpoint.

BREAKING CHANGE: the /auth/login endpoint now returns a
JWT token instead of setting a session cookie. All API
requests must include the Authorization header with a
Bearer token.

Refs: #245, #312
```

## 4. Multi-file refactor

```bash
refactor(db): extract query builders into dedicated modules

Move inline SQL query construction from repository classes
into specialized query builder modules. This reduces
duplication across 12 repository files and centralizes
query logic for easier testing.
```

## 5. Documentation

```bash
docs: add API authentication guide to README
```

## 6. Chore without scope

```bash
chore: upgrade eslint to v9 and update config format
```

## 7. Performance improvement

```bash
perf(worker): add caching for product catalog queries

Implement Redis caching for product catalog queries, reducing
response time from 500ms to 50ms for cached responses.
```

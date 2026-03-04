# Pull Request Review Example

---

## PR #187 — Add rate limiting to public API endpoints

**Author:** @maria-dev
**Branch:** `feature/rate-limit` → `main`
**Files changed:** 8 | **+342** / **−41**

---

## Executive Summary

This PR implements rate limiting on public API endpoints using a token bucket-based middleware with Redis storage. The overall approach is solid and well-structured, but there is a critical issue in the fallback configuration when Redis is unavailable — the middleware silently disables rate limiting, leaving the API unprotected. There are also recommended improvements for header handling and test coverage.

**Verdict: Request Changes**

---

## Findings

### Critical

#### 1. Rate limiting silently disabled when Redis goes down
`src/middleware/rateLimiter.ts:45`

The catch block in the Redis connection fallback returns `next()` without any rate limiting. If Redis becomes unavailable, all endpoints are left unprotected.

```typescript
// Current code
catch (error) {
  logger.warn('Redis unavailable, skipping rate limit');
  return next();
}
```

**Suggestion:** Implement an in-memory fallback using `Map` with TTL, or reject requests with `503 Service Unavailable` when the rate limiter is unavailable.

```typescript
catch (error) {
  logger.error('Redis unavailable, using in-memory fallback');
  return inMemoryRateLimiter.check(req, res, next);
}
```

---

### Major

#### 2. `Retry-After` header returns value in milliseconds instead of seconds
`src/middleware/rateLimiter.ts:72`

RFC 7231 specifies that the `Retry-After` header must contain the value in seconds. The current code passes the Redis TTL value directly, which is in milliseconds.

```typescript
// Current code
res.set('Retry-After', String(ttl));

// Suggestion
res.set('Retry-After', String(Math.ceil(ttl / 1000)));
```

#### 3. Rate limit key does not account for authentication
`src/middleware/rateLimiter.ts:28`

The key uses only the request IP. Authenticated users behind a corporate proxy would share the same limit. Consider including the user ID in the key when authenticated.

```typescript
// Suggestion
const key = req.user?.id
  ? `rate:user:${req.user.id}`
  : `rate:ip:${req.ip}`;
```

---

### Minor

#### 4. Hardcoded configuration constants
`src/middleware/rateLimiter.ts:8-10`

The rate limit values (100 requests, 60s window) are hardcoded. Moving them to environment variables or config would allow adjustments without redeploying.

#### 5. Test does not cover Redis unavailable scenario
`tests/middleware/rateLimiter.test.ts`

Tests cover the normal flow and the rate limit exceeded scenario, but do not test behavior when Redis is offline. Given critical finding #1, this scenario needs coverage.

---

### Nitpick

#### 6. Middleware name could be more specific
`src/middleware/rateLimiter.ts:15`

`rateLimiter` is generic. Since it is applied only to public endpoints, `publicApiRateLimiter` would better communicate the intent.

#### 7. Outdated comment
`src/middleware/rateLimiter.ts:3`

The comment says "// TODO: implement rate limiting" but the implementation is already done in this PR.

---

## Summary by Severity

| Severity | Count |
|----------|-------|
| Critical | 1 |
| Major | 2 |
| Minor | 2 |
| Nitpick | 2 |

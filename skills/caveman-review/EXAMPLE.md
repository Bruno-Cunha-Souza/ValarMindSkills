# Caveman Review — Example

## PR #187 — Add rate limiting to public API endpoints

**Author:** @maria-dev  
**Branch:** `feature/rate-limit` → `main`  
**Files changed:** 8 | **+342** / **−41**

---

## Executive Summary

Token-bucket rate limiter with Redis backing, applied to public endpoints. Solid shape, but the Redis-failure path silently disables the limiter.

> **Verdict:** Request Changes

---

## Findings

### Critical

- `src/middleware/rateLimiter.ts:45` — catch block calls `next()` with no limiter. Fall back to in-memory limiter or return `503`.

```ts
catch (error) {
  logger.error('Redis unavailable, using in-memory fallback');
  return inMemoryRateLimiter.check(req, res, next);
}
```

### Major

- `src/middleware/rateLimiter.ts:72` — `Retry-After` value is ms, RFC 7231 wants seconds. Divide by 1000 and ceil.
- `src/middleware/rateLimiter.ts:28` — rate key is IP-only; users behind a proxy share a bucket. Key by user id when authenticated.

```ts
const key = req.user?.id ? `rate:user:${req.user.id}` : `rate:ip:${req.ip}`;
```

### Minor

- `src/middleware/rateLimiter.ts:8-10` — limits hardcoded. Move to env vars.
- `tests/middleware/rateLimiter.test.ts` — no coverage for Redis-down path. Add a test that forces the catch branch.

---

## Severity Count

| Severity | Count |
| :--- | :--- |
| Critical | 1 |
| Major | 2 |
| Minor | 2 |
| Nitpick | 0 |

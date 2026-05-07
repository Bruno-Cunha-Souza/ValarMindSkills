# Pull Request Review Examples

Two canonical templates:

1. **Request Changes** — a worked review with findings across four severities.
2. **Approve / LGTM** — zero-findings template used when Step 8 verification yields no Critical / Major / Minor findings.

---

## Template 1 — Request Changes (worked example)

### PR #187 — Add rate limiting to public API endpoints

**Author:** @maria-dev
**Branch:** `feature/rate-limit` → `main`
**Files changed:** 8 | **+342** / **−41**

---

### Executive Summary

This PR implements rate limiting on public API endpoints via token-bucket middleware with Redis storage. The approach is solid, but a critical issue in the Redis-down fallback silently disables rate limiting, leaving the API unprotected. Recommended improvements for header handling and test coverage.

> **Verdict:** Request Changes

---

### Findings

#### Critical

##### 1. Rate limiting silently disabled when Redis goes down

`src/middleware/rateLimiter.ts:45` · **Confidence:** High

The catch block in the Redis connection fallback returns `next()` without any rate limiting. If Redis becomes unavailable, all endpoints are left unprotected.

```typescript
// Current code (verbatim from diff)
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

#### Major

##### 2. `Retry-After` header returns value in milliseconds instead of seconds

`src/middleware/rateLimiter.ts:72` · **Confidence:** High

RFC 7231 specifies that the `Retry-After` header must contain the value in seconds. The current code passes the Redis TTL value directly, which is in milliseconds.

```typescript
// Current code (verbatim from diff)
res.set('Retry-After', String(ttl));
```

**Suggestion:**

```typescript
res.set('Retry-After', String(Math.ceil(ttl / 1000)));
```

##### 3. Rate limit key does not account for authentication

`src/middleware/rateLimiter.ts:28` · **Confidence:** Medium

The key uses only the request IP. Authenticated users behind a corporate proxy would share the same limit. Consider including the user ID in the key when authenticated.

```typescript
// Current code (verbatim from diff)
const key = `rate:ip:${req.ip}`;
```

**Suggestion:**

```typescript
const key = req.user?.id
  ? `rate:user:${req.user.id}`
  : `rate:ip:${req.ip}`;
```

---

#### Minor

##### 4. Hardcoded configuration constants

`src/middleware/rateLimiter.ts:8-10` · **Confidence:** High

The rate limit values (100 requests, 60s window) are hardcoded. Moving them to environment variables or config would allow adjustments without redeploying.

```typescript
// Current code (verbatim from diff)
const MAX_REQUESTS = 100;
const WINDOW_MS = 60_000;
```

##### 5. Test does not cover Redis unavailable scenario

`tests/middleware/rateLimiter.test.ts` · **Confidence:** High

Tests cover the normal flow and the rate limit exceeded scenario, but do not test behavior when Redis is offline. Given critical finding #1, this scenario needs coverage.

---

#### Nitpick

##### 6. Middleware name could be more specific

`src/middleware/rateLimiter.ts:15` · **Confidence:** Low

`rateLimiter` is generic. Since it is applied only to public endpoints, `publicApiRateLimiter` would better communicate the intent.

##### 7. Outdated comment

`src/middleware/rateLimiter.ts:3` · **Confidence:** High

The comment says `// TODO: implement rate limiting` but the implementation is already done in this PR.

---

### Summary by Severity

| Severity | Count |
| :--- | :--- |
| Critical | 1 |
| Major | 2 |
| Minor | 2 |
| Nitpick | 2 |

### Verification log (Step 8)

- [x] Every cited `path:line` exists in the diff
- [x] Every code quote is verbatim from the diff
- [x] Every finding has `Severity` + `Confidence`
- [x] Verdict (`Request Changes`) matches highest severity (`Critical`)
- [x] No Minor was promoted to Major

---

## Template 2 — Approve / LGTM (zero-findings)

Use this template **only** when Step 8 verification passes with zero Critical / Major / Minor findings. Nitpicks alone do not block `Approve`.

> Do not synthesize findings to populate this template. Zero findings is a valid outcome.

---

### PR #204 — Replace `lodash.get` with optional chaining in user service

**Author:** @joao-dev
**Branch:** `chore/drop-lodash-get` → `main`
**Files changed:** 3 | **+18** / **−24**

---

### Executive Summary

Mechanical replacement of `lodash.get(obj, 'a.b.c')` calls with native optional chaining (`obj?.a?.b?.c`) across the user service. Behavior is preserved; tests cover the previously-asserted paths and pass on the new code. Dependency footprint shrinks by one transitive package. No Critical / Major / Minor issues found.

> **Verdict:** Approve · **LGTM**

---

### Findings

_None — see verification log below._

---

### Summary by Severity

| Severity | Count |
| :--- | :--- |
| Critical | 0 |
| Major | 0 |
| Minor | 0 |
| Nitpick | 0 |

### Verification log (Step 8)

- [x] Diff reviewed end-to-end (all 3 files, all 42 changed lines)
- [x] Behavioral equivalence checked: every `lodash.get(x, path, default)` mapped to `x?.path ?? default` correctly
- [x] No new control flow, no new error paths, no new external calls
- [x] Existing tests cover the changed code paths
- [x] No type narrowing regressions (TS strict mode preserved)
- [x] No fabricated findings to populate the report

---

## Notes for the model

- Pick **Template 1** when at least one Critical / Major / Minor finding survives Step 8 verification.
- Pick **Template 2** when zero Critical / Major / Minor findings survive — Nitpick-only output also goes here, listed under a `Nitpick` subsection above the `Summary by Severity` table; the verdict remains `Approve · LGTM` if the user opted to surface Nitpicks.
- Never mix templates. Never invent findings to avoid using Template 2.

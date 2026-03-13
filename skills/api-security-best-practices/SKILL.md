---
name: api-security-best-practices
description: "Implement secure API design for REST and GraphQL APIs in Python (FastAPI),
  Go (Gin/Fiber), and TypeScript (Bun/Elysia). Covers authentication, authorization,
  input validation, rate limiting, supply chain security, and OWASP API Top 10 2023."
source: ValarMindSkills
---

# API Security Best Practices

## When to Use

Use this skill when:

- Designing new API endpoints in **FastAPI**, **Gin**, **Fiber**, or **Elysia**
- Reviewing existing APIs for security weaknesses
- Implementing authentication (JWT, OAuth 2.1, API keys) and authorization (RBAC, ABAC)
- Adding rate limiting, input validation, or security headers
- Preparing for a security audit or compliance review
- Responding to a vulnerability report or CVE affecting your stack

## Security Foundations (Core Principles)

These principles are language and framework agnostic:

| Principle | Meaning |
| --- | --- |
| **Defence in Depth** | Multiple independent security layers — one failure should not compromise the system |
| **Least Privilege** | Every component and user gets only the minimum access needed |
| **Zero Trust** | Never assume a request is safe because it originates inside the network |
| **Shift Left** | Embed security checks in development and CI, not only in production monitoring |
| **Fail Secure** | On error, deny access rather than allow it |

## Authentication & Authorization

### OAuth 2.1 Key Changes from 2.0

OAuth 2.1 (draft consolidation) codifies best practices that were previously scattered across RFCs:

- **PKCE is mandatory for all clients** — including confidential server-side clients
- **Implicit flow removed** — use Authorization Code + PKCE instead
- **Resource Owner Password Credentials (ROPC) removed** — migrate to Device Flow for CLI/native apps
- **Redirect URIs must be exact matches** — no wildcard or partial matching

### DPoP (Demonstrating Proof-of-Possession)

DPoP binds an access token to a specific client key pair, preventing token replay if stolen:

1. Client generates an ephemeral key pair per session
2. Each request includes a signed `DPoP` header with the public key thumbprint and request method/URI
3. Authorization server issues a token bound to that thumbprint
4. Resource server verifies the `DPoP` header on every request

Use DPoP when tokens cross trust boundaries (public APIs, mobile apps) and bearer token theft is a realistic threat.

### JWT Best Practices

- Prefer **RS256** (RSA) or **EdDSA** (Ed25519) over **HS256** (HMAC) — asymmetric keys allow public verification without sharing the secret
- Always validate `iss` (issuer) and `aud` (audience) claims explicitly — do not rely on library defaults
- Set short access token TTL (15–60 min); use refresh tokens for long sessions
- Implement **rotating refresh tokens with reuse detection**: each use invalidates the current token and issues a new one — a second use of the same token should revoke the entire family

### Framework Callouts

#### FastAPI

```python
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/token")

async def get_current_user(token: str = Depends(oauth2_scheme)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=["RS256"],
                             audience="your-api", issuer="your-auth-server")
        user_id: str = payload.get("sub")
        if user_id is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception
    return user_id
```

Packages: `fastapi-users` (full auth solution), `python-jose` or `authlib` (JWT), `passlib[bcrypt]` (password hashing).

#### Gin

```go
// Use appleboy/gin-jwt middleware
authMiddleware, _ := jwt.New(&jwt.GinJWTMiddleware{
    Realm:       "your-api",
    Key:         []byte(os.Getenv("JWT_SECRET")),
    Timeout:     time.Hour,
    IdentityKey: "user_id",
    PayloadFunc: func(data interface{}) jwt.MapClaims {
        if v, ok := data.(*User); ok {
            return jwt.MapClaims{"user_id": v.ID}
        }
        return jwt.MapClaims{}
    },
})
r.POST("/auth/login", authMiddleware.LoginHandler)
auth := r.Group("/api")
auth.Use(authMiddleware.MiddlewareFunc())
```

#### Fiber

```go
// Use gofiber/contrib/jwt
app.Use(jwtware.New(jwtware.Config{
    SigningKey: jwtware.SigningKey{
        JWTAlg: jwtware.RS256,
        Key:    publicKey,
    },
    ErrorHandler: func(c *fiber.Ctx, err error) error {
        return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "invalid token"})
    },
}))
```

#### Elysia (Bun)

```typescript
import { Elysia } from "elysia";
import { jwt } from "@elysiajs/jwt";
import { bearer } from "@elysiajs/bearer";

// Note: @elysiajs/bearer ONLY extracts the token from the Authorization header.
// It does NOT validate it. JWT validation must be explicit.
const app = new Elysia()
  .use(jwt({ name: "jwt", secret: process.env.JWT_SECRET! }))
  .use(bearer())
  .derive(async ({ bearer, jwt }) => {
    const payload = await jwt.verify(bearer);
    if (!payload) throw new Error("Unauthorized");
    return { user: payload };
  });
```

### Anti-Pattern: `allow_credentials=True` + Wildcard Origin

```python
# CRITICAL — CVE-2025-34291 (Langflow) class of vulnerability
# This combination allows any website to make credentialed cross-origin requests
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],          # ← wildcard
    allow_credentials=True,       # ← credentials
    allow_methods=["*"],
    allow_headers=["*"],
)
# Browsers will reject this combination per the CORS spec,
# but some HTTP clients (curl, httpx) will not — creating SSRF and data exfiltration risks.
# ALWAYS use an explicit allowlist when credentials=True.
```

## Input Validation & Injection Prevention

**Principle: validate at the boundary, reject early.**

Accept only what you explicitly define; reject everything else.

### Framework Callouts: Input Validation

#### FastAPI / Pydantic

```python
from pydantic import BaseModel, ConfigDict, field_validator
import re

class CreateUserRequest(BaseModel):
    model_config = ConfigDict(strict=True)  # reject coercion (int → str, etc.)

    email: str
    username: str
    age: int

    @field_validator("email")
    @classmethod
    def validate_email(cls, v: str) -> str:
        # Avoid regex engines on untrusted input — use a simple check or a library
        # CVE-2024-3772: pydantic < 2.4.0 ReDoS via email validator on long inputs
        if len(v) > 254 or "@" not in v:
            raise ValueError("invalid email")
        return v.lower()
```

> **CVE-2024-3772**: pydantic < 2.4.0 — ReDoS via malformed email strings. Upgrade to 2.4.0+.
> **CVE-2024-24762**: python-multipart — unbounded memory on form-data. Pin `python-multipart >= 0.0.7`.

#### Go (pgx / sqlx)

```go
// Always use parameterized queries — never fmt.Sprintf for SQL
row := db.QueryRow(ctx,
    "SELECT id, email FROM users WHERE id = $1", userID)

// go-playground/validator for struct validation
type CreateUserRequest struct {
    Email    string `json:"email" validate:"required,email,max=254"`
    Username string `json:"username" validate:"required,alphanum,min=3,max=32"`
}

validate := validator.New()
if err := validate.Struct(req); err != nil {
    c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
    return
}
```

#### Elysia (TypeBox)

```typescript
import { t } from "elysia";

// TypeBox schema — validated at compile-time AND runtime
// additionalProperties: false prevents mass assignment
app.post("/users", ({ body }) => createUser(body), {
  body: t.Object({
    email: t.String({ format: "email", maxLength: 254 }),
    username: t.String({ minLength: 3, maxLength: 32, pattern: "^[a-zA-Z0-9_]+$" }),
    age: t.Integer({ minimum: 0, maximum: 150 }),
  }, { additionalProperties: false }),
});
```

### Injection Prevention Rules

| Vector | Prevention |
| --- | --- |
| SQL Injection | Parameterized queries or ORM — never string concatenation |
| NoSQL Injection | Cast/validate input type before passing to query builder |
| Command Injection | Avoid shell execution; if unavoidable, use argument arrays, not strings |
| SSRF | URL allowlist + block RFC1918/loopback; do not follow redirects automatically |
| XXE | Disable external entity processing in XML parsers |

## Rate Limiting & Throttling

### Algorithm Selection

| Algorithm | Best for | Trade-off |
| --- | --- | --- |
| **Token Bucket** | APIs with bursty traffic | Allows short bursts above average rate |
| **Sliding Window** | Strict fairness, auth endpoints | Higher Redis memory usage |
| **Fixed Window** | Simple implementations | Boundary burst vulnerability |

Use **sliding window** for authentication endpoints (brute force prevention) and **token bucket** for general API traffic.

### For AI APIs: Rate Limit by Token Count

Request count is an insufficient proxy for compute cost. Rate limit by input + output token count using a leaky-bucket or quota system, similar to OpenAI's TPM (tokens per minute) model.

### Framework Callouts: Rate Limiting

#### FastAPI (SlowAPI)

```python
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

limiter = Limiter(key_func=get_remote_address, storage_uri="redis://localhost:6379")
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

@app.post("/auth/login")
@limiter.limit("5/15minutes")  # strict limit for auth endpoints
async def login(request: Request, ...):
    ...

@app.get("/api/data")
@limiter.limit("100/minute")
async def get_data(request: Request, ...):
    ...
```

#### Gin Rate Limiting

```go
// Using gin-contrib/ratelimit or a custom Redis middleware
func RateLimitMiddleware(rdb *redis.Client, limit int, window time.Duration) gin.HandlerFunc {
    return func(c *gin.Context) {
        key := "rl:" + c.ClientIP()
        count, _ := rdb.Incr(ctx, key).Result()
        if count == 1 {
            rdb.Expire(ctx, key, window)
        }
        if int(count) > limit {
            c.Header("Retry-After", strconv.Itoa(int(window.Seconds())))
            c.AbortWithStatusJSON(429, gin.H{"error": "rate limit exceeded"})
            return
        }
        c.Header("X-RateLimit-Remaining", strconv.Itoa(limit-int(count)))
        c.Next()
    }
}
```

#### Fiber (built-in) Rate Limiting

```go
import "github.com/gofiber/fiber/v2/middleware/limiter"

app.Use(limiter.New(limiter.Config{
    Max:        100,
    Expiration: 1 * time.Minute,
    KeyGenerator: func(c *fiber.Ctx) string {
        return c.IP()
    },
    LimitReached: func(c *fiber.Ctx) error {
        return c.Status(fiber.StatusTooManyRequests).JSON(fiber.Map{
            "error": "rate limit exceeded",
        })
    },
}))
```

#### Elysia Rate Limiting

```typescript
// Elysia does not include a built-in rate limiter as of 2025
// Use the community plugin or implement middleware:
import { Elysia } from "elysia";

const rateLimitMap = new Map<string, { count: number; reset: number }>();

const rateLimit = (limit: number, windowMs: number) =>
  new Elysia().derive(({ request, set }) => {
    const ip = request.headers.get("x-forwarded-for") ?? "unknown";
    const now = Date.now();
    const entry = rateLimitMap.get(ip) ?? { count: 0, reset: now + windowMs };
    if (now > entry.reset) { entry.count = 0; entry.reset = now + windowMs; }
    entry.count++;
    rateLimitMap.set(ip, entry);
    set.headers["X-RateLimit-Limit"] = String(limit);
    set.headers["X-RateLimit-Remaining"] = String(Math.max(0, limit - entry.count));
    if (entry.count > limit) {
      set.status = 429;
      set.headers["Retry-After"] = String(Math.ceil((entry.reset - now) / 1000));
      return { error: "rate limit exceeded" };
    }
  });
```

### Required Rate Limit Response Headers

```http
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 87
X-RateLimit-Reset: 1740000000
Retry-After: 900
```

## Security Headers & CORS

### CORS Rules

- **Never** combine `allow_origins=["*"]` with `allow_credentials=True`
- Use explicit allowlists — validate `Origin` against a list, not a wildcard regex
- Restrict `allow_methods` to only what each route needs

### Framework Callouts: CORS

#### FastAPI CORS

```python
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://app.example.com", "https://admin.example.com"],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["Authorization", "Content-Type"],
)
```

#### Gin CORS

```go
import "github.com/gin-contrib/cors"

r.Use(cors.New(cors.Config{
    AllowOrigins:     []string{"https://app.example.com"},
    AllowMethods:     []string{"GET", "POST", "PUT", "DELETE"},
    AllowHeaders:     []string{"Authorization", "Content-Type"},
    AllowCredentials: true,
    MaxAge:           12 * time.Hour,
    // AllowAllOrigins: true would prevent cookies/credentials from working
}))
```

#### Fiber CORS

```go
import (
    "github.com/gofiber/fiber/v2/middleware/cors"
    "github.com/gofiber/fiber/v2/middleware/helmet"
)

app.Use(helmet.New())  // sets XSS, MIME sniff, X-Frame-Options, HSTS
app.Use(cors.New(cors.Config{
    AllowOrigins:     "https://app.example.com",
    AllowHeaders:     "Authorization, Content-Type",
    AllowCredentials: true,
}))
```

#### Elysia CORS

```typescript
import cors from "@elysiajs/cors";

app.use(cors({
  origin: ["https://app.example.com"],
  credentials: true,
  allowedHeaders: ["Authorization", "Content-Type"],
}));
```

### Minimum Required Security Headers

| Header | Value | Purpose |
| --- | --- | --- |
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains` | Enforce HTTPS |
| `X-Content-Type-Options` | `nosniff` | Prevent MIME sniffing |
| `X-Frame-Options` | `DENY` | Prevent clickjacking |
| `Content-Security-Policy` | `default-src 'self'` | Restrict resource loading |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Limit referrer leakage |

## Data Protection & Error Handling

### Error Handling Rules

- **Never** return stack traces, SQL errors, or file paths to the client in production
- Return generic error messages to clients; log full details internally
- Use consistent error response shape — `{"error": "message", "code": "ERROR_CODE"}`
- Return `404 Not Found` for missing resources regardless of whether the record exists vs. access is denied for sensitive resources (prevents enumeration)

### Data Serialization Rules

- **Never** serialize ORM model objects directly — define explicit DTO/response schemas
- Explicitly list allowed fields in responses; use `select` or `include` patterns
- Do not log passwords, tokens, secrets, PII, or payment card data

### TLS Requirements

- TLS 1.2 minimum; TLS 1.3 preferred (removes weak cipher suites, provides 0-RTT option)
- Use `HSTS` with `preload` for public APIs
- For internal service-to-service: see mTLS section below

**FastAPI — production error handler example:**

```python
from fastapi import Request
from fastapi.responses import JSONResponse
import logging

logger = logging.getLogger(__name__)

@app.exception_handler(Exception)
async def generic_exception_handler(request: Request, exc: Exception):
    logger.error("Unhandled exception", exc_info=exc, extra={"path": request.url.path})
    return JSONResponse(
        status_code=500,
        content={"error": "An unexpected error occurred"},
    )
```

## Supply Chain Security

### Python

```bash
# Audit installed packages for CVEs
pip-audit

# Lock dependencies with hashes (tamper detection)
pip install --require-hashes -r requirements.txt

# In CI — fail if any vulnerable package is found
pip-audit --strict
```

Recommended: use `poetry.lock` or `pip-compile` with hash verification. Never `--no-verify`.

### Go

```bash
# Verify module checksums against go.sum
go mod verify

# Scan for known vulnerabilities in dependencies
govulncheck ./...

# go.sum MUST be committed — it is the source of truth for module integrity
```

Set `GONOSUMDB` only for internal-only modules. Do not set `GONOSUMCHECK` globally.

### Bun / Node

```bash
# CI — fail if lockfile does not match package.json
bun install --frozen-lockfile

# Audit for CVEs
bun audit           # or: npm audit --audit-level=high

# lockfile (bun.lockb) MUST be committed
```

> **PackageGate (Jan 2026)**: Bun's `trustedDependencies` list allows lifecycle scripts from specific packages by default. Review which packages are on this list and audit their postinstall scripts before adding to production builds.

### Cross-Stack Tools

| Tool | Stack | Command |
| --- | --- | --- |
| `snyk` | All | `snyk test` |
| `trivy` | Container + deps | `trivy fs .` |
| `govulncheck` | Go | `govulncheck ./...` |
| `pip-audit` | Python | `pip-audit` |
| `bun audit` | Bun/Node | `bun audit` |

## mTLS for Service-to-Service Communication

Mutual TLS requires both client and server to present certificates, eliminating reliance on network perimeter for trust.

### When to Use mTLS

- Microservices in zero-trust networks
- Service-to-database connections containing sensitive data
- Internal APIs that should never be reachable from external clients

### mTLS Implementation Options

#### Service mesh (recommended for Kubernetes)

Istio, Linkerd, and Consul Connect provide transparent mTLS without application code changes. The sidecar proxy handles certificate negotiation automatically.

```yaml
# Istio — enforce mTLS for the entire namespace
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: production
spec:
  mtls:
    mode: STRICT
```

#### cert-manager (Kubernetes)

Automates certificate issuance, rotation, and renewal from Let's Encrypt, Vault, or internal CAs. Short certificate validity (24–72 hours) limits the blast radius of a leaked certificate.

#### Application-level (FastAPI example)

```python
import ssl
import httpx

ssl_ctx = ssl.create_default_context(ssl.Purpose.SERVER_AUTH, cafile="ca.pem")
ssl_ctx.load_cert_chain(certfile="client.pem", keyfile="client.key")

async with httpx.AsyncClient(verify=ssl_ctx) as client:
    response = await client.get("https://internal-service/api/data")
```

## AI / LLM API Security

When your API is AI-powered or consumes LLM services:

### Prompt Injection

**OWASP GenAI Top 10 #1 (2025)** — present in ~73% of production LLM deployments.

- Isolate system prompts from user inputs architecturally — never concatenate them into a single string
- Treat LLM output as **untrusted user input** before using it in downstream systems
- Implement output filtering for known injection patterns and sensitive data regexes
- Use behavioral monitoring to detect prompt injection attempts at runtime

### Token-Based Rate Limiting

```python
# Count tokens before sending to LLM; reject if over budget
from tiktoken import encoding_for_model

enc = encoding_for_model("gpt-4o")
token_count = len(enc.encode(user_input))
if token_count > MAX_INPUT_TOKENS:
    raise HTTPException(status_code=400, detail="Input too long")
```

### Compliance Note

**EU AI Act** enforcement begins **August 2, 2026** for high-risk AI systems. APIs that make consequential decisions (credit, hiring, healthcare) must implement risk assessment, human oversight mechanisms, and audit logging.

## OWASP API Security Top 10 (2023)

This is the **2023 list** — the 2019 list is obsolete.

| # | Vulnerability | Key Risk |
| --- | --- | --- |
| **API1** | Broken Object Level Authorization (BOLA) | Attacker accesses another user's resources by changing an ID |
| **API2** | Broken Authentication | Weak tokens, missing expiry, no brute force protection |
| **API3** | Broken Object Property Level Authorization | Over-fetching (returning private fields) or mass assignment (accepting unexpected fields) |
| **API4** | Unrestricted Resource Consumption | No rate limiting — DoS, cost amplification, brute force |
| **API5** | Broken Function Level Authorization (BFLA) | Regular users can call admin functions |
| **API6** | Unrestricted Access to Sensitive Business Flows | Automated abuse of checkout, account creation, voting |
| **API7** | Server-Side Request Forgery (SSRF) | *New in 2023* — server makes requests to attacker-controlled URLs |
| **API8** | Security Misconfiguration | Debug mode in prod, permissive CORS, missing headers, default creds |
| **API9** | Improper Inventory Management | Shadow APIs, deprecated versions, undocumented endpoints |
| **API10** | Unsafe Consumption of APIs | *New in 2023* — trusting third-party API responses without validation |

### Changes from 2019

- **Removed as separate items**: "Excessive Data Exposure" and "Mass Assignment" — merged into API3 (Broken Object Property Level Authorization)
- **Renamed**: "Lack of Resources and Rate Limiting" → API4 "Unrestricted Resource Consumption"
- **Added**: API7 SSRF and API10 Unsafe Consumption of APIs

## Quick Audit Cheat Sheet

Run these checks before deploying any API:

- [ ] **Auth required**: every non-public endpoint returns `401` without a valid token
- [ ] **Authorization checked**: resource ownership verified before returning or modifying data (BOLA)
- [ ] **CORS explicit**: no `allow_origins=["*"]` + `allow_credentials=True` combination
- [ ] **Input validated**: all request bodies/params validated against a schema with strict types
- [ ] **Parameterized queries**: no string concatenation in SQL/database calls
- [ ] **Rate limiting active**: auth endpoints ≤ 5 req/15 min; general API ≤ 100 req/min
- [ ] **Error messages generic**: no stack traces or internal details in `4xx`/`5xx` responses
- [ ] **Security headers present**: `HSTS`, `X-Content-Type-Options`, `X-Frame-Options`, `CSP`
- [ ] **Dependencies audited**: `pip-audit` / `govulncheck` / `bun audit` passing in CI
- [ ] **No debug mode in production**: FastAPI `app = FastAPI(docs_url=None)`, Gin `gin.SetMode(gin.ReleaseMode)`, Fiber `app := fiber.New()`

## Related Skills

- `@web-vulnerabilities` — reference for 100 web vulnerabilities including injection, XSS, and CSRF
- `@api-security-testing` — standalone testing workflow to verify the controls defined here

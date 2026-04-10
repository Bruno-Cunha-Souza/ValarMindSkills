---
name: golang-api-security
description: "Complete security lifecycle specialist for Go 1.25+ REST APIs using Gin or Fiber.
  Auto-detects the framework, audits source code for OWASP API Top 10 2023, middleware
  misconfigurations, AuthN/AuthZ flaws, supply chain CVEs, and 25+ Go-specific
  vulnerability classes. Generates patches with build-gated apply and includes Go-specific
  active testing. Use when auditing, hardening, or fixing security issues in Go API projects."
source: ValarMindSkills
---

# Go API Security Lifecycle

## When to Use

Use this skill when:

- Auditing a **Gin** or **Fiber** API on Go 1.25+ for security issues
- Hardening a Go service before production rollout
- Responding to a vulnerability report against a Go REST API
- Reviewing middleware stacks, JWT/OAuth implementations, or supply chain integrity in a Go project
- Applying or validating fixes for Go-specific issues (race conditions, goroutine leaks, slowloris, ServeMux conflicts)
- Mapping a Go codebase against the **OWASP API Security Top 10 (2023)**

This skill is **Go-native and lifecycle-driven**: it covers identification → analysis → correction → validation in a single workflow. For language-agnostic API testing, complement with `@api-security-testing`. For multi-language design patterns, see `@api-security-best-practices`. Both are referenced explicitly in the relevant phases below.

Out of scope: gRPC, graphql-go, and non-Go services. The skill assumes a Gin or Fiber HTTP API; pure `net/http` projects work with most checks but framework-specific phases are best-effort.

## Prerequisites

Install the following tools before starting an audit:

| Tool | Purpose | Install |
| --- | --- | --- |
| **Go 1.25+** | toolchain | https://go.dev/dl |
| **govulncheck** | CVE scan for Go modules | `go install golang.org/x/vuln/cmd/govulncheck@latest` |
| **gosec** | static security analyzer | `go install github.com/securego/gosec/v2/cmd/gosec@latest` |
| **staticcheck** | linter (catches unsafe patterns) | `go install honnef.co/go/tools/cmd/staticcheck@latest` |
| **osv-scanner** | OSV database cross-check | `go install github.com/google/osv-scanner/cmd/osv-scanner/v2@latest` |
| **nancy** | Sonatype OSS index scan | `go install github.com/sonatype-nexus-community/nancy@latest` |
| **k6** | concurrent load + race trigger | `brew install k6` |
| **httpx** / **curl** | active probing | `pip install httpx[cli]` / system package |

Required access:

- [ ] Read access to the Go module source tree (`go.mod`, `go.sum`, all `*.go` files)
- [ ] Permission to run `go build`, `go test`, and `go test -race`
- [ ] If active testing is in scope: a running instance of the API and authorization to test it

## Phase 0 — Framework Auto-Detection

Detect Gin vs Fiber (and Fiber v2 vs v3) before running the framework-specific phases. Run the steps in order and stop at the first conclusive match.

```bash
# Step 1: declared imports in go.mod
grep -E "github.com/gin-gonic/gin"        go.mod && echo "candidate: gin"
grep -E "github.com/gofiber/fiber/v3"     go.mod && echo "candidate: fiber-v3"
grep -E "github.com/gofiber/fiber/v2"     go.mod && echo "candidate: fiber-v2"

# Step 2: actual usage in source (tiebreaker for monorepos)
rg -l '"github.com/gin-gonic/gin"'         --type go | wc -l   # gin files
rg -l '"github.com/gofiber/fiber/v[23]"'   --type go | wc -l   # fiber files

# Step 3: router instantiation
rg -n 'gin\.(New|Default)\(\)'             --type go
rg -n 'fiber\.New\('                       --type go
```

Persist the result as `$FRAMEWORK ∈ {gin, fiber-v2, fiber-v3, stdlib, mixed}`. The next phases branch on this value.

| `$FRAMEWORK` | Behavior |
| --- | --- |
| `gin` | Run all phases with Gin-specific middleware tables |
| `fiber-v2` | Run all phases with Fiber v2 middleware imports (`gofiber/fiber/v2`) |
| `fiber-v3` | Run all phases with Fiber v3 middleware imports (`gofiber/fiber/v3`) — note that v3 changed many middleware APIs |
| `stdlib` | Skip Phase 2 framework-specific tables; run only `net/http` checks |
| `mixed` | Monorepo detected. Run Phase 0 per-subdirectory; do not merge findings across services. |

## Phase 1 — Static Security Audit

Run the automated tools first, then sweep for patterns the tools miss.

### 1.1 Automated Toolchain

```bash
# Vulnerability database scan (Go's official tool)
govulncheck -json ./... > govulncheck.json

# Static security analyzer (CWE-mapped)
gosec -fmt=json -out=gosec.json ./...

# Generic linter (catches unsafe patterns, shadowing, copy locks)
staticcheck ./...

# Built-in vet (race-prone constructs)
go vet -all ./...

# Race detector (requires tests)
go test -race -count=1 ./...
```

Review every reported issue. Calibration: gosec false-positive rate is high on TLS and unchecked-error checks (G104) — start every gosec finding at **Medium** severity and only promote to **High** with manual confirmation.

### 1.2 Pattern Sweep (manual)

For each category below, run the grep, then read the matching files for context.

| # | Category | Detection |
| --- | --- | --- |
| 1 | **SQL Injection** | `rg 'fmt\.Sprintf\([^)]*(SELECT|INSERT|UPDATE|DELETE)' --type go` and `rg 'db\.(Query|Exec)\(.*\+' --type go` |
| 2 | **XSS** | `rg '"text/template"' --type go` (use `html/template` for HTML output); `rg 'c\.HTML\(|c\.String\('` near user input |
| 3 | **SSRF** | `rg 'http\.(Get|Post|NewRequest)\(' --type go`; `rg 'httputil\.NewSingleHostReverseProxy'` |
| 4 | **Path Traversal** | `rg 'os\.(Open|Create|ReadFile)\(.*c\.(Param|Query)'`; `rg 'filepath\.Join\([^)]*c\.'` |
| 5 | **Command Injection** | `rg 'exec\.Command\([^)]*c\.(Param|Query|PostForm)'` |
| 6 | **Insecure Deserialization** | `rg 'gob\.NewDecoder\('`; `rg 'json\.Unmarshal\([^)]*interface\{\}'` |
| 7 | **Hardcoded Secrets** | `rg -i '(password|secret|api[_-]?key|token)\s*[:=]\s*"[A-Za-z0-9]{8,}"' --type go` + `gosec G101` |
| 8 | **Insecure Crypto** | `rg '"crypto/(md5|des|sha1)"'`; `rg '"math/rand"'` (must be `crypto/rand` for tokens); `rg 'InsecureSkipVerify\s*:\s*true'` |
| 9 | **Stack Trace Exposure** | `rg 'gin\.Default\(\)'` (verbose recovery in prod); `rg 'c\.JSON\([^,]+,\s*err\)'`; `rg 'fmt\.Errorf\("%v",\s*err\)' --type go` |
| 10 | **`unsafe` Package** | `rg 'unsafe\.(Pointer|Sizeof|Offsetof)' --type go` |
| 11 | **Open Redirect** | `rg 'c\.Redirect\([^,]+,\s*c\.(Param|Query)'` |
| 12 | **Log Injection** | `rg 'log\.[A-Z]\w*\([^)]*c\.(Param|Query|PostForm)'` |

For deep remediation patterns per item, see [references/VULNERABILITIES.md](references/VULNERABILITIES.md).

## Phase 2 — Middleware Configuration Analysis

Branch on `$FRAMEWORK`. Each row in the table below maps to a check that must pass before promoting to production.

| Item | Gin | Fiber v2 / v3 |
| --- | --- | --- |
| **Mode/Debug** | `gin.SetMode(gin.ReleaseMode)` mandatory; `gin.Default()` is verbose and leaks stack traces | `fiber.New(fiber.Config{DisableStartupMessage: true})` and avoid `app.Use(logger.New())` with default format in prod |
| **CORS** | `gin-contrib/cors` with explicit `AllowOrigins` allowlist; never `AllowAllOrigins=true` together with `AllowCredentials=true` | `gofiber/fiber/v2/middleware/cors` (or `v3` equivalent); same allowlist rule |
| **Security Headers** | `gin-contrib/secure` or custom middleware setting HSTS, X-Frame-Options, X-Content-Type-Options, CSP | `gofiber/fiber/v2/middleware/helmet` (v2) / `gofiber/fiber/v3/middleware/helmet` (v3) |
| **Rate Limiting** | Redis-backed middleware or `gin-contrib/ratelimit` — strict limit on auth endpoints (≤ 5/15min) | `gofiber/fiber/v2/middleware/limiter` (built-in); same for v3 |
| **CSRF** | `utrack/gin-csrf` for cookie-based auth; not needed for stateless JWT | `gofiber/fiber/v2/middleware/csrf` (or v3 equivalent) for cookie-based auth; not needed for pure JWT |
| **Body Size Limit** | `c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, N)` per handler or via global middleware | `fiber.New(fiber.Config{BodyLimit: N})` |
| **Server Timeouts** | `&http.Server{ReadHeaderTimeout: 10*time.Second, ReadTimeout: 30*time.Second, WriteTimeout: 30*time.Second, IdleTimeout: 120*time.Second}` — wrap `r.Handler()` | Same on the underlying `fasthttp.Server` (Fiber v2) or via `fiber.Config{ReadTimeout, WriteTimeout, IdleTimeout}` |
| **Trusted Proxies** | `r.SetTrustedProxies([]string{"10.0.0.0/8"})` — never `0.0.0.0/0` | `fiber.New(fiber.Config{EnableTrustedProxyCheck: true, TrustedProxies: []string{...}})` |
| **pprof Exposure** | `rg '"net/http/pprof"'` — must NOT auto-register on the public router | Same — block `/debug/pprof/*` from public ingress |
| **TLS Enforcement** | `r.RunTLS(":443", certFile, keyFile)` or terminate at reverse proxy with HSTS | `app.ListenTLS(":443", certFile, keyFile)` or reverse proxy |

Anti-patterns to flag immediately as **High** severity:

- `gin.Default()` in production code (combines logger + recovery with default config that prints stack traces)
- `cors.New(cors.Config{AllowAllOrigins: true, AllowCredentials: true, ...})` — this combination is forbidden by the CORS spec but some HTTP clients honor it
- `r.SetTrustedProxies(nil)` or `r.SetTrustedProxies([]string{"0.0.0.0/0"})` — trusts all `X-Forwarded-For` headers
- Missing `ReadHeaderTimeout` on `http.Server` — exposes the service to slowloris
- `app.Use(logger.New())` with default format printing request body in production (PII leak)

For framework-specific snippets and Fiber v2/v3 API drift, see [references/MIDDLEWARE.md](references/MIDDLEWARE.md).

## Phase 3 — Authentication & Authorization Audit

### 3.1 JWT Library and Validation

```bash
# Library check — alert if archived dgrijalva/jwt-go is still used
grep -E '"github.com/dgrijalva/jwt-go"' go.mod && echo "ARCHIVED: migrate to golang-jwt/jwt/v5"
grep -E '"github.com/golang-jwt/jwt"'   go.mod  # current canonical library

# Validation patterns to verify
rg 'jwt\.Parse\(' --type go        # must pass key func that whitelists alg
rg 'token\.Method' --type go       # explicit alg check
rg 'claims\.(VerifyIssuer|VerifyAudience|VerifyExpiresAt)' --type go
```

JWT validation checklist (each must hold):

- [ ] Algorithm whitelist explicit in `Keyfunc` — reject `none`, accept only RS256/ES256/EdDSA (or HS256 only with rotated server-side secrets)
- [ ] `iss` validated against expected issuer
- [ ] `aud` validated against this service's audience identifier
- [ ] `exp`, `nbf`, `iat` enforced
- [ ] Signing key from env var or secret manager (not hardcoded)
- [ ] Key rotation mechanism documented (kid header + JWKS endpoint)

### 3.2 OAuth 2.1 + PKCE

If the service is an OAuth client or authorization server:

- [ ] PKCE `code_challenge` mandatory for all clients (including confidential)
- [ ] `redirect_uri` exact-match validation (no wildcards, no partial matching)
- [ ] No implicit flow (`response_type=token` removed in OAuth 2.1)
- [ ] No Resource Owner Password Credentials grant (use Device Flow for CLIs)
- [ ] Refresh token rotation with reuse detection (second use revokes the family)

### 3.3 Session Management

If using cookie-based sessions (`gorilla/sessions`, `alexedwards/scs`):

- [ ] `Secure: true`, `HttpOnly: true`, `SameSite: SameSiteStrictMode`
- [ ] Session ID rotated on login (prevents session fixation)
- [ ] Server-side store (Redis, Postgres) — never client-only signed cookies for high-value sessions
- [ ] Inactivity timeout (≤ 30 min) and absolute timeout (≤ 12 h)

### 3.4 Authorization (RBAC/ABAC)

- [ ] Policy library used: `casbin/casbin/v2`, `ory/keto`, or equivalent — never hardcoded role checks scattered across handlers
- [ ] Resource ownership verified before returning or mutating data (BOLA prevention — API1:2023)
- [ ] Function-level authorization on admin endpoints (BFLA prevention — API5:2023)
- [ ] **Route protection completeness**: cross-reference handler registration with auth middleware coverage:

```bash
# List every handler registration
rg -n '\.(GET|POST|PUT|DELETE|PATCH)\(' --type go > all_routes.txt

# List all auth middleware applications
rg -n '\.Use\([^)]*[Aa]uth' --type go > auth_routes.txt

# Manually verify every sensitive route in all_routes.txt is covered by auth_routes.txt
```

### 3.5 Cryptographic Comparison

- [ ] Token / HMAC comparison uses `crypto/subtle.ConstantTimeCompare` (never `==`) to prevent timing attacks
- [ ] `bcrypt.GenerateFromPassword(pw, 12)` minimum cost (recommend 12+ in 2026)
- [ ] Password reset / verification tokens generated from `crypto/rand`, never `math/rand`

## Phase 4 — Dependency & Supply Chain Audit

```bash
# 1. Verify go.sum integrity — fails if any module checksum mismatches
go mod verify

# 2. CVE scan against Go vulnerability database
govulncheck -json ./... > govulncheck.json

# 3. OSV cross-check (covers CVEs not yet in Go's database)
osv-scanner --lockfile=go.sum

# 4. Outdated dependencies
go list -m -u all | grep '\['

# 5. Replace directives — common supply-chain injection vector
grep -E '^replace' go.mod  # any unexpected entry is a finding

# 6. Module proxy / sumcheck configuration
go env GOPROXY GOSUMDB GOPRIVATE GONOSUMCHECK
# GOSUMDB should be "sum.golang.org" (default); GONOSUMCHECK should be empty
```

Archived or risky dependencies to flag (each is at least **Medium**):

| Dep | Reason | Replacement |
| --- | --- | --- |
| `github.com/dgrijalva/jwt-go` | Archived 2021, multiple CVEs | `github.com/golang-jwt/jwt/v5` |
| `github.com/satori/go.uuid` | Last release 2018, panics on bad input | `github.com/google/uuid` |
| `github.com/gin-gonic/gin@<v1.9.1` | CVE-2023-29401 path traversal | upgrade to `>= v1.10.0` |
| `github.com/gofiber/fiber/v2@<v2.52.5` | Multiple security fixes accumulated | upgrade to latest v2 or migrate to v3 |
| `github.com/labstack/echo@<v4.11.0` | CVE-2023-4220 file upload | upgrade |

`go.sum` MUST be committed. Treat any uncommitted `go.sum` change as a supply-chain incident — re-verify with `go mod verify` and inspect the diff.

## Phase 5 — Go-Specific Advanced Vulnerabilities

These are issues unique to Go's runtime, standard library, or memory model. Each is detailed in [references/VULNERABILITIES.md](references/VULNERABILITIES.md).

| # | Vulnerability | Detection | Severity baseline |
| --- | --- | --- | --- |
| 1 | **Race conditions** | `go test -race -count=1 ./...` | High |
| 2 | **Goroutine leaks** | Audit context cancellation in every `go func() {...}`; `rg 'go func' --type go` | Medium |
| 3 | **Panic in HTTP handlers** | Verify `recover()` middleware exists; `rg 'panic\(' --type go` in handler files | High |
| 4 | **`unsafe.Pointer`** | `rg 'unsafe\.' --type go` | Medium (depends on use) |
| 5 | **Integer overflow** | `rg 'int(32|64)\(' --type go` near user input; `gosec G115` | Medium |
| 6 | **Log injection** | `rg 'log\.\w+\([^)]*c\.(Param|Query|PostForm)' --type go` | Medium |
| 7 | **TOCTOU** | `rg 'os\.Stat.*os\.Open' --type go` | Medium |
| 8 | **Slowloris** | Verify `ReadHeaderTimeout` on `http.Server`; `rg 'http\.Server\{' -A 5 --type go` | High |
| 9 | **`http.ServeMux` 1.22+ pattern conflicts** | `rg 'http\.NewServeMux\(\)' --type go` and inspect overlapping registrations | Medium |
| 10 | **File upload** | `rg 'multipart|FormFile' --type go` — verify `MaxBytesReader`, MIME sniff, filename sanitization, zip slip | High |
| 11 | **JSON unknown fields** | `rg 'json\.NewDecoder' --type go` — should call `.DisallowUnknownFields()` | Medium |
| 12 | **JSON deep nesting** | Verify body size limit + reasonable parser depth | Medium |
| 13 | **pprof exposure** | `rg '"net/http/pprof"' --type go` — must not auto-register on public mux | High |
| 14 | **`math/rand` for security** | `rg '"math/rand"' --type go` near tokens/IDs/secrets | Critical |
| 15 | **TLS misconfiguration** | `rg 'tls\.Config\{' -A 5 --type go` — `MinVersion`, no `InsecureSkipVerify`, no weak ciphers | Critical |
| 16 | **Trusted proxy spoofing** | Phase 2 covers; cross-link here | High |
| 17 | **`httputil.ReverseProxy` SSRF** | `rg 'httputil\.(NewSingleHostReverseProxy|ReverseProxy\{)' --type go` — director must validate target | High |
| 18 | **`text/template` in HTML** | `rg '"text/template"' --type go` in any handler returning HTML | High |
| 19 | **bcrypt cost factor < 10** | `rg 'bcrypt\.GenerateFromPassword' --type go` | Medium |
| 20 | **JWT secret rotation absent** | Phase 3 covers; cross-link here | Medium |
| 21 | **`database/sql` null handling** | `rg 'rows\.Scan' --type go` — verify `sql.NullString`/`NullInt64` for nullable columns | Low |
| 22 | **Error wrapping leakage** | `rg 'fmt\.Errorf\("%v"' --type go` in HTTP responses | Medium |
| 23 | **`go:embed` of secrets** | `rg '//go:embed' -A 1 --type go` — verify embedded paths exclude `.env`, `*.pem`, `*.key` |  Critical |
| 24 | **CGO surface** | `rg 'import "C"' --type go` — every CGO file is a memory-safety boundary | Medium |
| 25 | **Open redirect** | Phase 1 covers; cross-link here | Medium |

## Phase 6 — Auto-Fix / Patch Generation

> **Default behavior: NEVER apply patches automatically.** Always present diffs first, group by severity, and require explicit user confirmation per group.

### Patch Protocol

For every finding from Phases 1–5:

1. Generate a unified diff using the matching template from [references/PATCHES.md](references/PATCHES.md)
2. Tag the patch with a **risk classification**:
   - **SAFE** — isolated change, no API contract or behavior shift (e.g., adding `MinVersion: tls.VersionTLS12`)
   - **REVIEW** — affects middleware stack, auth, or shared code paths (e.g., changing CORS allowlist)
   - **BREAKING** — changes the public API contract or response shape (e.g., removing a field exposed via mass assignment)
3. Output the diffs grouped by severity in the report (Phase 8)
4. Prompt the user: *"Apply [Critical] and [High] SAFE patches now? Review REVIEW/BREAKING patches manually first."*

### Apply Sequence

When the user confirms a group:

```bash
# For each patch, in severity order:
# 1. Apply via Edit tool (one file at a time, never bulk Write)
# 2. Build gate
go build ./...
# If build fails:
#   git restore <file>
#   re-emit the patch as "manual review required"
#   continue to next patch
```

### Post-Patch Validation

After all confirmed patches are applied:

```bash
# Re-run automated audit to verify findings are gone
gosec ./...
govulncheck ./...
go test -race ./...

# Build validation
go build ./...

# If unit/integration tests exist
go test ./...
```

The skill must report any patch that introduced new findings or test failures and offer to revert via `git restore`.

## Phase 7 — Active Testing

For generic OWASP API Top 10 attack payloads (auth bypass, BOLA, SQLi, NoSQL injection, mass assignment, rate limit bypass, CORS reflection, JWT confusion), **delegate to `@api-security-testing`** Phases 1–7. Do not duplicate them here.

Return to this phase for **Go-specific** attacks not covered by the generic skill. All payloads live in [references/TESTING_PAYLOADS.md](references/TESTING_PAYLOADS.md):

| Attack | Triggers | Expected if vulnerable |
| --- | --- | --- |
| **Slowloris** | Slow `Header:` line writes against `http.Server` without `ReadHeaderTimeout` | Connection held until exhaustion; goroutine count climbs in pprof |
| **pprof extraction** | `curl https://target/debug/pprof/goroutine?debug=2` | Full stack dump returned (should be 404 in prod) |
| **Race trigger via k6** | 100 VUs hammering the same endpoint that mutates shared state | `go test -race` reproducing the data race; sporadic 500s or panics |
| **JSON bomb** | Deeply nested JSON (`[[[[[[...]]]]]]`) without `MaxBytesReader` and no decoder depth limit | OOM or stack overflow |
| **gzip bomb** | 10 MB compressed payload that decompresses to 10 GB | OOM if `MaxBytesReader` is not applied to the decompressed stream |
| **ServeMux conflict** (Go 1.22+) | Send `OPTIONS` and `POST` to the same path with overlapping pattern registrations | Panic at startup (caught at registration) or unexpected handler dispatch at runtime |
| **Goroutine leak detection** | Send 1000 cancelled requests, then check `runtime.NumGoroutine()` via expvar | Goroutine count keeps climbing → leaked goroutines on cancellation |
| **Concurrent map write** | Concurrent writes to a non-`sync.Map` shared map via 10 VUs | Panic: `concurrent map writes` |

## Phase 8 — Security Report

Generate the report in **Report Format v1**. Versioned because the schema is meant to be machine-parseable for downstream tooling.

```markdown
# Go API Security Report — <project name>

## Executive Summary
- **Framework detected:** Gin v1.10.1 / Fiber v3.0.0 / stdlib / mixed
- **Go version:** 1.25.x
- **Files audited:** N
- **Findings:** Critical X · High Y · Medium Z · Low W · Info V
- **OWASP API Top 10 2023 categories affected:** N / 10
- **Patches generated:** P (S SAFE · R REVIEW · B BREAKING)
- **Patches applied:** A (post-confirmation)
- **Post-fix validation:** PASS / FAIL

## Findings Table

| ID | Severity | OWASP | CWE | File:Line | Title | Risk tag | Status |
|----|----------|-------|-----|-----------|-------|----------|--------|
| GOAPI-001 | Critical | API1:2023 | CWE-639 | `handlers/orders.go:42` | BOLA — missing user_id check in GetOrder | SAFE | Patched |
| GOAPI-002 | High     | API8:2023 | CWE-489 | `main.go:18`            | gin.Default() in production | REVIEW | Diff available |
| GOAPI-003 | High     | API4:2023 | CWE-770 | `main.go:34`            | Missing ReadHeaderTimeout (slowloris) | SAFE | Patched |

## Detailed Findings

### GOAPI-001 — Critical — BOLA in GetOrder handler

- **OWASP:** API1:2023 Broken Object Level Authorization
- **CWE/CVE:** CWE-639 / N/A
- **Location:** `handlers/orders.go:42`
- **Framework:** Gin v1.10.1
- **Description:** The `GetOrder` handler retrieves an order by URL path parameter without verifying that the authenticated user owns the order. Any authenticated user can read any other user's orders by guessing or enumerating IDs.
- **Impact:** Full read access to all orders in the system. Severity Critical because the data is sensitive (PII + payment) and the attack requires only a valid token.
- **Evidence:**
  ```go
  func GetOrder(c *gin.Context) {
      order, _ := db.GetOrder(c.Param("id"))
      c.JSON(200, order)
  }
  ```
- **Fix (diff):**
  ```diff
  - func GetOrder(c *gin.Context) {
  -     order, _ := db.GetOrder(c.Param("id"))
  -     c.JSON(200, order)
  - }
  + func GetOrder(c *gin.Context) {
  +     userID := c.GetString("user_id")
  +     order, err := db.GetOrderForUser(c.Param("id"), userID)
  +     if err != nil {
  +         c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
  +         return
  +     }
  +     c.JSON(http.StatusOK, order)
  + }
  ```
- **Risk tag:** SAFE
- **Post-fix test:**
  ```bash
  # As user_b, attempt to read user_a's order — expect 404
  curl -H "Authorization: Bearer $USER_B_TOKEN" https://target/api/orders/$USER_A_ORDER_ID
  ```
- **References:** OWASP API1:2023, CWE-639

## OWASP API Top 10 2023 Compliance Matrix

- [ ] **API1** Broken Object Level Authorization — 1 finding (GOAPI-001)
- [x] **API2** Broken Authentication
- [x] **API3** Broken Object Property Level Authorization
- [ ] **API4** Unrestricted Resource Consumption — 1 finding (GOAPI-003)
- [x] **API5** Broken Function Level Authorization
- [x] **API6** Unrestricted Access to Sensitive Business Flows
- [x] **API7** Server-Side Request Forgery
- [ ] **API8** Security Misconfiguration — 1 finding (GOAPI-002)
- [x] **API9** Improper Inventory Management
- [x] **API10** Unsafe Consumption of APIs

## Remediation Roadmap

1. **Critical (immediate):** GOAPI-001
2. **High (≤ 48h):** GOAPI-002, GOAPI-003
3. **Medium (next sprint):** ...
4. **Low (next refactor):** ...
```

### Severity Reference

| Severity | CVSS Range | Example |
| --- | --- | --- |
| **Critical** | 9.0–10.0 | BOLA returning any user's data, hardcoded JWT secret, `math/rand` for tokens |
| **High** | 7.0–8.9 | SQLi, SSRF reaching internal services, `gin.Default()` in prod, slowloris exposure |
| **Medium** | 4.0–6.9 | Missing rate limiting, CORS misconfig, log injection, unknown JSON fields accepted |
| **Low** | 1.0–3.9 | Version disclosure, `database/sql` null handling, missing security headers |
| **Informational** | N/A | Outdated but non-vulnerable dependencies, debug logs in staging |

## Quick Audit Cheat Sheet

Run before every release:

- [ ] `gin.SetMode(gin.ReleaseMode)` (Gin) or `fiber.Config{DisableStartupMessage: true}` (Fiber) in production binary
- [ ] No `gin.Default()` in production code paths
- [ ] All SQL queries use parameterized form (`$1`/`?`) — no `fmt.Sprintf` building queries
- [ ] JWT validation whitelists `alg` (no `none`), validates `iss`/`aud`/`exp`
- [ ] `crypto/rand` (never `math/rand`) for tokens, IDs, password reset codes
- [ ] `crypto/subtle.ConstantTimeCompare` for token equality checks
- [ ] `bcrypt` cost factor ≥ 12
- [ ] `http.Server{ReadHeaderTimeout: ...}` set (slowloris prevention)
- [ ] `http.MaxBytesReader` on every endpoint accepting bodies
- [ ] CORS explicit allowlist; never `*` + `AllowCredentials: true`
- [ ] `r.SetTrustedProxies` configured (not `nil`, not `0.0.0.0/0`)
- [ ] `net/http/pprof` not exposed on the public router
- [ ] `go test -race ./...` passes
- [ ] `govulncheck ./...` returns no findings
- [ ] `go mod verify` passes
- [ ] No archived dependencies (`dgrijalva/jwt-go`, `satori/go.uuid`)
- [ ] Recovery middleware in place; no raw `panic` reaches the response writer
- [ ] `json.NewDecoder(...).DisallowUnknownFields()` on all request decoders

## OWASP API Top 10 2023 → Go Prevention Mapping

| # | Vulnerability | Go Prevention |
| --- | --- | --- |
| **API1** | Broken Object Level Authorization | Verify resource ownership in handler before returning/mutating; use Casbin for centralized policy |
| **API2** | Broken Authentication | golang-jwt/jwt/v5 with explicit alg whitelist; bcrypt cost ≥ 12; constant-time token compare |
| **API3** | Broken Object Property Level Authorization | Explicit response DTO structs (no direct ORM model serialization); `json.NewDecoder.DisallowUnknownFields()` for inputs |
| **API4** | Unrestricted Resource Consumption | Rate limiting middleware; `http.MaxBytesReader`; `ReadHeaderTimeout`; `BodyLimit` (Fiber) |
| **API5** | Broken Function Level Authorization | RBAC middleware on admin route group; explicit role check before sensitive operations |
| **API6** | Unrestricted Access to Sensitive Business Flows | CAPTCHA / device fingerprint on signup/checkout; per-user rate limits |
| **API7** | Server-Side Request Forgery | URL allowlist + block RFC1918/loopback; `httputil.ReverseProxy` director must validate target host |
| **API8** | Security Misconfiguration | Release mode; CORS allowlist; security headers; no pprof exposure; TLS 1.2+; `ErrorHandler` strips internals |
| **API9** | Improper Inventory Management | Document all `/v1/`, `/v2/` routes; remove `/legacy/` and `/beta/` from production; OpenAPI spec maintained |
| **API10** | Unsafe Consumption of APIs | Validate third-party API responses against schemas; do not blindly forward upstream errors; mTLS for internal calls |

## Related Skills

- `@api-security-testing` — language-agnostic active testing workflow (Phases 1–7 of generic OWASP attacks)
- `@api-security-best-practices` — multi-language secure design patterns (FastAPI, Gin, Fiber, Elysia)
- `@web-vulnerabilities` — base catalog of 100+ web vulnerability classes
- `@code-review` — security-aware code review for PRs

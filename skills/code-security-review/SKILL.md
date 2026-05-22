---
name: code-security-review
description: "Web+API+Go+Next.js+Python security lifecycle. FastAPI/Django/Flask/Gin/Fiber/Elysia/Next.js 16 App Router. Phase 0 stack detect. Design + active testing + Go/Next/Python stack-specific vulns + 100-vuln catalog. OWASP Web 2021 + API 2023."
source: ValarMindSkills
---

# Code Security Review

Lifecycle skill for REST and GraphQL APIs: covers **secure design** (controls to implement) and **active security testing** (payloads to validate those controls). One skill, two complementary modes — invoke whichever fits the current phase of work.

## When to Use

Use this skill when:

- **Designing** new endpoints or middleware in **FastAPI**, **Gin**, **Fiber**, or **Elysia** (→ `references/DESIGN_CONTROLS.md`)
- **Reviewing** an existing API for security weaknesses against the OWASP API Top 10 (2023)
- **Pre-release security assessment** before deploying to production (→ `references/TESTING_PHASES.md`)
- **Bug bounty** engagements or **pentest** of an API target
- Implementing or auditing **AuthN/AuthZ** (JWT, OAuth 2.1, DPoP, API keys, RBAC/ABAC)
- Adding **rate limiting**, **input validation**, **CORS**, or **security headers**
- **Reporting** findings — use the standardized template in `references/REPORT_TEMPLATE.md`
- Consulting the **catalog of 100 web vulnerabilities** by category (→ `references/WEB_VULNERABILITIES.md`)

This skill is **fully standalone** — every payload, snippet, and checklist needed lives in this directory.

## How This Skill Is Organized

| File / Directory | Use when |
| --- | --- |
| `SKILL.md` (this file) | Foundations, Phase 0 stack detection, OWASP API Top 10 map, audit cheat sheet |
| `references/DESIGN_CONTROLS.md` | Implementing or reviewing controls (proactive) — language-agnostic |
| `references/TESTING_PHASES.md` | Running 7-phase active testing workflow (reactive) — language-agnostic |
| `references/REPORT_TEMPLATE.md` | Documenting findings with consistent severity rubric |
| `references/WEB_VULNERABILITIES.md` | Reference catalog of 100 web vulnerabilities by category (XSS, CSRF, deserialization, mobile/IoT, etc.) |
| `references/golang/` | Go stack lifecycle (Gin/Fiber): `API.md`, `MIDDLEWARE.md`, `VULNERABILITIES.md`, `PATCHES.md`, `TESTING_PAYLOADS.md` |
| `references/python/` | Python stack lifecycle (FastAPI / Django / Flask, CPython 3.13/3.14): `API.md`, `CONFIGURATION.md`, `VULNERABILITIES.md`, `PATCHES.md`, `TESTING_PAYLOADS.md` |
| `references/nextjs/` | Next.js 16 App Router lifecycle: `API.md`, `CONFIGURATION.md`, `VULNERABILITIES.md`, `PATCHES.md`, `TESTING_PAYLOADS.md` |
| `scripts/` | Executable probes — automate Phase 0–7 against a live target. See `scripts/README.md`. |

## Phase 0 — Stack Detection

Detect the language/framework before loading stack-specific references. Run the steps in order, stop at the first match.

```bash
# Step 1 — Go (Gin / Fiber)
test -f go.mod && grep -E 'gin-gonic/gin|gofiber/fiber/v[23]' go.mod && echo "stack: go"

# Step 2 — Next.js 16+ App Router
test -f package.json && rg '"next":\s*"\^?1[6-9]' package.json && test -d app/ && echo "stack: nextjs-app"

# Step 3 — Python (FastAPI / Django / Flask)
if test -f pyproject.toml || test -f requirements.txt || test -f setup.py; then
    rg -q '\bfastapi\b' pyproject.toml requirements*.txt 2>/dev/null && echo "stack: python (framework: fastapi)"
    rg -q '\bdjango\b'  pyproject.toml requirements*.txt 2>/dev/null && echo "stack: python (framework: django)"
    rg -q '\bflask\b'   pyproject.toml requirements*.txt 2>/dev/null && echo "stack: python (framework: flask)"
fi

# Step 4 — Elysia / generic
test -f bun.lockb && rg 'elysia' package.json && echo "stack: elysia"
```

| `$STACK` | References to load (in addition to generic) | Notes |
| --- | --- | --- |
| `go` | `references/golang/{API,MIDDLEWARE,VULNERABILITIES,PATCHES,TESTING_PAYLOADS}.md` | Gin v1.10.1+, Fiber v2/v3, OWASP API 2023 + Go-specific (race, slowloris, `math/rand`, pprof, `ServeMux` conflicts) |
| `python` | `references/python/{API,CONFIGURATION,VULNERABILITIES,PATCHES,TESTING_PAYLOADS}.md` | FastAPI 0.115+, Django 5.x, Flask 3.x, CPython 3.13/3.14 — Pydantic Settings, ASGI middleware, pickle/yaml deserialization, JWT alg confusion, ALLOWED_HOSTS, SECRET_KEY, free-threaded 3.14t races |
| `nextjs-app` | `references/nextjs/{API,CONFIGURATION,VULNERABILITIES,PATCHES,TESTING_PAYLOADS}.md` | Next.js 16.2.x App Router — RSC, Server Actions, Route Handlers, `proxy.ts`, `"use cache"`, Image Optimizer |
| `elysia` / `generic` | `references/{DESIGN_CONTROLS,TESTING_PHASES,WEB_VULNERABILITIES,REPORT_TEMPLATE}.md` | Generic references cover the language-agnostic surface |

The generic references (`DESIGN_CONTROLS.md`, `TESTING_PHASES.md`, `WEB_VULNERABILITIES.md`, `REPORT_TEMPLATE.md`) apply to **every** stack — load them in addition to the stack-specific bundle. Stack-specific references inherit the OWASP map and severity rubric from the generic ones; do not duplicate.

## Security Foundations (Core Principles)

These principles are language and framework agnostic:

| Principle | Meaning |
| --- | --- |
| **Defence in Depth** | Multiple independent security layers — one failure should not compromise the system |
| **Least Privilege** | Every component and user gets only the minimum access needed |
| **Zero Trust** | Never assume a request is safe because it originates inside the network |
| **Shift Left** | Embed security checks in development and CI, not only in production monitoring |
| **Fail Secure** | On error, deny access rather than allow it |

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

## OWASP → Phase Map

| OWASP Item | Design (`DESIGN_CONTROLS.md`) | Testing (`TESTING_PHASES.md`) |
| --- | --- | --- |
| API1 BOLA | Authorization patterns | Phase 2.2 Cross-User Access |
| API2 Broken Auth | JWT/OAuth 2.1/DPoP | Phase 1 Authentication Testing |
| API3 BOPLA | DTOs, mass assignment guards | Phase 2.3 Over-Fetching, Phase 2.4 Mass Assignment |
| API4 Unrestricted Consumption | Rate limit algorithms | Phase 4 Rate Limiting Testing |
| API5 BFLA | RBAC enforcement | Phase 2.5 Admin Endpoints |
| API6 Sensitive Flows | Anti-abuse + MFA | Phase 4.5 Brute Force |
| API7 SSRF | URL allowlist | Phase 3.4 SSRF Payloads |
| API8 Misconfiguration | Headers, CORS, debug-off | Phase 5 Info Disclosure, Phase 7 CORS |
| API9 Inventory | Versioning, doc gating | Pre-Testing Checklist |
| API10 Unsafe Consumption | Response validation | Phase 3 Input Injection (mirrored) |

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

## Framework-Specific Production Flags

| Framework | Production Risk | Check |
| --- | --- | --- |
| FastAPI | `/docs`, `/redoc`, `/openapi.json` exposed | `curl https://target/docs` → should return 404 |
| Django | `DEBUG=True`, `ALLOWED_HOSTS=["*"]` | `curl https://target/<nonexistent>` → must not render Django traceback; `python manage.py check --deploy` clean |
| Flask | `app.debug=True`, missing `Flask-Talisman` / `CSRFProtect` | Inspect `app.config`; `curl -I https://target/` must include HSTS + CSP |
| Gin | Debug mode active | `GIN_MODE` env var should be `release` |
| Fiber | Prefork mode or Helmet missing | Review middleware stack |
| Elysia | Bun runtime exposes raw errors | Verify global error handler is in place |

For detailed implementation patterns per framework, see `references/DESIGN_CONTROLS.md`. For active probes that exercise these flags, see `references/TESTING_PHASES.md`.

## Workflow Recommendations

### Greenfield API

1. Read `references/DESIGN_CONTROLS.md` end-to-end before writing the first endpoint.
2. Pick framework section; copy auth/validation/rate-limit/CORS scaffolds.
3. After MVP is functional, run `references/TESTING_PHASES.md` Phase 1–7 against staging.
4. File findings using `references/REPORT_TEMPLATE.md`.

### Existing API (audit / pre-release)

1. Run `references/TESTING_PHASES.md` Phase 1–7 against the target.
2. For each finding, cross-reference the corresponding section in `references/DESIGN_CONTROLS.md` to identify the missing or misconfigured control.
3. Apply fix → re-run the specific phase to validate.
4. File using `references/REPORT_TEMPLATE.md`.

### Bug Bounty / Pentest

1. Pre-Testing Checklist in `references/TESTING_PHASES.md` — confirm scope and authorization.
2. Run all 7 phases; document each finding with `references/REPORT_TEMPLATE.md`.
3. Severity rubric (CVSS bands) in the same file.

### Automated Probes (CI / Pre-Release)

Use `scripts/` for hands-off execution:

```bash
cd skills/code-security-review/scripts/
export TARGET="https://api.staging.example.com"
export TOKEN_USER_A="..." TOKEN_USER_B="..." USER_A_RESOURCE_ID="42"
export ORIGIN_ALLOWED="https://app.example.com"
export I_HAVE_AUTHORIZATION=1
./run-all.sh
```

Each phase from `TESTING_PHASES.md` has a script counterpart that emits findings as JSON-Lines (`out/findings.jsonl`) plus an aggregated Markdown report (`out/report.md`). Designed to gate CI on critical/high findings. See `scripts/README.md` for env vars and CI integration example.

## Related Skills

- `@code-review` — broader code-quality review that pairs with this skill for security-specific concerns. For Next.js performance audits, see `@code-review` `references/NEXTJS.md`.

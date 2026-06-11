---
name: code-security-review
description: "Web/API security lifecycle for Go, Next.js, Python, and Bun — design controls, active testing, supply-chain/CI-CD, and LLM/agentic/MCP coverage. Maps to OWASP Web Top 10 2025 + API 2023 + LLM 2025 + Agentic 2026. Triggers: 'security review', 'revisão de segurança', 'auditar segurança', 'pentest', '/code-security-review'."
source: ValarMindSkills
---

# Code Security Review

Lifecycle skill for REST and GraphQL APIs: covers **secure design** (controls to implement) and **active security testing** (payloads to validate those controls). One skill, two complementary modes — invoke whichever fits the current phase of work.

## When to Use

Use this skill when:

- **Designing** or hardening **FastAPI / Django / Flask** APIs (→ `references/python/`), **Gin / Fiber** APIs (→ `references/golang/`), or **Elysia** APIs (→ `references/DESIGN_CONTROLS.md`)
- **Reviewing** an existing API for security weaknesses against the OWASP Web Top 10 (2025) + API Top 10 (2023)
- **Pre-release security assessment** before deploying to production (→ `references/TESTING_PHASES.md`)
- **Bug bounty** engagements or **pentest** of an API target
- Implementing or auditing **AuthN/AuthZ** (JWT, OAuth 2.1, DPoP, API keys, RBAC/ABAC)
- Adding **rate limiting**, **input validation**, **CORS**, or **security headers**
- **Reporting** findings — use the standardized template in `references/REPORT_TEMPLATE.md`
- Consulting the **catalog of 100 web vulnerabilities** by category (→ `references/WEB_VULNERABILITIES.md`)
- Auditing **CI/CD + software supply chain** (GitHub Actions, lockfile pinning, secrets, SBOM) — A03:2025 (→ `references/SUPPLY_CHAIN_CICD.md`)
- Reviewing **LLM / agentic / MCP** features (prompt injection, tool misuse, AI-generated-code patterns) — OWASP LLM 2025 + Agentic 2026 (→ `references/AI_SECURITY.md`)

This skill is **fully standalone** — every payload, snippet, and checklist needed lives in this directory.

## How This Skill Is Organized

| File / Directory | Use when |
| --- | --- |
| `SKILL.md` (this file) | Foundations, Phase 0 stack + surface detection, OWASP Web 2025 + API 2023 maps, AI/agentic pointer, audit cheat sheet |
| `references/DESIGN_CONTROLS.md` | Implementing or reviewing controls (proactive) — language-agnostic |
| `references/TESTING_PHASES.md` | Running 7-phase active testing workflow (reactive) — language-agnostic |
| `references/REPORT_TEMPLATE.md` | Documenting findings with consistent severity rubric |
| `references/WEB_VULNERABILITIES.md` | Reference catalog of 100 web vulnerabilities by category (XSS, CSRF, deserialization, mobile/IoT, etc.) |
| `references/golang/` | Go stack lifecycle (Gin/Fiber): `API.md`, `MIDDLEWARE.md`, `VULNERABILITIES.md`, `PATCHES.md`, `TESTING_PAYLOADS.md` |
| `references/python/` | Python stack lifecycle (FastAPI / Django / Flask, CPython 3.13/3.14): `API.md`, `CONFIGURATION.md`, `VULNERABILITIES.md`, `PATCHES.md`, `TESTING_PAYLOADS.md` |
| `references/nextjs/` | Next.js 16 App Router lifecycle: `API.md`, `CONFIGURATION.md`, `VULNERABILITIES.md`, `PATCHES.md`, `TESTING_PAYLOADS.md` |
| `references/SUPPLY_CHAIN_CICD.md` | A03:2025 deep-dive — dependency pinning, GitHub Actions hardening, secrets, SBOM, incident case studies |
| `references/AI_SECURITY.md` | LLM Top 10 2025, Agentic Top 10 2026, MCP security, prompt-injection controls, AI-generated-code review |
| `scripts/` | Executable probes — automate Phase 0–10 against a live target, or static phases (07/09/10/11) with `STATIC_ONLY=1`. See `scripts/README.md`. |

## Phase 0 — Stack Detection

Detect the language/framework before loading stack-specific references. Steps 1–4 pick **one** `$STACK` (stop at the first match). Step 5 runs **always** and adds orthogonal surface overlays — AI and CI are independent of the stack.

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

# Step 5 — Surface overlays (always run, additive — not exclusive with the stack above)
rg -lq 'openai|@anthropic-ai/sdk|anthropic|langchain|llamaindex|litellm|ai-sdk|mcp' \
    package.json pyproject.toml requirements*.txt go.mod 2>/dev/null && echo "surface: ai-llm"
ls .mcp.json .cursor/mcp.json 2>/dev/null && echo "surface: mcp"
ls .github/workflows/*.y*ml 2>/dev/null && echo "surface: ci-cd"
```

| `$STACK` | References to load (in addition to generic) | Notes |
| --- | --- | --- |
| `go` | `references/golang/{API,MIDDLEWARE,VULNERABILITIES,PATCHES,TESTING_PAYLOADS}.md` | Gin v1.10.1+, Fiber v2/v3, OWASP API 2023 + Go-specific (race, slowloris, `math/rand`, pprof, `ServeMux` conflicts) |
| `python` | `references/python/{API,CONFIGURATION,VULNERABILITIES,PATCHES,TESTING_PAYLOADS}.md` | FastAPI 0.115+, Django 5.x, Flask 3.x, CPython 3.13/3.14 — Pydantic Settings, ASGI middleware, pickle/yaml deserialization, JWT alg confusion, ALLOWED_HOSTS, SECRET_KEY, free-threaded 3.14t races |
| `nextjs-app` | `references/nextjs/{API,CONFIGURATION,VULNERABILITIES,PATCHES,TESTING_PAYLOADS}.md` | Next.js 16.2.x App Router — RSC, Server Actions, Route Handlers, `proxy.ts`, `"use cache"`, Image Optimizer |
| `elysia` / `generic` | `references/{DESIGN_CONTROLS,TESTING_PHASES,WEB_VULNERABILITIES,REPORT_TEMPLATE}.md` | Generic references cover the language-agnostic surface |

The generic references (`DESIGN_CONTROLS.md`, `TESTING_PHASES.md`, `WEB_VULNERABILITIES.md`, `REPORT_TEMPLATE.md`) apply to **every** stack — load them in addition to the stack-specific bundle. Stack-specific references inherit the OWASP map and severity rubric from the generic ones; do not duplicate.

Step 5 overlays are additive and combine with any `$STACK`:

| Overlay | References to load | Scripts |
| --- | --- | --- |
| `ai-llm` / `mcp` | `references/AI_SECURITY.md` | `11-ai-llm-probes.sh` |
| `ci-cd` | `references/SUPPLY_CHAIN_CICD.md` | `09-cicd-workflows.sh`, `10-secrets-scan.sh` |

## Security Foundations (Core Principles)

These principles are language and framework agnostic:

| Principle | Meaning |
| --- | --- |
| **Defence in Depth** | Multiple independent security layers — one failure should not compromise the system |
| **Least Privilege** | Every component and user gets only the minimum access needed |
| **Zero Trust** | Never assume a request is safe because it originates inside the network |
| **Shift Left** | Embed security checks in development and CI, not only in production monitoring |
| **Fail Secure** | On error, deny access rather than allow it |

## OWASP Top 10:2025 (Web)

The current Web list (final 2025 edition; replaces 2021). Use these tags for web findings; the API list below is a separate, still-current catalog.

| # | Category | Key Risk |
| --- | --- | --- |
| **A01** | Broken Access Control | Missing/again-broken authz; **SSRF merged in** (was A10 in 2021) |
| **A02** | Security Misconfiguration | Moved up from #5 — debug on, permissive CORS, missing headers, defaults |
| **A03** | Software Supply Chain Failures | *Broadened* from "Vulnerable Components" — deps, build, CI, registries |
| **A04** | Cryptographic Failures | Weak/absent crypto, plaintext secrets, bad TLS |
| **A05** | Injection | SQL/NoSQL/command/XSS — untrusted input reaching an interpreter |
| **A06** | Insecure Design | Missing controls by design — no rate limit, no threat model |
| **A07** | Authentication Failures | Renamed — weak sessions, no brute-force protection, credential stuffing |
| **A08** | Software or Data Integrity Failures | Unsigned updates, insecure deserialization, untrusted CI artifacts |
| **A09** | Logging & Alerting Failures | Renamed — no audit trail, no alerting on abuse |
| **A10** | Mishandling of Exceptional Conditions | *New* — fail-open error handling, leaked stack traces, logic edge cases |

### Changes from 2021

- **New: A03 Software Supply Chain Failures** broadens the old "Vulnerable & Outdated Components" to the whole dependency→artifact path (see `references/SUPPLY_CHAIN_CICD.md`).
- **New: A10 Mishandling of Exceptional Conditions** — error-handling and fail-open logic become a first-class category.
- **SSRF merged into A01** Broken Access Control (was its own A10 in 2021).
- **Security Misconfiguration rose to #2.** Several categories renamed (Auth Failures, Logging & Alerting Failures).

The OWASP **API** Top 10 below is a distinct list; its current edition is still **2023** (no 2025 API release).

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

## AI / LLM & Agentic Surface

When Phase 0 Step 5 flags `ai-llm`, `mcp`, or the code drives LLMs / agents, the web+API catalogs are necessary but not sufficient. Three additional catalogs apply:

- **OWASP Top 10 for LLM Applications 2025** (`LLM01:2025` Prompt Injection … `LLM10:2025` Unbounded Consumption) — for any LLM-integrated app.
- **OWASP Top 10 for Agentic Applications 2026** (`ASI01:2026` Agent Goal Hijack … `ASI10:2026` Rogue Agents) — for code that acts via tools, runs multi-step, or talks to other agents.
- **OWASP GenAI MCP guides** (Secure MCP Server Development; Securely Using Third-Party MCP Servers) — for projects wiring Model Context Protocol servers.

Full tables, controls, AI-generated-code review checklist, and testing payloads in `references/AI_SECURITY.md`. Static + gated active probes in `scripts/11-ai-llm-probes.sh`.

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
| A03:2025 Supply Chain | `SUPPLY_CHAIN_CICD.md` — pinning, SBOM | Phase 6/8 (`scripts/07`, `09`) |
| Secrets (CWE-798) | `SUPPLY_CHAIN_CICD.md` — secrets hygiene | Phase 9 (`scripts/10`) |
| LLM01:2025 / ASI (AI surface) | `AI_SECURITY.md` — prompt isolation, tool authz | Phase 10 (`scripts/11`) |

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
- [ ] **Dependencies audited**: `pip-audit` / `govulncheck` / `bun audit` / `osv-scanner` passing in CI; lockfiles committed (A03:2025)
- [ ] **No debug mode in production**: FastAPI `app = FastAPI(docs_url=None)`, Gin `gin.SetMode(gin.ReleaseMode)`, Fiber `app := fiber.New()`
- [ ] **CI/CD hardened**: GitHub Actions pinned by 40-hex SHA (not tags); no `pull_request_target` + PR-head checkout; `zizmor` clean
- [ ] **No committed secrets**: `gitleaks` / `trufflehog` clean over tree + history
- [ ] **AI/LLM surface safe**: system prompt isolated from user input; LLM output encoded before any sink; MCP servers version-pinned

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
./run-all.sh                                    # active phases 00–08 + static 09–11

# Static-only — no live target, no authorization needed (deps, CI, secrets, AI):
STATIC_ONLY=1 PROJECT_ROOT=. ./run-all.sh
```

Each phase from `TESTING_PHASES.md` has a script counterpart that emits findings as JSON-Lines (`out/findings.jsonl`) plus an aggregated Markdown report (`out/report.md`). Active phases (00–08) need an authorized `TARGET`; static phases (`07` supply chain, `09` CI/CD, `10` secrets, `11` AI/LLM) read repository files and run without a target. The active prompt-injection battery in `11` stays gated by `LLM_ENDPOINT` + `I_HAVE_AUTHORIZATION=1`. Designed to gate CI on critical/high findings. See `scripts/README.md` for env vars and CI integration example.

## Related Skills

- `@code-review` — broader code-quality review that pairs with this skill for security-specific concerns. For Next.js performance audits, see `@code-review` `references/NEXTJS.md`.

For a formal verification standard, deep audits can map findings to **OWASP ASVS 5.0** (17 chapters, levels 1–3); use it to set a coverage bar beyond the Top 10.

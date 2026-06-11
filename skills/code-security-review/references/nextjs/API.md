# Next.js 16.2.x Security Lifecycle — `code-security-review` Next.js branch reference

> Stack-specific reference loaded by `code-security-review/SKILL.md` Phase 0 when `next` 16+ + `app/` directory are detected. Sibling references in this folder: `CONFIGURATION.md`, `PATCHES.md`, `TESTING_PAYLOADS.md`, `VULNERABILITIES.md`. Generic phases (`DESIGN_CONTROLS.md`, `TESTING_PHASES.md`, `WEB_VULNERABILITIES.md`, `REPORT_TEMPLATE.md`) live one directory up.

## When to Use

Load this reference when the parent skill is active and the project is detected as Next.js 16+ App Router. Use it when:

- Auditing a **Next.js 16.2.x App Router** project for security issues
- Hardening a Next.js service before production rollout
- Responding to a CVE against Next.js, React, or the RSC protocol
- Reviewing `proxy.ts`, Server Actions, Route Handlers, or `next.config.mjs`
- Mapping a Next.js codebase against the **OWASP Web Top 10 2025** and **OWASP API Top 10 2023**
- Applying or validating fixes for Next.js-specific issues (RSC leakage, cache poisoning, Server Action auth bypass, image optimizer SSRF)

This reference is **Next.js-native and lifecycle-driven**: identification → analysis → correction → validation in a single workflow. The generic catalog (`../WEB_VULNERABILITIES.md`), design patterns (`../DESIGN_CONTROLS.md`), and active testing phases (`../TESTING_PHASES.md`) live one directory up — load them in addition to this file.

**Out of scope:**
- **Pages Router projects** (`pages/` directory without `app/`) — Phase 0 hard-aborts and falls back to the generic flow.
- Raw React without Next.js (use the generic `../WEB_VULNERABILITIES.md`).
- Non-Next.js meta-frameworks (Remix, SvelteKit, Nuxt).

## Prerequisites

Install the following tools before starting an audit:

| Tool | Purpose | Install |
| --- | --- | --- |
| **Node.js 20+** | runtime required by Next.js 16 | https://nodejs.org |
| **npm audit** | built-in CVE scanner | ships with Node |
| **npx next info** | collects Next.js + runtime info | `npx next info` |
| **eslint-plugin-security** | static security rules | `npm i -D eslint-plugin-security` |
| **@next/eslint-plugin-next** | Next.js-specific lint rules | `npm i -D @next/eslint-plugin-next` |
| **semgrep** | multi-ruleset pattern scanner | `brew install semgrep` or `pip install semgrep` |
| **socket** | supply-chain analysis (trojans, typosquats) | `npm i -g socket` or use https://socket.dev |
| **osv-scanner** | OSV database cross-check | `brew install osv-scanner` |
| **retire** | legacy JS library CVE scan | `npm i -g retire` |
| **curl** / **httpie** | header + endpoint probing | system package |
| **DOMPurify** (target) | HTML sanitizer for `dangerouslySetInnerHTML` | `npm i isomorphic-dompurify` |

Required access:

- [ ] Read access to the project source (`package.json`, `package-lock.json`, `app/**`, `proxy.ts`, `next.config.*`)
- [ ] Permission to run `npm ci`, `npx next build`
- [ ] If active testing is in scope: a running instance of the app and written authorization to test it

## Phase 0 — Version & Environment Detection

Detect the project's Next.js version, router, auth library, and deploy target before running the remaining phases. Run the steps in order and stop at the first conclusive match per category.

### 0.1 Router gate (hard abort)

```bash
# Hard abort if the project is Pages Router only.
if [ ! -d app ] && [ -d pages ]; then
    echo "ERROR: Pages Router detected. This reference only supports App Router."
    echo "Fall back to the generic flow (../WEB_VULNERABILITIES.md) for legacy pages/ projects."
    exit 1
fi
test -d app/ || { echo "ERROR: neither app/ nor pages/ detected — not a Next.js project."; exit 1; }
```

### 0.2 Version detection

```bash
# Next.js version
rg '"next":\s*"[^"]+"' package.json
# React version (relevant for CVE-2025-66478 / 55183 / 55184)
rg '"react":\s*"[^"]+"' package.json
rg '"react-dom":\s*"[^"]+"' package.json
# Authoritative via CLI
npx next info
```

Flag immediately if any of the following hold:
- `next < 16.0.7` → vulnerable to CVE-2025-66478 (RSC RCE), CVE-2025-55183, CVE-2025-55184 — **Critical**
- `next < 16.0.0` → additionally vulnerable to CVE-2025-57822 (proxy SSRF) and CVE-2025-57752 (image cache poisoning) — **Critical**
- `react < 19.2.2` or `react-dom < 19.2.2` → RSC protocol CVEs — **Critical**

### 0.3 Auth library detection

```bash
# Priority order — first match wins
rg '"next-auth":\s*"\^?5' package.json   && echo "AUTH: next-auth-v5 (Auth.js)"
rg '"next-auth":\s*"\^?4' package.json   && echo "AUTH: next-auth-v4 (deprecated)"
rg '"@clerk/nextjs"'      package.json   && echo "AUTH: clerk"
rg '"@supabase/(ssr|auth-helpers-nextjs)"' package.json && echo "AUTH: supabase"
rg '"lucia"'              package.json   && echo "AUTH: lucia"
rg '"iron-session"'       package.json   && echo "AUTH: iron-session"
```

Persist the result as `$AUTH_LIB ∈ {next-auth-v5, next-auth-v4, clerk, supabase, lucia, iron-session, custom, none}`. Phase 3 branches on this value.

### 0.4 Deploy target

```bash
# Vercel — presence of vercel.json or .vercel/
ls -la vercel.json .vercel 2>/dev/null
# Standalone / self-hosted
rg 'output:\s*"standalone"' next.config.*
# Edge runtime usage
rg 'runtime:\s*"edge"' app/ --type ts
```

Persist as `$DEPLOY ∈ {vercel, standalone, node, mixed}`. Affects recommendations in Phase 2 (headers, rate limit backing).

## Phase 1 — Static Security Audit

Run the automated toolchain first, then sweep for patterns the tools miss.

### 1.1 Automated toolchain

```bash
# Dependency CVE scan
npm audit --production --json > npm-audit.json

# Next.js-specific lint rules
npx next lint --format json > next-lint.json

# Multi-ruleset semgrep scan
semgrep --config p/nextjs --config p/react --config p/typescript \
        --config p/javascript --json --output semgrep.json .

# Supply-chain analysis (trojans, typosquats, install scripts)
socket scan create .    # or: snyk test

# OSV cross-check (catches CVEs not yet in npm audit)
osv-scanner --lockfile=package-lock.json

# Legacy JS libs (jQuery, lodash versions, etc.)
retire --path . --outputformat json --outputpath retire.json
```

Calibration: start every finding at **Medium** severity and promote to **High** only with manual confirmation. `npm audit` is especially noisy on transitive devDependencies — filter with `--production` for release audits.

### 1.2 Pattern sweep (manual)

For each category below, run the grep and read the matching files for context. Deep detail per item lives in [VULNERABILITIES.md](VULNERABILITIES.md).

| # | Category | Detection |
| --- | --- | --- |
| 1 | **`dangerouslySetInnerHTML` unsanitized** | `rg 'dangerouslySetInnerHTML' --type ts --type js -A 2` |
| 2 | **`javascript:` / `data:` href** | `rg 'href=\{[^}]*\}' --type ts -A 1` then inspect input sources |
| 3 | **Server Action without auth guard** | `rg '"use server"' -A 30 --type ts` |
| 4 | **RSC over-fetching (DTO leakage)** | `rg '<[A-Z]\w+\s+[^>]*\b(user\|account\|session)=\{[^}]+\}' --type ts` |
| 5 | **`"use cache"` with user-specific data** | `rg '"use cache"' -A 30 --type ts` |
| 6 | **Server secrets leaking to client** | `rg 'process\.env\.(?!NEXT_PUBLIC_)[A-Z_]+' --type ts --type js` |
| 7 | **SQL injection in Route Handlers** | `rg '\$\{[^}]*\.(searchParams\|nextUrl\|body)' --type ts -g 'route.ts'` |
| 8 | **SSRF via server-side fetch** | `rg 'fetch\([^)]*(searchParams\|body\|params)' --type ts` |
| 9 | **Open redirect** | `rg '(redirect\|NextResponse\.redirect)\([^)]*(searchParams\|body)' --type ts` |
| 10 | **`eval` / `new Function`** | `rg 'eval\(\|new Function\(' --type ts` |
| 11 | **`unstable_*` APIs** | `rg 'unstable_(catchError\|retry\|after)' --type ts` |
| 12 | **`console.log` with PII/secrets** | `rg 'console\.(log\|error\|info)\([^)]*\b(password\|token\|email\|secret)' --type ts` |
| 13 | **`Math.random()` for security** | `rg 'Math\.random\(\)' --type ts` |
| 14 | **Mass assignment via `request.json()`** | `rg 'await\s+(request\|req)\.json\(\)' --type ts` then check for a schema parser nearby |
| 15 | **`cookies()` inside cached component** | `rg 'cookies\(\)' -B 3 -A 1 --type ts` and cross-check with Category 5 |

## Phase 2 — Next.js Surface Configuration Analysis

Covers `next.config.*`, `proxy.ts`, `headers()`, caching directives, and environment files. Full config snippets live in [CONFIGURATION.md](CONFIGURATION.md).

### 2.1 `next.config.{js,mjs,ts}`

| Field | Expected | Anti-pattern (severity) |
| --- | --- | --- |
| `images.remotePatterns` | Explicit hostname allowlist | `hostname: '*'` or missing allowlist — **High** |
| `images.dangerouslyAllowLocalIP` | `false` or absent | `true` in production — **Critical** (SSRF to internal network) |
| `images.maximumRedirects` | `3` (Next 16 default) or lower | `> 3` — **Medium** (SSRF allowlist bypass amplifier) |
| `eslint.ignoreDuringBuilds` | `false` or absent | `true` — **High** (hides security rules in CI) |
| `typescript.ignoreBuildErrors` | `false` or absent | `true` — **High** (ships code with type holes) |
| `poweredByHeader` | `false` | `true` or absent (default `true`) — **Low** |
| `reactStrictMode` | `true` | `false` — **Informational** |
| `headers()` function | Returns HSTS, X-Frame-Options, X-Content-Type-Options, CSP, Referrer-Policy, Permissions-Policy | Any of these missing — **Medium** |
| `experimental.*` | Reviewed per flag | Any `unstable_*` flag without justification — **Medium** |

### 2.2 `proxy.ts` (formerly `middleware.ts`)

> Next.js 16 renamed `middleware.ts` → **`proxy.ts`** and moved it to the **Node.js runtime**. The config option `skipMiddlewareUrlNormalize` is now `skipProxyUrlNormalize`. If you still see `middleware.ts`, the project is mid-migration — flag as Informational and audit both.

**Mandatory checks:**

- [ ] `matcher` covers every sensitive route (cross-reference with Phase 3.2)
- [ ] All calls to `next()` (rewrite) validate the destination against a hard-coded allowlist — mitigates **CVE-2025-57822** SSRF
- [ ] `request.ip` / `x-forwarded-for` validated against trusted proxy allowlist before used for rate limiting, geo blocks, or audit logs
- [ ] No auth decisions rely on headers the client can forge (`x-user-id`, `x-role`)
- [ ] Response does not set `Set-Cookie` with secrets visible in the proxy source code
- [ ] No calls to `fetch(request.url)` with user-controlled URL (open-proxy / SSRF)

**Defense in depth principle:** the proxy is a first gate, never the only gate. Route Handlers and Server Actions **must** re-perform critical auth/permission checks.

### 2.3 Security headers via `headers()`

Required headers (verify with `curl -I https://target/`):

- `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload`
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY` (or `SAMEORIGIN` with justification)
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Permissions-Policy: camera=(), microphone=(), geolocation=()`
- `Content-Security-Policy: default-src 'self'; script-src 'self' 'nonce-{nonce}'; ...`

**CSP with nonce** is the only safe way to allow inline scripts with Server Components. See [CONFIGURATION.md](CONFIGURATION.md) for a full `proxy.ts` + `headers()` template that generates a per-request nonce and injects it into `<Script nonce={...}>`.

### 2.4 Caching directives (Next 16 is opt-in)

Next.js 16 flipped from **implicit caching** (v15 and earlier) to **opt-in caching**. Dynamic code executes at request time by default. This shift can cause two opposing failure modes:

- **Under-caching**: migrations from v15 forget to add `"use cache"` where it's safe, causing perf regressions.
- **Over-caching**: migrations eagerly add `"use cache"` everywhere, including to components that read `cookies()` or `headers()` — causing **user data leak across sessions**.

**Mandatory checks:**

- [ ] Every `"use cache"` directive audited: does the cached function read `cookies()`, `headers()`, `draftMode()`, or any user-scoped state? If yes, the cache key **must** include a user-scoped `cacheTag()` AND be invalidated on session change.
- [ ] `cacheTag()` values are never derived from unsanitized user input (cache key injection / cache poisoning)
- [ ] `cacheLife()` values match the data's freshness requirement — do not use `"static"` for user-mutable content
- [ ] `export const dynamic = "force-dynamic"` is present on every Route Handler that must never cache (auth callbacks, webhook receivers, personalized APIs)
- [ ] `Cache-Control` headers set explicitly on Route Handlers that return sensitive data (`private, no-store`)

**Anti-pattern to flag immediately as High:**

```tsx
"use cache"
async function Dashboard() {
  const user = await getUser(cookies().get("session")) // LEAKS across users
  return <div>Welcome, {user.name}</div>
}
```

### 2.5 Environment variables

```bash
# Public vars must use NEXT_PUBLIC_ prefix; everything else is server-only
rg 'process\.env\.' --type ts --type js -n | rg -v 'NEXT_PUBLIC_'
# Files that should NEVER be committed
ls -la .env .env.local .env.production 2>/dev/null
git ls-files | rg '\.env(\.local|\.production)?$'
```

- [ ] `.env*` files are in `.gitignore` and not committed
- [ ] No `process.env.FOO` usage in Client Components unless `FOO` starts with `NEXT_PUBLIC_`
- [ ] `NEXT_PUBLIC_*` variables contain only values safe to ship to every browser (no API keys with write scope)

## Phase 3 — Authentication & Authorization Audit

Branch on `$AUTH_LIB` from Phase 0.

### 3.1 Server Actions & Route Handlers (common to all auth libraries)

Every Server Action and mutating Route Handler must satisfy:

- [ ] Explicit auth check at the top of the function (`const session = await auth(); if (!session) throw new Error("unauthorized")`)
- [ ] Explicit authorization check (resource ownership / RBAC) **before** any database mutation
- [ ] Input validated with a runtime parser (`zod`, `valibot`, `arktype`) — TypeScript types are **not** runtime checks
- [ ] Function body minimized — no internal helper logic exposed (Server Action sources can leak to the RSC payload)
- [ ] Rate limit applied per `userId` (or IP fallback) — the framework does not do this natively
- [ ] `GET` Route Handlers do **not** mutate state (CSRF surface — framework protection only covers POST Server Actions)
- [ ] Response DTOs exclude sensitive fields (no direct `return user` with `passwordHash`, `stripeCustomerId`, etc.)

**Detection of GET mutations (High severity if found):**

```bash
rg -U 'export\s+async\s+function\s+GET[\s\S]*?(INSERT\|UPDATE\|DELETE\|\.create\(\|\.update\(\|\.delete\()' \
    --type ts -g 'route.ts'
```

### 3.2 Proxy route protection completeness

```bash
# All Route Handlers
rg -l 'export\s+(async\s+)?function\s+(GET\|POST\|PUT\|DELETE\|PATCH)' app/ --type ts > all_routes.txt

# All Server Action files
rg -l '"use server"' app/ --type ts > actions.txt

# Proxy matcher
rg -n 'matcher:' proxy.ts
```

Manually verify that every sensitive route falls under the proxy's matcher OR revalidates auth inside the handler. Document the gaps explicitly in the report.

### 3.3 Branch: Auth.js / NextAuth v5

- [ ] `AUTH_SECRET` loaded from env, not hardcoded (rotate if leaked — old git history counts as leak)
- [ ] `session.strategy` matches the threat model: `"jwt"` for stateless APIs, `"database"` for revocable sessions
- [ ] Callback `redirect` returns a URL validated against an allowlist (prevents open redirect)
- [ ] `trustHost: true` set **only** behind a trusted proxy with `X-Forwarded-Host` stripping
- [ ] Cookie flags: `secure: true`, `httpOnly: true`, `sameSite: "lax"` (or `"strict"` if no OAuth callback)
- [ ] `providers[].authorize` callback does constant-time credential comparison (`crypto.timingSafeEqual`)
- [ ] Session rotation on privilege change (e.g., admin elevation issues a new session ID)

### 3.4 Branch: NextAuth v4 (deprecated)

NextAuth v4 is in maintenance mode. Flag immediately as **Medium** (migrate to v5/Auth.js) even if otherwise configured correctly. Additional checks:

- [ ] No `jwt.encode` / `jwt.decode` custom overrides that bypass signature validation
- [ ] `pages` config does not expose `/api/auth/error` in production with verbose errors

### 3.5 Branch: Clerk

- [ ] `@clerk/nextjs` version current (check CVE advisory feed)
- [ ] `publishableKey` (public) vs `secretKey` (server-only) usage is correct
- [ ] `clerkMiddleware()` (or `authMiddleware()` in older versions) is wired in `proxy.ts` AND `ignoredRoutes` / `publicRoutes` are reviewed per-route
- [ ] No direct `currentUser()` calls in `"use cache"` components

### 3.6 Branch: Supabase

- [ ] `@supabase/ssr` (not deprecated `@supabase/auth-helpers-nextjs`) for App Router
- [ ] `anon key` is the only key shipped to the client; `service_role` key is **never** referenced outside server code
- [ ] Row Level Security (RLS) policies enabled on every table the client can reach via PostgREST
- [ ] `createServerClient()` cookie handlers never cache across requests

### 3.7 Branch: Lucia / Iron Session / Custom

- [ ] Session ID generated with `crypto.randomUUID()` or `crypto.getRandomValues()` (never `Math.random()`)
- [ ] Session store is server-side (Redis, Postgres) — never signed-cookie-only for high-value sessions
- [ ] Inactivity timeout ≤ 30 min; absolute timeout ≤ 12h
- [ ] Session rotation on login (prevents session fixation)

### 3.8 Cryptographic hygiene (all branches)

- [ ] `crypto.randomUUID()` / `crypto.getRandomValues()` for tokens, IDs, password reset codes (**never** `Math.random()`)
- [ ] `crypto.timingSafeEqual()` for token comparisons (**never** `===` or `==`)
- [ ] `bcrypt` cost factor ≥ 12, or `argon2id` with OWASP 2025 parameters (`t=3, m=65536, p=4`)
- [ ] No custom crypto implementations — defer to Web Crypto API / Node crypto

## Phase 4 — Dependency & Supply Chain Audit

```bash
# 1. Production-only CVE scan
npm audit --production --json > npm-audit.json

# 2. Check what's outdated
npm outdated --json

# 3. Supply-chain analysis — trojans, typosquats, suspicious install scripts
socket scan create .

# 4. OSV cross-check
osv-scanner --lockfile=package-lock.json

# 5. Legacy JS library CVEs
retire --path . --outputformat json

# 6. Lockfile integrity
git log --follow --oneline package-lock.json | head -20  # unexpected churn is a red flag

# 7. Override / resolution detection
rg '"overrides":\s*\{' package.json
rg '"resolutions":\s*\{' package.json   # yarn/pnpm

# 8. Install script red flags
rg '"(preinstall\|postinstall\|prepare)":' package.json
```

### Dependencies to flag automatically

| Dep | Severity | Reason | Replacement |
| --- | --- | --- | --- |
| `next@<16.0.7` | Critical | CVE-2025-66478 / 55183 / 55184 (RSC RCE) | `next@^16.0.7` (16.2 satisfies) |
| `next@<16.0.0` | Critical | CVE-2025-57822 (proxy SSRF), CVE-2025-57752 (image cache poisoning) | `next@^16.0.0` |
| `react@<19.2.2` / `react-dom@<19.2.2` | Critical | RSC protocol CVEs | `react@^19.2.2`, `react-dom@^19.2.2` |
| `next-auth@^4` | Medium | Maintenance mode | `next-auth@^5` (Auth.js) |
| `@supabase/auth-helpers-nextjs` | Medium | Deprecated | `@supabase/ssr` |
| `node-fetch@^2` | Low | Deprecated; use built-in `fetch` | Remove and use Node 18+ `fetch` |
| `request` | High | Archived since 2020, known CVEs | `undici`, `ofetch`, or native `fetch` |
| `xmldom` / `xml2js@<0.5` | High | Multiple CVEs | `@xmldom/xmldom@latest`, `fast-xml-parser` |

**`package-lock.json` MUST be committed.** Treat any uncommitted change to the lockfile as a supply chain incident — re-run `npm ci` and inspect the diff.

After upgrading Next.js to `>= 16.0.7`, run `npx fix-react2shell-next` (if available in the published advisory) to confirm no vulnerable transitive dependencies remain.

## Phase 5 — Next.js-Specific Advanced Vulnerabilities

These are issues unique to Next.js 16, React Server Components, or the App Router runtime. Each is detailed in [VULNERABILITIES.md](VULNERABILITIES.md) under the `NEXTJS-VULN-NNN` catalog.

| # | Vulnerability | Detection | Severity baseline |
| --- | --- | --- | --- |
| 1 | **RSC Payload RCE (CVE-2025-66478)** | `rg '"next":\s*"[^"]+"' package.json` — fails if `< 16.0.7` | Critical |
| 2 | **Proxy `next()` SSRF (CVE-2025-57822)** | `rg 'next\(\s*[^)]*request\.' proxy.ts` | High |
| 3 | **Image Optimizer cache poisoning (CVE-2025-57752)** | `rg '"next":\s*"[^"]+"' package.json` — fails if `< 16.0.0` | High |
| 4 | **RSC DTO over-fetching** | `rg '<[A-Z]\w+\s+[^>]*=\{[a-z]\w+\}' --type ts` — manual review | High |
| 5 | **Server Action without `await auth()`** | `rg '"use server"' -A 10 --type ts` — manual review | Critical |
| 6 | **Server Action source exposure** | Manual review: Server Action functions should be thin wrappers | High |
| 7 | **`"use cache"` + user-specific data** | `rg '"use cache"' -A 30 --type ts` | High |
| 8 | **`cacheTag()` from user input** | `rg 'cacheTag\(' --type ts` | Medium |
| 9 | **`dangerouslySetInnerHTML` unsanitized** | `rg 'dangerouslySetInnerHTML' --type ts --type js` | High |
| 10 | **`href={userInput}` with `javascript:` scheme** | Manual review of hrefs built from state | High |
| 11 | **`proxy.ts` matcher hole** | Cross-reference Phase 3.2 | Critical |
| 12 | **`eslint.ignoreDuringBuilds: true`** | `rg 'ignoreDuringBuilds:\s*true' next.config.*` | High |
| 13 | **`typescript.ignoreBuildErrors: true`** | `rg 'ignoreBuildErrors:\s*true' next.config.*` | High |
| 14 | **`images.dangerouslyAllowLocalIP: true`** | `rg 'dangerouslyAllowLocalIP:\s*true' next.config.*` | Critical |
| 15 | **`images.remotePatterns` wildcard** | `rg "hostname:\s*['\\\"]\\*" next.config.*` | High |
| 16 | **`images.maximumRedirects` > 3** | `rg 'maximumRedirects:\s*[4-9]' next.config.*` | Medium |
| 17 | **CSP missing or `'unsafe-inline'` without nonce** | `curl -sI target \| rg -i content-security-policy` | High |
| 18 | **HSTS / X-Frame-Options / X-Content-Type-Options missing** | `curl -sI target` | Medium |
| 19 | **`unstable_catchError` leaking stack/cause to client** | `rg 'unstable_catchError' -A 20 --type ts` | High |
| 20 | **`unstable_after` running unaudited post-response code** | `rg 'unstable_after' -A 10 --type ts` | Medium |
| 21 | **Server Function Logging (16.2) — PII in args** | Terminal/log review + `rg 'use server' -A 5` | Medium |
| 22 | **Open redirect in `redirect()` / `NextResponse.redirect()`** | `rg '(redirect\|NextResponse\.redirect)\(' --type ts` | Medium |
| 23 | **Secret env var leaking to client (no `NEXT_PUBLIC_` prefix misuse)** | `rg 'process\.env\.' --type ts --type js` | Critical (if secret) |
| 24 | **`process.env.*` inside Client Component** | `rg '"use client"' -l` + cross-check Category 23 | High |
| 25 | **Route Handler without rate limit** | `rg 'export\s+async\s+function\s+(POST\|PUT\|DELETE\|PATCH)' -g 'route.ts'` | Medium |
| 26 | **GET Route Handler mutating state** | See Phase 3.1 detection | High |
| 27 | **Mass assignment via `request.json()` without parser** | `rg 'await\s+(request\|req)\.json\(\)' --type ts` | Medium |
| 28 | **Server-side `fetch` without timeout** | `rg 'fetch\(' --type ts -B 1 -A 3` — check for `AbortSignal.timeout()` | Medium |
| 29 | **`new URL(userInput)` passed to `fetch` without allowlist** | `rg 'new URL\([^)]*\b(searchParams\|body\|params)' --type ts` | High |
| 30 | **`cookies()` / `headers()` inside cached component** | Cross-reference Phase 2.4 + Category 7 | High |

## Phase 6 — Auto-Fix / Patch Generation

> **Default behavior: NEVER apply patches automatically.** Always present diffs first, group by severity, and require explicit user confirmation per group.

### Patch protocol

For every finding from Phases 1–5:

1. Generate a unified diff using the matching template from [PATCHES.md](PATCHES.md)
2. Tag the patch with a **risk classification**:
   - **SAFE** — isolated change, no API contract or behavior shift (e.g., adding `DOMPurify.sanitize()`, removing `dangerouslyAllowLocalIP: true`)
   - **REVIEW** — affects auth, middleware, or shared code paths (e.g., adding `await auth()` to a Server Action, tightening `images.remotePatterns`)
   - **BREAKING** — changes the public API contract or response shape (e.g., introducing a response DTO to prevent RSC over-fetching, enforcing CSP with nonce)
3. Group diffs by severity in the Phase 8 report
4. Prompt the user: *"Apply [Critical] and [High] SAFE patches now? Review REVIEW/BREAKING patches manually first."*

### Apply sequence

```bash
# For each confirmed patch, in severity order:
# 1. Apply via Edit tool (one file at a time, never bulk Write)
# 2. Build gate
npx next build
# If build fails:
#   git restore <file>
#   re-emit the patch as "manual review required"
#   continue to next patch
```

### Post-patch validation

```bash
# Re-run the automated audit to verify findings are gone
npm audit --production
npx next lint
semgrep --config p/nextjs --config p/react --config p/typescript .
osv-scanner --lockfile=package-lock.json

# Build validation
npx next build

# If tests exist
npm run test
```

The skill must report any patch that introduced new findings or test failures and offer to revert via `git restore`.

## Phase 7 — Active Testing

For generic OWASP API Top 10 attack payloads (auth bypass, BOLA, SQLi, NoSQL injection, JWT confusion, CORS reflection, rate-limit bypass), use the generic [`../TESTING_PHASES.md`](../TESTING_PHASES.md) Phases 1–7. Do not duplicate them here.

This phase covers **Next.js-specific** attacks not covered by the generic flow. All payloads live in [TESTING_PAYLOADS.md](TESTING_PAYLOADS.md):

| Attack | Triggers | Expected if vulnerable |
| --- | --- | --- |
| **RSC payload fuzz (CVE-2025-66478)** | POST malformed RSC protocol to any Server Action endpoint | 500 + stack leak or RCE |
| **Image Optimizer SSRF** | `GET /_next/image?url=http://169.254.169.254/&w=16&q=75` | Response from AWS metadata |
| **Image cache poisoning (CVE-2025-57752)** | Crafted `Accept` / `Accept-Encoding` headers forcing cache-key collision | One user receives another user's cached image response |
| **Proxy `next()` SSRF (CVE-2025-57822)** | URL with encoded `@` or double-slash that bypasses matcher | `proxy.ts` rewrites to internal host |
| **Server Action CSRF via Origin forge** | POST Server Action with forged `Origin` header | Action executes (framework should reject) |
| **Server Action source leak** | Inspect RSC chunk in DevTools Network tab after loading page with Server Action | Function body visible in payload |
| **`"use cache"` user data leak** | User A logs in, triggers cached path; User B on another device requests same path | User B receives User A's data |
| **Header injection in `redirect()`** | `?to=https://evil.com%0d%0aX-Inject:%20pwn` | Extra `X-Inject` header in response |
| **Goroutine-style leak via Server Actions** | Fire-and-forget Server Actions with `unstable_after`, measure process RSS | RSS climbs without bound |
| **`eslint.ignoreDuringBuilds` smoke test** | Introduce a known-bad pattern + run `next build` | Build succeeds silently — configuration is dangerous |

## Phase 8 — Security Report

Generate the report in **Report Format v1** (same schema as the sibling Go branch — `../golang/API.md` Phase 8).

```markdown
# Next.js App Router Security Report — <project name>

## Executive Summary
- **Next.js version:** 16.2.x
- **React version:** 19.2.x
- **Router:** App Router
- **Auth library:** next-auth v5 / Clerk / Supabase / Lucia / custom
- **Deploy target:** Vercel / standalone / self-hosted Node
- **Files audited:** N
- **Findings:** Critical X · High Y · Medium Z · Low W · Info V
- **OWASP Web Top 10 2025 categories affected:** N / 10
- **OWASP API Top 10 2023 categories affected:** N / 10
- **Patches generated:** P (S SAFE · R REVIEW · B BREAKING)
- **Patches applied:** A (post-confirmation)
- **Post-fix validation:** PASS / FAIL

## Findings Table

| ID | Severity | OWASP | CWE | File:Line | Title | Risk tag | Status |
|----|----------|-------|-----|-----------|-------|----------|--------|
| NEXTJS-001 | Critical | A01:2025 / API1:2023 | CWE-639 | `app/(dashboard)/orders/actions.ts:14` | Server Action missing auth guard | REVIEW | Diff available |
| NEXTJS-002 | Critical | A03:2025 | CWE-1395 | `package.json:24` | `next < 16.0.7` vulnerable to RSC RCE (CVE-2025-66478) | SAFE | Patched |
| NEXTJS-003 | High | A05:2025 | CWE-79 | `app/blog/[slug]/page.tsx:42` | `dangerouslySetInnerHTML` without DOMPurify | SAFE | Patched |
| NEXTJS-004 | High | A01:2025 | CWE-918 | `proxy.ts:18` | `next()` SSRF via user-controlled rewrite (CVE-2025-57822 class) | REVIEW | Diff available |

## Detailed Findings

### NEXTJS-001 — Critical — Server Action missing auth guard

- **OWASP:** A01:2025 Broken Access Control / API1:2023 Broken Object Level Authorization
- **CWE:** CWE-639 (Authorization Bypass Through User-Controlled Key)
- **Location:** `app/(dashboard)/orders/actions.ts:14`
- **Auth library:** next-auth v5
- **Description:** The `updateOrder` Server Action mutates an order record using only the `orderId` from the form data, without verifying that the authenticated user owns that order.
- **Impact:** Any authenticated user can modify any other user's orders by guessing IDs. Severity Critical because the data is sensitive (PII + payment) and the attack requires only a valid session.
- **Evidence:**
  ```tsx
  "use server"
  export async function updateOrder(formData: FormData) {
      const id = formData.get("id") as string
      const status = formData.get("status") as string
      await db.order.update({ where: { id }, data: { status } })
  }
  ```
- **Fix (diff):**
  ```diff
  + import { auth } from "@/auth"
  + import { z } from "zod"
  +
  + const UpdateOrderSchema = z.object({
  +     id: z.string().uuid(),
  +     status: z.enum(["pending", "shipped", "delivered"]),
  + })
  +
    "use server"
  - export async function updateOrder(formData: FormData) {
  -     const id = formData.get("id") as string
  -     const status = formData.get("status") as string
  -     await db.order.update({ where: { id }, data: { status } })
  - }
  + export async function updateOrder(formData: FormData) {
  +     const session = await auth()
  +     if (!session?.user) throw new Error("unauthorized")
  +
  +     const parsed = UpdateOrderSchema.safeParse({
  +         id: formData.get("id"),
  +         status: formData.get("status"),
  +     })
  +     if (!parsed.success) throw new Error("invalid input")
  +
  +     // Ownership check — critical for BOLA prevention
  +     const order = await db.order.findUnique({ where: { id: parsed.data.id } })
  +     if (!order || order.userId !== session.user.id) throw new Error("not found")
  +
  +     await db.order.update({
  +         where: { id: parsed.data.id },
  +         data: { status: parsed.data.status },
  +     })
  + }
  ```
- **Risk tag:** REVIEW
- **Post-fix test:**
  ```bash
  # As user B, attempt to update user A's order — expect error
  curl -X POST https://target/api/actions/updateOrder \
      -H "Cookie: next-auth.session-token=$USER_B_TOKEN" \
      -F "id=$USER_A_ORDER_ID" \
      -F "status=delivered"
  ```
- **References:** OWASP A01:2025, API1:2023, CWE-639, NEXTJS-VULN-007

## OWASP Web Top 10 2025 Compliance Matrix

- [ ] **A01** Broken Access Control — 2 findings (NEXTJS-001, NEXTJS-004 SSRF)
- [x] **A02** Security Misconfiguration
- [ ] **A03** Software Supply Chain Failures — 1 finding (NEXTJS-002)
- [x] **A04** Cryptographic Failures
- [ ] **A05** Injection — 1 finding (NEXTJS-003)
- [x] **A06** Insecure Design
- [x] **A07** Authentication Failures
- [x] **A08** Software or Data Integrity Failures
- [x] **A09** Logging & Alerting Failures
- [x] **A10** Mishandling of Exceptional Conditions

## OWASP API Top 10 2023 Compliance Matrix

- [ ] **API1** Broken Object Level Authorization — 1 finding (NEXTJS-001)
- [x] **API2** Broken Authentication
- [x] **API3** Broken Object Property Level Authorization
- [x] **API4** Unrestricted Resource Consumption
- [x] **API5** Broken Function Level Authorization
- [x] **API6** Unrestricted Access to Sensitive Business Flows
- [ ] **API7** Server-Side Request Forgery — 1 finding (NEXTJS-004)
- [ ] **API8** Security Misconfiguration — 1 finding (NEXTJS-002)
- [x] **API9** Improper Inventory Management
- [x] **API10** Unsafe Consumption of APIs

## Remediation Roadmap

1. **Critical (immediate):** NEXTJS-001, NEXTJS-002
2. **High (≤ 48h):** NEXTJS-003, NEXTJS-004
3. **Medium (next sprint):** ...
4. **Low (next refactor):** ...
```

### Severity reference

| Severity | CVSS Range | Example |
| --- | --- | --- |
| **Critical** | 9.0–10.0 | Server Action without auth, `next < 16.0.7` (RSC RCE), `dangerouslyAllowLocalIP: true`, secret leaking via `process.env.FOO` in Client Component |
| **High** | 7.0–8.9 | `dangerouslySetInnerHTML` unsanitized, `proxy.ts` matcher hole, `images.remotePatterns` wildcard, `"use cache"` with `cookies()`, GET Route Handler mutating state |
| **Medium** | 4.0–6.9 | Missing rate limit, missing security header, `unstable_after` abuse, `cacheTag()` from user input, open redirect via `redirect()` |
| **Low** | 1.0–3.9 | `poweredByHeader: true`, outdated but non-vulnerable dependency, verbose error in staging |
| **Informational** | N/A | `reactStrictMode: false`, legacy `middleware.ts` still present mid-migration |

## Quick Audit Cheat Sheet (Next.js 16.2.x App Router)

Run before every release:

- [ ] `next@^16.2` (confirms RSC CVE mitigation) and `react@^19.2.2`
- [ ] Project uses App Router (`app/` exists); no drift from migration
- [ ] `next.config`: `eslint.ignoreDuringBuilds: false`, `typescript.ignoreBuildErrors: false`, `poweredByHeader: false`
- [ ] `next.config.images`: explicit `remotePatterns`, `dangerouslyAllowLocalIP` absent/`false`, `maximumRedirects <= 3`
- [ ] `headers()` function returns HSTS, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy, CSP with nonce
- [ ] `proxy.ts` matcher covers every sensitive route; all `next()` rewrites validated against allowlist
- [ ] Every Server Action starts with `await auth()` + schema validation (`zod`/`valibot`)
- [ ] Every `"use cache"` audited against `cookies()`/`headers()` usage
- [ ] All `cacheTag()` values derived from server-known state (never user input)
- [ ] All `dangerouslySetInnerHTML` passed through `DOMPurify.sanitize()`
- [ ] No `process.env.*` (without `NEXT_PUBLIC_` prefix) in Client Components
- [ ] No `Math.random()` for tokens, IDs, or session values — use `crypto.randomUUID()`
- [ ] `bcrypt` cost ≥ 12 or `argon2id` with OWASP 2025 params
- [ ] `crypto.timingSafeEqual` for token comparison
- [ ] `npm audit --production` clean; `osv-scanner` clean
- [ ] No `unstable_catchError` leaking `error.stack`/`error.cause` to Client Components
- [ ] `.env*` files in `.gitignore` and not committed
- [ ] Rate limit on auth endpoints (≤ 5/15min) and on expensive Route Handlers

## OWASP → Next.js Prevention Mapping

### OWASP Web Top 10 2025

| # | Vulnerability | Next.js Prevention |
| --- | --- | --- |
| **A01** | Broken Access Control (incl. SSRF) | `await auth()` + ownership check at the top of every Server Action / Route Handler; `proxy.ts` matcher + handler-level revalidation (defense in depth). SSRF (merged into A01 in 2025): allowlist `proxy.ts` `next()` rewrites; `images.dangerouslyAllowLocalIP: false`; validate `new URL()` hostname before `fetch()` |
| **A02** | Security Misconfiguration | `next.config` audited (Phase 2.1); CSP with nonce; `headers()` function; no `ignoreDuringBuilds`/`ignoreBuildErrors`; `poweredByHeader: false` |
| **A03** | Software Supply Chain Failures | `npm audit --production`; `osv-scanner`; `socket scan`; commit `package-lock.json`; pin `next`/`react` versions; **pin GitHub Actions by full 40-hex SHA, not tags**; verify package existence/age before adding AI-suggested deps (slopsquatting). See `../SUPPLY_CHAIN_CICD.md` |
| **A04** | Cryptographic Failures | Web Crypto API (`crypto.randomUUID`, `crypto.subtle`); bcrypt ≥ 12 / argon2id; `crypto.timingSafeEqual` |
| **A05** | Injection (XSS, SQLi) | React auto-escaping (JSX); `DOMPurify.sanitize` for `dangerouslySetInnerHTML`; parameterized queries via Prisma/Drizzle; Zod/Valibot for input validation |
| **A06** | Insecure Design | Response DTOs to prevent RSC over-fetching; rate limit on expensive flows; CAPTCHA on signup/checkout |
| **A07** | Authentication Failures | Auth.js v5 / Clerk / Supabase; session rotation on login; `sameSite: "lax"` cookies; rate limit on `/api/auth/*` |
| **A08** | Software or Data Integrity Failures | `package-lock.json` committed; `subresource-integrity` on third-party scripts; Vercel Deployment Protection or equivalent |
| **A09** | Logging & Alerting Failures | `slog`-style structured logger; audit Server Function Logging 16.2 output; no PII in args; alert on auth-failure spikes |
| **A10** | Mishandling of Exceptional Conditions | `error.tsx` / `global-error.tsx` boundaries fail secure; no `error.stack`/`error.cause` leaked to Client Components via `unstable_catchError`; thrown auth errors must deny (never fall through to render) |

### OWASP API Top 10 2023 (applies to Route Handlers + Server Actions)

| # | Vulnerability | Next.js Prevention |
| --- | --- | --- |
| **API1** | Broken Object Level Authorization | Resource ownership check after auth, before mutation (in Server Actions and Route Handlers) |
| **API2** | Broken Authentication | Auth.js / Clerk / Supabase with Web Crypto-based sessions; rate limit on auth |
| **API3** | Broken Object Property Level Authorization | Explicit response DTO structs; never `return user` with `passwordHash` |
| **API4** | Unrestricted Resource Consumption | `@upstash/ratelimit` per-user; timeout on every server-side `fetch` via `AbortSignal.timeout()`; body size limits |
| **API5** | Broken Function Level Authorization | RBAC check in admin Server Actions / Route Handlers; proxy matcher for admin paths |
| **API6** | Unrestricted Access to Sensitive Business Flows | CAPTCHA + per-user rate limit on signup/checkout/password-reset |
| **API7** | Server-Side Request Forgery | See A01 above (SSRF merged into Broken Access Control in Web 2025) |
| **API8** | Security Misconfiguration | See A05 above |
| **API9** | Improper Inventory Management | Document all Route Handlers; remove `/legacy` and `/beta` from production; maintain OpenAPI spec if public |
| **API10** | Unsafe Consumption of APIs | Validate third-party responses with Zod; do not blindly forward upstream errors; mTLS for internal calls |

## Sibling references

- [`../DESIGN_CONTROLS.md`](../DESIGN_CONTROLS.md) — language-agnostic design controls (auth, CORS, headers, rate limit)
- [`../TESTING_PHASES.md`](../TESTING_PHASES.md) — 7-phase active testing flow
- [`../WEB_VULNERABILITIES.md`](../WEB_VULNERABILITIES.md) — 100-vuln catalog
- [`../REPORT_TEMPLATE.md`](../REPORT_TEMPLATE.md) — finding documentation template
- [`../golang/API.md`](../golang/API.md) — companion lifecycle for Gin/Fiber Go projects
- For Next.js performance audits (RSC, `<img>`, Turbopack), see `@code-review` `references/NEXTJS.md`

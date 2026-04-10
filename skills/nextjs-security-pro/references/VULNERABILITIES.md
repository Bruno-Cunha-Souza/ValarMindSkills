# Next.js App Router Vulnerability Catalog

Catalog of Next.js-specific vulnerability patterns for use by the `nextjs-security-pro` skill. Each entry follows the same structure: ID, CWE, severity baseline, vulnerable snippet, fixed snippet, detection command, notes.

Use the IDs (`NEXTJS-VULN-NNN`) when emitting findings in the security report so they can be cross-referenced.

## Index by Category

- RSC & Server Components — NEXTJS-VULN-001 to NEXTJS-VULN-006
- Server Actions & Route Handlers — NEXTJS-VULN-007 to NEXTJS-VULN-014
- Proxy — NEXTJS-VULN-015 to NEXTJS-VULN-020
- Caching — NEXTJS-VULN-021 to NEXTJS-VULN-024
- Image Optimizer — NEXTJS-VULN-025 to NEXTJS-VULN-028
- Configuration & Headers — NEXTJS-VULN-029 to NEXTJS-VULN-034
- Client-side XSS & DOM — NEXTJS-VULN-035 to NEXTJS-VULN-038
- Secrets & Environment — NEXTJS-VULN-039 to NEXTJS-VULN-042

---

## RSC & Server Components

### NEXTJS-VULN-001 — RSC Payload RCE (CVE-2025-66478)
- **CWE:** CWE-502 (Deserialization of Untrusted Data)
- **Severity:** Critical
- **Affected versions:** React 19.0.0–19.2.1 combined with Next.js 13.x–16.x prior to 16.0.7
- **Vulnerable:** Any project on `next < 16.0.7` — the RSC protocol parser can execute attacker-controlled code when a crafted payload is sent to a Server Action endpoint.
- **Fixed:** Upgrade to `next@>=16.0.7` (Next 16.2 satisfies). Also upgrade `react@>=19.2.2` and `react-dom@>=19.2.2`.
- **Detection:**
  ```bash
  rg '"next":\s*"[^"]+"' package.json
  rg '"react":\s*"[^"]+"' package.json
  ```
- **Notes:** If your project has any custom code that deserializes RSC payloads outside the framework (rare — usually in experimental libs), audit that path separately. The official Next.js fix does not cover third-party RSC deserializers.

### NEXTJS-VULN-002 — Additional RSC Protocol CVEs (CVE-2025-55183 / 55184)
- **CWE:** CWE-20 (Improper Input Validation)
- **Severity:** Critical
- **Notes:** Disclosed alongside CVE-2025-66478. Same fix: `next@>=16.0.7`. No separate remediation required if NEXTJS-VULN-001 is patched. Flag both CVE IDs in the report for compliance completeness.

### NEXTJS-VULN-003 — RSC Data Over-Fetching (DTO Leakage)
- **CWE:** CWE-213 (Exposure of Sensitive Information Due to Incompatible Policies)
- **Severity:** High
- **Vulnerable:**
  ```tsx
  // app/dashboard/page.tsx — Server Component
  export default async function Dashboard() {
      const user = await db.user.findUnique({ where: { id: session.userId } })
      return <UserCard user={user} />   // passes full DB row as prop
  }
  ```
  The RSC payload serializes every field of `user` (including `passwordHash`, `stripeCustomerId`, `apiKeys`) and ships it in the HTML, even if `UserCard` only renders `user.name`.
- **Fixed:**
  ```tsx
  type UserCardDTO = { id: string; name: string; avatarUrl: string }

  export default async function Dashboard() {
      const row = await db.user.findUnique({ where: { id: session.userId } })
      const dto: UserCardDTO = { id: row.id, name: row.name, avatarUrl: row.avatarUrl }
      return <UserCard user={dto} />
  }
  ```
- **Detection:**
  ```bash
  rg '<[A-Z]\w+\s+[^>]*\b(user|account|session|order)=\{[a-z]\w+\}' --type ts
  ```
- **Notes:** Use `server-only` in the DAL file to trigger a build error if a Client Component ever imports it directly. Reminder: the RSC payload is visible to anyone with DevTools, not just to the rendered Client Component.

### NEXTJS-VULN-004 — `server-only` Missing from DAL
- **CWE:** CWE-200 (Information Exposure)
- **Severity:** Medium
- **Vulnerable:** `lib/db.ts` reads env secrets and is importable by both Server and Client Components. A refactor may accidentally pull it into a `"use client"` boundary.
- **Fixed:**
  ```tsx
  // lib/db.ts
  import "server-only"
  export const db = /* ... */
  ```
  Any Client Component import now fails `next build` with a clear error.
- **Detection:**
  ```bash
  # DAL files that reference env secrets but don't import "server-only"
  rg -l 'process\.env\.[A-Z_]+' lib/ | xargs -I{} sh -c 'rg -L "server-only" "{}" || echo "{}"'
  ```
- **Notes:** Complement is `"client-only"` for modules that must never run on the server (e.g., ones that touch `window`).

### NEXTJS-VULN-005 — `unstable_catchError` Leaking Server Error to Client
- **CWE:** CWE-209 (Information Exposure Through Error Message)
- **Severity:** High
- **Vulnerable:**
  ```tsx
  // app/report/page.tsx
  import { unstable_catchError } from "next"
  export default async function Report() {
      return unstable_catchError(async () => {
          return <Chart data={await fetchAnalytics()} />
      }, (err) => <ErrorCard message={err.message} stack={err.stack} cause={err.cause} />)
  }
  ```
  `err.stack` leaks file paths, DB query strings, and stack frames to the browser.
- **Fixed:**
  ```tsx
  return unstable_catchError(async () => {
      return <Chart data={await fetchAnalytics()} />
  }, (err) => {
      logger.error("report render failed", { err })
      return <ErrorCard errorId={crypto.randomUUID()} />   // user-facing ID; look up details server-side
  })
  ```
- **Detection:**
  ```bash
  rg 'unstable_catchError' -A 20 --type ts
  ```
- **Notes:** The `unstable_` prefix means the API may change in patch releases. Re-audit every usage on each Next.js upgrade. Never send `error.message`, `error.stack`, or `error.cause` unredacted to a Client Component.

### NEXTJS-VULN-006 — `unstable_after` Running Unaudited Post-Response Code
- **CWE:** CWE-662 (Improper Synchronization)
- **Severity:** Medium
- **Vulnerable:** `unstable_after(() => logExpensiveThing())` at the end of every Server Action. Looks harmless, but the callback runs after the response is sent, without the cancellation signal that tied it to the request. Repeated invocations can stack up and exhaust process resources.
- **Fixed:** Limit `unstable_after` callbacks to fast, bounded operations. Prefer a proper background job queue for anything > 100ms.
- **Detection:**
  ```bash
  rg 'unstable_after' -A 10 --type ts
  ```
- **Notes:** Measure process RSS and active handle count with `unstable_after` vs. without under load. Unbounded usage is a slow goroutine-leak equivalent.

---

## Server Actions & Route Handlers

### NEXTJS-VULN-007 — Server Action Without Auth Guard
- **CWE:** CWE-862 (Missing Authorization)
- **Severity:** Critical
- **Vulnerable:**
  ```tsx
  "use server"
  export async function deleteUser(id: string) {
      await db.user.delete({ where: { id } })
  }
  ```
- **Fixed:**
  ```tsx
  "use server"
  import { auth } from "@/auth"
  import { z } from "zod"

  const schema = z.object({ id: z.string().uuid() })

  export async function deleteUser(rawId: string) {
      const session = await auth()
      if (!session?.user || session.user.role !== "admin") throw new Error("unauthorized")
      const { id } = schema.parse({ id: rawId })
      await db.user.delete({ where: { id } })
  }
  ```
- **Detection:**
  ```bash
  rg '"use server"' -A 20 --type ts
  # Then manually verify each exported function starts with await auth()
  ```
- **Notes:** Server Actions are RPC endpoints exposed to the internet. There is no implicit auth protection — every action must explicitly check session AND authorization.

### NEXTJS-VULN-008 — Server Action Missing Input Validation (Mass Assignment)
- **CWE:** CWE-915 (Improperly Controlled Modification of Dynamically-Determined Object Attributes)
- **Severity:** High
- **Vulnerable:**
  ```tsx
  "use server"
  export async function updateProfile(formData: FormData) {
      const data = Object.fromEntries(formData)   // includes any field the attacker sends
      await db.user.update({ where: { id: session.user.id }, data })
  }
  ```
  Attacker adds `role=admin` or `isVerified=true` to the form.
- **Fixed:**
  ```tsx
  import { z } from "zod"
  const ProfileSchema = z.object({
      name: z.string().min(1).max(100),
      bio:  z.string().max(500).optional(),
  })

  "use server"
  export async function updateProfile(formData: FormData) {
      const parsed = ProfileSchema.parse({
          name: formData.get("name"),
          bio:  formData.get("bio"),
      })
      await db.user.update({ where: { id: session.user.id }, data: parsed })
  }
  ```
- **Detection:**
  ```bash
  rg 'Object\.fromEntries\(\s*formData\s*\)' --type ts
  rg 'await\s+(request|req)\.json\(\)' --type ts
  ```
- **Notes:** TypeScript types are erased at runtime and offer zero protection against mass assignment. A runtime parser (`zod`, `valibot`, `arktype`) is mandatory at every trust boundary.

### NEXTJS-VULN-009 — Server Action Source Leak via RSC Payload
- **CWE:** CWE-540 (Information Exposure Through Source Code)
- **Severity:** High
- **Vulnerable:** A Server Action function whose body contains sensitive logic (pricing rules, feature flag resolution, crypto details). The RSC payload streamed to the browser includes the function reference, and in some bundler configurations the source can be extracted.
- **Fixed:**
  ```tsx
  // Keep the Server Action a thin wrapper
  "use server"
  import { updateSubscriptionInternal } from "./_internal/subscription"
  export async function updateSubscription(input: Input) {
      const session = await auth()
      if (!session) throw new Error("unauthorized")
      return updateSubscriptionInternal(session.user.id, input)
  }
  ```
- **Detection:** Manual review. For each `"use server"` file, confirm the exported functions are thin authentication + validation wrappers that delegate to private helpers.
- **Notes:** The private helper (`_internal/subscription.ts`) is bundled server-only, never shipped in the RSC payload. Naming it with a `_` prefix or placing it under `_internal/` is a convention that `tsconfig.json` can enforce via path-based access rules.

### NEXTJS-VULN-010 — GET Route Handler Mutating State (CSRF Surface)
- **CWE:** CWE-352 (Cross-Site Request Forgery)
- **Severity:** High
- **Vulnerable:**
  ```ts
  // app/api/unsubscribe/route.ts
  export async function GET(request: Request) {
      const token = new URL(request.url).searchParams.get("token")
      await db.subscription.update({ where: { token }, data: { active: false } })
      return Response.redirect("/bye")
  }
  ```
  Attacker embeds `<img src="https://victim.example/api/unsubscribe?token=...">` in an email and the action fires on load.
- **Fixed:** Move the mutation to a POST (or DELETE) handler; the GET handler only renders a confirmation page with a form.
- **Detection:**
  ```bash
  rg -U 'export\s+async\s+function\s+GET[\s\S]*?(db\.\w+\.(create|update|delete)|INSERT|UPDATE|DELETE)' \
      --type ts -g 'route.ts'
  ```
- **Notes:** Next.js Server Actions (POST) have built-in Origin checks; Route Handlers do not. GET must be side-effect-free by definition.

### NEXTJS-VULN-011 — Route Handler Without Rate Limit
- **CWE:** CWE-770 (Allocation of Resources Without Limits)
- **Severity:** Medium
- **Vulnerable:** `app/api/send-email/route.ts` triggers an external SMTP call per request with no per-user rate limit.
- **Fixed:**
  ```ts
  // lib/ratelimit.ts
  import { Ratelimit } from "@upstash/ratelimit"
  import { Redis } from "@upstash/redis"
  export const ratelimit = new Ratelimit({
      redis: Redis.fromEnv(),
      limiter: Ratelimit.slidingWindow(5, "15 m"),
  })

  // app/api/send-email/route.ts
  export async function POST(request: Request) {
      const session = await auth()
      if (!session) return new Response("unauthorized", { status: 401 })
      const { success } = await ratelimit.limit(`email:${session.user.id}`)
      if (!success) return new Response("rate limited", { status: 429 })
      // ...
  }
  ```
- **Detection:**
  ```bash
  rg -l 'export\s+async\s+function\s+(POST|PUT|DELETE|PATCH)' app/ -g 'route.ts' \
      | xargs rg -L 'ratelimit|rateLimit|throttle'
  ```
- **Notes:** IP-only rate limiting is bypassable via residential proxies. Key by `userId` whenever possible.

### NEXTJS-VULN-012 — SQL Injection in Route Handler via Template Literal
- **CWE:** CWE-89 (SQL Injection)
- **Severity:** Critical
- **Vulnerable:**
  ```ts
  export async function GET(request: Request) {
      const q = new URL(request.url).searchParams.get("q")
      const rows = await db.$queryRawUnsafe(`SELECT * FROM products WHERE name LIKE '%${q}%'`)
      return Response.json(rows)
  }
  ```
- **Fixed:**
  ```ts
  const rows = await db.$queryRaw`SELECT * FROM products WHERE name LIKE ${`%${q}%`}`
  // Prisma tagged template = parameterized
  ```
- **Detection:**
  ```bash
  rg '\$queryRawUnsafe|\$executeRawUnsafe' --type ts
  rg '\$\{[^}]*\.(searchParams|body|params)' --type ts -g 'route.ts'
  ```
- **Notes:** Prisma's `$queryRaw` tagged template is parameterized; `$queryRawUnsafe` is not. Drizzle ORM's `sql` template tag behaves like `$queryRaw`. Knex: use `.where("name", value)`, never string concat.

### NEXTJS-VULN-013 — SSRF via Server-Side `fetch` with User-Controlled URL
- **CWE:** CWE-918 (Server-Side Request Forgery)
- **Severity:** High
- **Vulnerable:**
  ```ts
  export async function GET(request: Request) {
      const target = new URL(request.url).searchParams.get("url")!
      const resp = await fetch(target)
      return new Response(await resp.text())
  }
  ```
- **Fixed:**
  ```ts
  function isAllowedTarget(u: URL): boolean {
      const host = u.hostname
      const allowed = new Set(["api.partner.com", "cdn.partner.com"])
      return (u.protocol === "https:") && allowed.has(host)
  }
  export async function GET(request: Request) {
      const target = new URL(new URL(request.url).searchParams.get("url")!)
      if (!isAllowedTarget(target)) return new Response("blocked", { status: 400 })
      const resp = await fetch(target, {
          signal: AbortSignal.timeout(5000),
          redirect: "error",   // do not auto-follow
      })
      return new Response(await resp.text())
  }
  ```
- **Detection:**
  ```bash
  rg 'fetch\([^)]*(searchParams|body|params)' --type ts
  rg 'new URL\([^)]*(searchParams|body|params)' --type ts
  ```
- **Notes:** Resolve the hostname server-side and block RFC1918, loopback, link-local, and `169.254.169.254` (AWS metadata). `redirect: "error"` prevents bypass via 302 to a blocked host.

### NEXTJS-VULN-014 — Open Redirect via `redirect()` / `NextResponse.redirect()`
- **CWE:** CWE-601 (URL Redirection to Untrusted Site)
- **Severity:** Medium
- **Vulnerable:**
  ```ts
  import { redirect } from "next/navigation"
  export async function POST(request: Request) {
      const to = (await request.formData()).get("redirect") as string
      redirect(to)   // attacker sends `https://phishing.example`
  }
  ```
- **Fixed:**
  ```ts
  const target = (await request.formData()).get("redirect") as string
  // Only allow same-origin redirects (relative paths starting with /)
  if (!target.startsWith("/") || target.startsWith("//")) redirect("/")
  redirect(target)
  ```
- **Detection:**
  ```bash
  rg '(redirect|NextResponse\.redirect)\([^)]*(searchParams|body|formData|params)' --type ts
  ```
- **Notes:** `startsWith("/")` alone is not enough — `//evil.example` is interpreted as a protocol-relative URL. Always check `!target.startsWith("//")` too.

---

## Proxy (proxy.ts)

### NEXTJS-VULN-015 — Proxy `next()` SSRF (CVE-2025-57822 class)
- **CWE:** CWE-918
- **Severity:** High
- **Vulnerable:**
  ```ts
  // proxy.ts
  export default function proxy(request: NextRequest) {
      const dest = request.headers.get("x-backend")
      if (dest) return NextResponse.rewrite(new URL(dest, request.url))
      return NextResponse.next()
  }
  ```
  Attacker sends `X-Backend: http://169.254.169.254/latest/meta-data/`.
- **Fixed:**
  ```ts
  const ALLOWED_BACKENDS = new Set(["https://api.internal.example"])
  export default function proxy(request: NextRequest) {
      const dest = request.headers.get("x-backend")
      if (dest && ALLOWED_BACKENDS.has(dest)) {
          return NextResponse.rewrite(new URL(dest))
      }
      return NextResponse.next()
  }
  ```
- **Detection:**
  ```bash
  rg 'NextResponse\.rewrite\(' proxy.ts -A 2
  rg 'next\(\s*[^)]*request\.' proxy.ts
  ```
- **Notes:** Any rewrite destination derived from request input (headers, cookies, URL) is a candidate for SSRF. Only a hard-coded allowlist is safe.

### NEXTJS-VULN-016 — `proxy.ts` Matcher Hole
- **CWE:** CWE-862 (Missing Authorization)
- **Severity:** Critical
- **Vulnerable:**
  ```ts
  export const config = {
      matcher: ["/admin"],   // misses /admin/users, /admin/settings, etc.
  }
  ```
- **Fixed:**
  ```ts
  export const config = {
      matcher: ["/admin/:path*", "/api/admin/:path*"],
  }
  ```
- **Detection:**
  ```bash
  rg -n 'matcher:' proxy.ts
  # Cross-reference with every /admin/** route under app/
  ```
- **Notes:** Always use `:path*` (or regex equivalents) for any protected subtree. Better yet: apply defense in depth — re-validate auth in every protected Route Handler and Server Action, so a matcher miss is not a total bypass.

### NEXTJS-VULN-017 — Proxy Trusting Forgeable Client Headers
- **CWE:** CWE-348 (Use of Less Trusted Source)
- **Severity:** High
- **Vulnerable:**
  ```ts
  export default function proxy(request: NextRequest) {
      const userId = request.headers.get("x-user-id")   // attacker sets any value
      if (userId) return NextResponse.next({ headers: { "x-user-id": userId } })
  }
  ```
- **Fixed:** Never derive auth state from client-settable headers. Validate the session token (`cookies().get("session")`) against the server-side store.
- **Detection:**
  ```bash
  rg 'request\.headers\.get\(["\x27]x-user-id' proxy.ts
  rg 'request\.headers\.get\(["\x27]x-role' proxy.ts
  ```
- **Notes:** Common pitfall: developer adds `X-User-Id` in dev tools for testing, forgets that production clients can set the same header. Strip all `X-User-*` at the ingress before they reach the app.

### NEXTJS-VULN-018 — Proxy Reading `X-Forwarded-For` Without Trusted Proxy Allowlist
- **CWE:** CWE-348
- **Severity:** Medium
- **Vulnerable:**
  ```ts
  const ip = request.headers.get("x-forwarded-for")   // client can forge this
  await rateLimit.consume(ip ?? "anon")
  ```
- **Fixed:**
  ```ts
  const TRUSTED_PROXIES = ["10.0.0.0/8", "172.16.0.0/12"]
  function realIp(request: NextRequest): string {
      const forwarded = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim()
      // Only trust X-Forwarded-For if the socket remote address is a trusted proxy.
      // On Vercel: use request.ip (which is set after validation by the platform).
      return request.ip ?? forwarded ?? "anon"
  }
  ```
- **Detection:**
  ```bash
  rg 'x-forwarded-for' proxy.ts --type ts
  ```
- **Notes:** On Vercel, `request.ip` is already validated. On self-hosted Node behind nginx/Caddy, ensure the reverse proxy strips client-supplied `X-Forwarded-For` and adds its own.

### NEXTJS-VULN-019 — Legacy `middleware.ts` Still Present Mid-Migration
- **CWE:** CWE-710 (Improper Adherence to Coding Standards)
- **Severity:** Informational → Medium (depends on drift)
- **Vulnerable:** Project has both `middleware.ts` and `proxy.ts`. Next.js 16 prefers `proxy.ts` and may silently ignore `middleware.ts`, leaving half the auth logic inactive.
- **Fixed:** Migrate all logic to `proxy.ts`; delete `middleware.ts`. Ensure matcher is preserved.
- **Detection:**
  ```bash
  test -f middleware.ts && test -f proxy.ts && echo "Both present — migration incomplete"
  ```
- **Notes:** If only `middleware.ts` is present, the project is mid-migration — suggest upgrading to `proxy.ts` and flag as Informational.

### NEXTJS-VULN-020 — Proxy `fetch(request.url)` Open Proxy
- **CWE:** CWE-918
- **Severity:** High
- **Vulnerable:**
  ```ts
  export default async function proxy(request: NextRequest) {
      const resp = await fetch(request.url)   // accidental self-referential loop
      return new NextResponse(await resp.text())
  }
  ```
- **Fixed:** Never call `fetch(request.url)` inside `proxy.ts`. If forwarding is needed, build a new URL from a validated template.
- **Detection:**
  ```bash
  rg 'fetch\([^)]*request\.url' proxy.ts
  ```
- **Notes:** In addition to SSRF risk, this creates an infinite request loop that exhausts the Node.js process.

---

## Caching

### NEXTJS-VULN-021 — `"use cache"` Reading User-Specific State
- **CWE:** CWE-524 (Use of Cache Containing Sensitive Information)
- **Severity:** High
- **Vulnerable:**
  ```tsx
  "use cache"
  async function Dashboard() {
      const user = await getUserFromCookie(cookies().get("session"))
      return <h1>Welcome, {user.name}</h1>
  }
  ```
  The first request caches User A's data. Every subsequent request returns that cached HTML regardless of session.
- **Fixed:** Remove `"use cache"` entirely, OR scope the cache with a user-specific tag:
  ```tsx
  import { unstable_cacheTag as cacheTag } from "next/cache"

  async function Dashboard() {
      const user = await getUserFromCookie(cookies().get("session"))
      cacheTag(`user:${user.id}`)   // now the cache key includes user id
      return <h1>Welcome, {user.name}</h1>
  }
  ```
  Even then, invalidate with `revalidateTag(`user:${userId}`)` on logout.
- **Detection:**
  ```bash
  rg '"use cache"' -A 30 --type ts
  # Then grep for cookies() / headers() / draftMode() in the cached function body
  ```
- **Notes:** Next.js 16 made caching opt-in; migrations from v15 may over-apply `"use cache"` to components that should stay dynamic. Review every migration PR.

### NEXTJS-VULN-022 — `cacheTag()` Derived from User Input
- **CWE:** CWE-138 (Improper Neutralization of Special Elements)
- **Severity:** Medium
- **Vulnerable:**
  ```ts
  cacheTag(searchParams.get("filter")!)   // attacker controls the cache key
  ```
  Attacker can poison or enumerate cache entries.
- **Fixed:**
  ```ts
  const allowed = new Set(["active", "archived", "all"])
  const filter = searchParams.get("filter")
  if (!allowed.has(filter ?? "")) throw new Error("invalid filter")
  cacheTag(`filter:${filter}`)
  ```
- **Detection:**
  ```bash
  rg 'cacheTag\(' --type ts -A 1
  ```
- **Notes:** Combine with hard allowlist validation. Never pass raw query parameters to `cacheTag()`.

### NEXTJS-VULN-023 — Missing `export const dynamic = "force-dynamic"` on Auth Callback
- **CWE:** CWE-524
- **Severity:** Medium
- **Vulnerable:** OAuth callback Route Handler is not marked dynamic. Next.js may cache the first successful callback response and replay it for subsequent callers.
- **Fixed:**
  ```ts
  export const dynamic = "force-dynamic"
  export async function GET(request: Request) {
      // ... OAuth callback exchange
  }
  ```
- **Detection:** Manual review of every file under `app/api/auth/**/route.ts`.
- **Notes:** Also applicable to webhook receivers, payment confirmations, and any Route Handler whose response should never be cached.

### NEXTJS-VULN-024 — `Cache-Control` Missing on Sensitive Route Handler
- **CWE:** CWE-524
- **Severity:** Low
- **Vulnerable:** Route Handler returning user-specific JSON without `Cache-Control: private, no-store`. CDNs (Vercel Edge Network, Cloudflare) may apply their own caching heuristics.
- **Fixed:**
  ```ts
  return new Response(JSON.stringify(data), {
      headers: {
          "Content-Type": "application/json",
          "Cache-Control": "private, no-store, must-revalidate",
      },
  })
  ```
- **Detection:** Manual review. Cross-reference with responses that contain PII.
- **Notes:** `private` ensures shared caches (CDN) do not store the response; `no-store` ensures the browser does not persist it.

---

## Image Optimizer

### NEXTJS-VULN-025 — `images.dangerouslyAllowLocalIP: true` (SSRF)
- **CWE:** CWE-918
- **Severity:** Critical
- **Vulnerable:**
  ```js
  // next.config.mjs
  export default { images: { dangerouslyAllowLocalIP: true } }
  ```
  The image optimizer will fetch `/_next/image?url=http://169.254.169.254/...` and return the AWS metadata response as an "image".
- **Fixed:** Remove the field or set to `false`. Next.js 16 blocks local/private IPs by default.
- **Detection:**
  ```bash
  rg 'dangerouslyAllowLocalIP:\s*true' next.config.*
  ```
- **Notes:** Sometimes added to local dev configs and accidentally shipped to production. CI should reject any `next.config.*` diff that introduces this.

### NEXTJS-VULN-026 — `images.remotePatterns` Wildcard Hostname
- **CWE:** CWE-918
- **Severity:** High
- **Vulnerable:**
  ```js
  images: { remotePatterns: [{ protocol: "https", hostname: "*" }] }
  ```
- **Fixed:**
  ```js
  images: {
      remotePatterns: [
          { protocol: "https", hostname: "cdn.example.com", pathname: "/public/**" },
          { protocol: "https", hostname: "images.unsplash.com" },
      ],
  }
  ```
- **Detection:**
  ```bash
  rg "hostname:\s*['\"]\*['\"]" next.config.*
  ```
- **Notes:** `hostname: '**.example.com'` is acceptable (restricted to a domain). `hostname: '*'` allows any origin and lets attackers use your image optimizer as a proxy/anonymizer.

### NEXTJS-VULN-027 — `images.maximumRedirects` Set Too High
- **CWE:** CWE-918
- **Severity:** Medium
- **Vulnerable:** `images.maximumRedirects: 10` allows an attacker-controlled CDN to redirect through allowed → disallowed → internal hosts.
- **Fixed:** Use the Next 16 default (`3`) or lower (`1`):
  ```js
  images: { maximumRedirects: 3 }
  ```
- **Detection:**
  ```bash
  rg 'maximumRedirects:\s*[4-9]' next.config.*
  rg 'maximumRedirects:\s*[1-9][0-9]+' next.config.*
  ```
- **Notes:** Paired with a strict `remotePatterns` allowlist, setting this to `0` is safest if no redirects are expected.

### NEXTJS-VULN-028 — Image Cache Poisoning (CVE-2025-57752)
- **CWE:** CWE-525 (Use of Web Browser Cache Containing Sensitive Information)
- **Severity:** High
- **Affected versions:** `next < 16.0.0`
- **Vulnerable:** Any project on `next < 16.0.0` — the image optimizer cache key did not include all request-varying headers, allowing attackers to poison the cache so that authenticated users receive another user's image.
- **Fixed:** Upgrade to `next@>=16.0.0` (Next 16.2 satisfies).
- **Detection:**
  ```bash
  rg '"next":\s*"[^"]+"' package.json
  ```
- **Notes:** This is a framework-level fix. No code changes needed beyond the upgrade.

---

## Configuration & Headers

### NEXTJS-VULN-029 — `eslint.ignoreDuringBuilds: true`
- **CWE:** CWE-1127 (Compilation with Insufficient Warnings)
- **Severity:** High
- **Vulnerable:**
  ```js
  // next.config.mjs
  export default { eslint: { ignoreDuringBuilds: true } }
  ```
  Ships code with undetected security issues because `eslint-plugin-security` and `@next/eslint-plugin-next` rules are skipped in CI.
- **Fixed:** Remove the flag. If specific rules are blocking the build, fix them or disable the specific rule in `.eslintrc` with justification.
- **Detection:**
  ```bash
  rg 'ignoreDuringBuilds:\s*true' next.config.*
  ```

### NEXTJS-VULN-030 — `typescript.ignoreBuildErrors: true`
- **CWE:** CWE-1127
- **Severity:** High
- **Vulnerable:** Ships code with unresolved type errors. Often hides real bugs like mismatched auth shapes, wrong DB schema types, or missing null checks.
- **Fixed:** Remove the flag. Fix the underlying type errors.
- **Detection:**
  ```bash
  rg 'ignoreBuildErrors:\s*true' next.config.*
  ```
- **Notes:** `@ts-expect-error` comments with specific justifications are acceptable; a global bypass is not.

### NEXTJS-VULN-031 — Missing Security Headers
- **CWE:** CWE-693 (Protection Mechanism Failure)
- **Severity:** Medium
- **Vulnerable:** `next.config` has no `headers()` function, or it misses one of the required headers.
- **Fixed:** See `references/CONFIGURATION.md` for a complete `headers()` template. Mandatory headers:
  - `Strict-Transport-Security`
  - `X-Content-Type-Options: nosniff`
  - `X-Frame-Options: DENY`
  - `Referrer-Policy: strict-origin-when-cross-origin`
  - `Permissions-Policy`
  - `Content-Security-Policy` (with nonce)
- **Detection:**
  ```bash
  curl -sI https://target | rg -i 'strict-transport|x-frame|x-content-type|referrer-policy|permissions-policy|content-security-policy'
  ```

### NEXTJS-VULN-032 — CSP with `'unsafe-inline'` Without Nonce
- **CWE:** CWE-1021 (Improper Restriction of Rendered UI Layers or Frames)
- **Severity:** High
- **Vulnerable:**
  ```
  Content-Security-Policy: script-src 'self' 'unsafe-inline'
  ```
- **Fixed:** Generate a nonce per request in `proxy.ts`, inject into `<Script nonce={...}>`, and set CSP:
  ```
  Content-Security-Policy: script-src 'self' 'nonce-{nonce}' 'strict-dynamic'
  ```
  See `references/CONFIGURATION.md` for the full `proxy.ts` + CSP nonce template.
- **Detection:**
  ```bash
  curl -sI https://target | rg -i "content-security-policy.*unsafe-inline"
  ```
- **Notes:** `'strict-dynamic'` lets nonce-validated scripts load additional scripts without needing nonces on every one; this is the standard modern CSP pattern.

### NEXTJS-VULN-033 — `poweredByHeader: true` (Default)
- **CWE:** CWE-200
- **Severity:** Low
- **Vulnerable:** The `X-Powered-By: Next.js` header is sent by default, disclosing the framework to attackers.
- **Fixed:**
  ```js
  // next.config.mjs
  export default { poweredByHeader: false }
  ```
- **Detection:**
  ```bash
  curl -sI https://target | rg -i 'x-powered-by'
  rg 'poweredByHeader' next.config.*
  ```

### NEXTJS-VULN-034 — `experimental.*` Flags Without Justification
- **CWE:** CWE-710
- **Severity:** Medium
- **Vulnerable:**
  ```js
  experimental: { ppr: "incremental", dynamicIO: true, after: true }
  ```
  Each `experimental` flag is a surface Next.js may change in patch releases without notice.
- **Fixed:** Document every `experimental` flag with a comment explaining why it is enabled, and re-audit on every Next.js upgrade.
- **Detection:**
  ```bash
  rg 'experimental:\s*\{' next.config.* -A 10
  ```
- **Notes:** Treat each `experimental` flag as a Known-Risk item in the report, not an automatic fail.

---

## Client-side XSS & DOM

### NEXTJS-VULN-035 — `dangerouslySetInnerHTML` Without Sanitizer
- **CWE:** CWE-79 (XSS)
- **Severity:** High
- **Vulnerable:**
  ```tsx
  export function BlogPost({ html }: { html: string }) {
      return <div dangerouslySetInnerHTML={{ __html: html }} />
  }
  ```
- **Fixed:**
  ```tsx
  import DOMPurify from "isomorphic-dompurify"
  export function BlogPost({ html }: { html: string }) {
      const clean = DOMPurify.sanitize(html, { USE_PROFILES: { html: true } })
      return <div dangerouslySetInnerHTML={{ __html: clean }} />
  }
  ```
- **Detection:**
  ```bash
  rg 'dangerouslySetInnerHTML' --type ts --type js -A 2
  ```
- **Notes:** For Server Components, DOMPurify needs `isomorphic-dompurify` (which includes `jsdom`). Never trust CMS-sourced HTML; always sanitize at render time.

### NEXTJS-VULN-036 — `href={userInput}` with `javascript:` Scheme
- **CWE:** CWE-79
- **Severity:** High
- **Vulnerable:**
  ```tsx
  <a href={user.website}>Visit site</a>
  ```
  `user.website = "javascript:fetch('/api/leak?t='+document.cookie)"`.
- **Fixed:**
  ```tsx
  function safeHref(url: string): string {
      try {
          const u = new URL(url)
          if (u.protocol !== "http:" && u.protocol !== "https:") return "#"
          return u.toString()
      } catch {
          return "#"
      }
  }
  <a href={safeHref(user.website)} rel="noopener noreferrer" target="_blank">Visit site</a>
  ```
- **Detection:**
  ```bash
  rg 'href=\{[^}]+\}' --type ts -A 1
  ```
- **Notes:** Also block `data:`, `file:`, `vbscript:`. Always add `rel="noopener noreferrer"` on external links.

### NEXTJS-VULN-037 — `Math.random()` for Security Values
- **CWE:** CWE-338 (Use of Cryptographically Weak PRNG)
- **Severity:** Critical
- **Vulnerable:**
  ```ts
  const token = Math.random().toString(36).slice(2)
  ```
- **Fixed:**
  ```ts
  const token = crypto.randomUUID()
  // or, for longer tokens:
  const b = new Uint8Array(32)
  crypto.getRandomValues(b)
  const token = Buffer.from(b).toString("hex")
  ```
- **Detection:**
  ```bash
  rg 'Math\.random\(\)' --type ts
  ```
- **Notes:** `Math.random()` is predictable. Web Crypto (`crypto.randomUUID`, `crypto.getRandomValues`) is available in both Node and Edge runtimes.

### NEXTJS-VULN-038 — Non-Constant-Time Token Comparison
- **CWE:** CWE-208 (Observable Timing Discrepancy)
- **Severity:** Medium
- **Vulnerable:**
  ```ts
  if (token === expected) { /* ok */ }
  ```
- **Fixed:**
  ```ts
  import { timingSafeEqual } from "node:crypto"
  const a = Buffer.from(token)
  const b = Buffer.from(expected)
  if (a.length !== b.length) return false
  if (timingSafeEqual(a, b)) { /* ok */ }
  ```
- **Detection:** Manual review of auth/middleware files; grep for `token ===` / `secret ===`.
- **Notes:** In Edge runtime (no `node:crypto`), use a constant-time comparison polyfill or compute `crypto.subtle.timingSafeEqual` if available.

---

## Secrets & Environment

### NEXTJS-VULN-039 — Secret `process.env.FOO` Used Inside Client Component
- **CWE:** CWE-798 (Use of Hard-coded Credentials) / CWE-200
- **Severity:** Critical
- **Vulnerable:**
  ```tsx
  "use client"
  export function Widget() {
      return <div data-key={process.env.STRIPE_SECRET_KEY} />
  }
  ```
  Next.js will either fail the build (if it detects the prefix rule) OR inline the value into the client bundle.
- **Fixed:**
  - Server-side-only secrets: move usage to a Server Component or Server Action.
  - Client-safe values: rename with `NEXT_PUBLIC_` prefix AND verify the value is actually safe to ship.
- **Detection:**
  ```bash
  # All process.env uses in Client-boundary files
  rg -l '"use client"' --type ts --type js \
      | xargs rg 'process\.env\.[A-Z_]+' \
      | rg -v 'NEXT_PUBLIC_'
  ```
- **Notes:** Use `"server-only"` import in modules that hold secret accessors to get a clear build error on misuse.

### NEXTJS-VULN-040 — Hardcoded Secret in Source
- **CWE:** CWE-798
- **Severity:** Critical
- **Vulnerable:**
  ```ts
  const JWT_SECRET = "supersecret-dev-key-123"
  ```
- **Fixed:**
  ```ts
  const JWT_SECRET = process.env.AUTH_SECRET
  if (!JWT_SECRET) throw new Error("AUTH_SECRET not set")
  ```
  After fix: immediately rotate the previously-hardcoded value — it's in git history and must be considered compromised.
- **Detection:**
  ```bash
  rg -i "(password|secret|token|api[_-]?key|jwt_secret)\s*[:=]\s*['\"][a-zA-Z0-9]{8,}" --type ts
  ```
- **Notes:** Use `git log -p -S "the_secret_value"` to find when it was introduced and confirm rotation scope.

### NEXTJS-VULN-041 — `.env*` Files Committed
- **CWE:** CWE-540
- **Severity:** Critical
- **Vulnerable:** `git ls-files` shows `.env`, `.env.local`, or `.env.production`.
- **Fixed:**
  ```bash
  git rm --cached .env .env.local .env.production
  echo -e ".env\n.env.local\n.env.production" >> .gitignore
  git commit -m "security: stop tracking env files"
  # Then rotate every secret they contained (they are in git history forever)
  ```
- **Detection:**
  ```bash
  git ls-files | rg '\.env(\.local|\.production)?$'
  ```
- **Notes:** A deleted-but-committed file is still in git history. Secret rotation is mandatory; history rewrite is optional and risky.

### NEXTJS-VULN-042 — Server Function Logging PII (Next 16.2)
- **CWE:** CWE-532 (Insertion of Sensitive Information into Log File)
- **Severity:** Medium
- **Vulnerable:** Next.js 16.2 dev server now logs Server Action / Server Function calls to the terminal, including function name, arguments, execution time, and source file path. If sensitive values (tokens, passwords, PII) are passed as arguments, they appear in plaintext in CI and staging logs.
- **Fixed:**
  - Validate and parse inputs at the Server Action boundary so raw values are not passed around.
  - Never pass secrets as function arguments — pull them from env inside the function body.
  - Ensure CI and staging terminal output is not persisted to logs accessible to unauthorized parties.
- **Detection:** Review terminal/log sinks in CI, Vercel dashboard, and staging environments. Grep for Server Actions that accept password/token parameters:
  ```bash
  rg '"use server"' -A 5 --type ts | rg -i '(password|token|secret|ssn|card)'
  ```
- **Notes:** The correct mitigation is validating inputs at the boundary and never passing secrets as function arguments — not suppressing logs. Log suppression hides other useful signals too.

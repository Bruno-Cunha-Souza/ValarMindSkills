# Next.js App Router Security Patch Templates

Patch templates for the auto-fix phase of `code-security-review` (Next branch — `references/nextjs/API.md` Phase 6). Each template is keyed to a `NEXTJS-VULN-NNN` ID from `VULNERABILITIES.md`.

Risk tag legend:
- **SAFE** — isolated change, no API contract or behavior shift, no shared state mutation
- **REVIEW** — affects middleware/proxy, auth, or shared code paths; needs human inspection
- **BREAKING** — changes the public API contract, response shape, or third-party integration; requires coordination with consumers

Every patch must pass `npx next build` before the skill marks it as applied. If the build fails, the change is reverted with `git restore <file>` and re-emitted as "manual review required".

---

## PATCH-001 — Sanitize `dangerouslySetInnerHTML` (NEXTJS-VULN-035)

**Risk:** SAFE
**Validation:** `npx next build`, then render a page with `<script>alert(1)</script>` in the source HTML and verify it is escaped.

```diff
+ import DOMPurify from "isomorphic-dompurify"
+
  export function BlogPost({ html }: { html: string }) {
-     return <div dangerouslySetInnerHTML={{ __html: html }} />
+     const clean = DOMPurify.sanitize(html, { USE_PROFILES: { html: true } })
+     return <div dangerouslySetInnerHTML={{ __html: clean }} />
  }
```

Notes: Requires `npm install isomorphic-dompurify` (works in both Server and Client Components). For Server Components only, `sanitize-html` is a lighter alternative.

---

## PATCH-002 — Add `await auth()` Guard to Server Action (NEXTJS-VULN-007)

**Risk:** REVIEW (changes who can invoke the action — verify that unauthenticated invocations were never intended)
**Validation:** `npx next build` and an end-to-end test calling the action without a session (expect error).

```diff
  "use server"
+ import { auth } from "@/auth"
+ import { z } from "zod"
+
+ const DeleteUserSchema = z.object({ id: z.string().uuid() })
+
- export async function deleteUser(id: string) {
-     await db.user.delete({ where: { id } })
+ export async function deleteUser(rawId: string) {
+     const session = await auth()
+     if (!session?.user || session.user.role !== "admin") {
+         throw new Error("unauthorized")
+     }
+     const { id } = DeleteUserSchema.parse({ id: rawId })
+     await db.user.delete({ where: { id } })
  }
```

---

## PATCH-003 — Fix `next()` SSRF in proxy.ts (NEXTJS-VULN-015)

**Risk:** REVIEW (affects request routing — verify allowlisted targets cover all legitimate internal rewrites)
**Validation:** `npx next build` and a probe with `X-Backend: http://169.254.169.254/` (expect 400 or default routing).

```diff
+ const ALLOWED_BACKENDS = new Set(["https://api.internal.example"])
+
  export default function proxy(request: NextRequest) {
      const dest = request.headers.get("x-backend")
-     if (dest) {
-         return NextResponse.rewrite(new URL(dest, request.url))
+     if (dest && ALLOWED_BACKENDS.has(dest)) {
+         return NextResponse.rewrite(new URL(dest))
      }
      return NextResponse.next()
  }
```

---

## PATCH-004 — Remove `dangerouslyAllowLocalIP` (NEXTJS-VULN-025)

**Risk:** SAFE (Next 16 default is `false`; removing restores default behavior)
**Validation:** `npx next build` and a probe with `/_next/image?url=http://127.0.0.1/...&w=16&q=75` (expect 400).

```diff
  // next.config.mjs
  export default {
      images: {
-         dangerouslyAllowLocalIP: true,
          remotePatterns: [
              { protocol: "https", hostname: "cdn.example.com" },
          ],
      },
  }
```

---

## PATCH-005 — Restrict `images.remotePatterns` (NEXTJS-VULN-026)

**Risk:** REVIEW (images from previously-allowed hosts will break — coordinate with the content team)
**Validation:** `npx next build` and verify that all production images still load.

```diff
  images: {
-     remotePatterns: [{ protocol: "https", hostname: "*" }],
+     remotePatterns: [
+         { protocol: "https", hostname: "cdn.example.com", pathname: "/public/**" },
+         { protocol: "https", hostname: "images.unsplash.com" },
+     ],
  }
```

Ask the operator for the complete list of legitimate image CDN hostnames before applying.

---

## PATCH-006 — Add CSP with Per-Request Nonce (NEXTJS-VULN-032)

**Risk:** BREAKING (may break inline scripts, third-party analytics tags, and GTM — requires coordination)
**Validation:** `npx next build`, then load every page and check the browser console for CSP violations.

See `references/CONFIGURATION.md` Section 3 for the complete `proxy.ts` + `layout.tsx` nonce template.

Key changes:
```diff
  // proxy.ts — add nonce generation and CSP header
+ const nonce = generateNonce()
+ const csp = `default-src 'self'; script-src 'self' 'nonce-${nonce}' 'strict-dynamic'; ...`
+ response.headers.set("Content-Security-Policy", csp)
+ response.headers.set("x-csp-nonce", nonce)

  // app/layout.tsx — consume nonce
+ const nonce = (await headers()).get("x-csp-nonce") ?? undefined
  // Pass nonce to all <Script> components
```

Rollout strategy:
1. Start with `Content-Security-Policy-Report-Only` in production for 1–2 weeks.
2. Monitor reported violations via a CSP reporting endpoint.
3. Once violations are resolved, switch to enforcing `Content-Security-Policy`.

---

## PATCH-007 — Replace `Math.random()` with `crypto.randomUUID()` (NEXTJS-VULN-037)

**Risk:** SAFE
**Validation:** `npx next build`

```diff
- const token = Math.random().toString(36).slice(2)
+ const token = crypto.randomUUID()
```

For longer tokens:
```diff
- const token = Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2)
+ const bytes = new Uint8Array(32)
+ crypto.getRandomValues(bytes)
+ const token = Buffer.from(bytes).toString("hex")
```

---

## PATCH-008 — Add Zod Input Validation to Server Action (NEXTJS-VULN-008)

**Risk:** REVIEW (clients sending extra fields will receive errors — coordinate if there are mobile/native consumers)
**Validation:** `npx next build` and test with an extra field in the form (expect rejection).

```diff
  "use server"
+ import { z } from "zod"
+
+ const UpdateProfileSchema = z.object({
+     name: z.string().min(1).max(100),
+     bio:  z.string().max(500).optional(),
+ })
+
  export async function updateProfile(formData: FormData) {
-     const data = Object.fromEntries(formData)
-     await db.user.update({ where: { id: session.user.id }, data })
+     const parsed = UpdateProfileSchema.parse({
+         name: formData.get("name"),
+         bio:  formData.get("bio"),
+     })
+     await db.user.update({ where: { id: session.user.id }, data: parsed })
  }
```

---

## PATCH-009 — Create Response DTO for RSC Over-Fetching (NEXTJS-VULN-003)

**Risk:** BREAKING (response shape changes — downstream consumers of the RSC payload may rely on extra fields)
**Validation:** `npx next build` and check the browser's RSC payload in DevTools to confirm no sensitive fields.

```diff
+ type UserCardDTO = {
+     id: string
+     name: string
+     avatarUrl: string
+ }
+
  export default async function Dashboard() {
      const user = await db.user.findUnique({ where: { id: session.userId } })
-     return <UserCard user={user} />
+     const dto: UserCardDTO = {
+         id: user!.id,
+         name: user!.name,
+         avatarUrl: user!.avatarUrl,
+     }
+     return <UserCard user={dto} />
  }
```

---

## PATCH-010 — Fix `"use cache"` with User-Specific Data (NEXTJS-VULN-021)

**Risk:** REVIEW (may change caching behavior and increase server load)
**Validation:** `npx next build`, login as User A, trigger the path, then login as User B and verify B sees their own data.

Option A — remove `"use cache"`:
```diff
- "use cache"
  async function Dashboard() {
      const user = await getUserFromCookie(cookies().get("session"))
      return <h1>Welcome, {user.name}</h1>
  }
```

Option B — scope with `cacheTag` (only if per-user caching is intentional):
```diff
+ import { unstable_cacheTag as cacheTag } from "next/cache"
+
  async function Dashboard() {
      const user = await getUserFromCookie(cookies().get("session"))
+     cacheTag(`user:${user.id}`)
      return <h1>Welcome, {user.name}</h1>
  }
```

**Invalidation required:** call `revalidateTag(`user:${userId}`)` on logout, profile update, and session change.

---

## PATCH-011 — Add Rate Limiting via `@upstash/ratelimit` (NEXTJS-VULN-011)

**Risk:** REVIEW (requires Redis infrastructure — coordinate with ops)
**Validation:** `npx next build` and send 6 requests to an auth endpoint within 15 minutes (expect 429 on the 6th).

See `references/CONFIGURATION.md` Section 4 for the full rate limiter setup.

```diff
+ import { authRateLimit } from "@/lib/ratelimit"
+
  export async function POST(request: Request) {
+     const session = await auth()
+     const key = session?.user?.id ?? request.ip ?? "anon"
+     const { success } = await authRateLimit.limit(`login:${key}`)
+     if (!success) return new Response("rate limited", { status: 429 })
+
      // ... existing handler logic
  }
```

---

## PATCH-012 — Sanitize `unstable_catchError` Output (NEXTJS-VULN-005)

**Risk:** SAFE
**Validation:** `npx next build`, then trigger the error path and verify the browser sees only the error ID, not the stack.

```diff
  return unstable_catchError(async () => {
      return <Chart data={await fetchAnalytics()} />
- }, (err) => <ErrorCard message={err.message} stack={err.stack} />)
+ }, (err) => {
+     const errorId = crypto.randomUUID()
+     console.error(`[${errorId}]`, err)
+     return <ErrorCard errorId={errorId} />
+ })
```

---

## PATCH-013 — Add `server-only` Import to DAL (NEXTJS-VULN-004)

**Risk:** SAFE (may cause build failure if already imported by a Client Component — which is exactly the intent)
**Validation:** `npx next build` — if it fails, trace the import chain and move the affected code server-side.

```diff
  // lib/db.ts
+ import "server-only"
+
  import { PrismaClient } from "@prisma/client"
  export const db = new PrismaClient()
```

---

## PATCH-014 — Remove `eslint.ignoreDuringBuilds` (NEXTJS-VULN-029)

**Risk:** REVIEW (the build may now fail on existing lint errors — fix the lint errors first)
**Validation:** `npx next build` — fix any lint errors that surface.

```diff
  // next.config.mjs
  export default {
-     eslint: { ignoreDuringBuilds: true },
  }
```

---

## PATCH-015 — Remove `typescript.ignoreBuildErrors` (NEXTJS-VULN-030)

**Risk:** REVIEW (same pattern as PATCH-014)
**Validation:** `npx next build` — fix any type errors that surface.

```diff
  // next.config.mjs
  export default {
-     typescript: { ignoreBuildErrors: true },
  }
```

---

## PATCH-016 — Disable `poweredByHeader` (NEXTJS-VULN-033)

**Risk:** SAFE
**Validation:** `curl -sI https://target | rg 'X-Powered-By'` should return nothing.

```diff
  // next.config.mjs
  export default {
+     poweredByHeader: false,
  }
```

---

## PATCH-017 — Add Security Headers via `headers()` (NEXTJS-VULN-031)

**Risk:** REVIEW (HSTS with `preload` requires a TLS-everywhere setup; X-Frame-Options DENY breaks iframing)
**Validation:** `curl -sI https://target` — verify all six required headers.

See `references/CONFIGURATION.md` Section 2 for the complete `createSecureHeaders()` function.

```diff
  // next.config.mjs
+ import { createSecureHeaders } from "./lib/security-headers.mjs"
+
  export default {
+     async headers() {
+         return [{ source: "/:path*", headers: createSecureHeaders() }]
+     },
  }
```

---

## PATCH-018 — Fix Open Redirect in `redirect()` (NEXTJS-VULN-014)

**Risk:** SAFE
**Validation:** `npx next build` and probe with `?redirect=https://evil.example` (expect redirect to `/`).

```diff
  export async function POST(request: Request) {
      const to = (await request.formData()).get("redirect") as string
-     redirect(to)
+     // Only allow same-origin redirects (relative paths starting with /)
+     if (!to || !to.startsWith("/") || to.startsWith("//")) {
+         redirect("/")
+     }
+     redirect(to)
  }
```

---

## PATCH-019 — Fix SQL Injection in Route Handler (NEXTJS-VULN-012)

**Risk:** SAFE
**Validation:** `npx next build` and probe with `?q='; DROP TABLE products;--` (expect safe results).

```diff
  export async function GET(request: Request) {
      const q = new URL(request.url).searchParams.get("q")
-     const rows = await db.$queryRawUnsafe(`SELECT * FROM products WHERE name LIKE '%${q}%'`)
+     const rows = await db.$queryRaw`SELECT * FROM products WHERE name LIKE ${`%${q}%`}`
      return Response.json(rows)
  }
```

Notes: Prisma's tagged template literal `$queryRaw` is parameterized. `$queryRawUnsafe` is not.

---

## PATCH-020 — Add SSRF Allowlist to Server-Side `fetch` (NEXTJS-VULN-013)

**Risk:** REVIEW (the allowlist must include all legitimate targets — coordinate with the team)
**Validation:** `npx next build` and probe with `?url=http://169.254.169.254/` (expect 400).

```diff
+ function isAllowedTarget(u: URL): boolean {
+     const allowed = new Set(["api.partner.com", "cdn.partner.com"])
+     return u.protocol === "https:" && allowed.has(u.hostname)
+ }
+
  export async function GET(request: Request) {
      const raw = new URL(request.url).searchParams.get("url")!
-     const resp = await fetch(raw)
+     let target: URL
+     try { target = new URL(raw) } catch { return new Response("invalid url", { status: 400 }) }
+     if (!isAllowedTarget(target)) return new Response("blocked", { status: 400 })
+     const resp = await fetch(target, {
+         signal: AbortSignal.timeout(5000),
+         redirect: "error",
+     })
      return new Response(await resp.text())
  }
```

---

## PATCH-021 — Add `crypto.timingSafeEqual` for Token Comparison (NEXTJS-VULN-038)

**Risk:** SAFE
**Validation:** `npx next build`

```diff
+ import { timingSafeEqual } from "node:crypto"
+
  function verifyToken(token: string, expected: string): boolean {
-     return token === expected
+     const a = Buffer.from(token)
+     const b = Buffer.from(expected)
+     if (a.length !== b.length) return false
+     return timingSafeEqual(a, b)
  }
```

---

## PATCH-022 — Remove Committed `.env` Files (NEXTJS-VULN-041)

**Risk:** REVIEW (must rotate every secret in the committed files — they are in git history)
**Validation:** `git ls-files | rg '\.env'` should return nothing.

```bash
# 1. Stop tracking the files
git rm --cached .env .env.local .env.production 2>/dev/null

# 2. Ensure they are ignored
echo -e ".env\n.env.local\n.env.production\n.env.*.local" >> .gitignore

# 3. Commit
git add .gitignore
git commit -m "security: stop tracking env files"

# 4. ROTATE EVERY SECRET — they are compromised via git history
```

---

## PATCH-023 — Fix GET Route Handler Mutating State (NEXTJS-VULN-010)

**Risk:** BREAKING (clients calling GET for mutation will need to switch to POST — coordinate)
**Validation:** `npx next build` and test with a GET request (expect no mutation).

```diff
  // app/api/unsubscribe/route.ts
- export async function GET(request: Request) {
-     const token = new URL(request.url).searchParams.get("token")
-     await db.subscription.update({ where: { token }, data: { active: false } })
-     return Response.redirect("/bye")
- }
+
+ // GET only shows a confirmation page
+ export async function GET(request: Request) {
+     const token = new URL(request.url).searchParams.get("token")
+     if (!token) return new Response("missing token", { status: 400 })
+     return new Response(
+         `<form method="POST"><input type="hidden" name="token" value="${token}" /><button>Confirm unsubscribe</button></form>`,
+         { headers: { "Content-Type": "text/html" } },
+     )
+ }
+
+ // POST performs the mutation
+ export async function POST(request: Request) {
+     const token = (await request.formData()).get("token") as string
+     if (!token) return new Response("missing token", { status: 400 })
+     await db.subscription.update({ where: { token }, data: { active: false } })
+     return Response.redirect("/bye", 303)
+ }
```

---

## PATCH-024 — Hardcoded Secret to Environment Variable (NEXTJS-VULN-040)

**Risk:** REVIEW (the env var must be deployed to every environment before the code ships)
**Validation:** `npx next build` and verify the env var is set in CI/deployment.

```diff
- const JWT_SECRET = "supersecret-dev-key-123"
+ const JWT_SECRET = process.env.AUTH_SECRET
+ if (!JWT_SECRET) throw new Error("AUTH_SECRET environment variable is not set")
```

After applying: **immediately rotate the leaked secret** — the previous value is in git history.

---

## PATCH-025 — Fix Proxy Matcher Hole (NEXTJS-VULN-016)

**Risk:** REVIEW (expanding the matcher may start intercepting routes that were previously unprotected — verify intentionality)
**Validation:** `npx next build` and probe `/admin/users` without a session (expect redirect to `/login`).

```diff
  export const config = {
-     matcher: ["/admin"],
+     matcher: ["/admin/:path*", "/api/admin/:path*"],
  }
```

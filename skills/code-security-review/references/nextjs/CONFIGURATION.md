# Next.js 16.2.x Configuration Reference

Complete configuration patterns for the security items checked in Phase 2 of `code-security-review` (Next branch — `references/nextjs/API.md`). This document is the Next.js equivalent of `references/golang/MIDDLEWARE.md`.

> **Scope:** App Router only. Pages Router configurations are deliberately omitted.

---

## 1. `next.config.mjs` — Hardened Baseline

```js
// next.config.mjs
import { createSecureHeaders } from "./lib/security-headers.mjs"

/** @type {import('next').NextConfig} */
const nextConfig = {
    // Disclose nothing about the stack
    poweredByHeader: false,

    // React best practices
    reactStrictMode: true,

    // Never ship code that fails lint or type check
    eslint: {
        ignoreDuringBuilds: false,
    },
    typescript: {
        ignoreBuildErrors: false,
    },

    // Image Optimizer hardening
    images: {
        // Strict allowlist — never use hostname: '*'
        remotePatterns: [
            {
                protocol: "https",
                hostname: "cdn.example.com",
                pathname: "/public/**",
            },
            {
                protocol: "https",
                hostname: "images.unsplash.com",
            },
        ],
        // Next 16 blocks local/private IPs by default; do NOT re-enable
        // dangerouslyAllowLocalIP: false,   // keep absent

        // Next 16 default is 3; keep or lower
        maximumRedirects: 3,

        // Supported formats
        formats: ["image/avif", "image/webp"],

        // Optional: additional safety on upload processing
        minimumCacheTTL: 60,
    },

    // Security headers
    async headers() {
        return [
            {
                source: "/:path*",
                headers: createSecureHeaders(),
            },
        ]
    },

    // Experimental flags — document every one that is enabled
    experimental: {
        // Partial prerendering — audit per upgrade
        // ppr: "incremental",
    },
}

export default nextConfig
```

---

## 2. Security Headers Module

```js
// lib/security-headers.mjs
export function createSecureHeaders() {
    return [
        {
            key: "Strict-Transport-Security",
            value: "max-age=31536000; includeSubDomains; preload",
        },
        {
            key: "X-Content-Type-Options",
            value: "nosniff",
        },
        {
            key: "X-Frame-Options",
            value: "DENY",
        },
        {
            key: "Referrer-Policy",
            value: "strict-origin-when-cross-origin",
        },
        {
            key: "Permissions-Policy",
            value: [
                "camera=()",
                "microphone=()",
                "geolocation=()",
                "interest-cohort=()",
                "browsing-topics=()",
            ].join(", "),
        },
        {
            key: "X-DNS-Prefetch-Control",
            value: "on",
        },
        // Note: CSP is set in proxy.ts (nonce per request).
        // Do NOT set CSP statically here if you use a nonce.
    ]
}
```

### Required headers (verify with `curl -I`)

- `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload`
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Permissions-Policy: camera=(), microphone=(), geolocation=(), ...`
- `Content-Security-Policy: default-src 'self'; script-src 'self' 'nonce-{nonce}' 'strict-dynamic'; ...`

---

## 3. `proxy.ts` — Auth Guard + Per-Request CSP Nonce

```ts
// proxy.ts
import { NextRequest, NextResponse } from "next/server"

/**
 * This file replaces the legacy `middleware.ts` in Next.js 16.
 * It runs in the Node.js runtime (not Edge).
 */

// Hard-coded allowlist for any internal rewrites (mitigates CVE-2025-57822 class)
const ALLOWED_REWRITE_TARGETS = new Set<string>([
    // "https://api.internal.example",
])

// Public routes that skip the auth gate
const PUBLIC_ROUTES = ["/", "/login", "/signup", "/api/auth"]

export default async function proxy(request: NextRequest) {
    const { pathname } = request.nextUrl

    // 1. Generate a CSP nonce for this request
    const nonce = generateNonce()

    // 2. Build the CSP header using the nonce
    const cspHeader = buildCSP(nonce)

    // 3. Auth gate for protected routes
    if (isProtectedRoute(pathname)) {
        const session = request.cookies.get("authjs.session-token")?.value
        if (!session) {
            const loginUrl = new URL("/login", request.url)
            loginUrl.searchParams.set("from", pathname)
            return NextResponse.redirect(loginUrl)
        }
    }

    // 4. Forward the nonce to Server Components via a header (readable via headers())
    const requestHeaders = new Headers(request.headers)
    requestHeaders.set("x-csp-nonce", nonce)

    const response = NextResponse.next({
        request: { headers: requestHeaders },
    })

    // 5. Set CSP + other dynamic headers on the outgoing response
    response.headers.set("Content-Security-Policy", cspHeader)
    response.headers.set("x-csp-nonce", nonce)

    return response
}

function isProtectedRoute(pathname: string): boolean {
    if (PUBLIC_ROUTES.some((route) => pathname === route || pathname.startsWith(route + "/"))) {
        return false
    }
    // Everything under /dashboard, /admin, /api/admin is protected
    return (
        pathname.startsWith("/dashboard") ||
        pathname.startsWith("/admin") ||
        pathname.startsWith("/api/admin")
    )
}

function generateNonce(): string {
    const bytes = new Uint8Array(16)
    crypto.getRandomValues(bytes)
    return Buffer.from(bytes).toString("base64")
}

function buildCSP(nonce: string): string {
    const isDev = process.env.NODE_ENV === "development"
    return [
        `default-src 'self'`,
        `script-src 'self' 'nonce-${nonce}' 'strict-dynamic' ${isDev ? "'unsafe-eval'" : ""}`,
        `style-src 'self' 'nonce-${nonce}'`,
        `img-src 'self' blob: data: https://cdn.example.com`,
        `font-src 'self'`,
        `object-src 'none'`,
        `base-uri 'self'`,
        `form-action 'self'`,
        `frame-ancestors 'none'`,
        `upgrade-insecure-requests`,
    ]
        .filter(Boolean)
        .join("; ")
}

export const config = {
    // Match everything except Next.js internals and static assets.
    // Adjust the negative lookahead to match your public asset folders.
    matcher: [
        "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:png|jpg|jpeg|gif|svg|webp|avif|ico)$).*)",
    ],
}
```

### Consuming the nonce in a Server Component

```tsx
// app/layout.tsx
import { headers } from "next/headers"
import Script from "next/script"

export default async function RootLayout({ children }: { children: React.ReactNode }) {
    const nonce = (await headers()).get("x-csp-nonce") ?? undefined
    return (
        <html lang="en">
            <body>
                {children}
                <Script nonce={nonce} src="https://www.googletagmanager.com/gtag/js?id=G-XXX" />
            </body>
        </html>
    )
}
```

### Anti-patterns to flag immediately

- `NextResponse.rewrite(new URL(request.headers.get("x-backend")!, request.url))` — user-controlled rewrite (NEXTJS-VULN-015).
- `matcher: ["/admin"]` — misses `/admin/users`, `/admin/settings`. Use `:path*` or regex.
- `request.headers.get("x-user-id")` used for auth decisions (NEXTJS-VULN-017).
- `fetch(request.url)` inside `proxy.ts` — infinite loop + open proxy (NEXTJS-VULN-020).
- Static `Content-Security-Policy` with `'unsafe-inline'` — bypassable (NEXTJS-VULN-032).

---

## 4. Rate Limiting — `@upstash/ratelimit` with Redis

Next.js does not provide a built-in rate limiter. The recommended pattern is `@upstash/ratelimit` backed by Redis (works on both Vercel Edge and Node runtimes).

```ts
// lib/ratelimit.ts
import { Ratelimit } from "@upstash/ratelimit"
import { Redis } from "@upstash/redis"

const redis = Redis.fromEnv()   // UPSTASH_REDIS_REST_URL + UPSTASH_REDIS_REST_TOKEN

// Strict limit for auth endpoints (login, signup, password reset)
export const authRateLimit = new Ratelimit({
    redis,
    limiter: Ratelimit.slidingWindow(5, "15 m"),
    analytics: true,
    prefix: "rl:auth",
})

// General API limit
export const apiRateLimit = new Ratelimit({
    redis,
    limiter: Ratelimit.slidingWindow(100, "1 m"),
    analytics: true,
    prefix: "rl:api",
})

// Expensive operations (e.g., email send, image generation)
export const expensiveRateLimit = new Ratelimit({
    redis,
    limiter: Ratelimit.tokenBucket(10, "1 h", 10),
    analytics: true,
    prefix: "rl:expensive",
})
```

### Usage in a Route Handler

```ts
// app/api/send-email/route.ts
import { auth } from "@/auth"
import { expensiveRateLimit } from "@/lib/ratelimit"

export async function POST(request: Request) {
    const session = await auth()
    if (!session?.user) {
        return new Response("unauthorized", { status: 401 })
    }

    const { success, reset, remaining } = await expensiveRateLimit.limit(
        `email:${session.user.id}`,
    )
    if (!success) {
        return new Response("rate limited", {
            status: 429,
            headers: {
                "Retry-After": String(Math.ceil((reset - Date.now()) / 1000)),
                "X-RateLimit-Remaining": String(remaining),
            },
        })
    }

    // ... send email
    return new Response("sent", { status: 200 })
}
```

### Usage in a Server Action

```tsx
// app/actions/send-invite.ts
"use server"
import { auth } from "@/auth"
import { expensiveRateLimit } from "@/lib/ratelimit"
import { z } from "zod"

const Schema = z.object({ email: z.string().email() })

export async function sendInvite(formData: FormData) {
    const session = await auth()
    if (!session?.user) throw new Error("unauthorized")

    const { success } = await expensiveRateLimit.limit(`invite:${session.user.id}`)
    if (!success) throw new Error("rate limited")

    const { email } = Schema.parse({ email: formData.get("email") })
    // ... send invite
}
```

### Algorithm choice

- **Sliding window** — strictest fairness; recommended for auth endpoints.
- **Token bucket** — bursty traffic friendly; recommended for general API and expensive operations.
- **Fixed window** — simplest, has boundary burst issue; only acceptable for low-stakes endpoints.

### Key strategy

- **Always prefer `userId`** over IP. IP-only rate limits are bypassable via residential proxies and hurt shared NAT users.
- **IP fallback** for unauthenticated routes (login, signup). Use the platform-validated IP (`request.ip` on Vercel) not `x-forwarded-for`.
- **Include the action type in the prefix** (`rl:email:{userId}` vs `rl:export:{userId}`) so limits are scoped per action.

---

## 5. Deploy Target Differences

| Aspect | Vercel | Self-hosted Node | Standalone |
| --- | --- | --- | --- |
| Rate limit backing | `@upstash/ratelimit` (Vercel KV or external Redis) | External Redis | External Redis |
| Trusted proxy handling | `request.ip` validated by platform | Configure nginx/Caddy to strip `X-Forwarded-For` and add its own | Same |
| HSTS | Set via `headers()` in `next.config`; Vercel also applies defaults | Must set explicitly | Must set explicitly |
| Image Optimizer | Runs on Vercel Edge Network | Runs on the Node process (restrictive network policy recommended) | Same |
| `poweredByHeader: false` | Recommended | Recommended | Recommended |
| Secret management | Vercel Environment Variables + Vercel Deployment Protection | Kubernetes Secrets / Docker Secrets / HashiCorp Vault | Same |
| Edge runtime for `proxy.ts` | **Not applicable in Next 16** — proxy.ts runs in Node.js only | Same | Same |

---

## 6. Zod / Valibot Input Parser Template

Every Server Action and Route Handler that accepts input must parse it through a runtime schema. Never trust TypeScript types at boundaries.

```ts
// app/actions/create-post.ts
"use server"
import { auth } from "@/auth"
import { z } from "zod"

const CreatePostSchema = z.object({
    title: z.string().min(1).max(200),
    body: z.string().min(1).max(50_000),
    tags: z.array(z.string().min(1).max(32)).max(10).default([]),
})

export async function createPost(formData: FormData) {
    const session = await auth()
    if (!session?.user) throw new Error("unauthorized")

    const parsed = CreatePostSchema.safeParse({
        title: formData.get("title"),
        body: formData.get("body"),
        tags: formData.getAll("tags"),
    })
    if (!parsed.success) {
        throw new Error("invalid input: " + parsed.error.message)
    }

    await db.post.create({
        data: {
            ...parsed.data,
            authorId: session.user.id,
        },
    })
}
```

### Valibot alternative (smaller bundle)

```ts
import * as v from "valibot"

const CreatePostSchema = v.object({
    title: v.pipe(v.string(), v.minLength(1), v.maxLength(200)),
    body:  v.pipe(v.string(), v.minLength(1), v.maxLength(50_000)),
    tags:  v.pipe(v.array(v.string()), v.maxLength(10)),
})

const result = v.safeParse(CreatePostSchema, input)
if (!result.success) throw new Error("invalid input")
```

Rule of thumb:
- `zod` if you already use it elsewhere or need advanced refinements.
- `valibot` if bundle size matters (Client Component validation).
- `arktype` if you want TypeScript-native syntax.

Do not mix — pick one for the project.

---

## 7. Auth.js v5 Configuration Template

```ts
// auth.ts
import NextAuth from "next-auth"
import Credentials from "next-auth/providers/credentials"
import Google from "next-auth/providers/google"
import { z } from "zod"
import { verifyPassword } from "@/lib/password"

export const { handlers, auth, signIn, signOut } = NextAuth({
    // Sessions stored in the database (revocable)
    session: { strategy: "database" },
    // OR for stateless:
    // session: { strategy: "jwt" },

    // Secret from env — NEVER hardcode
    secret: process.env.AUTH_SECRET,

    // Cookie hardening
    cookies: {
        sessionToken: {
            name: "authjs.session-token",
            options: {
                httpOnly: true,
                secure: process.env.NODE_ENV === "production",
                sameSite: "lax",
                path: "/",
            },
        },
    },

    providers: [
        Google({
            clientId: process.env.GOOGLE_CLIENT_ID,
            clientSecret: process.env.GOOGLE_CLIENT_SECRET,
        }),
        Credentials({
            credentials: {
                email: {},
                password: {},
            },
            async authorize(credentials) {
                const parsed = z
                    .object({
                        email: z.string().email(),
                        password: z.string().min(1),
                    })
                    .safeParse(credentials)
                if (!parsed.success) return null

                const user = await db.user.findUnique({
                    where: { email: parsed.data.email },
                })
                if (!user) return null

                const ok = await verifyPassword(parsed.data.password, user.passwordHash)
                if (!ok) return null

                return { id: user.id, email: user.email, name: user.name }
            },
        }),
    ],

    callbacks: {
        async redirect({ url, baseUrl }) {
            // Only allow same-origin redirects
            if (url.startsWith("/")) return `${baseUrl}${url}`
            if (new URL(url).origin === baseUrl) return url
            return baseUrl
        },
    },

    pages: {
        signIn: "/login",
        error: "/auth/error",
    },

    // Don't leak versions
    debug: false,
})
```

### Mandatory checks after applying

- `AUTH_SECRET` is in env, not committed.
- Cookie `httpOnly: true` and `secure: true` in production.
- `sameSite: "lax"` if OAuth callbacks exist, else `"strict"`.
- `redirect` callback validates URL against `baseUrl`.
- `pages.error` does not render `error.stack` to the user.

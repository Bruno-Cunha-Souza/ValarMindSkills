# Middleware Configuration Reference (Gin / Fiber v2 / Fiber v3)

Side-by-side configuration patterns for the middleware items checked in Phase 2 of `golang-api-security`. Use the `$FRAMEWORK` value detected in Phase 0 to pick the correct column.

> **Fiber v2 vs v3**: Fiber v3 changed many middleware import paths from `gofiber/fiber/v2/middleware/X` to `gofiber/fiber/v3/middleware/X`. Some middleware moved to `gofiber/contrib/X`. Always confirm the import path against the version in `go.mod`.

---

## 1. Production Mode

| Aspect | Gin | Fiber v2 | Fiber v3 |
| --- | --- | --- | --- |
| Mode setter | `gin.SetMode(gin.ReleaseMode)` | `fiber.New(fiber.Config{DisableStartupMessage: true})` | `fiber.New(fiber.Config{DisableStartupMessage: true})` |
| Default constructor risk | `gin.Default()` adds verbose recovery + logger | `app.Use(logger.New())` with default format prints request bodies | Same as v2 |
| Recommended constructor | `r := gin.New()` | `app := fiber.New(fiber.Config{...})` | `app := fiber.New(fiber.Config{...})` |

**Detection:**
```bash
rg 'gin\.Default\(\)' --type go            # gin
rg 'fiber\.New\(\)\b' --type go            # missing config — review needed
```

**Recommended Gin:**
```go
gin.SetMode(gin.ReleaseMode)
r := gin.New()
r.Use(gin.Recovery())          // catches panics, returns 500
r.Use(structuredLogger())      // your custom logger that scrubs PII
```

**Recommended Fiber v2:**
```go
app := fiber.New(fiber.Config{
    DisableStartupMessage: true,
    ReadTimeout:           30 * time.Second,
    WriteTimeout:          30 * time.Second,
    IdleTimeout:           120 * time.Second,
    BodyLimit:             1 * 1024 * 1024,
    ErrorHandler: func(c *fiber.Ctx, err error) error {
        log.Error("internal error", "err", err, "path", c.Path())
        return c.Status(fiber.StatusInternalServerError).
            JSON(fiber.Map{"error": "internal error"})
    },
})
app.Use(recover.New())
```

**Recommended Fiber v3:**
```go
app := fiber.New(fiber.Config{
    DisableStartupMessage: true,
    ReadTimeout:           30 * time.Second,
    WriteTimeout:          30 * time.Second,
    IdleTimeout:           120 * time.Second,
    BodyLimit:             1 * 1024 * 1024,
    ErrorHandler: func(c fiber.Ctx, err error) error {  // note: c by value in v3
        log.Error("internal error", "err", err, "path", c.Path())
        return c.Status(fiber.StatusInternalServerError).
            JSON(fiber.Map{"error": "internal error"})
    },
})
app.Use(recover.New())
```

---

## 2. CORS

| Aspect | Gin | Fiber v2 | Fiber v3 |
| --- | --- | --- | --- |
| Package | `github.com/gin-contrib/cors` | `github.com/gofiber/fiber/v2/middleware/cors` | `github.com/gofiber/fiber/v3/middleware/cors` |
| Forbidden combo | `AllowAllOrigins: true` + `AllowCredentials: true` | `AllowOrigins: "*"` + `AllowCredentials: true` | Same as v2 |
| Origin allowlist field | `AllowOrigins []string` | `AllowOrigins string` (comma-separated) | `AllowOrigins []string` |

**Recommended Gin:**
```go
r.Use(cors.New(cors.Config{
    AllowOrigins:     []string{"https://app.example.com", "https://admin.example.com"},
    AllowMethods:     []string{"GET", "POST", "PUT", "DELETE"},
    AllowHeaders:     []string{"Authorization", "Content-Type"},
    AllowCredentials: true,
    MaxAge:           12 * time.Hour,
}))
```

**Recommended Fiber v2:**
```go
app.Use(cors.New(cors.Config{
    AllowOrigins:     "https://app.example.com,https://admin.example.com",
    AllowMethods:     "GET,POST,PUT,DELETE",
    AllowHeaders:     "Authorization,Content-Type",
    AllowCredentials: true,
    MaxAge:           int((12 * time.Hour).Seconds()),
}))
```

**Recommended Fiber v3:**
```go
app.Use(cors.New(cors.Config{
    AllowOrigins:     []string{"https://app.example.com", "https://admin.example.com"},
    AllowMethods:     []string{"GET", "POST", "PUT", "DELETE"},
    AllowHeaders:     []string{"Authorization", "Content-Type"},
    AllowCredentials: true,
    MaxAge:           int((12 * time.Hour).Seconds()),
}))
```

**Detection:**
```bash
rg 'AllowAllOrigins\s*:\s*true' --type go
rg 'AllowOrigins\s*:\s*"\*"' --type go
rg 'AllowOrigins\s*:\s*\[\]string\{"\*"\}' --type go
```

---

## 3. Security Headers

| Aspect | Gin | Fiber v2 | Fiber v3 |
| --- | --- | --- | --- |
| Package | `github.com/gin-contrib/secure` | `github.com/gofiber/fiber/v2/middleware/helmet` | `github.com/gofiber/fiber/v3/middleware/helmet` |

**Recommended Gin:**
```go
import "github.com/gin-contrib/secure"

r.Use(secure.New(secure.Config{
    AllowedHosts:          []string{"api.example.com"},
    SSLRedirect:           true,
    STSSeconds:            31536000,
    STSIncludeSubdomains:  true,
    STSPreload:            true,
    FrameDeny:             true,
    ContentTypeNosniff:    true,
    BrowserXssFilter:      true,
    ReferrerPolicy:        "strict-origin-when-cross-origin",
    ContentSecurityPolicy: "default-src 'self'",
}))
```

**Recommended Fiber v2:**
```go
import "github.com/gofiber/fiber/v2/middleware/helmet"

app.Use(helmet.New(helmet.Config{
    XSSProtection:         "0",
    ContentTypeNosniff:    "nosniff",
    XFrameOptions:         "DENY",
    HSTSMaxAge:            31536000,
    HSTSIncludeSubdomains: true,
    HSTSPreloadEnabled:    true,
    ContentSecurityPolicy: "default-src 'self'",
    ReferrerPolicy:        "strict-origin-when-cross-origin",
}))
```

**Recommended Fiber v3:**
```go
import "github.com/gofiber/fiber/v3/middleware/helmet"

app.Use(helmet.New(helmet.Config{
    XSSProtection:         "0",
    ContentTypeNosniff:    "nosniff",
    XFrameOptions:         "DENY",
    HSTSMaxAge:            31536000,
    HSTSIncludeSubdomains: true,
    HSTSPreloadEnabled:    true,
    ContentSecurityPolicy: "default-src 'self'",
    ReferrerPolicy:        "strict-origin-when-cross-origin",
}))
```

Required headers (verify with `curl -I`):
- `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload`
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `Content-Security-Policy: default-src 'self'`
- `Referrer-Policy: strict-origin-when-cross-origin`

---

## 4. Rate Limiting

| Aspect | Gin | Fiber v2 | Fiber v3 |
| --- | --- | --- | --- |
| Built-in option | None — use `gin-contrib/ratelimit` or custom Redis | `gofiber/fiber/v2/middleware/limiter` | `gofiber/fiber/v3/middleware/limiter` |
| Auth endpoint baseline | ≤ 5 requests / 15 min | Same | Same |
| General API baseline | ≤ 100 requests / minute | Same | Same |

**Recommended Gin (Redis-backed):**
```go
import (
    "github.com/redis/go-redis/v9"
    "github.com/gin-gonic/gin"
)

func RedisRateLimit(rdb *redis.Client, limit int, window time.Duration) gin.HandlerFunc {
    return func(c *gin.Context) {
        key := "rl:" + c.ClientIP() + ":" + c.FullPath()
        ctx := c.Request.Context()
        count, err := rdb.Incr(ctx, key).Result()
        if err != nil {
            c.Next() // fail open OR fail closed depending on policy
            return
        }
        if count == 1 {
            rdb.Expire(ctx, key, window)
        }
        if int(count) > limit {
            c.Header("Retry-After", strconv.Itoa(int(window.Seconds())))
            c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{"error": "rate limit exceeded"})
            return
        }
        c.Header("X-RateLimit-Limit", strconv.Itoa(limit))
        c.Header("X-RateLimit-Remaining", strconv.Itoa(limit-int(count)))
        c.Next()
    }
}

// Apply strict limit to auth, looser limit to general API
auth := r.Group("/auth", RedisRateLimit(rdb, 5, 15*time.Minute))
api  := r.Group("/api",  RedisRateLimit(rdb, 100, time.Minute))
```

**Recommended Fiber v2:**
```go
import "github.com/gofiber/fiber/v2/middleware/limiter"

app.Use("/auth", limiter.New(limiter.Config{
    Max:        5,
    Expiration: 15 * time.Minute,
    KeyGenerator: func(c *fiber.Ctx) string {
        return c.IP() + ":" + c.Path()
    },
    LimitReached: func(c *fiber.Ctx) error {
        return c.Status(fiber.StatusTooManyRequests).
            JSON(fiber.Map{"error": "rate limit exceeded"})
    },
}))
```

**Recommended Fiber v3:**
```go
import "github.com/gofiber/fiber/v3/middleware/limiter"

app.Use("/auth", limiter.New(limiter.Config{
    Max:        5,
    Expiration: 15 * time.Minute,
    KeyGenerator: func(c fiber.Ctx) string {
        return c.IP() + ":" + c.Path()
    },
    LimitReached: func(c fiber.Ctx) error {
        return c.Status(fiber.StatusTooManyRequests).
            JSON(fiber.Map{"error": "rate limit exceeded"})
    },
}))
```

Algorithm choice:
- **Sliding window** (Redis ZSET-backed) — strictest fairness; recommended for auth endpoints
- **Token bucket** — bursty traffic friendly; recommended for general API
- **Fixed window** (built-in counter) — simplest, has boundary burst issue; only acceptable for low-stakes endpoints

---

## 5. CSRF (cookie-based auth only)

| Aspect | Gin | Fiber v2 | Fiber v3 |
| --- | --- | --- | --- |
| Package | `github.com/utrack/gin-csrf` | `github.com/gofiber/fiber/v2/middleware/csrf` | `github.com/gofiber/fiber/v3/middleware/csrf` |
| Needed for | Cookie sessions | Cookie sessions | Cookie sessions |
| NOT needed for | Pure JWT in `Authorization` header | Same | Same |

**Recommended Fiber v2:**
```go
import "github.com/gofiber/fiber/v2/middleware/csrf"

app.Use(csrf.New(csrf.Config{
    KeyLookup:      "header:X-CSRF-Token",
    CookieName:     "csrf_token",
    CookieSameSite: "Strict",
    CookieSecure:   true,
    CookieHTTPOnly: false, // must be readable by JS to be sent in header
    Expiration:     1 * time.Hour,
}))
```

---

## 6. Body Size Limit

| Aspect | Gin | Fiber v2 | Fiber v3 |
| --- | --- | --- | --- |
| Mechanism | `http.MaxBytesReader` per handler or middleware | `fiber.Config{BodyLimit: N}` | Same as v2 |
| Default | unlimited | 4 MiB | 4 MiB |

**Recommended Gin (middleware):**
```go
func BodyLimit(max int64) gin.HandlerFunc {
    return func(c *gin.Context) {
        c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, max)
        c.Next()
    }
}
r.Use(BodyLimit(1 << 20)) // 1 MiB
```

**Recommended Fiber:**
```go
app := fiber.New(fiber.Config{
    BodyLimit: 1 * 1024 * 1024, // 1 MiB
})
```

For uploads, use a per-route override to bump the limit instead of globally relaxing it.

---

## 7. Server Timeouts

| Field | Purpose | Recommended |
| --- | --- | --- |
| `ReadHeaderTimeout` | mitigates slowloris | 10s |
| `ReadTimeout` | full request body read time | 30s |
| `WriteTimeout` | response generation time | 30s |
| `IdleTimeout` | keep-alive idle time | 120s |

**Gin** does not expose these via `r.Run`. Instead, build a `*http.Server` and assign `r` as the handler:

```go
srv := &http.Server{
    Addr:              ":80",
    Handler:           r,
    ReadHeaderTimeout: 10 * time.Second,
    ReadTimeout:       30 * time.Second,
    WriteTimeout:      30 * time.Second,
    IdleTimeout:       120 * time.Second,
}
log.Fatal(srv.ListenAndServe())
```

**Fiber v2/v3** exposes them in `fiber.Config`:
```go
app := fiber.New(fiber.Config{
    ReadTimeout:  30 * time.Second,
    WriteTimeout: 30 * time.Second,
    IdleTimeout:  120 * time.Second,
})
```

**Detection:**
```bash
rg 'http\.ListenAndServe\(' --type go         # bare call → likely no timeouts
rg 'http\.Server\{' -A 8 --type go            # check for timeout fields
```

---

## 8. Trusted Proxies

| Aspect | Gin | Fiber v2 | Fiber v3 |
| --- | --- | --- | --- |
| Method | `r.SetTrustedProxies([]string{...})` | `fiber.Config{EnableTrustedProxyCheck: true, TrustedProxies: []string{...}}` | Same as v2 |
| Bad value | `nil` (trusts everyone) or `[]string{"0.0.0.0/0"}` | `EnableTrustedProxyCheck: false` (default — does not validate) | Same |

**Recommended Gin:**
```go
r.SetTrustedProxies([]string{"10.0.0.0/8", "172.16.0.0/12"})
```

**Recommended Fiber v2:**
```go
app := fiber.New(fiber.Config{
    EnableTrustedProxyCheck: true,
    TrustedProxies:          []string{"10.0.0.0/8", "172.16.0.0/12"},
    ProxyHeader:             fiber.HeaderXForwardedFor,
})
```

**Recommended Fiber v3:** (renamed field)
```go
app := fiber.New(fiber.Config{
    TrustProxy:       true,
    TrustProxyConfig: fiber.TrustProxyConfig{Proxies: []string{"10.0.0.0/8"}},
    ProxyHeader:      fiber.HeaderXForwardedFor,
})
```

Operator must supply the actual ingress CIDR. Never apply `0.0.0.0/0` as a "default".

---

## 9. pprof Exposure

Both Gin and Fiber make it easy to mount pprof. Production code must NOT mount pprof on the public router.

**Detection:**
```bash
rg '"net/http/pprof"' --type go
rg '"github.com/gin-contrib/pprof"' --type go
rg '"github.com/gofiber/fiber/v[23]/middleware/pprof"' --type go
```

**Mitigation:**
- Remove the import entirely OR
- Bind pprof to a separate internal listener (`127.0.0.1:6060`) and route via firewall/security group OR
- Wrap the pprof routes in an admin-auth middleware

```go
// Internal-only pprof — recommended
go func() {
    log.Println(http.ListenAndServe("127.0.0.1:6060", nil))
}()
```

---

## 10. TLS Enforcement

| Aspect | Gin | Fiber v2 | Fiber v3 |
| --- | --- | --- | --- |
| Direct TLS listener | `r.RunTLS(":443", certFile, keyFile)` | `app.ListenTLS(":443", certFile, keyFile)` | `app.Listen(":443", fiber.ListenConfig{CertFile: ...})` |
| Reverse proxy termination | Gin behind nginx/Caddy with HSTS at proxy | Same | Same |
| `MinVersion` enforcement | Custom `*http.Server` with `TLSConfig.MinVersion = tls.VersionTLS12` | Custom `tls.Config` passed via `ListenMutualTLSWithCertificate` | Same |

**Recommended Gin:**
```go
srv := &http.Server{
    Addr:    ":443",
    Handler: r,
    TLSConfig: &tls.Config{
        MinVersion:       tls.VersionTLS12,
        CurvePreferences: []tls.CurveID{tls.X25519, tls.CurveP256},
    },
    ReadHeaderTimeout: 10 * time.Second,
}
log.Fatal(srv.ListenAndServeTLS("cert.pem", "key.pem"))
```

If terminating TLS at a reverse proxy, the proxy must:
- Enforce TLS 1.2+
- Set `Strict-Transport-Security` header
- Forward `X-Forwarded-Proto: https` so the app can detect HTTPS

---

## 11. Recovery Middleware

Every framework needs an explicit recovery middleware to catch panics in handlers and return a generic 500.

**Gin:**
```go
r.Use(gin.Recovery()) // built-in
```

**Fiber v2:**
```go
import "github.com/gofiber/fiber/v2/middleware/recover"
app.Use(recover.New(recover.Config{EnableStackTrace: false}))
```

**Fiber v3:**
```go
import "github.com/gofiber/fiber/v3/middleware/recover"
app.Use(recover.New(recover.Config{EnableStackTrace: false}))
```

`EnableStackTrace: false` is mandatory in production — otherwise the panic stack reaches the response writer.

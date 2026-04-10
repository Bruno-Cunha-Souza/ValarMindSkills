# Go API Security Patch Templates

Patch templates for the auto-fix phase of `golang-api-security`. Each template is keyed to a `GOVULN-NNN` ID from `VULNERABILITIES.md`.

Risk tag legend:
- **SAFE** — isolated change, no API contract or behavior shift, no shared state mutation
- **REVIEW** — affects middleware stack, auth, or shared code paths; needs human inspection
- **BREAKING** — changes the public API contract or response shape; requires coordination with consumers

Every patch must pass `go build ./...` before the skill marks it as applied. If the build fails, the change is reverted with `git restore <file>` and re-emitted as "manual review required".

---

## PATCH-001 — SQL Injection (GOVULN-001/002)

**Risk:** SAFE
**Validation:** `go build ./...`, then run integration tests for the affected handler

```diff
- query := fmt.Sprintf("SELECT id, email FROM users WHERE name = '%s'", name)
- rows, err := db.Query(query)
+ rows, err := db.Query("SELECT id, email FROM users WHERE name = $1", name)
```

Notes: PostgreSQL uses `$1`, MySQL/SQLite use `?`. Identifiers (table/column names) cannot be parameterized — use a hard-coded allowlist if dynamic identifiers are required.

---

## PATCH-002 — Command Injection (GOVULN-003)

**Risk:** REVIEW (changes execution semantics — verify the host validator covers the deployment environment)
**Validation:** `go build ./...` and a probe with a malicious payload

```diff
- cmd := exec.Command("sh", "-c", "ping "+host)
- if err := cmd.Run(); err != nil { ... }
+ if !isValidHost(host) {
+     c.JSON(http.StatusBadRequest, gin.H{"error": "invalid host"})
+     return
+ }
+ cmd := exec.Command("ping", "-c", "1", host)
+ if err := cmd.Run(); err != nil { ... }
```

`isValidHost` should accept only IPs or DNS labels matching `^[a-zA-Z0-9.-]+$` and reject anything containing shell metacharacters.

---

## PATCH-003 — Path Traversal (GOVULN-004)

**Risk:** SAFE
**Validation:** `go build ./...` and a request with `../etc/passwd`

```diff
- data, err := os.ReadFile(filepath.Join("./uploads", c.Param("filename")))
+ filename := filepath.Base(c.Param("filename"))
+ cleaned := filepath.Clean(filepath.Join("./uploads", filename))
+ if !strings.HasPrefix(cleaned, "uploads"+string(os.PathSeparator)) {
+     c.JSON(http.StatusBadRequest, gin.H{"error": "invalid path"})
+     return
+ }
+ data, err := os.ReadFile(cleaned)
```

---

## PATCH-004 — SSRF in `http.Get` (GOVULN-005)

**Risk:** REVIEW (the URL allowlist is environment-dependent)
**Validation:** `go build ./...` and probe with `http://169.254.169.254/`, `http://127.0.0.1/`, `http://10.0.0.1/`

```diff
- resp, err := http.Get(target)
+ u, err := url.Parse(target)
+ if err != nil || (u.Scheme != "http" && u.Scheme != "https") {
+     return nil, errors.New("invalid url")
+ }
+ if isPrivateOrLoopback(u.Hostname()) {
+     return nil, errors.New("blocked host")
+ }
+ client := &http.Client{
+     Timeout: 5 * time.Second,
+     CheckRedirect: func(req *http.Request, via []*http.Request) error {
+         return http.ErrUseLastResponse
+     },
+ }
+ resp, err := client.Get(target)
```

Add a helper:

```go
func isPrivateOrLoopback(host string) bool {
    ips, err := net.LookupIP(host)
    if err != nil { return true } // fail closed
    for _, ip := range ips {
        if ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() ||
           ip.Equal(net.ParseIP("169.254.169.254")) {
            return true
        }
    }
    return false
}
```

---

## PATCH-005 — `math/rand` for tokens (GOVULN-007)

**Risk:** SAFE
**Validation:** `go build ./...`

```diff
- import "math/rand"
- token := strconv.FormatInt(rand.Int63(), 10)
+ import "crypto/rand"
+ b := make([]byte, 32)
+ if _, err := rand.Read(b); err != nil {
+     return "", err
+ }
+ token := hex.EncodeToString(b)
```

If multiple call sites exist, prefer extracting a `secureToken()` helper to a single `crypto/random.go` file.

---

## PATCH-006 — Hardcoded secret (GOVULN-008)

**Risk:** REVIEW (requires deploying the env var to every environment)
**Validation:** `go build ./...` and verify the env var is set in CI/CD secrets

```diff
- const jwtSecret = "supersecret123"
+ var jwtSecret = func() []byte {
+     v := os.Getenv("JWT_SECRET")
+     if v == "" {
+         log.Fatal("JWT_SECRET environment variable is not set")
+     }
+     return []byte(v)
+ }()
```

After applying, immediately rotate the leaked secret on the auth provider — the previous value is in git history and must be considered compromised.

---

## PATCH-007 — `InsecureSkipVerify: true` (GOVULN-010)

**Risk:** REVIEW (verify the target presents a valid certificate; if it uses a private CA, load it explicitly)
**Validation:** `go build ./...` and a successful TLS handshake against the real target

```diff
  client := &http.Client{
      Transport: &http.Transport{
-         TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
+         TLSClientConfig: &tls.Config{
+             MinVersion: tls.VersionTLS12,
+         },
      },
  }
```

For private CA cases:

```diff
+ caCert, err := os.ReadFile("/etc/ssl/private-ca.pem")
+ if err != nil { return err }
+ pool := x509.NewCertPool()
+ pool.AppendCertsFromPEM(caCert)
  client := &http.Client{
      Transport: &http.Transport{
+         TLSClientConfig: &tls.Config{
+             MinVersion: tls.VersionTLS12,
+             RootCAs:    pool,
+         },
      },
  }
```

---

## PATCH-008 — JWT `alg:none` accepted (GOVULN-013)

**Risk:** REVIEW (changes auth flow; verify the rest of the system tolerates the rejection of malformed tokens)
**Validation:** `go test ./...` and an end-to-end login probe

```diff
- token, err := jwt.Parse(tokenString, func(t *jwt.Token) (interface{}, error) {
-     return secretKey, nil
- })
+ token, err := jwt.Parse(tokenString, func(t *jwt.Token) (interface{}, error) {
+     if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
+         return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
+     }
+     return secretKey, nil
+ }, jwt.WithValidMethods([]string{"HS256"}))
```

For RSA: replace `*jwt.SigningMethodHMAC` with `*jwt.SigningMethodRSA` and the algorithm whitelist with `[]string{"RS256"}`.

---

## PATCH-009 — JWT missing claim validation (GOVULN-014)

**Risk:** REVIEW
**Validation:** integration test exercising token issued for a different audience/issuer

```diff
- parser := jwt.NewParser()
+ parser := jwt.NewParser(
+     jwt.WithIssuer("https://auth.example.com"),
+     jwt.WithAudience("api.example.com"),
+     jwt.WithExpirationRequired(),
+     jwt.WithValidMethods([]string{"RS256"}),
+ )
  token, err := parser.ParseWithClaims(tokenString, &claims, keyFunc)
```

---

## PATCH-010 — Insecure cookie flags (GOVULN-016)

**Risk:** SAFE (Strict mode may break OAuth callback flows — REVIEW if the app is OAuth client)
**Validation:** `go build ./...` and verify cookies still work in the integration tests

```diff
- c.SetCookie("session", token, 3600, "/", "", false, false)
+ c.SetSameSite(http.SameSiteStrictMode)
+ c.SetCookie("session", token, 3600, "/", "", true /*Secure*/, true /*HttpOnly*/)
```

If the service is an OAuth client receiving callbacks from another origin, switch `SameSiteStrictMode` to `SameSiteLaxMode` instead.

---

## PATCH-011 — bcrypt cost factor below 10 (GOVULN-018)

**Risk:** SAFE (hash format is forward-compatible; old hashes still verify)
**Validation:** `go test ./...`

```diff
- hash, err := bcrypt.GenerateFromPassword(pw, bcrypt.DefaultCost)
+ hash, err := bcrypt.GenerateFromPassword(pw, 12)
```

Existing hashes remain valid because `bcrypt.CompareHashAndPassword` reads the cost from the stored hash.

---

## PATCH-012 — `gin.Default()` in production (GOVULN-019)

**Risk:** REVIEW (changes the recovery + logger behavior — verify your custom logger covers what was logged before)
**Validation:** `go build ./...` and load test the service to verify panics are caught

```diff
- r := gin.Default()
+ gin.SetMode(gin.ReleaseMode)
+ r := gin.New()
+ r.Use(gin.Recovery())
+ r.Use(structuredLogger())
```

`structuredLogger` should use `log/slog` or `zap` and explicitly NOT log request bodies.

---

## PATCH-013 — CORS wildcard with credentials (GOVULN-020)

**Risk:** BREAKING (frontends served from disallowed origins will break)
**Validation:** `go build ./...` and verify approved frontends still work

```diff
  r.Use(cors.New(cors.Config{
-     AllowAllOrigins:  true,
-     AllowCredentials: true,
+     AllowOrigins:     []string{"https://app.example.com"},
+     AllowCredentials: true,
+     AllowMethods:     []string{"GET", "POST", "PUT", "DELETE"},
+     AllowHeaders:     []string{"Authorization", "Content-Type"},
+     MaxAge:           12 * time.Hour,
  }))
```

Provide the operator the list of expected origins and update CI tests.

---

## PATCH-014 — Trusted proxies misconfigured (GOVULN-021)

**Risk:** REVIEW (depends on the deployment topology — load balancer CIDR must be known)
**Validation:** `go build ./...` and verify `X-Forwarded-For` from the LB still resolves to client IP

```diff
- r.SetTrustedProxies(nil)
+ r.SetTrustedProxies([]string{"10.0.0.0/8", "172.16.0.0/12"})
```

Ask the operator for the actual ingress CIDR before applying.

---

## PATCH-015 — pprof on public router (GOVULN-022)

**Risk:** REVIEW (some teams rely on pprof for diagnostics — coordinate before removing)
**Validation:** `go build ./...` and probe `/debug/pprof/` (expect 404 on public; works on internal port)

```diff
  package main

  import (
      "net/http"
-     _ "net/http/pprof"
+     _ "net/http/pprof" // registers on http.DefaultServeMux only
  )

  func main() {
+     // Internal-only pprof binding — not reachable from public ingress
+     go func() {
+         log.Println(http.ListenAndServe("127.0.0.1:6060", nil))
+     }()
+
      mux := http.NewServeMux()
      mux.HandleFunc("/api/...", apiHandler)
      http.ListenAndServe(":80", mux) // serves the app, NOT DefaultServeMux
  }
```

Key change: the public listener uses an explicit `mux`, not `nil`/`DefaultServeMux`, so pprof is only reachable on `127.0.0.1:6060`.

---

## PATCH-016 — Missing `ReadHeaderTimeout` / slowloris (GOVULN-031)

**Risk:** SAFE
**Validation:** `go build ./...` and a slowloris test (see `TESTING_PAYLOADS.md`)

```diff
- http.ListenAndServe(":80", handler)
+ srv := &http.Server{
+     Addr:              ":80",
+     Handler:           handler,
+     ReadHeaderTimeout: 10 * time.Second,
+     ReadTimeout:       30 * time.Second,
+     WriteTimeout:      30 * time.Second,
+     IdleTimeout:       120 * time.Second,
+ }
+ srv.ListenAndServe()
```

For Gin: replace `r.Run(":80")` with `srv.ListenAndServe()` after wiring `srv.Handler = r`.

---

## PATCH-017 — Missing `MaxBytesReader` (GOVULN-032)

**Risk:** SAFE (clients hitting the limit get a clear 413; existing valid traffic is unaffected)
**Validation:** `go build ./...` and a probe with a 10 MiB body (expect 413)

```diff
+ r.Body = http.MaxBytesReader(w, r.Body, 1<<20) // 1 MiB
  body, err := io.ReadAll(r.Body)
+ if err != nil {
+     http.Error(w, "request body too large", http.StatusRequestEntityTooLarge)
+     return
+ }
```

Tune the limit per endpoint (uploads need more, JSON APIs need less).

---

## PATCH-018 — gzip bomb (GOVULN-034)

**Risk:** SAFE
**Validation:** `go build ./...` and a probe with a 1 KiB compressed payload that decompresses to 1 GiB (expect error)

```diff
+ r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
  gz, err := gzip.NewReader(r.Body)
+ if err != nil {
+     http.Error(w, "invalid gzip", http.StatusBadRequest); return
+ }
  defer gz.Close()
- data, err := io.ReadAll(gz)
+ data, err := io.ReadAll(io.LimitReader(gz, 10<<20)) // cap decompressed bytes
```

---

## PATCH-019 — Zip slip (GOVULN-036)

**Risk:** SAFE
**Validation:** `go build ./...` and a probe with a malicious zip containing `../etc/passwd`

```diff
  for _, f := range zipReader.File {
-     out, err := os.Create(filepath.Join(destDir, f.Name))
+     cleaned := filepath.Clean(filepath.Join(destDir, f.Name))
+     if !strings.HasPrefix(cleaned, destDir+string(os.PathSeparator)) {
+         return errors.New("zip slip detected: " + f.Name)
+     }
+     out, err := os.Create(cleaned)
  }
```

---

## PATCH-020 — JSON unknown fields (GOVULN-037)

**Risk:** REVIEW (clients sending extra fields will start receiving 400 — coordinate)
**Validation:** `go build ./...` and run all integration tests

```diff
- var req CreateUserRequest
- if err := json.NewDecoder(r.Body).Decode(&req); err != nil { ... }
+ var req CreateUserRequest
+ dec := json.NewDecoder(r.Body)
+ dec.DisallowUnknownFields()
+ if err := dec.Decode(&req); err != nil {
+     http.Error(w, "invalid request: "+err.Error(), http.StatusBadRequest)
+     return
+ }
```

This is the primary defense against mass assignment in Go.

---

## PATCH-021 — Stack trace in error response (GOVULN-038)

**Risk:** SAFE
**Validation:** `go build ./...` and a probe that triggers an error (expect generic message)

```diff
  if err != nil {
-     c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("%+v", err)})
+     log.Error("internal error",
+         "err", err,
+         "path", c.Request.URL.Path,
+         "method", c.Request.Method,
+     )
+     c.JSON(http.StatusInternalServerError, gin.H{"error": "internal server error"})
      return
  }
```

---

## PATCH-022 — Direct ORM model serialization (GOVULN-039)

**Risk:** BREAKING (response shape changes)
**Validation:** `go build ./...` + integration tests + downstream consumer tests

```diff
+ type UserResponse struct {
+     ID    string `json:"id"`
+     Email string `json:"email"`
+     Name  string `json:"name"`
+ }
+
  func GetUser(c *gin.Context) {
      var u User
      db.First(&u, c.Param("id"))
-     c.JSON(http.StatusOK, u) // exposes PasswordHash, internal fields
+     c.JSON(http.StatusOK, UserResponse{
+         ID:    u.ID,
+         Email: u.Email,
+         Name:  u.Name,
+     })
  }
```

---

## PATCH-023 — `text/template` for HTML (GOVULN-040)

**Risk:** SAFE
**Validation:** `go build ./...` and a probe with `<script>alert(1)</script>` (expect escaped output)

```diff
- import "text/template"
+ import "html/template"
```

The API surface is identical; just the import path changes. `html/template` performs context-aware escaping for HTML, JS, CSS, and URL contexts.

---

## PATCH-024 — Log injection (GOVULN-041)

**Risk:** SAFE
**Validation:** `go build ./...` and a probe with newline-containing input

```diff
- log.Printf("user login: %s", c.Query("user"))
+ slog.Info("user login", "user", c.Query("user"))
```

`slog` is in the standard library since Go 1.21 and escapes field values by default. For older logger choices: `zap` and `zerolog` also escape; `log.Printf` does not.

---

## PATCH-025 — `go:embed` overly broad pattern (GOVULN-042)

**Risk:** SAFE
**Validation:** `go build ./...` and inspect the binary contents

```diff
- //go:embed config/*
+ //go:embed config/public.json config/templates/*.html
  var configFS embed.FS
```

After applying, run `go run main.go` once and verify no expected file is missing. If one is, add it explicitly to the embed pattern (never broaden back to `*`).

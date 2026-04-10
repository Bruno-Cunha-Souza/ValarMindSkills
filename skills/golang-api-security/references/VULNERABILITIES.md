# Go API Vulnerability Catalog

Catalog of Go-specific vulnerability patterns for use by the `golang-api-security` skill. Each entry follows the same structure: ID, CWE, vulnerable pattern, fix pattern, detection command, severity baseline.

Use the IDs (`GOVULN-NNN`) when emitting findings in the security report so they can be cross-referenced.

## Index by Category

- Injection — GOVULN-001 to GOVULN-006
- Crypto & Secrets — GOVULN-007 to GOVULN-012
- Auth & Sessions — GOVULN-013 to GOVULN-018
- Configuration & Headers — GOVULN-019 to GOVULN-024
- Concurrency & Runtime — GOVULN-025 to GOVULN-030
- Resource Consumption & DoS — GOVULN-031 to GOVULN-036
- Data Handling & Disclosure — GOVULN-037 to GOVULN-042

---

## Injection

### GOVULN-001 — SQL Injection via `fmt.Sprintf`
- **CWE:** CWE-89
- **Severity:** Critical
- **Vulnerable:**
  ```go
  query := fmt.Sprintf("SELECT * FROM users WHERE name = '%s'", c.Param("name"))
  rows, _ := db.Query(query)
  ```
- **Fixed:**
  ```go
  rows, err := db.Query("SELECT id, email FROM users WHERE name = $1", c.Param("name"))
  ```
- **Detection:** `rg 'fmt\.Sprintf\([^)]*(SELECT|INSERT|UPDATE|DELETE)' --type go`
- **Notes:** Always parameterize. `database/sql` placeholders are `?` (MySQL/SQLite) or `$1` (PostgreSQL). For schema names use a hard-coded allowlist — placeholders cannot bind identifiers.

### GOVULN-002 — SQL Injection via `db.Query` with concatenation
- **CWE:** CWE-89
- **Severity:** Critical
- **Vulnerable:**
  ```go
  rows, _ := db.Query("SELECT * FROM users WHERE id = " + c.Query("id"))
  ```
- **Fixed:** see GOVULN-001 — pass placeholders + arguments
- **Detection:** `rg 'db\.(Query|Exec)\(.*\+' --type go`

### GOVULN-003 — Command Injection via `exec.Command`
- **CWE:** CWE-78
- **Severity:** Critical
- **Vulnerable:**
  ```go
  cmd := exec.Command("sh", "-c", "ping "+c.Query("host"))
  ```
- **Fixed:**
  ```go
  host := c.Query("host")
  if !isValidHost(host) { c.Status(400); return }
  cmd := exec.Command("ping", "-c", "1", host) // arguments as slice, no shell
  ```
- **Detection:** `rg 'exec\.Command\([^)]*c\.(Param|Query|PostForm)' --type go`
- **Notes:** Never invoke a shell with user input. Pass arguments as separate slice elements so `exec.Command` does not parse them.

### GOVULN-004 — Path Traversal in file operations
- **CWE:** CWE-22
- **Severity:** High
- **Vulnerable:**
  ```go
  data, _ := os.ReadFile(filepath.Join("./uploads", c.Param("filename")))
  ```
- **Fixed:**
  ```go
  filename := filepath.Base(c.Param("filename"))           // strip directory
  cleaned := filepath.Clean(filepath.Join("./uploads", filename))
  if !strings.HasPrefix(cleaned, "uploads/") {
      c.Status(http.StatusBadRequest); return
  }
  data, err := os.ReadFile(cleaned)
  ```
- **Detection:** `rg 'os\.(Open|ReadFile|Create)\(.*c\.(Param|Query)' --type go`
- **Notes:** `filepath.Clean` does NOT prevent absolute paths or `..` segments outside the base — always check the prefix after Clean.

### GOVULN-005 — Server-Side Request Forgery via `http.Get`
- **CWE:** CWE-918
- **Severity:** High
- **Vulnerable:**
  ```go
  resp, _ := http.Get(c.Query("url"))
  ```
- **Fixed:**
  ```go
  target := c.Query("url")
  u, err := url.Parse(target)
  if err != nil || (u.Scheme != "http" && u.Scheme != "https") {
      c.Status(400); return
  }
  if isPrivateOrLoopback(u.Host) {
      c.Status(400); return
  }
  client := &http.Client{
      Timeout: 5 * time.Second,
      CheckRedirect: func(req *http.Request, via []*http.Request) error {
          return http.ErrUseLastResponse // do not auto-follow
      },
  }
  resp, err := client.Get(target)
  ```
- **Detection:** `rg 'http\.(Get|Post|NewRequest)\(' --type go`
- **Notes:** Block RFC1918, loopback, link-local, and AWS metadata (`169.254.169.254`). Do not auto-follow redirects.

### GOVULN-006 — SSRF via `httputil.ReverseProxy` Director
- **CWE:** CWE-918
- **Severity:** High
- **Vulnerable:**
  ```go
  proxy := &httputil.ReverseProxy{
      Director: func(req *http.Request) {
          req.URL.Host = req.Header.Get("X-Backend") // attacker-controlled
      },
  }
  ```
- **Fixed:** validate `X-Backend` against an allowlist before assigning, or use a fixed target with `httputil.NewSingleHostReverseProxy(allowedURL)`.
- **Detection:** `rg 'httputil\.(NewSingleHostReverseProxy|ReverseProxy\{)' --type go`

---

## Crypto & Secrets

### GOVULN-007 — `math/rand` used for security tokens
- **CWE:** CWE-338
- **Severity:** Critical
- **Vulnerable:**
  ```go
  import "math/rand"
  token := strconv.Itoa(rand.Int()) // predictable
  ```
- **Fixed:**
  ```go
  import "crypto/rand"
  b := make([]byte, 32)
  if _, err := rand.Read(b); err != nil { return err }
  token := hex.EncodeToString(b)
  ```
- **Detection:** `rg '"math/rand"' --type go` then audit nearby use of "token", "id", "secret", "password"
- **Notes:** Go 1.20+ seeds `math/rand` automatically but it remains non-cryptographic. Always `crypto/rand` for any security-sensitive randomness.

### GOVULN-008 — Hardcoded secret in source
- **CWE:** CWE-798
- **Severity:** Critical
- **Vulnerable:**
  ```go
  const jwtSecret = "supersecret123"
  ```
- **Fixed:**
  ```go
  jwtSecret := os.Getenv("JWT_SECRET")
  if jwtSecret == "" { log.Fatal("JWT_SECRET not set") }
  ```
- **Detection:** `gosec -include=G101 ./...` and `rg -i '(password|secret|token|api[_-]?key)\s*[:=]\s*"[A-Za-z0-9]{8,}"' --type go`

### GOVULN-009 — Insecure hash function (MD5/SHA1) for security purposes
- **CWE:** CWE-327
- **Severity:** High (security context) / Low (non-security checksums)
- **Vulnerable:**
  ```go
  h := md5.Sum([]byte(password))
  ```
- **Fixed:**
  ```go
  hash, err := bcrypt.GenerateFromPassword([]byte(password), 12)
  ```
- **Detection:** `rg '"crypto/(md5|sha1)"' --type go` and check the use site

### GOVULN-010 — `tls.Config{InsecureSkipVerify: true}`
- **CWE:** CWE-295
- **Severity:** Critical
- **Vulnerable:**
  ```go
  client := &http.Client{
      Transport: &http.Transport{
          TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
      },
  }
  ```
- **Fixed:** remove the field; if a custom CA is required, load it via `x509.NewCertPool()` and assign to `RootCAs`.
- **Detection:** `rg 'InsecureSkipVerify\s*:\s*true' --type go`

### GOVULN-011 — TLS version below 1.2
- **CWE:** CWE-326
- **Severity:** High
- **Vulnerable:** server with no `MinVersion` set (defaults to TLS 1.0 in older Go)
- **Fixed:**
  ```go
  srv := &http.Server{
      Addr: ":443",
      TLSConfig: &tls.Config{
          MinVersion: tls.VersionTLS12,
          CurvePreferences: []tls.CurveID{tls.X25519, tls.CurveP256},
      },
  }
  ```
- **Detection:** `rg 'tls\.Config\{' -A 5 --type go` then verify `MinVersion`

### GOVULN-012 — Non-constant-time token comparison
- **CWE:** CWE-208
- **Severity:** Medium
- **Vulnerable:**
  ```go
  if userToken == expectedToken { ... }
  ```
- **Fixed:**
  ```go
  if subtle.ConstantTimeCompare([]byte(userToken), []byte(expectedToken)) == 1 { ... }
  ```
- **Detection:** Manual review of token comparisons in auth/middleware files

---

## Auth & Sessions

### GOVULN-013 — JWT `alg:none` accepted
- **CWE:** CWE-347
- **Severity:** Critical
- **Vulnerable:**
  ```go
  token, _ := jwt.Parse(tokenString, func(t *jwt.Token) (interface{}, error) {
      return secretKey, nil
  })
  ```
- **Fixed:**
  ```go
  token, err := jwt.Parse(tokenString, func(t *jwt.Token) (interface{}, error) {
      if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
          return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
      }
      return secretKey, nil
  })
  ```
- **Detection:** `rg 'jwt\.Parse\(' --type go`

### GOVULN-014 — JWT missing `iss`/`aud`/`exp` validation
- **CWE:** CWE-345
- **Severity:** High
- **Vulnerable:** `jwt.Parse` without explicit `WithIssuer`, `WithAudience`, `WithExpirationRequired`
- **Fixed:**
  ```go
  parser := jwt.NewParser(
      jwt.WithIssuer("https://auth.example.com"),
      jwt.WithAudience("api.example.com"),
      jwt.WithExpirationRequired(),
      jwt.WithValidMethods([]string{"RS256"}),
  )
  token, err := parser.ParseWithClaims(tokenString, &claims, keyFunc)
  ```
- **Detection:** Manual review of every `jwt.Parse` call

### GOVULN-015 — Archived `dgrijalva/jwt-go` dependency
- **CWE:** CWE-1395
- **Severity:** High
- **Detection:** `grep 'dgrijalva/jwt-go' go.mod`
- **Fix:** Migrate to `github.com/golang-jwt/jwt/v5` (drop-in compatible imports for most use cases)

### GOVULN-016 — Insecure cookie flags
- **CWE:** CWE-614 / CWE-1004
- **Severity:** High
- **Vulnerable:**
  ```go
  c.SetCookie("session", token, 3600, "/", "", false, false)
  ```
- **Fixed:**
  ```go
  c.SetCookie("session", token, 3600, "/", "", true /*Secure*/, true /*HttpOnly*/)
  // Then set SameSite separately:
  c.SetSameSite(http.SameSiteStrictMode)
  ```
- **Detection:** `rg 'SetCookie\(' --type go` and verify Secure/HttpOnly arguments

### GOVULN-017 — Missing route protection (handler outside auth group)
- **CWE:** CWE-862
- **Severity:** High
- **Detection:**
  ```bash
  rg -n '\.(GET|POST|PUT|DELETE|PATCH)\(' --type go > all_routes.txt
  rg -n '\.Use\([^)]*[Aa]uth' --type go > auth_routes.txt
  # Manually cross-check that every sensitive route falls under an auth-protected group
  ```
- **Fix:** Move handler into the authenticated route group, or wrap with `authMiddleware()` explicitly

### GOVULN-018 — bcrypt cost factor below 10
- **CWE:** CWE-916
- **Severity:** Medium
- **Vulnerable:**
  ```go
  hash, _ := bcrypt.GenerateFromPassword(pw, bcrypt.MinCost) // 4
  ```
- **Fixed:**
  ```go
  hash, _ := bcrypt.GenerateFromPassword(pw, 12)
  ```
- **Detection:** `rg 'bcrypt\.GenerateFromPassword' --type go`

---

## Configuration & Headers

### GOVULN-019 — `gin.Default()` in production
- **CWE:** CWE-489
- **Severity:** High
- **Vulnerable:**
  ```go
  r := gin.Default()  // logger writes to stdout, recovery prints stack to client
  ```
- **Fixed:**
  ```go
  gin.SetMode(gin.ReleaseMode)
  r := gin.New()
  r.Use(gin.Recovery())              // recovery without verbose output
  r.Use(structuredLogger())          // your own logger that scrubs PII
  ```
- **Detection:** `rg 'gin\.Default\(\)' --type go`

### GOVULN-020 — CORS wildcard with credentials
- **CWE:** CWE-942
- **Severity:** Critical
- **Vulnerable:**
  ```go
  r.Use(cors.New(cors.Config{
      AllowAllOrigins:  true,
      AllowCredentials: true,
  }))
  ```
- **Fixed:**
  ```go
  r.Use(cors.New(cors.Config{
      AllowOrigins:     []string{"https://app.example.com"},
      AllowCredentials: true,
      AllowMethods:     []string{"GET", "POST", "PUT", "DELETE"},
      AllowHeaders:     []string{"Authorization", "Content-Type"},
      MaxAge:           12 * time.Hour,
  }))
  ```
- **Detection:** `rg 'AllowAllOrigins\s*:\s*true' --type go` and check for `AllowCredentials: true` in same struct

### GOVULN-021 — Trusted proxies set to `0.0.0.0/0` or nil
- **CWE:** CWE-348
- **Severity:** High
- **Vulnerable:**
  ```go
  r.SetTrustedProxies(nil) // trusts every X-Forwarded-For
  ```
- **Fixed:**
  ```go
  r.SetTrustedProxies([]string{"10.0.0.0/8", "172.16.0.0/12"})
  ```
- **Detection:** `rg 'SetTrustedProxies' --type go`

### GOVULN-022 — pprof exposed on public router
- **CWE:** CWE-200
- **Severity:** High
- **Vulnerable:**
  ```go
  import _ "net/http/pprof"  // auto-registers on http.DefaultServeMux
  http.ListenAndServe(":80", nil)
  ```
- **Fixed:**
  ```go
  // Bind pprof to a separate, internal-only port
  go func() {
      log.Println(http.ListenAndServe("127.0.0.1:6060", nil))
  }()
  http.ListenAndServe(":80", appMux) // app uses its own mux, not Default
  ```
- **Detection:** `rg '"net/http/pprof"' --type go`

### GOVULN-023 — Missing security headers
- **CWE:** CWE-693
- **Severity:** Medium
- **Detection:** Probe the running service:
  ```bash
  curl -I https://target/ | grep -E 'Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|Content-Security-Policy'
  ```
- **Fix:** Add `gin-contrib/secure` or equivalent middleware setting all five headers (HSTS, X-Frame-Options DENY, X-Content-Type-Options nosniff, CSP, Referrer-Policy)

### GOVULN-024 — Default Gin recovery middleware in prod (verbose)
- **CWE:** CWE-209
- **Severity:** Medium
- **Notes:** `gin.Recovery()` writes the panic stack to the response writer in development mode. Wrap with a custom recovery that returns a generic 500 in production.

---

## Concurrency & Runtime

### GOVULN-025 — Data race in shared map
- **CWE:** CWE-362
- **Severity:** High
- **Vulnerable:**
  ```go
  var cache = map[string]string{}
  func handler(c *gin.Context) {
      cache[c.Query("k")] = c.Query("v") // concurrent map writes → panic
  }
  ```
- **Fixed:**
  ```go
  var cache sync.Map
  func handler(c *gin.Context) {
      cache.Store(c.Query("k"), c.Query("v"))
  }
  ```
- **Detection:** `go test -race ./...` and `rg 'map\[string\]' --type go`

### GOVULN-026 — Goroutine leak (missing context cancellation)
- **CWE:** CWE-401
- **Severity:** Medium
- **Vulnerable:**
  ```go
  go func() {
      for {
          select {
          case msg := <-ch:
              process(msg) // never returns, no ctx
          }
      }
  }()
  ```
- **Fixed:**
  ```go
  go func(ctx context.Context) {
      for {
          select {
          case <-ctx.Done():
              return
          case msg := <-ch:
              process(msg)
          }
      }
  }(ctx)
  ```
- **Detection:** `rg 'go func' --type go` then audit each for context handling

### GOVULN-027 — Panic in handler reaches the response writer
- **CWE:** CWE-755
- **Severity:** High
- **Detection:** Verify a recovery middleware exists at the top of the chain. For Gin: `r.Use(gin.Recovery())` (or custom). For Fiber: built-in recover available via `gofiber/fiber/v2/middleware/recover`.
- **Fix:** Add the middleware before the route group registration.

### GOVULN-028 — `unsafe.Pointer` arithmetic on untrusted input
- **CWE:** CWE-119
- **Severity:** Critical (if input-driven)
- **Detection:** `rg 'unsafe\.' --type go` — every match must be reviewed manually
- **Notes:** `unsafe` is sometimes legitimate (interop, perf). Findings here require human judgment, not automatic flagging.

### GOVULN-029 — TOCTOU between `os.Stat` and `os.Open`
- **CWE:** CWE-367
- **Severity:** Medium
- **Vulnerable:**
  ```go
  if _, err := os.Stat(path); err == nil {
      f, _ := os.Open(path) // race: file may be replaced with symlink
      ...
  }
  ```
- **Fixed:** `os.OpenFile(path, os.O_RDONLY, 0)` directly and handle the error — no separate stat
- **Detection:** `rg -U 'os\.Stat[\s\S]*?os\.Open' --type go` (requires `-U`/`--multiline`; otherwise the regex fails silently)

### GOVULN-030 — `http.ServeMux` 1.22+ pattern conflict
- **CWE:** CWE-436
- **Severity:** Medium
- **Vulnerable:**
  ```go
  mux := http.NewServeMux()
  mux.HandleFunc("GET /api/", listHandler)
  mux.HandleFunc("/api/", catchHandler) // panics on registration in 1.22+
  ```
- **Fix:** Resolve overlapping registrations; use distinct method-prefixed patterns or merge handlers.
- **Detection:** Run the service with `-test.run=^$` and observe startup; pattern conflicts panic immediately on `Handle/HandleFunc`.

---

## Resource Consumption & DoS

### GOVULN-031 — Missing `ReadHeaderTimeout` (slowloris)
- **CWE:** CWE-770
- **Severity:** High
- **Vulnerable:**
  ```go
  http.ListenAndServe(":80", handler) // uses default Server with no timeouts
  ```
- **Fixed:**
  ```go
  srv := &http.Server{
      Addr:              ":80",
      Handler:           handler,
      ReadHeaderTimeout: 10 * time.Second,
      ReadTimeout:       30 * time.Second,
      WriteTimeout:      30 * time.Second,
      IdleTimeout:       120 * time.Second,
  }
  srv.ListenAndServe()
  ```
- **Detection:** `rg 'http\.(ListenAndServe|Server\{)' -A 5 --type go`

### GOVULN-032 — No body size limit (`http.MaxBytesReader` missing)
- **CWE:** CWE-770
- **Severity:** High
- **Vulnerable:**
  ```go
  body, _ := io.ReadAll(r.Body)
  ```
- **Fixed:**
  ```go
  r.Body = http.MaxBytesReader(w, r.Body, 1<<20) // 1 MiB
  body, err := io.ReadAll(r.Body)
  if err != nil { http.Error(w, "body too large", http.StatusRequestEntityTooLarge); return }
  ```
- **Detection:** `rg 'io\.ReadAll\(.*\.Body\)' --type go` and verify `MaxBytesReader` precedes it

### GOVULN-033 — JSON deep nesting / decoder DoS
- **CWE:** CWE-674
- **Severity:** Medium
- **Vulnerable:** `json.NewDecoder(r.Body).Decode(&v)` with no body size limit
- **Fixed:** combine with `MaxBytesReader` (GOVULN-032) and `dec.DisallowUnknownFields()`
- **Detection:** `rg 'json\.NewDecoder' --type go`

### GOVULN-034 — gzip bomb without size limit
- **CWE:** CWE-409
- **Severity:** High
- **Vulnerable:**
  ```go
  gz, _ := gzip.NewReader(r.Body)
  data, _ := io.ReadAll(gz) // decompresses to 10 GB
  ```
- **Fixed:**
  ```go
  r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
  gz, err := gzip.NewReader(r.Body)
  if err != nil { http.Error(w, "bad gzip", http.StatusBadRequest); return }
  data, err := io.ReadAll(io.LimitReader(gz, 10<<20)) // cap decompressed bytes
  ```
- **Detection:** `rg 'gzip\.NewReader' --type go`

### GOVULN-035 — Unbounded multipart upload
- **CWE:** CWE-770
- **Severity:** High
- **Vulnerable:**
  ```go
  r.ParseMultipartForm(0) // no limit
  ```
- **Fixed:**
  ```go
  r.Body = http.MaxBytesReader(w, r.Body, 32<<20) // 32 MiB total
  if err := r.ParseMultipartForm(8<<20); err != nil { /* 413 */ }
  ```
- **Detection:** `rg 'ParseMultipartForm' --type go`

### GOVULN-036 — File upload: zip slip / path traversal in filename
- **CWE:** CWE-22
- **Severity:** High
- **Vulnerable:**
  ```go
  for _, f := range zipReader.File {
      out, _ := os.Create(filepath.Join("/data", f.Name)) // f.Name may be "../../etc/passwd"
  }
  ```
- **Fixed:**
  ```go
  for _, f := range zipReader.File {
      cleaned := filepath.Clean(filepath.Join("/data", f.Name))
      if !strings.HasPrefix(cleaned, "/data/") { return errors.New("zip slip") }
      out, _ := os.Create(cleaned)
  }
  ```
- **Detection:** `rg 'zip\.(NewReader|Open)' --type go`

---

## Data Handling & Disclosure

### GOVULN-037 — JSON unknown fields silently accepted (mass assignment)
- **CWE:** CWE-915
- **Severity:** Medium
- **Vulnerable:**
  ```go
  var req CreateUserRequest
  json.NewDecoder(r.Body).Decode(&req)
  ```
- **Fixed:**
  ```go
  dec := json.NewDecoder(r.Body)
  dec.DisallowUnknownFields()
  if err := dec.Decode(&req); err != nil { /* 400 */ }
  ```
- **Detection:** `rg 'json\.NewDecoder\([^)]+\)\.Decode' --type go`

### GOVULN-038 — Stack trace returned in error response
- **CWE:** CWE-209
- **Severity:** Medium
- **Vulnerable:**
  ```go
  if err != nil {
      c.JSON(500, gin.H{"error": fmt.Sprintf("%+v", err)})
  }
  ```
- **Fixed:**
  ```go
  if err != nil {
      log.Error("internal error", "err", err, "path", c.Request.URL.Path)
      c.JSON(500, gin.H{"error": "internal error"})
  }
  ```
- **Detection:** `rg 'fmt\.(Errorf|Sprintf)\("%[+]?v"' --type go` near response writers

### GOVULN-039 — Direct ORM model serialization (over-fetching)
- **CWE:** CWE-213
- **Severity:** Medium
- **Vulnerable:**
  ```go
  var u User
  db.First(&u, id)
  c.JSON(200, u) // exposes PasswordHash, internal fields
  ```
- **Fixed:** Define an explicit response DTO and copy only safe fields:
  ```go
  type UserResponse struct { ID string `json:"id"`; Email string `json:"email"` }
  c.JSON(200, UserResponse{ID: u.ID, Email: u.Email})
  ```
- **Detection:** Manual — review `c.JSON` / `json.Marshal` calls for direct model passing

### GOVULN-040 — `text/template` used for HTML rendering
- **CWE:** CWE-79
- **Severity:** High
- **Vulnerable:**
  ```go
  t := template.New("page") // text/template — does NOT escape HTML
  ```
- **Fixed:**
  ```go
  import "html/template"
  t := template.New("page") // html/template — context-aware escaping
  ```
- **Detection:** `rg '"text/template"' --type go` then check the rendering context

### GOVULN-041 — Log injection via newline in user input
- **CWE:** CWE-117
- **Severity:** Medium
- **Vulnerable:**
  ```go
  log.Printf("user login: %s", c.Query("user")) // user="alice\nINFO: admin login"
  ```
- **Fixed:** Use a structured logger (`log/slog`, `zerolog`, `zap`) that escapes field values:
  ```go
  slog.Info("user login", "user", c.Query("user"))
  ```
- **Detection:** `rg 'log\.\w+\([^)]*c\.(Param|Query|PostForm)' --type go`

### GOVULN-042 — `go:embed` embedding sensitive files
- **CWE:** CWE-538
- **Severity:** Critical
- **Vulnerable:**
  ```go
  //go:embed config/*
  var configFS embed.FS  // may include .env, *.pem
  ```
- **Fixed:** narrow the pattern:
  ```go
  //go:embed config/public.json config/templates/*.html
  var configFS embed.FS
  ```
- **Detection:** `rg '//go:embed' --type go` then verify the patterns do not include secrets

# Go — Clean Code Reference

> Language-specific companion for the [clean-code](../SKILL.md) skill. Covers Go idioms, tooling, smells, and refactoring patterns.

## Tools

| Tool | Purpose | Install / Run |
|------|---------|---------------|
| `golangci-lint` | Meta-linter (runs 50+ linters) | `go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest` |
| `staticcheck` | Advanced static analysis | `go install honnef.co/go/tools/cmd/staticcheck@latest` |
| `go vet` | Built-in correctness checks | Included with Go |
| `gofumpt` | Stricter `gofmt` | `go install mvdan.cc/gofumpt@latest` |
| `gocritic` | Opinionated style linter | Included in `golangci-lint` |
| `govulncheck` | Known vulnerability scanner | `go install golang.org/x/vuln/cmd/govulncheck@latest` |

### Quick Audit

```bash
# Full lint sweep
golangci-lint run ./...

# Static analysis
staticcheck ./...

# Built-in vet checks (shadow, printf, structtag, etc.)
go vet ./...

# Find unused code
go install golang.org/x/tools/cmd/deadcode@latest
deadcode ./...

# Check test coverage
go test -coverprofile=cover.out ./...
go tool cover -func=cover.out | tail -1
```

## Go-Specific Smells

### 1. Stuttering Names

Package name is repeated in the exported symbol.

```diff
# Bad — user.UserName stutters
- package user
- type UserService struct{}
- func (s *UserService) GetUserByID(userID string) (*UserRecord, error)

# Good — package provides context
+ package user
+ type Service struct{}
+ func (s *Service) ByID(id string) (*Record, error)
```

**Detect:** `rg 'type [A-Z]\w+' --type go -o | while read -r line; do pkg=$(dirname "$line" | xargs basename); type=$(echo "$line" | grep -oP 'type \K\w+'); echo "$pkg → $type"; done | grep -i -E '(\w+).*\1'`

### 2. Empty Interface Abuse

Using `interface{}` / `any` when a concrete type or constrained generic exists.

```diff
# Bad — loses type safety
- func Process(data any) any {

# Good — typed
+ func Process(data Request) Response {

# Good — constrained generic
+ func Process[T Processable](data T) Result[T] {
```

**Detect:** `rg 'interface\{\}|func.*\bany\b' --type go`

### 3. init() Abuse

Hidden side effects that run at import time — hard to test, hard to reason about.

```diff
# Bad — global state set at import
- var db *sql.DB
- func init() {
-     var err error
-     db, err = sql.Open("postgres", os.Getenv("DB_URL"))
-     if err != nil { log.Fatal(err) }
- }

# Good — explicit initialization
+ func NewDB(dsn string) (*sql.DB, error) {
+     return sql.Open("postgres", dsn)
+ }
```

**Detect:** `rg 'func init\(\)' --type go`

### 4. Naked Returns

Named return values with bare `return` — obscures what's being returned.

```diff
# Bad — what does this return?
- func parse(input string) (result int, err error) {
-     // ... 40 lines ...
-     return
- }

# Good — explicit
+ func parse(input string) (int, error) {
+     // ... 40 lines ...
+     return result, nil
+ }
```

**Detect:** `rg -U 'func \w+\([^)]*\)\s*\([^)]*\)\s*\{[\s\S]*?\breturn\s*\n' --type go --multiline`

### 5. Error String Formatting

Error strings should not be capitalized or end with punctuation (they compose with `fmt.Errorf`).

```diff
# Bad — capitalized, punctuation
- return fmt.Errorf("Failed to connect to database.")

# Good — lowercase, no punctuation
+ return fmt.Errorf("connecting to database: %w", err)
```

**Detect:** `rg 'fmt\.Errorf\("[A-Z]' --type go` and `rg 'errors\.New\("[A-Z]' --type go`

### 6. Package-Level Mutable Globals

Shared mutable state makes testing and concurrency unsafe.

```diff
# Bad — mutable global
- var config = loadConfig()
- var logger = log.New(os.Stdout, "", log.LstdFlags)

# Good — dependency injection
+ type Server struct {
+     config Config
+     logger *slog.Logger
+ }
```

**Detect:** `rg '^var \w+ =' --type go | grep -v '_test.go' | grep -v 'const\|sync\.Once\|Mutex'`

### 7. Oversized Interfaces

Interfaces with too many methods — violates Interface Segregation Principle.

```diff
# Bad — consumers forced to implement 10 methods
- type Repository interface {
-     Create(ctx context.Context, u User) error
-     Update(ctx context.Context, u User) error
-     Delete(ctx context.Context, id string) error
-     FindByID(ctx context.Context, id string) (*User, error)
-     FindByEmail(ctx context.Context, email string) (*User, error)
-     List(ctx context.Context, filter Filter) ([]User, error)
-     Count(ctx context.Context) (int, error)
-     // ... more
- }

# Good — small, focused interfaces
+ type UserReader interface {
+     FindByID(ctx context.Context, id string) (*User, error)
+     FindByEmail(ctx context.Context, email string) (*User, error)
+ }
+ type UserWriter interface {
+     Create(ctx context.Context, u User) error
+     Update(ctx context.Context, u User) error
+ }
```

**Detect:** `rg -U 'type \w+ interface \{' --type go -A 20 | awk '/interface \{/{name=$2; count=0} /^\s+\w+\(/{count++} /\}/{if(count>5) print name": "count" methods"}'`

## Go Refactoring Patterns

### Table-Driven Tests

Eliminates duplicated test logic.

```diff
# Before: duplicated test functions
- func TestAdd_positives(t *testing.T) {
-     if Add(1, 2) != 3 { t.Error("expected 3") }
- }
- func TestAdd_negatives(t *testing.T) {
-     if Add(-1, -2) != -3 { t.Error("expected -3") }
- }
- func TestAdd_zero(t *testing.T) {
-     if Add(0, 0) != 0 { t.Error("expected 0") }
- }

# After: table-driven
+ func TestAdd(t *testing.T) {
+     tests := []struct {
+         name string
+         a, b int
+         want int
+     }{
+         {"positives", 1, 2, 3},
+         {"negatives", -1, -2, -3},
+         {"zero", 0, 0, 0},
+     }
+     for _, tt := range tests {
+         t.Run(tt.name, func(t *testing.T) {
+             if got := Add(tt.a, tt.b); got != tt.want {
+                 t.Errorf("Add(%d, %d) = %d, want %d", tt.a, tt.b, got, tt.want)
+             }
+         })
+     }
+ }
```

### Functional Options

Replaces long constructor parameter lists.

```diff
# Before: constructor with 6 parameters
- func NewServer(addr string, port int, timeout time.Duration,
-     maxConns int, logger *slog.Logger, tls *tls.Config) *Server {

# After: functional options
+ type Option func(*Server)
+
+ func WithTimeout(d time.Duration) Option {
+     return func(s *Server) { s.timeout = d }
+ }
+ func WithMaxConns(n int) Option {
+     return func(s *Server) { s.maxConns = n }
+ }
+ func WithLogger(l *slog.Logger) Option {
+     return func(s *Server) { s.logger = l }
+ }
+
+ func NewServer(addr string, opts ...Option) *Server {
+     s := &Server{addr: addr, timeout: 30 * time.Second, maxConns: 100}
+     for _, opt := range opts {
+         opt(s)
+     }
+     return s
+ }
+
+ // Usage
+ srv := NewServer(":8080", WithTimeout(5*time.Second), WithLogger(logger))
```

### Accept Interfaces, Return Structs

Decouples callers from concrete implementations.

```diff
# Bad — accepts concrete type
- func SaveReport(db *sql.DB, r Report) error {

# Good — accepts interface defined by consumer
+ type ReportWriter interface {
+     ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error)
+ }
+ func SaveReport(w ReportWriter, r Report) error {
```

## Go Verification Commands

```bash
# Run tests
go test ./...

# Run tests with race detector
go test -race ./...

# Check exported API hasn't changed
go doc ./pkg/...

# Vet for correctness
go vet ./...

# Full lint
golangci-lint run ./...
```

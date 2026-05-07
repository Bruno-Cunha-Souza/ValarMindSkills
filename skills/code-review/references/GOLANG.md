# Code Review — Go Reference

> Reference companion for the [code-review](../SKILL.md) skill. Go-specific patterns, sweeps, and example findings. Pairs with [clean-code/references/GOLANG.md](../../clean-code/references/GOLANG.md) for refactor patterns and with [@code-security-review (Go branch)](../../code-security-review/references/golang/API.md) for deeper security audit.

## Tools

| Tool | Purpose | Install / Run |
| --- | --- | --- |
| `golangci-lint` | Meta-linter (50+ linters: govet, staticcheck, gosec, errcheck, ...) | `go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest` |
| `staticcheck` | Advanced static analysis | `go install honnef.co/go/tools/cmd/staticcheck@latest` |
| `go vet` | Built-in correctness checks | bundled |
| `gosec` | Security-focused static analyzer | `go install github.com/securego/gosec/v2/cmd/gosec@latest` |
| `govulncheck` | CVE scan against Go vulnerability DB | `go install golang.org/x/vuln/cmd/govulncheck@latest` |
| `gocyclo` | Cyclomatic complexity | `go install github.com/fzipp/gocyclo/cmd/gocyclo@latest` |
| `deadcode` | Unreachable code detection | `go install golang.org/x/tools/cmd/deadcode@latest` |
| `errcheck` | Unchecked errors | bundled in `golangci-lint` |
| `ineffassign` | Ineffectual assignments | bundled in `golangci-lint` |
| `goleak` | Goroutine leak detection in tests | `go get go.uber.org/goleak` |

## Quick sweep

```bash
# Static toolchain sweep from the touched Go module root
golangci-lint run --new-from-rev="$BASE_SHA" ./...
staticcheck ./...
go vet -all ./...
gosec -severity medium ./...
govulncheck ./...
gocyclo -over 15 .
deadcode ./...

# Optional verification only
go test -count=1 ./...
go test -race -count=1 ./...    # concurrency findings or explicit request
```

## Findings catalog — 25 patterns to scan

Each row: detection (`rg`), severity floor, why it matters, suggested fix. Run patterns against changed Go files through the [Diff Scope Contract](../SKILL.md#01-diff-scope-contract), then open matching files before filing a finding.

### 1. Unchecked error from a non-trivial call

```bash
rg -n '\b(\w+,\s*err\s*:?=.+)\n\s*[^i]' --type go    # err declared but no `if err != nil`
```

Severity floor: **Medium**. `err` is silently dropped. `errcheck` and `gosec G104` flag this — calibrate as in [SEVERITY_RUBRIC](SEVERITY_RUBRIC.md).

```diff
- json.Unmarshal(body, &v)
+ if err := json.Unmarshal(body, &v); err != nil {
+     return fmt.Errorf("decode body: %w", err)
+ }
```

### 2. `panic` in a request handler

```bash
rg -n '\bpanic\(' --type go
```

Severity floor: **High**. A panic in a handler crashes the goroutine; without `recover` middleware it can bring down the request. Replace with an error return or, when a true invariant break, leave a comment justifying it.

### 3. Goroutine without `context.Context`

```bash
rg -n 'go\s+func\b' --type go
```

Severity floor: **Medium**. New goroutines should accept and respect a context, otherwise they leak on cancellation. Use `goleak.VerifyTestMain` to assert in tests.

### 4. SQL string concatenation

```bash
rg -n '(db|tx)\.(Query|QueryContext|Exec|ExecContext)\(.*\+' --type go
rg -n 'fmt\.Sprintf\([^)]*(SELECT|INSERT|UPDATE|DELETE)' --type go
```

Severity floor: **Critical**. CWE-89. Always use placeholder binding (`$1`, `?`).

### 5. `interface{}` / `any` in a public signature

```bash
rg -n '\bfunc\s+\w+\s*\([^)]*\b(interface\{\}|any)\b' --type go
rg -n '^func [A-Z]\w*.*\b(interface\{\}|any)\b' --type go
```

Severity floor: **Low** by default. Promote to **Medium** if the function is exported and the type can be expressed as a generic constraint or a concrete interface.

### 6. `init()` with side effects

```bash
rg -n '^func init\(\)' --type go -A 20
```

Severity floor: **Medium**. `init()` is run on package import — opening files, reading env, dialing services there make the package non-testable.

### 7. Stuttering exported names

```bash
rg -n '^(type|func) ([A-Z]\w+)' --type go    # then compare to `package <pkg>`
```

Severity floor: **Low**. `user.UserService` reads as `userUserService`.

### 8. Naked returns in functions > 10 lines

```bash
rg -n -B 12 '^\s*return$' --type go
```

Severity floor: **Low**. `return` without explicit values is fine in tiny helpers; in long functions it hides which named return is being yielded.

### 9. Shadowed variables

```bash
go vet -vettool=$(which shadow) ./...    # requires shadow tool
```

Severity floor: **Medium** when the shadow is `err`. CVE-grade in security-sensitive paths.

### 10. `time.Sleep` in a hot path

```bash
rg -n 'time\.Sleep\(' --type go
```

Severity floor: **Medium** in handlers and goroutines that serve requests. **Low** in tests and CLI tools.

### 11. `math/rand` for security tokens

```bash
rg -n '"math/rand"' --type go
```

Severity floor: **Critical** if used to generate tokens, IDs, or session material. Use `crypto/rand`. CWE-338.

### 12. `InsecureSkipVerify: true`

```bash
rg -n 'InsecureSkipVerify\s*:\s*true' --type go
```

Severity floor: **High**. CWE-295. Allowed only in localhost test fixtures with a comment.

### 13. `os.Open` / `filepath.Join` with user-controlled path

```bash
rg -n '(os\.(Open\|Create\|ReadFile)|filepath\.Join)\([^)]*(c\.Param\|c\.Query\|r\.URL\.Query)' --type go
```

Severity floor: **High**. CWE-22 (path traversal). Validate against an allow-list and use `filepath.Clean` + `filepath.IsLocal` (Go 1.20+).

### 14. `exec.Command` with user input

```bash
rg -n 'exec\.(Command|CommandContext)\([^)]*(c\.Param|c\.Query|r\.URL)' --type go
```

Severity floor: **Critical**. CWE-78. Command injection. Use a fixed binary + an arg list; never `sh -c`.

### 15. `fmt.Sprintf` for HTML / SQL output

```bash
rg -n 'fmt\.Sprintf\(.*<[a-z]+' --type go
rg -n 'fmt\.Sprintf\(.*"(SELECT\|INSERT\|UPDATE\|DELETE)' --type go
```

Severity floor: **Critical** (XSS or SQLi). Use `html/template` or parameterised SQL.

### 16. Logger format leaks PII / secret

```bash
rg -n 'log\.[A-Z]\w*\(.*\b(password|token|secret|cookie|authorization|email)\b' --type go
```

Severity floor: **High**. CWE-532.

### 17. Mutex copied (struct passed by value)

```bash
go vet ./...    # `copylocks` rule fires
```

Severity floor: **Medium**. Each copy has its own zero-state mutex; locking does nothing.

### 18. `sync.WaitGroup.Add` inside the goroutine

```bash
rg -n -C 4 'go\s+func|wg\.Add' --type go
```

Severity floor: **Medium**. Race between `Add` and `Wait`. `Add` must happen before the `go`.

### 19. Channel close on receive side

Severity floor: **High**. Sender owns the close. Closing on the receiver side risks "send on closed channel" panics.

### 20. `defer` inside a loop

```bash
rg -n -C 3 '^\s*defer\b|for ' --type go
```

Severity floor: **Medium**. Defers stack up until function exit, holding resources (file handles, locks).

### 21. Return of a pointer to a local

This is fine in Go (escape analysis), but be wary of returning a pointer to a slice element: the slice may grow and reallocate, leaving the pointer stale.

### 22. `time.Now()` in tests

Severity floor: **Low**. Inject a clock (`func() time.Time`) so tests are deterministic.

### 23. Map iteration order assumed

Severity floor: **Medium**. Go map iteration is randomized. If order matters, sort keys explicitly.

### 24. `http.Server` without timeouts

```bash
rg -n -A 12 'http\.Server\{' --type go    # manually verify Read/Write/Idle timeouts
```

Severity floor: **High**. Slowloris exposure (CWE-400).

### 25. `gin.Default()` in production

```bash
rg -n 'gin\.Default\(\)' --type go
```

Severity floor: **Medium**. `Default()` enables verbose logger and recovery that prints stack traces — leaks info in error responses. Use `gin.New()` and add the middleware you actually want.

## Test smell sweep

```bash
# Tests with no assertions
rg -L 't\.(Error|Fatal|Run|Helper|Cleanup)' --glob '**/*_test.go'

# Tests that print instead of assert
rg -n 'fmt\.Println\(' --glob '**/*_test.go'

# Skipped tests with no reason
rg -n 't\.Skip\(\)' --glob '**/*_test.go'

# Tests that share state via package vars
rg -n '^var ' --glob '**/*_test.go'
```

## Performance sweep

```bash
# Allocations in hot loops (manual read after this list)
rg -n -A 30 'for .*\{' --type go
rg -n '(make\(|append\(|\+=|fmt\.Sprintf)' --type go

# Unbounded reads
rg -n 'io\.ReadAll\(' --type go    # check that input is bounded

# `bufio.Scanner` without `Buffer()` for large lines
rg -n 'bufio\.NewScanner\(' --type go
```

## Hand-off triggers

- Any **API1–API10** finding from Phase 3 → recommend `@code-security-review` (Go branch — `references/golang/`).
- A **Gin/Fiber middleware** misuse → `@code-security-review` (`references/golang/MIDDLEWARE.md`).
- Refactor opportunity (function size, duplication) → `@clean-code` with [GOLANG reference](../../clean-code/references/GOLANG.md).
- Runtime crash, panic, race observed in tests → `@code-debugger`.

> Reference companion for the [code-optimization](../SKILL.md) skill.

# Go Performance Reference

Targets: Go 1.23+ (default), Go 1.25+ (`encoding/json/v2`, GOMEMLIMIT default behavior). Frameworks: Gin, Fiber v2/v3, fx (DI).

## 1. Tooling matrix

| Concern | Tool | Invocation |
| --- | --- | --- |
| CPU profile | `runtime/pprof` + `go tool pprof` | `go test -cpuprofile=cpu.pprof -bench=.` then `go tool pprof -top -cum cpu.pprof` |
| Alloc profile | `runtime/pprof` | `go test -memprofile=mem.pprof -bench=.` then `go tool pprof -alloc_objects mem.pprof` |
| Goroutine leak | `pprof goroutine` + `goleak` | `curl :6060/debug/pprof/goroutine` + `goleak.VerifyNone(t)` in tests |
| Mutex contention | `pprof mutex` | `go test -mutexprofile=mu.pprof` or `runtime.SetMutexProfileFraction(1)` |
| Block profile | `pprof block` | `runtime.SetBlockProfileRate(1)` |
| Trace | `runtime/trace` | `go test -trace=trace.out` then `go tool trace trace.out` |
| Escape analysis | `gcflags='-m'` | `go build -gcflags='-m=2' ./... 2>&1 \| rg 'escapes to heap'` |
| Benchmarks | `testing.B` + `benchstat` | `go test -bench=. -count=10 -benchmem \| tee old.txt`; compare runs with `benchstat old.txt new.txt` |
| Duplication | `dupl` | `dupl -t 50 ./...` |
| Linter (perf-aware) | `golangci-lint` + `staticcheck` | enable `prealloc`, `ineffassign`, `unconvert`, `gocritic` (with perf checks), `perfsprint` |

## 2. Hot-path antipatterns

### 2.1 Allocation in hot loops

| Anti-pattern | Fix |
| --- | --- |
| `s := ""` + `s += ...` in a loop | `strings.Builder` with `Grow(estimated)` |
| `append(s, ...)` without `make([]T, 0, n)` pre-size | `s := make([]T, 0, n)` + `append` |
| Allocating maps inside loops | hoist outside; consider `sync.Pool` for reusable maps |
| Returning `[]byte` from a per-request encoder | `sync.Pool` of `*bytes.Buffer` + `WriteTo(w)` |
| `fmt.Sprintf` for hot-path concatenation | `strconv.Itoa` / `strings.Builder` |

### 2.2 GC pressure

`GODEBUG=gctrace=1` to count GC cycles per benchmark run. If GC is dominating, weigh:

- **`sync.Pool`** for short-lived large objects (`*bytes.Buffer`, `*json.Encoder`, request-scoped slices). Beware: `Pool` cleared on every GC; pool only what is allocated per-request, not request-scoped state.
- **`GOGC` tuning** — default `100` (1× heap per cycle). Lower for latency, higher for throughput. Test with `GOGC=200`.
- **`GOMEMLIMIT`** — soft heap ceiling (Go 1.19+). Pairs with cgroup memory limit; prevents OOM-kill at the cost of more GC.
- **Inlineable functions** — `//go:inline` hint (Go 1.21+) and avoiding methods on non-pointer receivers in tight loops.

### 2.3 Goroutine pool / fanout

| Anti-pattern | Fix |
| --- | --- |
| `go fetch(ctx, x)` in a loop without bound | `errgroup` + semaphore channel of size N |
| Spawning goroutines without `context.Context` propagation | always pass `ctx`; respect `ctx.Done()` |
| Returning channels from request handlers | scope channels to the request; close on the producer side |
| Blocking on unbuffered channel inside lock | swap to `sync.RWMutex` or `sync.Map`; never block under lock |

### 2.4 Locking

- Hot map under `sync.Mutex` → swap to `sync.Map` (read-heavy) or `sync.RWMutex` (mixed).
- `Arc<Mutex>`-equivalent overuse (Go: `sync.Mutex` everywhere) → consider sharded map (`hashicorp/go-immutable-radix`, `puzpuzpuz/xsync`).
- Lock held across I/O (`db.Query` inside `mu.Lock()`) → restructure to release before I/O.

### 2.5 String / byte handling

| Anti-pattern | Fix |
| --- | --- |
| `[]byte(s)` + `string(b)` round-trips in hot path | `unsafe.String` / `unsafe.Slice` (Go 1.20+, careful — only when safety can be proven) |
| `json.Marshal` per request without reuse | `bytes.Buffer` pool + `json.NewEncoder(buf)` |
| Manual TLV parsing | use `encoding/binary` + pre-sized slices, not `append` |

## 3. Framework-specific notes

### 3.1 Gin

- `c.JSON(...)` uses `encoding/json` by default. Swap with `jsoniter` (`gin.SetMode(gin.ReleaseMode)` + register) or `bytedance/sonic` for 2–3× CPU win on response-heavy APIs.
- `c.Bind*` allocates per call; prefer `c.ShouldBindBodyWith` only when you need to re-read.
- Middleware order matters: rate-limit before parsing; auth before expensive lookups.
- Avoid `c.Copy()` followed by goroutine writes — context Copy is for read-only follow-up.

### 3.2 Fiber

- Built on `fasthttp` — never use `net/http`-style middleware (`fasthttp.RequestCtx` is reused). Allocating a struct from `ctx` and returning it from a goroutine **leaks** because the underlying memory is recycled.
- `Prefork` mode (Fiber v2) sharded the listener; v3 deprecated in favor of `SO_REUSEPORT` — verify the version.
- JSON marshaler is `goccy/go-json` by default in v3; benchmark before swapping.

### 3.3 fx (DI)

- Resolution graph at startup is amortized; perf cost in steady state is near zero.
- Anti-pattern: building per-request dependencies in fx — fx is for app-scoped wiring, not per-request.
- Cyclic graphs cause graph rebuild cost — keep providers acyclic.

## 4. Connection pools

- `database/sql.DB` is a pool itself; **never** wrap it in another pool.
- Tuning:
  - `SetMaxOpenConns` — start at `2 * GOMAXPROCS`; tune with metrics.
  - `SetMaxIdleConns` — match `MaxOpenConns` to avoid churn.
  - `SetConnMaxLifetime` — to handle DB-side connection rotation (e.g., RDS Proxy).
- `pgx` (instead of `database/sql` + `lib/pq`) for high-throughput Postgres — uses binary protocol, no `database/sql` indirection.
- HTTP: single package-level `*http.Client`, configure `Transport.MaxConnsPerHost`, `IdleConnTimeout`.

## 5. Profiling recipes

```bash
# Quick CPU profile under load
go test -run='^$' -bench='BenchmarkHandler' -benchtime=10s -cpuprofile=/tmp/cpu.pprof ./api/
go tool pprof -http=:8080 /tmp/cpu.pprof

# Allocation top
go test -run='^$' -bench='BenchmarkHandler' -memprofile=/tmp/mem.pprof ./api/
go tool pprof -alloc_objects -top /tmp/mem.pprof | head -20

# Goroutine leak hunt
go test -count=1 ./... -gcflags='all=-N -l' -run TestX
# Add `defer goleak.VerifyNone(t)` to test entrypoints

# Escape analysis pinpoint
go build -gcflags='-m=2' ./pkg/handler 2>&1 | rg 'escapes to heap'

# Trace under benchmark
go test -bench='BenchmarkHandler' -trace=/tmp/trace.out ./api/
go tool trace /tmp/trace.out
```

## 6. Verification

- **Benchmark deltas via `benchstat`** with `-count=10` minimum to filter noise. Report `delta >= 5%` as a Quick Win.
- **`go test -race`** is correctness, not perf — keep findings separate; race-related slowness is a `@code-debugger` concern.
- **Production canary** with `pprof` HTTP endpoint exposed on `:6060` (firewall-protected) is the only way to validate live findings.

## 7. Anti-patterns specific to Go perf findings

- "Replace map with sync.Map" without read-vs-write profile — Map is faster only when read-heavy + disjoint key sets.
- "Add sync.Pool" without measuring GC — Pool overhead can exceed savings on short-lived objects.
- "Use channels for everything" — channels are slower than mutex for shared state; use them for coordination, not state.
- "Inline by hand" — compiler inlines small functions; manual inlining hurts maintainability without measurable gain. Use `gcflags='-m'` to check.

## 8. References (external)

- Go memory model: https://go.dev/ref/mem
- `runtime/pprof` package docs (cite via context7 `mcp__context7__resolve-library-id` for "Go pprof" then `query-docs`).
- `dgryski/go-perfbook` for community recipes.

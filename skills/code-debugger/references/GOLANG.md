# Code Debugger — Go Reference

> Reference companion for the [code-debugger](../SKILL.md) skill. Go-specific debugging techniques, command snippets, and bug-class playbooks. Pairs with [code-review/references/GOLANG.md](../../code-review/references/GOLANG.md) (static smell catalogue) and [@code-security-review](../../code-security-review/references/golang/API.md) (security-driven runtime issues — Go branch).

## Tools

| Tool | Purpose | Install / Use |
| --- | --- | --- |
| `dlv` (Delve) | Step-debugger | `go install github.com/go-delve/delve/cmd/dlv@latest` |
| `pprof` | CPU / heap / goroutine / mutex / block profile | bundled (`go tool pprof`) |
| `go test -race` | Race detector | bundled |
| `go test -count=N` | Run a test N times (flake hunting) | bundled |
| `go test -trace=trace.out` | Execution trace | bundled |
| `go test -cpu=1,2,4,8` | Vary GOMAXPROCS | bundled |
| `goleak` | Goroutine leak detection | `go get go.uber.org/goleak` |
| `expvar` / `runtime/debug` | Runtime introspection | bundled |
| `gops` | List Go processes / state | `go install github.com/google/gops@latest` |
| `staticcheck` / `go vet` | Find suspicious patterns post-mortem | bundled / per-tool |

## Quick reproducer commands

```bash
# Run a single test with verbose output
go test -run '^Test_<name>$' -v ./<pkg>

# Run many times to catch flakiness
go test -run '^Test_<name>$' -count=100 -v ./<pkg>

# Race detector
go test -race -count=1 ./<pkg>

# Vary GOMAXPROCS (concurrency surface)
go test -cpu=1,2,4,8 -race ./<pkg>

# Disable test cache
go clean -testcache && go test ./<pkg>

# Run with a timeout to see hangs as failures
go test -timeout=30s ./<pkg>

# Capture profiles during a test
go test -cpuprofile=cpu.prof -memprofile=mem.prof -bench=. ./<pkg>

# Goroutine dump (live process)
SIGQUIT triggers it: kill -3 <pid>
# Or programmatic:
import _ "net/http/pprof"
go func() { http.ListenAndServe(":6060", nil) }()
# then: curl http://localhost:6060/debug/pprof/goroutine?debug=2
```

## Bug-class playbooks

### Panic — nil pointer dereference

Stack trace pattern:

```text
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x18 pc=...]
goroutine N [running]:
example.com/<pkg>.(*<Type>).<Method>(...)
    <file>:<line>
```

Procedure:

1. Open `<file>` at `<line>`. Identify which receiver / pointer is dereferenced.
2. Walk back the call chain to find where that pointer was set.
3. If a constructor was supposed to populate it: was the constructor called?
4. If a context value: was the middleware that sets it actually wired?
5. Common roots: missing middleware, missing dependency injection, missing initialisation in test setup, returned `nil, nil` from a "find" function (use `nil, ErrNotFound` instead).

### Panic — index out of range / slice bounds

Pattern: `panic: runtime error: index out of range [N] with length M`.

Procedure:

1. Find the indexed access at the cited line.
2. Check the loop bound and the slice length at the same scope.
3. Common roots: off-by-one (`<=` vs `<`), assumption that input has ≥ N elements, slice mutated mid-iteration.

### Race detected

Pattern (truncated):

```text
WARNING: DATA RACE
Read at 0x... by goroutine X:
    <file>:<line>
Previous write at 0x... by goroutine Y:
    <file>:<line>
```

Procedure:

1. Both lines point to a shared variable. Identify it.
2. Check whether access is guarded (mutex, channel, atomic).
3. Common roots: closure over loop variable; shared map without `sync.RWMutex`; `WaitGroup.Add` inside the goroutine; `defer wg.Done` missing.

Falsifying tests:

```bash
go test -race -count=100 ./<pkg>     # confirm with N runs after fix
```

### Deadlock

Pattern: `fatal error: all goroutines are asleep - deadlock!` or hang with no output.

Procedure:

1. Send `SIGQUIT` (`kill -3 <pid>`) or use `dlv attach` to dump goroutines.
2. Look for two goroutines, each waiting on what the other holds (mutex / channel).
3. Look for unbuffered channel send/receive without a peer.
4. Common roots: `sync.Mutex` lock-order inversion; sending on a channel nobody reads; `sync.WaitGroup.Wait` after the producer finished but consumers are stuck.

### Goroutine leak

Procedure:

1. In the test: `goleak.VerifyTestMain(m)` flags a leak.
2. In production: `curl /debug/pprof/goroutine?debug=2` after the workload settles.
3. Look for goroutines stuck on `<-chan` reads or `select` without `default`.
4. Common roots: goroutine that never returns because its only exit condition is a channel that never closes; missing `ctx.Done()` branch; goroutine spawned in a loop without bounded lifetime.

```go
// goleak in TestMain
func TestMain(m *testing.M) {
    goleak.VerifyTestMain(m)
}
```

### Memory growth / leak

Procedure:

1. Run with `-memprofile=mem.prof` over a representative load.
2. `go tool pprof -alloc_space mem.prof` and `top10`.
3. Compare to `-inuse_space mem.prof` for live objects.
4. `runtime.GC(); runtime.ReadMemStats(&ms)` before and after a workload.
5. Common roots: unbounded cache; closure capturing a request-scoped value held by a long-lived goroutine; `context.WithValue` storing a heavy object; `time.AfterFunc` not stopped.

### Slow test / slow handler

Procedure:

1. `go test -cpuprofile=cpu.prof` then `go tool pprof -http=:8080 cpu.prof`.
2. Look at the flame graph. The widest leaves are the hot spots.
3. Common roots: N+1 queries; allocation in a hot loop; reflection-heavy serialisation; `regexp` compiled per call; sync.Mutex contention (use `-mutexprofile`).

### Flaky test

Procedure:

1. `go test -run '^Test_<name>$' -count=200 -v ./<pkg>` — measure flake rate.
2. `go test -race -count=200 ./<pkg>` — many flakes are races.
3. `go test -cpu=1,2,4,8 ./<pkg>` — surface order-dependence.
4. Look for: order-dependent tests, `t.Parallel()` mixed with shared state, time-dependent assertions (`time.Now()`, `time.Sleep`), tests that rely on file order (`map` iteration, `os.ReadDir` order before sort).

### Wrong build / wrong binary

Procedure:

1. `go version -m <binary>` — confirms the binary's main module and dependencies.
2. `git rev-parse HEAD` against the build's embedded version (if any).
3. `go clean -testcache` if a test "passes" but you suspect cached results.
4. Confirm `GOFLAGS`, `CGO_ENABLED`, `GOOS`, `GOARCH` match expectations.

## Delve quick recipe

```bash
# Debug a test
dlv test ./<pkg> -- -test.run '^Test_<name>$'

# Inside dlv:
(dlv) break <file>:<line>
(dlv) continue
(dlv) print <var>
(dlv) goroutines        # list all goroutines
(dlv) goroutine <N>     # switch to one
(dlv) bt                # backtrace
(dlv) locals
```

For a hung process:

```bash
dlv attach <pid>
(dlv) goroutines -t -s start    # group by start frame
(dlv) goroutine <stuck-id> bt
```

## pprof quick recipe

```bash
# CPU
go test -cpuprofile=cpu.prof -bench=. ./<pkg>
go tool pprof -http=:8080 cpu.prof

# Heap
go test -memprofile=mem.prof -bench=. ./<pkg>
go tool pprof -http=:8081 -alloc_space mem.prof
go tool pprof -http=:8082 -inuse_space mem.prof

# Goroutine (live)
curl -o goroutine.prof http://localhost:6060/debug/pprof/goroutine
go tool pprof -http=:8083 goroutine.prof

# Block / mutex (must enable explicitly)
runtime.SetBlockProfileRate(1)
runtime.SetMutexProfileFraction(1)
```

## Common false leads

- **`gofmt` differences** appear in the diff but never cause runtime bugs. Filter them out before reading.
- **Linter warnings** are leads, not causes. They suggest code that **could** be wrong; they do not prove the bug.
- **A scary error in unrelated middleware** can cascade into a generic 500. Read top-down; the first user frame in the stack is rarely the root cause but it's the closest to it.
- **Test-only failures** are sometimes test bugs (shared state, leaked goroutine from a prior test). Run the test in isolation before blaming production code.

## Hand-off triggers

- Security-class root cause (BOLA, SSRF, injection) → after fix, run `@code-security-review` (Go branch — `references/golang/`) to sweep for siblings.
- Refactor-class root cause (god function, hidden coupling) → recommend `@clean-code` for the follow-up PR.
- The fix is non-trivial and the diff is large → recommend `@code-review` before merge.

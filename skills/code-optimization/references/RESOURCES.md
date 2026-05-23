> Reference companion for the [code-optimization](../SKILL.md) skill.

# Resource Management

Resources here = anything the OS or runtime hands out under a quota: heap memory, CPU time, file descriptors, sockets, OS threads, goroutines / tasks, DB connections, cache slots. Leaks of any of these eventually fail the system — but the failure mode varies (OOM kill, EMFILE, pool starvation, scheduler thrashing), and so does the detection technique.

For language-specific tool invocations, see the per-language references. This file groups the **cross-language vocabulary and patterns**.

## 1. Categories

| Category | Symptom | Detection (cross-language) | Typical fix |
| --- | --- | --- | --- |
| **Memory leak** | RSS climbs monotonically; OOM-kill in steady state | `pprof -alloc_objects` (Go), `cargo flamegraph --alloc` / `heaptrack` (Rust), `clinic heapprofile` (Node), `tracemalloc` / `pytest-memray` / `py-spy --gil` (Python) | Close handles, break reference cycles, bound caches, drop request-scoped state |
| **CPU-bound hot spot** | 100% CPU; latency rises with load; no I/O wait | `go tool pprof -top` / `cargo flamegraph` / `clinic flame` / `py-spy record` | Algorithmic change, vectorization, batch processing, offload to worker |
| **File descriptor / socket leak** | `EMFILE`, `too many open files`; FD count grows | `lsof -p PID` count, `/proc/PID/fd/` count | RAII / `defer Close()` / `using` / `with` / context-manager; bound pool size |
| **Goroutine / task / thread leak** | Heap grows; thread count grows; pprof goroutine count > expected | `pprof -goroutine` (Go), `asyncio.all_tasks()` (Python), `tokio-console` (Rust), `clinic bubbleprof` (Node) | Add context / `AbortSignal` / `CancellationToken`; structured concurrency (`errgroup`, `TaskGroup`, `tokio::spawn_blocking` with timeout) |
| **DB connection pool exhaustion** | `pool exhausted`, `connection timeout` logs | Pool metrics; explicit `--pool-limit` in driver | Reduce hold time (close txn fast), increase pool ceiling **only** after profiling, add timeout per acquire, fix leak that holds connections |
| **Cache exhaustion** | OOM driven by cache; stampede on cache miss | Cache size logs; `pprof -inuse_space` highlights the cache map | TTL + size cap; LRU/LFU; single-flight ("singleflight" Go, `lru-cache` TS, `cachetools` Python); jittered TTL to avoid synchronized expiry |
| **GC pressure** | High CPU% in GC; latency hiccups | `GODEBUG=gctrace=1` (Go), `cargo flamegraph` showing alloc, `--trace-gc` Node, `gc.set_debug(gc.DEBUG_STATS)` (Python) | `sync.Pool` / `bytes.Buffer` reuse (Go); avoid `clone()` in hot loop (Rust); object pools / `__slots__` (Python); avoid intermediate arrays (TS) |
| **Synchronization overhead** | Lock contention; mutex profile heavy | `pprof -mutex`, `pprof -block`, `loom` (Rust), `clinic bubbleprof`, `py-spy --idle` | Reduce critical section, switch to `DashMap` / `RwLock` / `ShardedMap`; lock-free where applicable |

## 2. Heuristics by symptom

Use the following decision tree when triaging a perf finding tied to resources.

### 2.1 "Memory grows under load"

1. Is RSS growth bounded by a known cache? → look at the cache config (TTL + size cap). No → leak suspect.
2. Run alloc profiler (`pprof -alloc_objects`, `tracemalloc`, `heaptrack`). Top function is the suspect.
3. Inspect reference graph: does a request-scoped value escape into a long-lived structure (handler closure capturing `request`, global cache holding the response body)?
4. If GC language: check `runtime.GC()` / explicit `gc.collect()` does NOT reduce RSS — confirms a real leak, not stale GC heuristics.

### 2.2 "Latency spikes intermittently"

1. Run CPU profile during the spike. Look for GC (Go `runtime.gcBgMarkWorker`, Java `G1`, Python tracemalloc) → GC-tuning territory.
2. Look for lock contention in `mutex`/`block` profile → switch to lock-free / sharded.
3. Look for I/O on hot path (`syscall.Read`, `pq.Conn.Read`) → batch / cache / async.
4. Look for cold paths (cache miss, JIT warmup) → warm cache / preload.

### 2.3 "Throughput plateaus despite CPU headroom"

1. Pool exhaustion suspected — check DB connection metrics, HTTP client pool, worker pool.
2. Coroutine / task starvation — too many blocking tasks holding the runtime (e.g., sync `requests` inside FastAPI handler).
3. Lock contention — same as 2.2.3.
4. External rate limit — upstream API throttling.

## 3. Per-language quick reference

Full details in the per-language ref files; here is the at-a-glance table.

| Language | Memory profile | Goroutine/task leak | Pool exhaustion fix |
| --- | --- | --- | --- |
| **Go** | `go test -memprofile`, `pprof -alloc_objects` | `pprof goroutine` ; `goleak.VerifyNone(t)` in tests | `sql.DB.SetMaxOpenConns`, `http.Transport.MaxConnsPerHost`, `errgroup`+`context` |
| **Rust** | `heaptrack` ; `cargo flamegraph --alloc` | `tokio-console` ; `JoinHandle::abort()` ; `tokio::select! { _ = task => ..., _ = shutdown.cancelled() => ... }` | `bb8` / `deadpool` config ; `tokio::sync::Semaphore` |
| **Node** | `clinic heapprofile` ; `--inspect` + Chrome devtools | `clinic bubbleprof` ; `process._getActiveHandles()` | `pg-pool` config ; `undici.Pool` cap |
| **Bun** | `Bun.gc(true)` + `process.memoryUsage()` ; `--inspect-brk` | `Bun.spawn` cleanup ; `AbortSignal` ; structured concurrency in `Promise.all` | same Node libs apply on Bun |
| **Python** | `tracemalloc.take_snapshot()` + `Snapshot.compare_to` ; `pytest --memray` | `asyncio.all_tasks()` ; `pytest-asyncio --strict-mode` ; `anyio.create_task_group` | `sqlalchemy.pool` `pool_pre_ping`, `pool_recycle` ; `httpx.AsyncClient` reuse |

## 4. Reporting

When emitting findings from this category:

- Quote the **runtime evidence** in the finding (a `pprof -top` line, a `tracemalloc` diff, a `clinic` URL).
- If only static evidence is available (a missing `Close()`, a `Mutex` held across I/O), say so and lower Confidence to Medium.
- Always include the **fix mechanism** explicitly — "add `defer rows.Close()`" beats "close rows".

## 5. Anti-patterns specific to resource findings

- **"Just increase the pool size"** — without profiling, this hides the leak. Promote to STRATEGIC and require root-cause analysis.
- **Adding a cache with no eviction** — perf finding becomes a memory finding next quarter.
- **Goroutine-per-request without ceiling** — works until thundering herd. Demand a semaphore or worker pool.
- **`time.Sleep` to "fix" a race** — race finding masquerading as perf. Cross-link to `@code-debugger`.

## 6. Cross-skill handoffs

- Memory finding that doubles as a DoS surface (uncapped upload, decompression bomb, regex catastrophic backtracking) → cross-link to `@code-security-review`.
- Goroutine / task leak whose root cause is incorrect synchronization (race, deadlock) → cross-link to `@code-debugger`.
- Resource exhaustion in CI / Actions runner → cross-link to `@ci-cd-generator` for the gate (resource limits, timeouts).

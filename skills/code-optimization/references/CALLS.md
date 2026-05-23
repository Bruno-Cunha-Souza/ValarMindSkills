> Reference companion for the [code-optimization](../SKILL.md) skill.

# Call Efficiency

"Call efficiency" = anti-patterns in how the code crosses a boundary: DB, HTTP, RPC, serialization, file I/O. The boundary is where most latency lives. Findings in this category usually map to Impact High because the cost is multiplicative (one bad pattern × N requests = visible regression).

## 1. N+1 queries

The dominant ORM antipattern. A list endpoint loops over parent rows and lazy-loads a relation per row.

### 1.1 Detection

Per-framework grep (deeper recipes live in per-language refs):

```bash
# SQLAlchemy (Python) — list comprehension or for-loop touching a relationship after .all()
rg -nU '\.all\(\)[\s\S]{1,400}for\s+\w+\s+in\s+\w+:[\s\S]{1,200}\.\w+\.\w+' --type py

# Django ORM (Python) — queryset followed by attribute access in a loop
rg -n '\.objects\.(all|filter)\(' --type py
# pair with: -A 5 to read the loop after the queryset

# GORM (Go) — Find then range with .Association or relation access
rg -n '\.Find\(' --type go -A 5

# Sequelize / Prisma / Drizzle (TS) — findMany then map with included relation
rg -n 'findMany|findAll' --type ts -A 5

# sqlx / SeaORM / Diesel (Rust) — query then iterate and re-fetch
rg -n '\.fetch_all\(' --type rust -A 5
```

### 1.2 Fix patterns

| ORM | Eager load name | Example |
| --- | --- | --- |
| SQLAlchemy 2.0 | `selectinload`, `joinedload`, `subqueryload` | `db.query(User).options(selectinload(User.orders)).all()` |
| Django ORM | `select_related` (FK / OneToOne), `prefetch_related` (M2M / reverse FK) | `User.objects.select_related('profile').prefetch_related('orders').all()` |
| GORM | `Preload`, `Joins` | `db.Preload("Orders").Find(&users)` |
| Sequelize | `include: [{ model: Order }]` | `User.findAll({ include: [Order] })` |
| Prisma | `include` or `select` | `prisma.user.findMany({ include: { orders: true } })` |
| Drizzle | `with: { orders: true }` (relational queries) | `db.query.users.findMany({ with: { orders: true } })` |
| Diesel | `belonging_to` + `grouped_by` | `Order::belonging_to(&users).load(&conn)?.grouped_by(&users)` |

### 1.3 Verification

- Per language, attach a query counter in tests and assert the count is bounded:
  - SQLAlchemy: `event.listen(Engine, "before_cursor_execute", counter)`.
  - Django: `self.assertNumQueries(N)` on a `TestCase`.
  - GORM: enable `Logger` with a counter callback.
  - Sequelize: hook `beforeQuery` + counter.

## 2. Async batching

The async equivalent of N+1: awaiting a coroutine per item in a loop.

### 2.1 Detection

```bash
# Python — for loop with await inside
rg -nU 'for\s+\w+\s+in.*:[\s\S]{1,80}await\s+' --type py

# TS — for/forEach with await inside (sequential)
rg -nU 'for\s*\(.*of\s+.*\)\s*\{[\s\S]{1,100}await\s' --type ts

# Go — for loop with blocking call inside
rg -nU 'for\s+.*\{[\s\S]{1,100}<-' --type go    # channel receive in loop

# Rust — for over async iterator without buffer_unordered
rg -n '\.then\(' --type rust
```

### 2.2 Fix patterns

```python
# Python — gather
await asyncio.gather(*(fetch(u.id) for u in users))
# bounded gather (cap concurrency)
sem = asyncio.Semaphore(20)
async def bounded(u): 
    async with sem: return await fetch(u.id)
await asyncio.gather(*(bounded(u) for u in users))
```

```ts
// TypeScript — Promise.all (unbounded) or p-limit / Bun semaphore (bounded)
const results = await Promise.all(users.map(u => fetch(u.id)));

// Bounded
import pLimit from "p-limit";
const limit = pLimit(20);
const results = await Promise.all(users.map(u => limit(() => fetch(u.id))));
```

```go
// Go — errgroup with semaphore
g, ctx := errgroup.WithContext(ctx)
sem := make(chan struct{}, 20)
for _, u := range users {
    u := u
    sem <- struct{}{}
    g.Go(func() error {
        defer func() { <-sem }()
        return fetch(ctx, u.ID)
    })
}
err := g.Wait()
```

```rust
// Rust — buffer_unordered with stream
use futures::stream::{self, StreamExt};
let results: Vec<_> = stream::iter(users)
    .map(|u| async move { fetch(u.id).await })
    .buffer_unordered(20)
    .collect()
    .await;
```

**Always cap concurrency.** Unbounded `Promise.all` / `gather` / `errgroup` is a memory finding waiting to fire on the day a user has 10× the expected fan-out.

## 3. Caching strategies

| Pattern | When | Pitfall to avoid |
| --- | --- | --- |
| **TTL + size cap** | Read-heavy data with bounded freshness budget | Eviction policy (LRU vs LFU) matters; pick by access pattern |
| **Write-through** | Cache stays consistent with DB | Hides DB write latency from cache hit ratio metrics |
| **Write-behind** | Tolerate brief inconsistency for write throughput | Crash safety — buffer must be durable |
| **Read-through with single-flight** | Cache miss must not stampede DB | `golang.org/x/sync/singleflight`, `lru-cache` `staleWhileRevalidate`, `cachetools.cached(lock=...)` |
| **Jittered TTL** | Prevent synchronized expiration of related entries | Add ±10% randomness to TTL |
| **Negative caching** | Cache "not found" results | Use a shorter TTL than positive entries |

### 3.1 Cache stampede

A finding: "cache miss leads to thundering herd on the DB". Recommended fix: single-flight pattern.

```go
var sg singleflight.Group
v, err, _ := sg.Do("user:"+id, func() (any, error) { return db.GetUser(ctx, id) })
```

```python
# cachetools 5+
from cachetools import cached, TTLCache
from threading import Lock
cache = TTLCache(maxsize=10000, ttl=60)
@cached(cache, lock=Lock())
def get_user(id: int) -> User: ...
```

## 4. DataLoader / batch loader pattern

Used in GraphQL resolvers and any RPC-fanout situation. Batches in-flight requests with the same key within a tick.

| Language | Library |
| --- | --- |
| Node / Bun | `dataloader` (official Facebook lib) |
| Python | `aiodataloader`, `strawberry-graphql` builtins |
| Go | `graph-gophers/dataloader`, `vektah/dataloaden` |
| Rust | `async-graphql` builtin |

**Heuristic for `@code-optimization`:** when the codebase exposes GraphQL and resolvers call DB per parent type, look for a DataLoader. Missing one is Impact High in any GraphQL service with > 10 RPS.

## 5. HTTP keep-alive / connection reuse

Re-creating clients (Go `http.Client`, Python `httpx.Client`, Node `http`) defeats keep-alive and inflates TLS handshake cost.

| Language | Antipattern | Fix |
| --- | --- | --- |
| Go | `http.Get(...)` (uses `DefaultClient`, ok) or `&http.Client{...}` per call | Single `http.Client` package-level; tune `Transport.MaxConnsPerHost`, `MaxIdleConnsPerHost` |
| Python | `requests.get(url)` per request | `requests.Session()` or `httpx.AsyncClient()` reused |
| Node | `axios.create()` per request | Single `axios` instance, or undici `Agent` with pool |
| Bun | `fetch()` per request | `fetch` reuses connections; tune `dispatcher` for limits |
| Rust | `Client::new()` per request | Single `reqwest::Client` |

## 6. Serialization hot path

`json` / `JSON.stringify` / `serde_json` are not equal in cost. The "default JSON" can dominate hot-path CPU.

| Language | Slow default | Fast alternative | Trade-off |
| --- | --- | --- | --- |
| Python | `json` | `orjson` | C extension, slightly different `Decimal` and datetime handling |
| Python (FastAPI) | `JSONResponse` | `ORJSONResponse` | Wraps `orjson`; flag explicitly via `default_response_class=ORJSONResponse` |
| Go | `encoding/json` | `encoding/json/v2` (Go 1.25+), `github.com/bytedance/sonic`, `goccy/go-json` | sonic/sonjson have API parity; benchmark before adopting |
| Node | `JSON.stringify` | `fast-json-stringify` (schema-based) | Requires schema declaration; massive speedup on structured payloads |
| Bun | `JSON.stringify` | Bun's native is already fast; `Bun.write` for streaming | Usually no change needed |
| Rust | `serde_json` | `simd-json` | SIMD-accelerated; same API for most cases |

## 7. Pagination + streaming

Endpoints that return unbounded result sets are a perf AND security finding (DoS surface).

| Default pattern | Recommendation |
| --- | --- |
| `SELECT * FROM table WHERE user_id=?` | Add `LIMIT` and offset/cursor pagination |
| `return [...rows]` from a generator | Stream via response generator (FastAPI `StreamingResponse`, Node `Readable`, Go `http.Flusher`) |
| Loading entire CSV / Parquet into memory | `pandas.read_csv(chunksize=...)` or `csv.reader` iter; never `read().split('\n')` |

Cross-link any such finding to `@code-security-review` (API4 Unrestricted Resource Consumption).

## 8. Reporting heuristics

For findings in this category, the report should include:

- **Quantitative evidence** when possible: query count drop (101 → 2), p99 latency drop (50ms → 5ms), CPU drop (15%).
- **Per-framework recommendation** with the framework version and the exact method name (`selectinload`, not "use eager loading").
- **Verification step**: how to write a test that locks in the improvement (query counter, p99 assertion, allocation diff).

## 9. Cross-skill handoffs

- DataLoader missing → reference: `@code-review` Phase 4 for general perf scan; this skill for full audit.
- N+1 in a high-traffic endpoint → cross-link `@code-security-review` if the endpoint is also a DoS surface.
- Pagination missing on a public endpoint → cross-link `@code-security-review` API4.
- HTTP client churn under load → cross-link `@code-debugger` if the symptom is timeouts (root-cause analysis), then this skill for the prevention.

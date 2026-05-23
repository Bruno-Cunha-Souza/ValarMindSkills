> Reference companion for the [code-optimization](../SKILL.md) skill.

# TypeScript / Node / Bun Performance Reference

Targets: TypeScript 5.6+, Node 22+ LTS, Bun 1.2+. Frameworks: Elysia, Fastify, Hono, Express. Coexistence note: most antipatterns translate between Node and Bun; runtime-specific notes are tagged.

## 1. Tooling matrix

| Concern | Tool | Invocation |
| --- | --- | --- |
| Event-loop health | `clinic.js doctor` | `clinic doctor -- node dist/server.js` |
| CPU flamegraph | `clinic.js flame` / `0x` | `clinic flame -- node dist/server.js` |
| Async chain | `clinic.js bubbleprof` | `clinic bubbleprof -- node dist/server.js` |
| Heap profile | `clinic.js heapprofile` / Chrome devtools | `clinic heapprofile -- node dist/server.js` |
| V8 profile | `--prof` | `node --prof dist/server.js` → `node --prof-process isolate-*.log` |
| Bun profile | `Bun.nanoseconds()` + `bun --hot` | inline timing; or `bun --inspect-brk` for devtools |
| Micro-bench | `vitest bench` / `mitata` / `tinybench` | `vitest bench`; mitata best for V8 noise control |
| Unused exports | `knip` | `bunx knip` / `npx knip` |
| Type check perf | `tsc --extendedDiagnostics` | spots type-checking bottlenecks |
| Duplication | `jscpd` + `eslint-plugin-sonarjs` | `jscpd src/`; ESLint `no-duplicate-string` |

## 2. Hot-path antipatterns

### 2.1 Async boundaries

| Anti-pattern | Fix |
| --- | --- |
| `for (const item of items) { await fetch(...) }` (sequential) | `await Promise.all(items.map(i => fetch(...)))` (bounded with `p-limit`) |
| `Promise.all` without cap on user-controlled fan-out | `p-limit(20)` or `Bluebird.map(items, fn, { concurrency: 20 })` |
| `await` inside a synchronous loop hot path | hoist the awaited value if it's request-scoped |
| `await Promise.resolve(x)` to "make it async" | drop — V8 still microtasks even without `await` |
| Forgetting to `await` and silently swallowing rejection | enable `@typescript-eslint/no-floating-promises` |

### 2.2 V8 GC pressure

- **Hidden classes / inline caches** — initialize all properties in the constructor with the same shape. Adding properties later "deopts" the class.
- **Megamorphic call sites** — when a function is called with many shapes, V8 falls back to slow path. Solution: type-narrow at the boundary (use `instanceof` check or schema validation).
- **Large object literals in hot path** — preallocate with `Object.create(null)` for map-style usage; freeze for read-only.
- **String concatenation** — V8 ropes are fast for short concatenations; for large templates use `Buffer.concat` or template literals once.
- **Array sparse vs dense** — never assign `arr[100000] = x` to a small array; use `new Array(n).fill(default)` to preallocate.

### 2.3 Bun vs Node specifics

Bun is generally 2–4× faster on:

- HTTP serving (`Bun.serve` vs `http.createServer`)
- File I/O (`Bun.file(path).text()` vs `fs.readFile`)
- Crypto (`Bun.password.hash` vs `bcrypt`)
- JSON parsing (Bun's `JSON.parse` uses simdjson under the hood)
- Subprocess (`Bun.spawn` vs `child_process`)

When auditing a Bun project, look for "compatibility imports" that defeat the speedup:

| Bun-replaceable npm | Bun native |
| --- | --- |
| `node-fetch`, `cross-fetch`, `axios` | global `fetch` (HTTP/2, keep-alive, caching) |
| `dotenv` | Bun auto-loads `.env` |
| `bcrypt` | `Bun.password.{hash,verify}` |
| `jest` / `ts-jest` | `bun test` |
| `nodemon` | `bun --hot` |
| `node-cron` (timers) | `Bun.scheduler` / `setInterval` (built-in) |
| `glob`, `fast-glob` | `Bun.Glob` |

Each unnecessary npm replacement is Impact=Medium, Risk=SAFE, Effort=S — Polish quadrant.

### 2.4 Allocations and arrays

| Anti-pattern | Fix |
| --- | --- |
| `[...arr, newItem]` in hot loop | `arr.push(newItem)` (mutates, faster); or pre-size with known length |
| `arr.filter(...).map(...).reduce(...)` (3-pass) | single `for` loop or `reduce` directly when chain depth > 3 |
| `JSON.parse(JSON.stringify(obj))` deep clone | `structuredClone(obj)` (faster, supports more types) or library |
| `Object.assign({}, obj, patch)` | spread `{...obj, ...patch}` (same shape, slightly faster on V8) |

### 2.5 Streaming

For large payloads (CSV, files, query results):

- Node: `Readable` / `Writable` / `pipeline` (avoid manual `on('data')` + `on('end')`).
- Bun: native `ReadableStream` via `Bun.file().stream()`.
- HTTP server: `res.flushHeaders()` early, then chunk; for SSE use `Transfer-Encoding: chunked`.

## 3. Framework-specific notes

### 3.1 Elysia (Bun-first)

- Route compilation at startup — minimal per-request overhead.
- Schema-first (`t.Object(...)`) generates a fast validator at startup; avoid runtime schema construction.
- Plugins are zero-cost when bound at app startup; per-request plugin construction is an antipattern.

### 3.2 Fastify

- Schema-based serializer (`fast-json-stringify`) is critical — define response schemas and the framework compiles a serializer 2–4× faster than `JSON.stringify`.
- `logger: false` in production hot path if not needed; pino is fast but not zero-cost.
- Decorators (`fastify.decorateRequest('user', null)`) preserve hidden class shape — use them instead of ad-hoc property assignment.

### 3.3 Hono

- Runs on Node, Bun, Deno, Workers — pick adapter wisely. Workers adapter has stricter execution-time caps.
- Routing is trie-based (`hono/router`) — very fast.
- Middleware chains are linear; expensive global middleware should be route-scoped.

### 3.4 Express (legacy)

- Sync middleware is fine, but `app.use((req, res, next) => fetchUser().then(...))` without `next(err)` on rejection silently hangs.
- `compression()` middleware is CPU heavy — apply only to large bodies or move to a reverse proxy.
- Body parsers (`express.json`) have a default 100KB limit; raising this is a DoS vector — cross-link `@code-security-review`.

## 4. Connection pools

| Library | Pool config |
| --- | --- |
| `pg` (node-postgres) | `pg-pool`: `max: 20`, `idleTimeoutMillis: 30000`, `connectionTimeoutMillis: 2000` |
| `mysql2` | `createPool({ connectionLimit: 20, waitForConnections: true })` |
| Prisma | `?connection_limit=20&pool_timeout=30` in DATABASE_URL |
| Drizzle + pg | reuses `pg-pool` config |
| `undici` (HTTP client) | `new Agent({ connections: 100, pipelining: 1 })` — global agent reused |

## 5. Profiling recipes

```bash
# Node — clinic doctor (high-level event-loop diagnosis)
clinic doctor --on-port 'autocannon -d 30 -c 100 localhost:3000' -- node dist/server.js

# Node — flamegraph
clinic flame -- node dist/server.js

# Node — V8 prof
node --prof dist/server.js
# Stop after load → process
node --prof-process isolate-*.log > prof.txt

# Bun — inline timing
bun --hot src/server.ts
# Use Bun.nanoseconds() around hot blocks

# Memory diff between two snapshots (Node)
clinic heapprofile -- node dist/server.js
# Snapshot 1 + Snapshot 2 from Chrome devtools → diff view
```

## 6. Verification

- **`autocannon`** / **`wrk`** for HTTP load. Report p99 deltas; only `>= 5%` improvements count as Quick Wins.
- **`vitest bench`** with multiple iterations and `mitata` engine for micro-benchmarks.
- **Bundle size** with `bun build --minify` or `esbuild --analyze` if shipping to browser/edge.

## 7. Anti-patterns specific to TS/Node/Bun perf findings

- "Bun is faster, switch everything" — Bun's native APIs are fast; npm packages run on a compatibility layer that may or may not be faster. Audit per-call.
- "Add `--max-old-space-size=8192`" — bandage over a heap leak. Demand alloc profile first.
- "Use cluster mode" — works but adds IPC overhead. Modern alternative: container orchestration with multiple replicas.
- "Cache everything in memory" — single-process cache doesn't scale horizontally. Use Redis / in-process LRU + cluster cache invalidation.
- "Use streaming for everything" — overhead for small payloads. Stream when payload > 1 MB or when serving many concurrent clients.

## 8. References (external)

- Node.js perf docs (cite via context7 `mcp__context7__resolve-library-id` for "Node.js").
- Bun docs https://bun.sh/docs.
- V8 design docs on hidden classes and ICs.
- `nodejs/node` GitHub for V8 flags and `--trace-*` options.

# Code Debugger — TypeScript / Node / Bun Reference

> Reference companion for the [code-debugger](../SKILL.md) skill. TypeScript-, Node-, and Bun-specific debugging techniques, command snippets, and bug-class playbooks. Pairs with [code-review/references/TYPESCRIPT.md](../../code-review/references/TYPESCRIPT.md) (static smell catalogue) and the Next.js skills (App Router runtime issues).

## Tools

| Tool | Purpose | Install / Use |
| --- | --- | --- |
| `node --inspect` / `node --inspect-brk` | Inspector protocol — Chrome DevTools / VSCode | bundled |
| `bun --inspect` / `bun --inspect-brk` | Bun debugger | bundled |
| `clinic` | `doctor`, `flame`, `bubbleprof` | `npm i -g clinic` |
| `0x` | Flame graph generator | `npm i -g 0x` |
| `heapdump` | V8 heap snapshot | `npm i heapdump` (or `node --inspect` "Take snapshot") |
| `--enable-source-maps` | Map stacks back to TS | `node --enable-source-maps` (default in Node 20+) |
| `node --trace-warnings` | Show warnings with stack | bundled |
| `node --trace-uncaught` | Stack on uncaught exceptions | bundled |
| `bun --hot` | Hot reload (rapid repro) | bundled |
| `unhandled-rejection` listener | Catch unhandled rejections | runtime |
| `async_hooks` / `AsyncLocalStorage` | Track async context | bundled |
| `vitest` / `bun:test` / `jest` | Test runners | per-project |

## Quick reproducer commands

```bash
# Run a single test
bun test <file> -t '<name>'                      # bun
npx vitest run -t '<name>' <file>                # vitest
npx jest -t '<name>' <file>                      # jest

# Repeat (flake hunt)
bun test <file> --rerun-each 200
npx vitest run --repeats 200
# Jest: write a `describe.each(Array(200).fill(null))(...)` wrapper.

# Run with the inspector
node --inspect-brk -r ts-node/register src/index.ts
bun --inspect-brk src/index.ts
# Then open chrome://inspect or attach VSCode "Node: Attach"

# Source maps (Node)
node --enable-source-maps dist/index.js          # default in Node 20+

# Trace warnings + uncaught
node --trace-warnings --trace-uncaught --enable-source-maps dist/index.js

# Memory snapshot via inspector OR heapdump:
const heapdump = require('heapdump');
heapdump.writeSnapshot('./heap-' + Date.now() + '.heapsnapshot');

# CPU / event-loop / async
clinic doctor   -- node dist/index.js
clinic flame    -- node dist/index.js
clinic bubbleprof -- node dist/index.js
0x dist/index.js
```

## Bug-class playbooks

### Unhandled promise rejection

Pattern (Node): process exits or warns.

```text
(node:1234) UnhandledPromiseRejection: This error originated either by
throwing inside of an async function without a catch block, or by rejecting
a promise which was not handled with .catch().
```

Procedure:

1. `node --trace-uncaught --enable-source-maps` to surface the source frame.
2. Find the unawaited promise. Possible owners:
   - `await` missing on a function call returning a promise.
   - `.then(...)` chain without `.catch`.
   - `Promise.all` / `Promise.allSettled` mismatch (the former rejects fast).
3. Add `.catch` or a top-level handler and rethrow as a domain error.

### `TypeError: Cannot read property X of undefined/null`

Procedure:

1. Source-mapped stack points to the line that did the read.
2. Inspect the value's origin: function arg, JSON parse, env var, route param.
3. Common roots: optional chaining missing (`a?.b`), JSON parse of empty body, `find()` returning `undefined`, missing `await` so the value is a Promise, not the resolved object.

### `RangeError: Maximum call stack size exceeded`

Procedure:

1. Stack itself is the answer — find the recursion.
2. Common roots: missing base case, mutual recursion via getters / proxies, accidental `this.toJSON()` calling `JSON.stringify(this)`.

### Memory growth / leak

Procedure:

1. Take two heap snapshots, minutes apart, under steady load. Diff them in DevTools.
2. Look at the "Retained size" sorted descending. Identify which constructors grow.
3. Common roots:
   - **Closures** capturing request-scoped values held by long-lived objects.
   - **Listeners** added but not removed (`emitter.on(...)` per request).
   - **Timers** (`setInterval`) not cleared.
   - **Caches** without max size or TTL.
   - **Async iterators** retaining buffered values.

### Event-loop stall

Pattern: requests slow down predictably; `clinic doctor` flags blocking.

Procedure:

1. `clinic doctor -- node dist/index.js` then run a load test.
2. Read the verdict: CPU-bound? Sync I/O? Event-loop blocked?
3. Common roots: `JSON.stringify` of huge objects on the request path; `crypto.pbkdf2Sync`; `fs.readFileSync` in a handler; large regex on user input (catastrophic backtracking).

### Async stack lost (`<anonymous>` only)

Procedure:

1. Run with `--enable-source-maps` (Node 20+ has it by default but compiled bundles may need explicit flag).
2. Use `Error.captureStackTrace` at boundary creation if needed.
3. Use `AsyncLocalStorage` to attach a request id for log correlation when stacks are insufficient.
4. For deeper async tracing: `--async-stack-traces` (default in V8 ≥ 7.3).

### Flaky test

Procedure:

1. `bun test --rerun-each 200` / `vitest run --repeats 200` — measure rate.
2. Look for:
   - **Order dependency** — `vitest run --sequence.shuffle=true` exposes it.
   - **Time** — `vi.useFakeTimers()` or `bun:test`'s `setSystemTime`.
   - **Real network** — mock with `msw`, `nock`, or `bun --hot` request stubs.
   - **Module-level state** — `vi.resetModules()` / `bun:test` `beforeEach` reset.
   - **Concurrent tests sharing a temp dir** — use unique paths.

### Wrong type at runtime (TS lied)

TypeScript's checks are erased at runtime. If a value's runtime shape disagrees with its static type, the cause is upstream:

- `JSON.parse` produces `any`.
- A library typed inaccurately.
- An `as` cast.

Procedure:

1. Add a runtime validator at the boundary (`zod`, `valibot`, `@sinclair/typebox`).
2. Failing the validator is the new error, with a precise location.

### "Works locally, fails in CI"

Procedure:

1. Diff Node / Bun versions: `node --version` vs CI image.
2. Diff lockfile install: `npm ci` vs `npm install` (CI must use `ci`).
3. Diff env vars and timezone — many flakes are `TZ=UTC` differences.
4. Diff filesystem case-sensitivity (macOS default is case-insensitive; Linux is sensitive).

### `EADDRINUSE` / `EACCES` / `ECONNREFUSED`

Procedure:

1. `lsof -i :<port>` — identify the holder.
2. Common roots: previous test process did not exit; port hardcoded; `before/afterEach` cleanup missing.

## Inspector quick recipe

```bash
# Start with break on first line
node --inspect-brk --enable-source-maps dist/index.js
# or
bun --inspect-brk src/index.ts

# Open chrome://inspect → click "Open dedicated DevTools for Node"

# In DevTools → Sources:
# - Set breakpoints (works on .ts via source maps)
# - Use the `console` for ad-hoc evaluation
# - Use `Memory` tab for heap snapshots
# - Use `Performance` tab for CPU profiles

# VSCode equivalent: launch.json
{
  "type": "node",
  "request": "attach",
  "name": "Attach",
  "port": 9229,
  "skipFiles": ["<node_internals>/**"],
  "outFiles": ["${workspaceFolder}/dist/**/*.js"],
  "sourceMaps": true
}
```

## clinic / 0x quick recipe

```bash
# Diagnose unknown perf issue
clinic doctor -- node --enable-source-maps dist/index.js
# (run load test against the server)
# clinic generates an HTML report

# Flame graph
clinic flame -- node --enable-source-maps dist/index.js
0x -- node dist/index.js              # alternative

# Async wait analysis
clinic bubbleprof -- node dist/index.js
```

## Bun-specific notes

- `bun --inspect` works the same as `node --inspect`; same DevTools UI.
- `bun:test` supports `expect(...).resolves.toBe(...)` without `await` in many cases — read failure messages carefully.
- `Bun.spawn(["cmd", "arg"])` exits with a `Subprocess` whose `.exited` is a Promise of the exit code; do not block on it incorrectly.
- `Bun.file(path).text()` returns a Promise; ensure you `await` it before using the value.
- `Bun.serve` errors thrown in a handler reach the `error` callback if defined, else become a 500. Set `error: (e) => ...` for clearer logs.

## TypeScript-specific notes

- Stack traces show **transpiled JS** unless `--enable-source-maps` is on. With `tsc`, ensure `"sourceMap": true` and `"inlineSources": true` in `tsconfig.json`.
- `error.cause` (ES2022) carries the underlying error — read it (`while (e?.cause) e = e.cause`) when the top error is wrapped.
- `JSON.stringify(error)` returns `{}` because `Error` properties are non-enumerable — log `error.message` and `error.stack` explicitly.

## Common false leads

- **`console.warn` in node_modules** — not your bug; ignore.
- **A linter complaining** — lead, not cause.
- **`as any` in the failing area** — investigate, but the runtime value is what matters; the assertion lied or the upstream type was wrong.
- **`Promise rejected` with no stack** — re-run with `--enable-source-maps` and a top-level rejection handler.

## Hand-off triggers

- Next.js App Router runtime bug (Server Component, Server Action, Route Handler) → `@code-security-review` (Next branch — `references/nextjs/`) for security; `@code-review` (`references/NEXTJS.md`) for performance.
- Refactor-class root cause → `@clean-code` with [TYPESCRIPT reference](../../clean-code/references/TYPESCRIPT.md) or [BUN reference](../../clean-code/references/BUN.md).
- API runtime issue with security implication → `@code-security-review`.

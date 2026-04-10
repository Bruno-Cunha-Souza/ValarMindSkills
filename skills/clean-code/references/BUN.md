# Bun — Clean Code Reference

> Language-specific companion for the [clean-code](../SKILL.md) skill. Covers Bun runtime idioms, native APIs, testing, and common anti-patterns. For TypeScript language smells, see [TYPESCRIPT.md](TYPESCRIPT.md).

## Tools

| Tool | Purpose | Run |
|------|---------|-----|
| `bun test` | Built-in test runner (Jest-compatible) | `bun test` |
| `bun run` | Script/task runner | `bun run <script>` |
| `bunx` | npx equivalent (auto-installs) | `bunx <package>` |
| `bun build` | Bundler (esbuild-based) | `bun build ./src/index.ts --outdir ./dist` |
| `bun install` | Package manager (fast, lockfile v2) | `bun install` |
| `biome` | Fast linter + formatter | `bunx biome check .` |
| `knip` | Find unused exports/deps | `bunx knip` |

### Quick Audit

```bash
# Run all tests
bun test

# Run tests with coverage
bun test --coverage

# Type check (Bun uses tsc under the hood)
bunx tsc --noEmit

# Lint with Biome (recommended for Bun projects)
bunx biome check .

# Find unused exports and dependencies
bunx knip

# Detect circular dependencies
bunx madge --circular --extensions ts src/

# Clone detection
bunx jscpd --min-lines 5 --min-tokens 50 ./src
```

## Bun-Specific Smells

### 1. Using Node.js APIs When Bun Natives Exist

Bun provides optimized built-in APIs. Using Node.js equivalents loses performance and idiom.

```diff
# Bad — Node.js fs for file reading
- import { readFileSync } from "node:fs";
- const content = readFileSync("config.json", "utf-8");
- const config = JSON.parse(content);

# Good — Bun.file (lazy, streamable, faster)
+ const config = await Bun.file("config.json").json();
```

```diff
# Bad — Node.js fs for writing
- import { writeFileSync } from "node:fs";
- writeFileSync("output.txt", data);

# Good — Bun.write
+ await Bun.write("output.txt", data);
```

```diff
# Bad — Node.js crypto for hashing
- import { createHash } from "node:crypto";
- const hash = createHash("sha256").update(password).digest("hex");

# Good — Bun.password (bcrypt/argon2 built-in) for passwords
+ const hash = await Bun.password.hash(password);
+ const valid = await Bun.password.verify(input, hash);

# Good — Bun.CryptoHasher for general hashing
+ const hash = new Bun.CryptoHasher("sha256").update(data).digest("hex");
```

**Detect:**
```bash
# Find Node.js imports that have Bun equivalents
rg 'from "node:fs"|require\("fs"\)' --type ts
rg 'from "node:crypto"|require\("crypto"\)' --type ts
rg 'from "node:path"|require\("path"\)' --type ts
```

### 2. Using Express/Fastify When Bun.serve Suffices

For simple HTTP servers, `Bun.serve` is native and faster — no external dependency needed.

```diff
# Bad — Express for a simple API
- import express from "express";
- const app = express();
- app.get("/health", (req, res) => res.json({ ok: true }));
- app.post("/users", (req, res) => {
-     const user = req.body;
-     res.status(201).json(user);
- });
- app.listen(3000);

# Good — Bun.serve (zero dependencies)
+ Bun.serve({
+     port: 3000,
+     fetch(req) {
+         const url = new URL(req.url);
+         if (req.method === "GET" && url.pathname === "/health") {
+             return Response.json({ ok: true });
+         }
+         if (req.method === "POST" && url.pathname === "/users") {
+             const user = await req.json();
+             return Response.json(user, { status: 201 });
+         }
+         return new Response("Not Found", { status: 404 });
+     },
+ });
```

**When to keep Express/Hono**: Complex routing, middleware chains, large APIs. `Bun.serve` is best for microservices and simple APIs.

**Detect:** `rg 'import.*express|require.*express' --type ts` — evaluate if the Express features are actually needed.

### 3. Using Jest When bun:test Is Available

Bun has a built-in test runner compatible with Jest APIs — no extra dependency needed.

```diff
# Bad — Jest with extra config
- // jest.config.ts
- import type { Config } from "jest";
- const config: Config = { preset: "ts-jest", testEnvironment: "node" };
- export default config;
-
- // __tests__/user.test.ts
- import { describe, it, expect } from "@jest/globals";

# Good — bun:test (zero config, built-in)
+ // user.test.ts
+ import { describe, it, expect, mock, beforeEach } from "bun:test";
+
+ describe("User", () => {
+     it("creates a user", () => {
+         const user = createUser("Alice");
+         expect(user.name).toBe("Alice");
+     });
+ });
```

**Detect:** `rg '"jest"|"ts-jest"|"@jest/globals"' package.json` and `rg 'from "@jest/globals"' --type ts`

### 4. Not Using Bun's Built-in SQLite

Bun has a native, synchronous SQLite driver — faster than `better-sqlite3` or other npm packages.

```diff
# Bad — npm package for SQLite
- import Database from "better-sqlite3";
- const db = new Database("app.db");

# Good — Bun native SQLite
+ import { Database } from "bun:sqlite";
+ const db = new Database("app.db");
+
+ // Bun also supports prepared statements with .query()
+ const stmt = db.query("SELECT * FROM users WHERE id = ?");
+ const user = stmt.get(userId);
```

**Detect:** `rg '"better-sqlite3"|"sql.js"' package.json`

### 5. Unnecessary Polyfills

Bun natively supports Web APIs that Node.js needed polyfills for.

```diff
# Bad — polyfills for things Bun has natively
- import fetch from "node-fetch";
- import { FormData } from "formdata-polyfill";
- import { ReadableStream } from "web-streams-polyfill";
- import { TextEncoder, TextDecoder } from "util";

# Good — all available globally in Bun
+ // fetch, FormData, ReadableStream, TextEncoder, TextDecoder
+ // are all global — just use them directly
+ const res = await fetch("https://api.example.com/data");
+ const form = new FormData();
```

**Detect:**
```bash
# Find polyfill packages in dependencies
rg '"node-fetch"|"cross-fetch"|"whatwg-fetch"|"formdata-polyfill"|"web-streams-polyfill"|"abort-controller"' package.json
```

### 6. Not Leveraging Bun's Glob API

Bun has a built-in `Bun.Glob` for file pattern matching — no `glob` or `fast-glob` npm packages needed.

```diff
# Bad — npm package for globbing
- import { glob } from "fast-glob";
- const files = await glob("src/**/*.ts");

# Good — Bun.Glob (native, faster)
+ const glob = new Bun.Glob("src/**/*.ts");
+ const files = Array.from(glob.scanSync("."));
```

**Detect:** `rg '"glob"|"fast-glob"|"globby"' package.json`

### 7. Ignoring Bun's Environment Variables

Bun auto-loads `.env` files — no `dotenv` needed.

```diff
# Bad — manual dotenv loading
- import "dotenv/config";
- // or
- import dotenv from "dotenv";
- dotenv.config();
- const dbUrl = process.env.DATABASE_URL;

# Good — Bun loads .env automatically
+ const dbUrl = Bun.env.DATABASE_URL;
+ // or process.env.DATABASE_URL (also works, auto-loaded)
```

**Detect:** `rg '"dotenv"' package.json`

## Bun Refactoring Patterns

### Migrate File I/O to Bun.file

Replaces scattered `fs.readFileSync` / `fs.writeFileSync` calls.

```diff
# Before: Node.js file operations
- import { readFileSync, writeFileSync } from "node:fs";
-
- function loadConfig(): Config {
-     const raw = readFileSync("config.json", "utf-8");
-     return JSON.parse(raw);
- }
- function saveConfig(config: Config): void {
-     writeFileSync("config.json", JSON.stringify(config, null, 2));
- }

# After: Bun.file / Bun.write
+ async function loadConfig(): Promise<Config> {
+     return Bun.file("config.json").json();
+ }
+ async function saveConfig(config: Config): Promise<void> {
+     await Bun.write("config.json", JSON.stringify(config, null, 2));
+ }
```

### Migrate to Bun.serve with Router Pattern

For APIs that outgrow a single `fetch` handler but don't need Express.

```diff
# Before: growing switch/if chain in fetch
- Bun.serve({
-     fetch(req) {
-         const url = new URL(req.url);
-         if (url.pathname === "/users" && req.method === "GET") { /* ... */ }
-         if (url.pathname === "/users" && req.method === "POST") { /* ... */ }
-         if (url.pathname.startsWith("/users/") && req.method === "GET") { /* ... */ }
-         if (url.pathname.startsWith("/users/") && req.method === "DELETE") { /* ... */ }
-         // ... 20 more routes
-     },
- });

# After: lightweight router (Hono works great with Bun)
+ import { Hono } from "hono";
+ const app = new Hono();
+
+ app.get("/users", listUsers);
+ app.post("/users", createUser);
+ app.get("/users/:id", getUser);
+ app.delete("/users/:id", deleteUser);
+
+ Bun.serve({ fetch: app.fetch, port: 3000 });
```

### Replace npm Packages with Bun Natives

Audit `package.json` and replace packages that Bun covers natively.

| npm Package | Bun Native | Migration |
|-------------|-----------|-----------|
| `node-fetch`, `cross-fetch` | `fetch` (global) | Remove import, use `fetch` directly |
| `dotenv` | Auto `.env` loading | Remove import, use `Bun.env` |
| `better-sqlite3` | `bun:sqlite` | Change import to `bun:sqlite` |
| `glob`, `fast-glob` | `Bun.Glob` | Use `new Bun.Glob(pattern).scanSync(".")` |
| `bcrypt`, `argon2` | `Bun.password` | Use `Bun.password.hash()` / `.verify()` |
| `jest`, `ts-jest` | `bun:test` | Remove jest config, import from `bun:test` |
| `nodemon`, `ts-node-dev` | `bun --watch` | Use `bun --watch src/index.ts` |
| `tsx` | `bun` (native TS) | Replace `tsx script.ts` with `bun script.ts` |

**Audit command:**
```bash
# List all dependencies and check for Bun-native replacements
rg '"(node-fetch|cross-fetch|dotenv|better-sqlite3|glob|fast-glob|globby|bcrypt|argon2|jest|ts-jest|nodemon|ts-node-dev|tsx)"' package.json
```

## Bun Verification Commands

```bash
# Run all tests
bun test

# Run tests with coverage
bun test --coverage

# Run specific test file
bun test src/user.test.ts

# Type check
bunx tsc --noEmit

# Lint + format
bunx biome check .

# Find unused dependencies
bunx knip

# Build check (ensure it bundles without errors)
bun build ./src/index.ts --outdir ./dist --target bun
```

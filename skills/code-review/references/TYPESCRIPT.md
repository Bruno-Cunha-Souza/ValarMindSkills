# Code Review — TypeScript / Node / Bun Reference

> Reference companion for the [code-review](../SKILL.md) skill. TypeScript-, Node-, and Bun-specific patterns, sweeps, and example findings. Pairs with [clean-code/references/TYPESCRIPT.md](../../clean-code/references/TYPESCRIPT.md) and [clean-code/references/BUN.md](../../clean-code/references/BUN.md). For Next.js App Router code, see [NEXTJS.md](NEXTJS.md) for performance and [@code-security-review (Next branch)](../../code-security-review/references/nextjs/API.md) for security.

## Tools

| Tool | Purpose | Install / Run |
| --- | --- | --- |
| `tsc --noEmit` | TypeScript type check (no output) | per-project |
| `eslint` | Lint with `@typescript-eslint` plugin | `npm i -D eslint @typescript-eslint/{eslint-plugin,parser}` |
| `biome` | Fast lint + format | `bun add -D @biomejs/biome` |
| `knip` | Detect unused exports / files / deps | `bunx knip` / `npx knip` |
| `npm audit` / `bun audit` | CVE scan against the registry | bundled |
| `semgrep` | Polyglot SAST | `pip install semgrep` |
| `madge` | Circular dependency detection | `npm i -g madge` |
| `size-limit` | Bundle / output size budget | `npm i -D size-limit` |
| `vitest` / `bun test` / `jest` | Test runner | per-project |

## Quick sweep

```bash
# Static sweep from the touched package/workspace root
bunx tsc --noEmit                              # or: npx tsc --noEmit
bunx biome check .                             # or: bunx eslint .

# Unused
bunx knip
bunx madge --circular --extensions ts,tsx src/

# Vulnerabilities
bun audit                                      # or: npm audit --omit=dev

# SAST
semgrep --config=auto

# Optional verification only
bun test                                       # or: npx vitest run
```

## Findings catalog — 25+ patterns to scan

Run patterns against changed TypeScript files through the [Diff Scope Contract](../SKILL.md#01-diff-scope-contract), then open matching files before filing a finding.

### 1. `any` in a public signature

```bash
rg -n ': any\b' --type ts --type tsx
rg -n 'export (function|const|async function)\s+\w+[^=]*: any\b' --type ts
```

Severity floor: **Medium** for exported symbols, **Low** for internal narrow boundaries (with comment).

### 2. `as` type assertion to a wider type

```bash
rg -n 'as (any|unknown|object|Record<string,\s*any>)' --type ts --type tsx
```

Severity floor: **Medium**. Each assertion is a tax on the type system; require justification.

### 3. Non-null assertion `!`

```bash
rg -n '\w+!\.' --type ts --type tsx
```

Severity floor: **Low**. Promote to **Medium** in production paths where the runtime invariant is not obvious.

### 4. Unhandled promise rejection

```bash
rg -n '\bnew Promise\(' --type ts --type tsx          # check that .catch or await follows
rg -n '^\s*[a-zA-Z_]\w*\([^)]*\)\.then\(' --type ts   # `.then` without `.catch`
```

Severity floor: **High**. Node 15+ exits the process on unhandled rejections by default.

### 5. `async` function that does not `await`

```bash
bunx eslint --rule '{"@typescript-eslint/require-await":"error"}' src/
```

Severity floor: **Low**. Often a refactor smell — function returns a `Promise` of a value that never awaits anything.

### 6. `await` inside a loop (sequential when parallel is fine)

```bash
rg -n -C 3 'for .*\{|await\b' --type ts --type tsx
```

Severity floor: **Medium**. Use `Promise.all` / `for await ... of` (with concurrency limit) when iterations are independent.

### 7. `JSON.parse(req.body)` without size limit / try

```bash
rg -n 'JSON\.parse\(' --type ts --type tsx
```

Severity floor: **High** when input is untrusted. Use a schema validator (`zod`, `valibot`, `@sinclair/typebox`).

### 8. Eval / dynamic require / `Function()` constructor

```bash
rg -n '\b(eval\(|new Function\(|globalThis\["[^"]+"\])' --type ts --type tsx
```

Severity floor: **Critical**. CWE-95.

### 9. `child_process.exec` with template literal

```bash
rg -n 'child_process\.(exec|execSync)\([^)]*\$\{' --type ts --type tsx
rg -n 'Bun\.spawn\(\[".*\$\{' --type ts --type tsx
```

Severity floor: **Critical**. CWE-78. Use `execFile` / `Bun.spawn(args[])` and pass arguments as an array.

### 10. SQL string concatenation

```bash
rg -n '\.(query|raw|execute)\(`[^`]*\$\{' --type ts --type tsx
```

Severity floor: **Critical**. CWE-89. Use prepared statements / parameter binding.

### 11. `crypto.createHash('md5'|'sha1')`

```bash
rg -n "createHash\('(md5|sha1)'" --type ts --type tsx
```

Severity floor: **High** for security-sensitive use; **Low** for cache keys / checksums (with comment).

### 12. `Math.random()` for security tokens

```bash
rg -n 'Math\.random\(\)' --type ts --type tsx
```

Severity floor: **Critical** if used for tokens / IDs / CSRF / session. Use `crypto.randomBytes` or `crypto.randomUUID`.

### 13. `process.env` read at module top-level

```bash
rg -n 'process\.env\.\w+' --type ts --type tsx    # manually verify module top-level vs function scope
```

Severity floor: **Low**. Promote to **Medium** when the value drives security-sensitive behavior — read inside a function so tests can override.

### 14. CORS `origin: '*'`

```bash
rg -n "origin:\s*['\"]\*['\"]" --type ts --type tsx
rg -n 'Access-Control-Allow-Origin.*\*' --type ts --type tsx
```

Severity floor: **Medium**. **High** if combined with `credentials: true`.

### 15. Missing `helmet` / security headers (Express / Fastify)

```bash
rg -n "(express\(\)|fastify\(\))" --type ts --type tsx
```

If found, check that `helmet` (or equivalent) is wired up. Severity floor: **Medium** when missing.

### 15a. API route without schema validation

```bash
rg -n '(app\.(get|post|put|patch|delete)|router\.(get|post|put|patch|delete)|new Elysia|Hono\()' --type ts --type tsx
rg -n '(z\.object|v\.object|Type\.Object|schema|validator|parse\(|safeParse\()' --type ts --type tsx
```

Severity floor: **Medium** for new public endpoints that read body/query/params without a schema boundary. Promote to **High** when the unchecked input controls auth, money movement, file paths, outbound URLs, SQL filters, or shell args.

### 15b. ORM raw query escape hatch

```bash
rg -n '(\$queryRawUnsafe|\$executeRawUnsafe|sql\.raw|db\.execute\(sql\.raw|unsafeSql|raw\()' --type ts --type tsx
```

Severity floor: **High** when user input can reach the raw string. **Critical** when direct interpolation builds SQL.

### 16. `Buffer.allocUnsafe` without overwrite

```bash
rg -n 'Buffer\.allocUnsafe\(' --type ts --type tsx
```

Severity floor: **High**. Returns uninitialized memory. CWE-908.

### 17. Logger leaks sensitive headers / cookies

```bash
rg -n 'logger?\.(info|debug|log)\(.*\b(authorization|cookie|password|token|secret)\b' --type ts --type tsx
```

Severity floor: **High**. CWE-532.

### 18. `setImmediate` / `setTimeout(fn, 0)` instead of awaiting

Severity floor: **Low**. Smell of fighting the event loop; investigate.

### 19. Error swallowed by `.catch(() => {})` or `.catch(_ => null)`

```bash
rg -n '\.catch\(\s*(\(\s*\)|_\s*)\s*=>\s*(\{\s*\}|null|undefined)\s*\)' --type ts --type tsx
```

Severity floor: **Medium**. Drop or log + rethrow.

### 20. `tsconfig` `strict: false` on a new module

Severity floor: **Low** repo-wide; **Medium** if the new module ships in strict packages.

### 21. Circular import

```bash
bunx madge --circular --extensions ts,tsx src/
```

Severity floor: **Medium**. Causes unpredictable load order.

### 22. Default export of a class with side-effecting constructor

```bash
rg -n 'export default class' --type ts --type tsx
```

Severity floor: **Low**. Verify constructor is side-effect-free; otherwise importing the module triggers I/O.

### 23. `useEffect` with missing or wrong dependency array (React)

```bash
rg -n 'useEffect\(' --type tsx
```

Run `eslint-plugin-react-hooks/exhaustive-deps`. Severity floor: **Medium**.

### 24. `dangerouslySetInnerHTML` (React) with non-static content

```bash
rg -n 'dangerouslySetInnerHTML' --type tsx
```

Severity floor: **High** unless wrapped by an explicit sanitizer (`DOMPurify`).

### 25. `npm` lockfile mismatch

```bash
git diff "$DIFF_RANGE" -- package.json package-lock.json bun.lockb pnpm-lock.yaml yarn.lock
```

Severity floor: **Low**. Confirm the lockfile updates match the manifest changes; mismatch indicates an incomplete commit.

## Bun-specific reminders

- Prefer `Bun.file`, `Bun.spawn`, `Bun.password`, `Bun.serve` over Node equivalents when the runtime is Bun.
- `bun:test` does not need `await` for asynchronous expectations using `expect().resolves.toBe(...)`.
- `Bun.env` is available alongside `process.env`; both are readable.
- `Bun.spawn(["cmd", ...args])` takes an array — pass user input as `args[i]`, never as part of the binary string.

## Test smell sweep

```bash
# Test files with no assertions
rg -L '(expect\(|assert\.|t\.)' --glob '**/*.{spec,test}.{ts,tsx}'

# Skipped / focused tests in the diff
rg -n '(\.skip\(|\.only\(|\bdescribe\.skip\b|\bit\.skip\b|\btest\.skip\b)' --type ts --type tsx

# `console.log` in tests (debugging leftover)
rg -n 'console\.log' --glob '**/*.{spec,test}.{ts,tsx}'
```

## Performance sweep

```bash
# `await` in a loop (see #6)
rg -n -C 3 'for .*\{|await\b' --type ts --type tsx

# Sync FS in handlers
rg -n '(readFileSync|writeFileSync|statSync|existsSync)' --type ts --type tsx

# Large `JSON.stringify` on hot paths
rg -n 'JSON\.stringify\(' --type ts --type tsx --glob '!**/*test*'

# React: unstable inline object/function as prop
rg -n '<\w+\s+\w+=\{\{' --type tsx     # candidate; manual review needed
```

## Hand-off triggers

- Next.js App Router code (RSC, Server Actions, Route Handlers) → `@code-security-review` (Next branch — `references/nextjs/`) for security; `@code-review` (`references/NEXTJS.md`) for performance.
- API security review (design + active testing) → `@code-security-review` (TypeScript Bun/Elysia patterns in the generic flow).
- Refactor / clean-code → `@clean-code` with [TYPESCRIPT reference](../../clean-code/references/TYPESCRIPT.md) or [BUN reference](../../clean-code/references/BUN.md).
- Runtime exception, memory leak, EventLoop stall → `@code-debugger`.

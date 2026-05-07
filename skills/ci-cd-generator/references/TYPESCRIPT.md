> Reference companion for the [ci-cd-generator](../SKILL.md) skill.

# TypeScript Pipeline Template

Generated when Phase 0 detects a `package.json`. Branches on runtime (Node vs Bun) and package manager (pnpm / npm / yarn / bun).

## Detection summary

| Lockfile | Runtime | Package manager | Test runner default |
| --- | --- | --- | --- |
| `bun.lockb` | Bun | bun | bun test (or vitest if configured) |
| `pnpm-lock.yaml` | Node | pnpm | vitest (preferred) or jest |
| `yarn.lock` | Node | yarn | jest or vitest |
| `package-lock.json` | Node | npm | jest or vitest |
| Multiple lockfiles | Conflict — abort | — | — |

If multiple lockfiles exist, the generator stops and asks the user which to keep before proceeding. Two lockfiles in the same project is a known footgun.

## Tooling matrix

| Concern | Tool | Action |
| --- | --- | --- |
| Runtime | `actions/setup-node@v4` or `oven-sh/setup-bun@v2` | reads `engines.node` if present |
| Package manager | `pnpm/action-setup@v4` (when pnpm) | otherwise the runtime ships its own |
| Type-check | `tsc --noEmit` | full project compile |
| Lint | `eslint` | `--max-warnings 0` |
| Format | `prettier --check` | `--check .` |
| Test (unit) | `vitest` or `jest` | leak-detection flags ON |
| Test (integration) | same runner, separate config | DB queries asserted |
| Coverage | `vitest --coverage` / `jest --coverage` | threshold ≥ 60% |
| Bundle size | `size-limit` | optional gate |
| SCA (audit) | `pnpm audit` / `bun pm audit` / `npm audit` | `--audit-level=high` |
| Build | runner-specific | `tsc -b` or framework-specific |

## Canonical workflow — Node + pnpm + Vitest

```yaml
name: ci

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

env:
  COVERAGE_MIN: "60"

jobs:
  meta:
    name: actionlint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: rhysd/actionlint@v1

  setup:
    needs: meta
    runs-on: ubuntu-latest
    outputs:
      node-version: ${{ steps.node.outputs.node-version }}
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
        with:
          version: 9
      - uses: actions/setup-node@v4
        id: node
        with:
          node-version-file: '.nvmrc'
          cache: 'pnpm'
      - run: pnpm install --frozen-lockfile
      - uses: actions/upload-artifact@v4
        with:
          name: node_modules
          path: node_modules
          retention-days: 1
          if-no-files-found: error

  lint:
    needs: setup
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
        with: { version: 9 }
      - uses: actions/setup-node@v4
        with:
          node-version-file: '.nvmrc'
          cache: 'pnpm'
      - run: pnpm install --frozen-lockfile
      - run: pnpm run typecheck    # tsc --noEmit
      - run: pnpm run lint         # eslint --max-warnings 0
      - run: pnpm run format:check # prettier --check .

  test:
    needs: setup
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
        with: { version: 9 }
      - uses: actions/setup-node@v4
        with:
          node-version-file: '.nvmrc'
          cache: 'pnpm'
      - run: pnpm install --frozen-lockfile
      - name: vitest with leak detection
        run: pnpm vitest run --coverage --logHeapUsage --isolate
        env:
          NODE_OPTIONS: --max-old-space-size=4096
      - name: coverage gate
        run: |
          pct=$(jq '.total.lines.pct' coverage/coverage-summary.json)
          echo "coverage=$pct%"
          awk -v p="$pct" -v min="$COVERAGE_MIN" 'BEGIN{
            if (p+0 < min+0) { print "::error::coverage "p"% < min "min"%"; exit 1 }
          }'
      - uses: actions/upload-artifact@v4
        with:
          name: coverage-${{ github.sha }}
          path: coverage/

  pbt:
    needs: setup
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
        with: { version: 9 }
      - uses: actions/setup-node@v4
        with:
          node-version-file: '.nvmrc'
          cache: 'pnpm'
      - run: pnpm install --frozen-lockfile
      - name: property-based concurrent tests (fast-check)
        run: pnpm test:pbt
        continue-on-error: true   # remove once PBT tests exist

  security:
    needs: setup
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
        with: { version: 9 }
      - uses: actions/setup-node@v4
        with:
          node-version-file: '.nvmrc'
          cache: 'pnpm'
      - run: pnpm install --frozen-lockfile
      - name: pnpm audit
        run: pnpm audit --prod --audit-level=high

  build:
    needs: [lint, test, security]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
        with: { version: 9 }
      - uses: actions/setup-node@v4
        with:
          node-version-file: '.nvmrc'
          cache: 'pnpm'
      - run: pnpm install --frozen-lockfile
      - run: pnpm build
```

Required secrets: none for the canonical workflow.

## Bun variant

When `bun.lockb` is present, the workflow uses `oven-sh/setup-bun@v2` and Bun's native test runner. Key differences:

```yaml
jobs:
  setup:
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2
        with:
          bun-version: latest
      - run: bun install --frozen-lockfile

  test:
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2
      - run: bun install --frozen-lockfile
      - name: bun test
        run: bun test --coverage
        env:
          BUN_INSTALL_GLOBAL: /tmp/bun-global

  security:
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2
      - run: bun install --frozen-lockfile
      - run: bun pm audit
```

Bun's test runner does not yet support Jest's `--detectOpenHandles --detectLeaks` flags. For projects that need leak detection on a Bun project, route the test job through Vitest (which works under Bun) instead of `bun test`.

## Memory leak detection

The owner's note prescribes Jest's `--detectOpenHandles --detectLeaks` flags. Vitest equivalents:

| Concern | Jest flag | Vitest equivalent |
| --- | --- | --- |
| Open handles (DB conn, sockets) | `--detectOpenHandles` | `--reporter=verbose` + `--isolate` (default) |
| Heap inflation between tests | `--detectLeaks` | `--logHeapUsage` (annotate; manual threshold check) |
| Sequential isolation | `--runInBand` | `--no-file-parallelism` (or `--isolate`, default) |

Jest variant of the test step:

```yaml
- name: jest with leak detection
  run: pnpm jest --detectOpenHandles --detectLeaks --runInBand --coverage
```

Both runners surface failures as red CI; the workflow does not need to interpret the output beyond the runner's exit code.

## N+1 detection template

For Prisma:

```ts
// tests/utils/capture-queries.ts
import { Prisma } from "@prisma/client";

export async function captureQueries(fn: () => Promise<unknown>) {
  const events: Prisma.QueryEvent[] = [];
  const handler = (e: Prisma.QueryEvent) => events.push(e);
  prisma.$on("query", handler);
  try {
    await fn();
  } finally {
    // prisma's $on does not expose a remove method; reset between tests via a fresh client
  }
  return events;
}
```

```ts
// tests/integration/users.test.ts
import { test, expect } from "vitest";
import { captureQueries } from "../utils/capture-queries";

test("GET /users fires at most 3 queries", async () => {
  const queries = await captureQueries(() =>
    request(app).get("/users").expect(200)
  );
  expect(queries.length).toBeLessThanOrEqual(3);
});
```

For Drizzle ORM, replace the `$on("query", ...)` plumbing with `db.execute` instrumented via `logger:` option. Pattern is identical: count, assert.

The pipeline picks up the assertion through the standard `test` job — no separate workflow needed.

## Bundle size guard (optional)

When `size-limit` is in the project, add a job:

```yaml
size:
  needs: setup
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: pnpm/action-setup@v4
      with: { version: 9 }
    - uses: actions/setup-node@v4
      with: { node-version-file: '.nvmrc', cache: 'pnpm' }
    - run: pnpm install --frozen-lockfile
    - uses: andresz1/size-limit-action@v1
      with:
        github_token: ${{ secrets.GITHUB_TOKEN }}
```

The action posts a PR comment with size delta and fails when the configured budget is exceeded.

## Load testing with Artillery

Artillery is the alternative to k6 documented in the owner's notes. Equivalent `nightly-load.yml`:

```yaml
name: nightly-load
on:
  schedule:
    - cron: "0 4 * * *"
  workflow_dispatch:

jobs:
  artillery:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: npm install -g artillery@latest
      - run: artillery run tests/load/scenarios.yml
        env:
          TARGET_URL: ${{ secrets.STAGING_URL }}
          TARGET_TOKEN: ${{ secrets.STAGING_TOKEN }}
```

## Caveats

- `pnpm install --frozen-lockfile` is mandatory in CI. Plain `pnpm install` updates the lockfile if it drifts, which silently masks the drift in PRs.
- Cache key uses the lockfile hash automatically via `cache: 'pnpm'`. Manual `actions/cache` is rarely needed.
- The `setup` job exists to install once and share `node_modules` via artifact when `node_modules` is large; for small projects, skip it and let each job install in parallel — the cache restore is fast.
- `--logHeapUsage` produces one line per test file. On large suites, the log volume can crowd out other annotations. Filter with `| grep MB` if needed.
- For Next.js projects, the framework's own `next build` warns on common misconfigurations; do not duplicate those checks here. See `@code-security-review` (Next branch — `references/nextjs/`) for Next-specific security checks the pipeline should call.
- Bun's `audit` is newer than npm/pnpm's; verify exit codes match expectations during the first run on a project with known vulnerabilities.

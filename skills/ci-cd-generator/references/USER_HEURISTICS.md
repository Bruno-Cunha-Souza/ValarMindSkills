> Reference companion for the [ci-cd-generator](../SKILL.md) skill.

# User Heuristics

The five opinionated checks the generator emits by default. Each one is sourced from the project owner's vault notes and is treated as a hard default — included unless the user opts out explicitly during Phase 1.

The rationale matters: when a heuristic catches something in the field, the failure message should point at the underlying intent, not the mechanism.

## 1. Coverage gate

**Why.** Unit tests are the foundation of every CI pipeline. The owner's note sets a hard floor of **60% project-wide coverage** and an aspirational ceiling of **80%**, with explicit acknowledgement that large or legacy projects may struggle to reach 80%.

**How to apply.**

- **Hard fail** the pipeline below 60%.
- **Warn (annotate)** between 60% and 80% with a non-blocking annotation.
- **Pass silently** at 80%+.
- Threshold lives in a single env var, not duplicated across jobs.

**Per-language enforcement.**

| Language | Tool | Failure command |
| --- | --- | --- |
| Go | `go test -cover -covermode=atomic -coverprofile=coverage.out ./...` then `go tool cover -func=coverage.out` | `awk '/total:/ {gsub("%",""); if ($3+0 < 60) exit 1}' coverage.out` |
| Rust | `cargo llvm-cov --workspace --lcov --output-path lcov.info` | `cargo llvm-cov report --fail-under-lines 60` |
| TypeScript | `vitest run --coverage --coverage.thresholds.lines=60` (or `jest --coverage --coverageThreshold='{"global":{"lines":60}}'`) | (built into the runner) |

**Snippet (env-var driven).**

```yaml
env:
  COVERAGE_MIN: "60"
  COVERAGE_TARGET: "80"

steps:
  - name: enforce coverage
    run: |
      pct=$(awk '/^total:/ {gsub("%",""); print $3}' coverage.out)
      echo "coverage=$pct%"
      awk -v p="$pct" -v min="$COVERAGE_MIN" -v tgt="$COVERAGE_TARGET" 'BEGIN{
        if (p+0 < min+0) { print "::error::coverage "p"% < min "min"%"; exit 1 }
        if (p+0 < tgt+0) { print "::warning::coverage "p"% < target "tgt"%" }
      }'
```

## 2. N+1 detection

**Why.** N+1 is a silent performance anti-pattern: 1 query for the list, then N queries (one per row) for related data. The owner's note is explicit that this fails silently in tests but tanks production. The CI gate must catch it before merge.

**How to apply.**

Two complementary mechanisms:

1. **Query-count middleware** (runtime, dev-only). Logs queries per HTTP request. Threshold: more than **10 queries on a simple `GET`** triggers a failure or alert.
2. **Integration-test assertion**. The test asserts an upper bound on queries per endpoint: *"this request fires at most 3 queries"*. If a future change introduces an N+1, the assertion fails in CI.

The mechanism the pipeline emits is the **integration-test assertion** — the middleware is shipped with the application code, not the workflow.

**Per-language template.**

### Go (using `gorm.io/gorm` + `prometheus/client_golang` for query counting)

```go
// integration_test.go
func TestGetUsers_QueryCount(t *testing.T) {
    db := newTestDB(t)
    counter := installQueryCounter(db)

    req := httptest.NewRequest("GET", "/users", nil)
    rec := httptest.NewRecorder()
    handler.ServeHTTP(rec, req)

    if got := counter.Count(); got > 3 {
        t.Fatalf("N+1 suspected: %d queries (max 3)", got)
    }
}
```

### TypeScript (Prisma)

```ts
// integration.test.ts
import { test, expect } from "vitest";
import { prisma, captureQueries } from "./test-utils";

test("GET /users fires at most 3 queries", async () => {
  const queries = await captureQueries(() =>
    request(app).get("/users").expect(200)
  );
  expect(queries.length).toBeLessThanOrEqual(3);
});
```

### Rust (sqlx)

`sqlx` exposes a logger; wrap it in a counter and assert in `#[tokio::test]`. Example template lives in [RUST.md](RUST.md#n1-detection-template).

**Workflow integration.** The N+1 tests run inside the standard `test` job — no separate job needed. The pipeline is configured to surface query counts as annotations on failure.

## 3. Race condition — Property-Based Testing (PBT)

**Why.** Race conditions are timing-dependent: code works in single-threaded tests and breaks under concurrent load. The owner's note describes Concurrent PBT as the right shape: a framework generates **random sequences of commands** and runs them in **parallel threads**, looking for a property violation (e.g., *"inventory balance is never negative"*).

**How to apply.**

| Language | Library | What CI runs |
| --- | --- | --- |
| Go | Built-in `go test -race` (data-race detector) + `pgregory.net/rapid` for concurrent PBT | `go test -race -count=1 ./...` and a separate `go test -tags=pbt -timeout=10m ./...` job |
| Rust | `proptest` + `loom` for concurrent state-machine tests | `cargo test --release` and `RUSTFLAGS="--cfg loom" cargo test --test loom_tests` |
| TypeScript | `fast-check` with `fc.assert(fc.asyncProperty(...))`; spawn N async workers | `pnpm test:pbt` (separate script) |

**Workflow snippet (Go reference).**

```yaml
race-pbt:
  runs-on: ubuntu-latest
  needs: meta
  steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-go@v5
      with:
        go-version-file: go.mod
        cache: true
    - name: race detector
      run: go test -race -count=1 -timeout=5m ./...
    - name: property-based concurrent tests
      run: go test -tags=pbt -timeout=10m ./...
```

If the project does not yet have property-based tests, the generator emits the job anyway with a `continue-on-error: true` flag and a header comment explaining the next step. This gives the test surface an obvious place to grow.

## 4. Memory leak detection

**Why.** Memory leaks accumulate silently and surface only in production after hours of uptime. The owner's note prescribes two layers: **test-time leak detection** (catches leaks introduced by new code) and **runtime memory limits** (auto-restart in containers when a leak escapes).

The pipeline owns the test-time layer.

**How to apply.**

| Language | Test-time tool | CI command |
| --- | --- | --- |
| TypeScript (Jest) | `--detectOpenHandles --detectLeaks` | `jest --detectOpenHandles --detectLeaks --runInBand` |
| TypeScript (Vitest) | `--reporter=verbose --logHeapUsage` + `--isolate` | `vitest run --logHeapUsage --isolate` |
| Go | `-race` (catches goroutine leaks indirectly) + `uber-go/goleak` in `TestMain` | `go test -race ./...` + dedicated `go test -run TestNoGoroutineLeak ./...` |
| Rust | `cargo miri test` (slow; opt-in nightly job) | `rustup +nightly component add miri && cargo +nightly miri test` |

**Workflow snippet (TypeScript / Jest).**

```yaml
test:
  steps:
    - run: pnpm jest --detectOpenHandles --detectLeaks --runInBand --coverage
    # Failure modes the workflow surfaces in annotations:
    #   - open db connection at end-of-test
    #   - dangling setTimeout / setInterval
    #   - heap inflation between tests above threshold
```

The runtime layer (Docker/Kubernetes memory limits with auto-restart) is documented in the owner's note but is **out of scope for this skill** — it lives in the deployment manifest, not the workflow.

## 5. Load testing — opt-in

**Why.** Load tests stress the system with k6 or Artillery to surface concurrency bugs (race conditions under realistic load), latency regressions, and breaking points. The owner's note lists k6 and Artillery as the preferred tools.

**How to apply.**

Load tests are **off by default** because:

- They are slow (minutes per run)
- They consume CI minutes
- They require a deployed target (staging URL) which not every project has

When the user opts in (`load_tests: true` in Phase 1), the generator emits a dedicated workflow file: `.github/workflows/nightly-load.yml`.

```yaml
name: nightly-load
on:
  schedule:
    - cron: "0 4 * * *"   # 04:00 UTC daily
  workflow_dispatch:

jobs:
  k6:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: grafana/setup-k6-action@v1
      - name: smoke (1 VU, 30s)
        run: k6 run --vus 1 --duration 30s tests/load/smoke.js
      - name: ramp (50 VUs, 5min)
        run: k6 run --vus 50 --duration 5m tests/load/ramp.js
        env:
          K6_BASE_URL: ${{ secrets.STAGING_URL }}
```

Artillery alternative is documented in [TYPESCRIPT.md](TYPESCRIPT.md#load-testing-with-artillery).

The job consumes `secrets.STAGING_URL` and `secrets.STAGING_TOKEN`; both are listed in the generation report so the user can configure them before the first nightly run.

## Override flags

Each heuristic can be turned off via Phase 1 input. The generator records the override in a header comment of the emitted YAML so future readers know why a default is missing.

| Override | Effect |
| --- | --- |
| `coverage: ignore` | Coverage gate omitted; warning printed in report |
| `n1: false` | N+1 assertion template not seeded into integration tests |
| `race: false` | Race-PBT job dropped; `-race` flag still kept in Go |
| `leak: false` | Jest/Vitest leak flags removed; `goleak` job dropped |
| `load: true` | Adds `nightly-load.yml` (off by default) |

If a user disables more than two heuristics, the generator surfaces a single warning in the report: *"3 of 5 default heuristics disabled — pipeline coverage may be insufficient."* No further action.

## Source

The owner's documented preferences live in the Obsidian vault at `Notes/Deploy/CI & CD.md` and `Notes/Deploy/Deploy.md`. The generator does **not** read those files at runtime — they are the source of truth for the heuristics encoded here, frozen at the time the skill was authored. Update this file when the source notes evolve.

---
name: code-optimization
description: "Lifecycle performance & efficiency review Go/Rust/TypeScript/Python (FastAPI/Django/Flask/Gin/Fiber/fx/Elysia/Bun/Node/Axum/Actix). Auto-detects toolchain, profiles, sweeps for duplication/leaks/N+1/CPU-bound/blocking I/O, classifies findings by Impact x Risk x Effort (tri-axis), writes OPTIMIZATION_REPORT.md at project root. Optional WebSearch + context7 validation for High/Critical findings. Read-only on code — every finding cites file:line. Triggers: 'optimize code', 'otimizar código', 'auditar performance', 'performance review', 'find bottlenecks', 'analisar gargalos', '/code-optimization'."
source: ValarMindSkills
---

# Code Optimization Lifecycle

> "Premature optimization is the root of all evil. Yet that does not mean we should ignore opportunities for optimization." — Donald Knuth

This skill conducts a structured, evidence-first **performance and efficiency** audit. It is **read-only on source code** — it never edits production code, but it writes a single report file (`OPTIMIZATION_REPORT.md`) at the project root. It is **language-aware** for Go (Gin/Fiber/fx), Rust (Axum/Actix/Tokio), TypeScript (Node/Bun/Elysia/Fastify), and Python (FastAPI/Django/Flask, CPython 3.13 / 3.14 including free-threaded 3.14t). It is **lifecycle-driven**: detect → triage → sweep → read → validate → classify → report.

The skill exists because **performance findings are the most prone to hallucination**: invented latency numbers, guessed bottlenecks, untested allocation claims. Every constraint pushes the reviewer to cite file:line, quote tool output, and grade Impact / Risk / Effort separately so the user can prioritize without re-reading the entire diff.

This skill is the perf-focus sibling to `@code-review` (broad), `@code-security-review` (security-focus), and `@code-debugger` (runtime). Coexists with them.

## When to Use

- **Latency regression** detected in staging / production — find the cause, prioritize the fix.
- **Cost reduction** — cloud bill driven by CPU, memory, or DB calls; find waste.
- **Pre-release perf gate** — confirm the build matches the SLO targets before tagging.
- **Post-incident sweep** — after an OOM, connection pool exhaustion, or thundering herd, audit related code for similar latent issues.
- **Refactor planning** — quantify perf debt before deciding scope.
- **Greenfield review** — ensure the new module does not bake in N+1, blocking I/O, or unbounded growth.
- The user explicitly asks: `'optimize code'`, `'otimizar código'`, `'performance review'`, `'auditar performance'`, `'find bottlenecks'`, `'analisar gargalos'`, or invokes `/valarmindskills:code-optimization`.

## Do not use when

- The user wants to **fix correctness bugs** (panic, wrong output, race that corrupts state) — use `@code-debugger`.
- The user wants a **security audit** — use `@code-security-review`. A perf finding that overlaps security (e.g., DoS via unbounded query) is reported here AND cross-linked to `@code-security-review`.
- The user wants a **generic PR review** covering correctness + style + security — use `@code-review` (perf appears in Phase 4 there, but shallow).
- The user wants pure **refactoring for readability** without perf motivation — use `@clean-code`.
- The diff is a single typo, comment edit, or trivial rename — overhead exceeds value; tell the user and stop.
- The project is in a language the skill does not cover (not Go, Rust, TypeScript, or Python). Surface the gap and ask whether the user wants a generic principles-only pass.

## Prerequisites

Each tool's absence is logged and the related Phase degrades but is never silently skipped. Default mode is **static perf review**: read sources, run linters, run language profilers when the user authorizes. Live benchmarking and load testing are **optional verification**, not part of the default review.

| Tool | Language | Purpose |
| --- | --- | --- |
| `git`, `gh`, `rg`, `fd` | all | Diff inspection, pattern sweep, file finder |
| `jscpd` | all | Multi-language clone detection (duplication audit) |
| `go test -bench` + `pprof` (`go tool pprof`) | Go | CPU / alloc / goroutine / mutex / block profiling |
| `go build -gcflags='-m'` | Go | Escape analysis |
| `dupl` | Go | Go-specific duplication |
| `cargo flamegraph` + `criterion` + `cargo bloat` | Rust | CPU flamegraph, micro-benchmark, binary size attribution |
| `cargo-machete` + `cargo-udeps` | Rust | Unused deps |
| `clinic.js` (`doctor`/`flame`/`bubbleprof`/`heapprofile`) | Node | Event-loop, CPU flame, async, heap |
| `bun --hot` + `Bun.nanoseconds()` | Bun | Native micro-bench |
| `knip` | TS | Unused exports / files / deps |
| `cProfile` + `py-spy` + `line_profiler` + `tracemalloc` + `pytest-memray` | Python | CPU sampling, line-level, alloc tracing |
| `pytest --benchmark` (`pytest-benchmark`) | Python | Micro-bench |
| `WebSearch` + context7 MCP (Claude Code: `mcp__context7__resolve-library-id` + `mcp__context7__query-docs`; Cursor: `CallMcpTool` on server `user-context7` with `resolve-library-id` / `query-docs`) | all | Phase 4 conditional validation. If context7 is not configured on the host, Phase 4 falls back to WebSearch only — document the gap in the report's `external validation:` field. |

Required access:

- [ ] Read access to the repo and the diff
- [ ] Permission to invoke linters, profilers, and dependency scanners on the host
- [ ] **Permission to write `OPTIMIZATION_REPORT.md` at project root** — this is the only write this skill performs
- [ ] Explicit user request before running live benchmarks or load tests

The skill does **not** require write access to source files. It never commits, never pushes, never edits source code.

## Phase 0 — Project & Documentation Detection

Detect language, framework, package manager. Read project docs (README, ARCHITECTURE, ADR, CONTRIBUTING) **before** any sweep — assumptions about hot paths or perf targets without docs lead to inflated findings.

```bash
# Step 1 — language at the repo root
test -f go.mod        && echo "language: go"
test -f Cargo.toml    && echo "language: rust"
test -f package.json  && echo "language: typescript"
{ test -f pyproject.toml || test -f requirements.txt || test -f setup.py; } && echo "language: python"

# Step 2 — framework (single most authoritative match wins)
case "$LANG" in
  go)
    rg -q 'gin-gonic/gin'       go.mod && echo "framework: gin"
    rg -q 'gofiber/fiber/v[23]' go.mod && echo "framework: fiber"
    rg -q 'go.uber.org/fx'      go.mod && echo "framework: fx (DI)"
    ;;
  rust)
    rg -q '\baxum\b'      Cargo.toml && echo "framework: axum"
    rg -q '\bactix-web\b' Cargo.toml && echo "framework: actix"
    rg -q '\brocket\b'    Cargo.toml && echo "framework: rocket"
    ;;
  typescript)
    test -f bun.lockb         && echo "runtime: bun"
    test -f package-lock.json && echo "runtime: node, pm: npm"
    test -f pnpm-lock.yaml    && echo "runtime: node, pm: pnpm"
    rg -q '"elysia"'  package.json && echo "framework: elysia"
    rg -q '"fastify"' package.json && echo "framework: fastify"
    rg -q '"express"' package.json && echo "framework: express"
    rg -q '"hono"'    package.json && echo "framework: hono"
    ;;
  python)
    test -f uv.lock       && echo "pm: uv"
    test -f poetry.lock   && echo "pm: poetry"
    test -f Pipfile.lock  && echo "pm: pipenv"
    rg -q '(^|[[:space:]"])fastapi[>=<~!"[:space:]]' pyproject.toml requirements*.txt 2>/dev/null && echo "framework: fastapi"
    rg -q '(^|[[:space:]"])django[>=<~!"[:space:]]'  pyproject.toml requirements*.txt 2>/dev/null && echo "framework: django"
    rg -q '(^|[[:space:]"])flask[>=<~!"[:space:]]'   pyproject.toml requirements*.txt 2>/dev/null && echo "framework: flask"
    ;;
esac

# Step 3 — project documentation (read before sweeping)
fd -t f -i -d 3 '(README|ARCHITECTURE|ADR|CONTRIBUTING|PERFORMANCE|BENCHMARKS)' .
```

Persist as `$LANG ∈ {go, rust, typescript, python}`, `$FRAMEWORK`, `$PM`, `$RUNTIME` (TS only).

| `$LANG` | Reference to load | Primary profiler |
| --- | --- | --- |
| `go` | [references/GOLANG.md](references/GOLANG.md) | `go test -bench` + `pprof` |
| `rust` | [references/RUST.md](references/RUST.md) | `cargo flamegraph` + `criterion` |
| `typescript` | [references/TYPESCRIPT.md](references/TYPESCRIPT.md) | `clinic.js` (Node) / `Bun.nanoseconds()` (Bun) |
| `python` | [references/PYTHON.md](references/PYTHON.md) | `py-spy` + `cProfile` + `tracemalloc` |

Cross-cutting refs are always loaded:

- [references/DUPLICATION.md](references/DUPLICATION.md) — DRY violations, duplicate detection (jscpd, dupl, cargo-duplicates, eslint-plugin-sonarjs), Rule of Three.
- [references/RESOURCES.md](references/RESOURCES.md) — memory leaks, CPU-bound, file/socket leaks, goroutine/task leaks, connection pool exhaustion.
- [references/CALLS.md](references/CALLS.md) — N+1, async batching, caching strategies, dataloader, HTTP keep-alive, serialization hot paths.

If no documentation exists, infer conventions from `git log --oneline -20`, top-level directory layout, and CI config. Document the inference in the Phase 6 report under `assumptions:`.

## Phase 1 — Scope & Module Triage

Count files and lines of code in the target. Large projects must be sliced into modules before review — sweeping a 50k-LOC monolith dilutes attention and amplifies hallucination risk.

```bash
fd -t f -e go -e rs -e ts -e tsx -e py -d 10 . | wc -l                          # total source files
fd -t f -e go -e rs -e ts -e tsx -e py -d 10 -x wc -l {} + | tail -1            # total LOC

# Module candidates
fd -t d -d 3 '^(cmd|internal|pkg|src|api|app|services?|core|domain)$' .
```

| Project size | Action |
| --- | --- |
| ≤ 100 files **and** ≤ 20k LOC | Sweep the whole project in one pass |
| > 100 files **or** > 20k LOC | List discovered modules, propose top 3–5 candidates (the ones changed most recently per `git log` OR named in `--scope` arg), ask user to confirm scope before continuing |
| > 500 files **or** > 100k LOC | Refuse a full sweep — require explicit module list |

Stop the phase here and confirm with the user when triage is required.

## Phase 2 — Static & Profile Sweep

Run the static perf-aware toolchain. Treat results as **leads**, never as conclusions. Calibration: every automated finding starts at **Medium** Impact; promotion to High / Critical requires manual evidence in Phase 3 (a quoted code path) or Phase 4 (external validation).

```bash
# Polyglot duplication (always)
jscpd --min-lines 5 --min-tokens 50 .

# Go — static (always; no consent needed)
go build -gcflags='-m=2' ./...                                                  # escape analysis → heap allocations
go vet ./...
golangci-lint run ./...
staticcheck ./...
dupl -t 50 ./...
# Optional with user consent (live profiling — may be slow on monorepos):
# go test -bench=. -benchmem -cpuprofile=/tmp/cpu.pprof -memprofile=/tmp/mem.pprof ./...
# go tool pprof -top -cum /tmp/cpu.pprof | head -30

# Rust
cargo build --release --timings                                                 # compile-time + dep graph
cargo clippy --all-targets -- -D warnings -W clippy::pedantic
cargo bloat --release --crates -n 30                                            # binary attribution
cargo machete                                                                   # unused deps
# Optional with user consent: cargo flamegraph -- <bench>

# TypeScript / Node / Bun
bunx tsc --noEmit
bunx knip
# Optional: clinic doctor -- node dist/server.js  (interactive, user runs)

# Python
ruff check . --select=PERF,SIM,B,C90                                            # PERF rules + complexity (ruff)
mypy --strict .                                                                 # type info catches inefficient typing
# Optional with user consent: py-spy record -d 30 -o /tmp/profile.svg -- python -m <app>
# Optional: pytest --benchmark-only --benchmark-save=baseline
```

Capture every tool's version (`<tool> --version`) and embed it in the report under `tools:`. A finding without a tool version is not reproducible.

## Phase 3 — Manual Read + Pattern Sweep

Read the targeted modules with perf eyes. The automated tools see syntax; only the reader sees intent.

### 3.1 Read order

1. **Hot path entry points** — request handlers, controllers, queue consumers.
2. **DB layer** — repositories, ORM queries, raw SQL.
3. **Loop-heavy logic** — batch jobs, transforms, serializers.
4. **External I/O** — HTTP clients, message brokers, cache clients.
5. **Concurrency primitives** — goroutines/tasks/threads/Promises, locks, channels.

### 3.2 Per-category sweeps

For each, run the per-language grep (`$LANG` reference file has the exact commands) plus the cross-cutting reference:

| Category | Cross-cutting ref | Per-language ref |
| --- | --- | --- |
| Duplication | [DUPLICATION.md](references/DUPLICATION.md) | language refs §Duplication |
| Resource leaks (memory, FD, goroutine, task, connection pool) | [RESOURCES.md](references/RESOURCES.md) | language refs §Resources |
| Call efficiency (N+1, batching, caching, serialization) | [CALLS.md](references/CALLS.md) | language refs §Calls |
| Language-specific hot-path antipatterns | — | language refs §Hot Path |

Every finding must include: `file:line`, a quoted code block (verbatim from the file), the anti-pattern category, the suggested change, and a draft tri-axis grade (Impact / Risk / Effort). Findings without all five fields are dropped at Phase 5.

### 3.3 Read-through questions

For each hot path read, answer:

- What does this code take in the **worst case** — time, memory, allocations? Quote the structures it iterates.
- Where does an **unbounded** input come from? (request body, DB row count, file size, message size)
- Could this be **batched** instead of done in a loop?
- Could this be **cached** safely? What is the cache key, TTL, invalidation?
- What resource is acquired? Is it released on the **error path** as well as the success path?
- Could this **block** the event loop / goroutine pool / async runtime?
- What is the **serialization cost** of the response? Is the dataset bounded?

A finding is born only when the answer reveals a concrete cost AND the evidence is in the code. Hallucinations are findings born without both.

## Phase 4 — External Validation (conditional)

**Trigger:** any draft finding with `Impact >= High AND Confidence < High`. Other findings skip this phase.

For each triggered finding:

1. **WebSearch** the anti-pattern in the context of the framework. Example queries:
   - `"FastAPI N+1 query SQLAlchemy 2.0 selectinload best practice"`
   - `"Go sync.Pool when not to use 2026"`
   - `"Rust tokio multi-thread runtime cost vs current-thread"`
2. **context7** for the specific library — invocation differs by harness:
   - **Claude Code:** `mcp__context7__resolve-library-id` with the library name, then `mcp__context7__query-docs` with the anti-pattern question.
   - **Cursor:** `CallMcpTool` on server `user-context7` with method `resolve-library-id`, then `query-docs`.
   - If context7 is not configured on the host, fall back to WebSearch only and record `external validation: web-only` in the report's Context section.
   Cite the doc snippet in the finding.
3. Promote `Confidence` to High if both sources agree, or demote to Low and rewrite the finding (or drop it) if they contradict the draft.

Findings that pass validation include the citation in their detail block (`Validation: context7 /sqlalchemy/sqlalchemy §loading.html ...` or `WebSearch: <url>`).

Findings that fail validation are either dropped or rewritten as `Info` observations.

This phase is **opt-out by default per-finding** — skip when the user passed `--no-validate` or when every High/Critical draft already has High confidence from Phase 3 evidence.

## Phase 5 — Classification & Synthesis

Grade every surviving finding on three axes per [references/SEVERITY_RUBRIC.md](references/SEVERITY_RUBRIC.md).

### 5.1 Tri-axis matrix

| Axis | Values | Calibrator |
| --- | --- | --- |
| **Impact** | Critical / High / Medium / Low | Latency delta (ms), throughput, cost ($/mo), memory delta (MB) — quote the units |
| **Risk** | SAFE / REVIEW / BREAKING | Same definition as `@code-review`: SAFE = no observable change, REVIEW = touches boundary or shared util, BREAKING = signature/schema/response changes |
| **Effort** | S (< 1h) / M (1–8h) / L (> 1 day) | Lines to touch + tests to write + surface affected |

### 5.2 Priority quadrants

- **Quick wins** — `Impact ∈ {Critical, High}` AND `Effort = S`. Top of the report.
- **Strategic** — `Impact ∈ {Critical, High}` AND `Effort ∈ {M, L}`. Plan and schedule.
- **Polish** — `Impact ∈ {Medium, Low}` AND `Effort = S`. Tackle opportunistically.
- **Defer / drop** — `Impact = Low` AND `Effort = L`. Drop from the report unless the user explicitly asked to include them.

### 5.3 Confidence tag

- **High** — evidence cited, validation passed (or Phase 4 not required), pattern is well-documented.
- **Medium** — pattern matches but intent could justify it; or validation was skipped.
- **Low** — needs a second opinion; escalate explicitly when `Confidence = Low AND Impact >= High`.

## Phase 6 — Report Write

Write a single file `OPTIMIZATION_REPORT.md` at the project root via the `Write` tool. Format per [references/REPORT_TEMPLATE.md](references/REPORT_TEMPLATE.md). The file is overwritten on every run (the user versions it via git).

After writing, **print to the terminal** the summary block defined in [Output format](#output-format) so the user can decide whether to open the file.

If `OPTIMIZATION_REPORT.md` already exists and the user has not confirmed overwrite, ask before overwriting. Default to overwrite when the user invoked the skill explicitly.

## Constraints

- **Never edit source code.** This skill writes exactly one file: `OPTIMIZATION_REPORT.md` at the project root. Source files are read-only.
- **Never invent findings to fill the report.** Zero findings is a valid outcome — emit the LGTM block (see [Output format](#output-format)) and stop. Do not promote Low → High to look thorough; do not pad with `Info` observations that are not grounded in a file actually read this run.
- **Never invent a file path, function name, latency number, or library version.** Every fact must come from a file you read or a tool you ran in this session.
- **Never claim a benchmark result without showing the command and the relevant output.** Benchmarks are optional verification, not default review.
- **Never quote a line you did not read.** Open the file at the cited line; the quote in the report must match byte-for-byte.
- **Never inflate Impact.** Use the rubric. Latency claims need a quoted profile or doc citation; "this might be slow" is not a finding.
- **Never list a finding without `file:line`, code quote, Impact, Risk, Effort, and a suggested change.** Drop incomplete findings.
- **Never skip Phase 0 detection.** Sweeping without language confirmation produces wrong-language patterns and false positives.
- **Never write the report without explicit overwrite consent** when `OPTIMIZATION_REPORT.md` already exists with newer content than the last run.
- **Always cap a single sweep at 100 files or 20k LOC** unless the user confirms a larger scope after Phase 1 triage.
- **Always include the tool versions used.** A report without tool versions is not reproducible.
- **Always cross-link to dedicated skills** when a finding belongs to their domain (`@code-security-review` for DoS-class issues, `@code-debugger` for runtime bugs masquerading as perf issues, `@clean-code` for refactor mechanics, `@ci-cd-generator` for CI gates).
- **Always run Phase 4 (external validation)** for any draft finding with `Impact >= High AND Confidence < High` unless `--no-validate` is set.

## Output format

After every run, print this terminal summary verbatim and then point the user to the file:

```text
code-optimization: <branch / scope>
  language(s):    <go | rust | typescript | python>
  framework:      <fastapi | gin | elysia | axum | ... | none>
  runtime:        <bun | node | cpython3.13 | cpython3.14 | cpython3.14t | go1.23+ | rust1.83+>
  pm:             <uv | poetry | pip | bun | pnpm | npm | yarn | go-mod | cargo>
  scope:          <N> files / <M> LOC  (<full | modules: <list>>)
  tools:          jscpd <ver>, py-spy <ver>, ruff <ver>, ...
  validation:     <skipped | N findings cross-validated via web+context7>
  report:         OPTIMIZATION_REPORT.md (written, <N> KB, <M> findings)

Findings summary (tri-axis):
  Impact       Critical: 0   High: 2   Medium: 5   Low: 3
  Effort       S: 4   M: 5   L: 1
  Quick wins (High impact + Low effort):   2  (O001, O004)
  Strategic  (High impact + Med/Large):    1  (O002)

Next steps:
  1. Read OPTIMIZATION_REPORT.md.
  2. Address Quick wins first.
  3. Re-run /code-optimization after fixes to confirm.
```

When there are zero findings, print this instead of inventing minor findings:

```text
Findings summary: 0 findings in scope.
LGTM — no perf issues found in <scope>. OPTIMIZATION_REPORT.md written with LGTM marker.
```

## Related Skills

- `@code-review` — broad PR review; Phase 4 there is perf-light, this skill is the deep-dive companion.
- `@code-security-review` — when a perf finding doubles as a DoS surface (unbounded query, regex catastrophic backtracking, decompression bomb), cross-link.
- `@code-debugger` — runtime bugs (panic, race that corrupts state, hang) are debugger territory; this skill stops at "looks slow / inefficient".
- `@clean-code` — for the refactor mechanics behind a Quick win.
- `@ci-cd-generator` — to turn a Strategic finding into a CI gate (coverage threshold, perf regression check, allocation budget).

## References

- [CHECKLIST](references/CHECKLIST.md) — copy-paste cheat sheet ordered by phase.
- [SEVERITY_RUBRIC](references/SEVERITY_RUBRIC.md) — tri-axis Impact x Risk x Effort calibration, with Quick-wins / Strategic / Polish quadrants.
- [REPORT_TEMPLATE](references/REPORT_TEMPLATE.md) — schema for `OPTIMIZATION_REPORT.md`.
- [DUPLICATION](references/DUPLICATION.md) — DRY, three duplication classes (literal/logical/structural), extract-method/strategy/template-method, when NOT to deduplicate.
- [RESOURCES](references/RESOURCES.md) — memory leaks, CPU-bound, FD/socket leaks, goroutine/task leaks, connection pool exhaustion.
- [CALLS](references/CALLS.md) — N+1, async batching, caching, dataloader, HTTP keep-alive, serialization hot paths.
- [GOLANG](references/GOLANG.md) — Go perf (pprof, sync.Pool, GC tuning, escape analysis, Gin/Fiber/fx routing).
- [RUST](references/RUST.md) — Rust perf (criterion, flamegraph, jemalloc/mimalloc, tokio runtime, Arc/Mutex vs DashMap, zero-cost abstractions verification).
- [TYPESCRIPT](references/TYPESCRIPT.md) — TS/Node/Bun perf (clinic.js, V8 GC, Promise.all batching, Elysia/Fastify routing, worker threads).
- [PYTHON](references/PYTHON.md) — Python 3.13/3.14 perf (cProfile, py-spy, line_profiler, tracemalloc, GIL vs 3.14t free-threaded, uvloop, ORJSONResponse, select_related/prefetch_related/selectinload, __slots__, functools.cache).
- [EXAMPLE](EXAMPLE.md) — end-to-end worked optimization of a FastAPI service with N+1 + tracemalloc + ORJSONResponse fixes.

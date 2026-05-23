> Reference companion for the [code-optimization](../SKILL.md) skill.

# Optimization Checklist

Copy-paste cheat sheet, one block per Phase. Track progress as you walk the lifecycle.

## Phase 0 — Detection

- [ ] Language identified (`go` / `rust` / `typescript` / `python`)
- [ ] Framework identified (FastAPI / Django / Flask / Gin / Fiber / fx / Axum / Actix / Elysia / Fastify / Hono / Express / none)
- [ ] Package manager identified (`uv` / `poetry` / `pip` / `cargo` / `bun` / `pnpm` / `npm` / `yarn` / `go mod`)
- [ ] Runtime version captured (`go.mod` Go version, `Cargo.toml` `rust-version`, `pyproject.toml` `requires-python`, `package.json` `engines`)
- [ ] Project docs read (`README`, `ARCHITECTURE`, `PERFORMANCE`, `BENCHMARKS`, ADRs)
- [ ] SLO / perf target identified (or noted absent under `assumptions:`)

## Phase 1 — Triage

- [ ] File count + LOC computed
- [ ] Scope decided: full sweep / module list / refused (too large)
- [ ] User confirmed scope when ≥ 100 files OR ≥ 20k LOC

## Phase 2 — Static & Profile Sweep

- [ ] Duplication scan run (`jscpd` + language-specific tool)
- [ ] Static perf-aware linter run (`ruff PERF` / `clippy::pedantic` / `staticcheck` / `knip`)
- [ ] CPU profile attempted with user consent (`pprof` / `cargo flamegraph` / `clinic flame` / `py-spy`)
- [ ] Alloc / memory profile attempted with user consent (`pprof -alloc_objects` / `heaptrack` / `clinic heapprofile` / `tracemalloc` / `pytest-memray`)
- [ ] Tool versions recorded for the report

## Phase 3 — Manual Read

- [ ] Hot path entry points walked (handlers, controllers)
- [ ] ORM / data layer walked
- [ ] Loop-heavy code walked
- [ ] External I/O walked (HTTP clients, brokers, caches)
- [ ] Concurrency primitives walked (locks, channels, goroutines, tasks, Promises)
- [ ] Each draft finding has: `file:line`, code quote, category, suggested change, draft tri-axis grade

## Phase 4 — External Validation (conditional)

- [ ] Identified findings with `Impact >= High AND Confidence < High`
- [ ] For each: at least one WebSearch result OR one context7 doc snippet cited
- [ ] Confidence updated based on validation outcome
- [ ] Contradicted draft findings rewritten or dropped

## Phase 5 — Classification

- [ ] Every finding scored on three axes (Impact / Risk / Effort)
- [ ] Confidence tag assigned
- [ ] Findings sorted into quadrants (Quick Win / Strategic / Polish / Defer / Drop)
- [ ] `Confidence=Low AND Impact >= High` findings flagged for human review
- [ ] Cross-link tags added (`@code-security-review` / `@code-debugger` / `@clean-code` / `@ci-cd-generator`)

## Phase 6 — Report

- [ ] `OPTIMIZATION_REPORT.md` overwrite confirmed (when file pre-existed)
- [ ] Report written at project root via `Write` tool
- [ ] Terminal summary printed (Findings summary, Quick wins count, Strategic count, Next steps)
- [ ] Report includes Context section (lang, framework, scope, tools, validation, assumptions)
- [ ] Report uses correct schema per `REPORT_TEMPLATE.md` (H3 per finding in QW/Strategic/Polish; table for Defer/Drop)

## Final pre-emit checks

- [ ] Every finding cites `file:line` (no exceptions)
- [ ] Every code quote matches the file byte-for-byte (re-read on doubt)
- [ ] No invented CVEs / latency numbers / library versions
- [ ] No `Edit` / `Write` calls on source files (only on `OPTIMIZATION_REPORT.md`)
- [ ] Cross-link to related skills (`@code-review`, `@clean-code`, `@code-security-review`, `@code-debugger`, `@ci-cd-generator`) where the finding domain overlaps
- [ ] If `Confidence=Low AND Impact >= High`: escalation phrase present (`needs human review before action`)

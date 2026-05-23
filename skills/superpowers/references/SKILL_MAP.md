# SKILL_MAP — Stage → Skills + Context Triggers

Companion to [SKILL.md](../SKILL.md). This is the **ground truth** the 1% rule scans against. When superpowers is active, walk this map before replying: pick candidates by stage, then narrow by context triggers.

The map is **not** a fence. If a skill applies and is missing here, invoke it anyway and update this file.

## 1. Stage → Skills

Each row: skills marked **default** apply to nearly every task in that stage; skills marked **conditional** activate only when the context triggers in §2 fire.

| Stage | Default | Conditional |
| :--- | :--- | :--- |
| 1. Brainstorm | — | `@skill-creator` (task is "create/edit a skill") |
| 2. Worktree | — | — (handled by harness `EnterWorktree`) |
| 3. Write plan | — | `@skill-creator` (skill authoring); `@context-optimization` (long plan, large surface) |
| 4. Execute / implement | `@clean-code` | `@code-review` (Next.js perf via `references/NEXTJS.md`), `@code-security-review` (Go branch — `references/golang/`; Next branch — `references/nextjs/`), `@code-optimization` (perf focus — bottleneck audit, latency/cost reduction, OPTIMIZATION_REPORT.md), `@ci-cd-generator`, `@obsidian-brain`, `@obsidian-markdown`, `@obsidian-cli`, `@obsidian-bases` (per §2) |
| 5. TDD + debugging | `@code-debugger` (when red/error) | `@code-security-review` (API under test) |
| 6. Request review | `@code-review` *or* `@github-pr-review` | `@code-security-review` (security-sensitive diff — pick the Go or Next branch) |
| 7. Finish branch | `@github-commit` | `@github-release-note` (tag/release in scope) |

Notes:

- `@code-review` = full-detail (lifecycle); `@github-pr-review` = PR-shaped. Pick by artifact (local diff vs GitHub PR). Caveman posture (`/caveman lite|full|ultra`) compresses prose around either skill.
- `@github-commit` = conventional commit from staged diff.
- Stage 2 has no skill — the harness's `EnterWorktree` capability covers it.

## 2. Context Triggers

Rules of the form `IF <signal> → invoke <skill(s)>`. Signals are **detected from the repo / task / error stream**, not asked. When multiple triggers fire, all named skills enter the scan; §3 resolves priority.

### Frontend / Next.js

- `IF` `next.config.{js,ts,mjs}` exists, or task touches `app/`, `pages/`, RSC, Server Actions, route handlers
  → `@code-review` (perf, RSC, rendering strategy via `references/NEXTJS.md`) + `@code-security-review` (Next branch — `references/nextjs/`: Server Actions, route handlers, `proxy.ts`, image optimizer)

### Backend APIs

- `IF` Go module + Gin or Fiber detected (`go.mod` mentions `gin-gonic/gin` or `gofiber/fiber`)
  → `@code-security-review` (Go branch — `references/golang/` for full lifecycle audit)
- `IF` new or modified REST/GraphQL endpoint, regardless of language
  → `@code-security-review` (design phase via `DESIGN_CONTROLS.md` + validation phase via `TESTING_PHASES.md`)
- `IF` API in FastAPI / Bun+Elysia / Gin / Fiber and security focus is "find issues now"
  → `@code-security-review` (active OWASP API Top 10 2023 tests via `TESTING_PHASES.md`)

### CI/CD / GitHub Actions

- `IF` `.github/workflows/` is missing or empty AND project root has `go.mod` / `Cargo.toml` / `package.json`, OR task is "set up CI/CD", "create GitHub Actions workflow", "add CI pipeline", "scaffold pipeline", "criar CI", "gerar pipeline", "configurar CI/CD"
  → `@ci-cd-generator` (phased GitHub Actions generation with documented heuristics: coverage gates, N+1 detection, race condition PBT, memory leak detection, optional load testing — plus SAST/SCA/secret/container/SBOM gates per chosen security level)
- `IF` editing an existing workflow with security-sensitive content (secrets, third-party actions without SHA pin, `pull_request_target`, broad `permissions:`)
  → `@ci-cd-generator` (refactor toward safer defaults) + `@code-security-review` (catalog of supply-chain attack classes via `references/WEB_VULNERABILITIES.md`)

### Performance / Optimization focus

- `IF` task mentions "latency", "slow", "performance", "throughput", "cost reduction", "memory", "memoria", "vazamento", "leak", "otimizar", "bottleneck", "gargalo", "N+1", "profile", "profiling"
  → `@code-optimization` (lifecycle audit; Impact × Risk × Effort tri-axis grading; writes `OPTIMIZATION_REPORT.md` at project root; optional WebSearch + context7 validation for High/Critical findings)
- `IF` repo contains existing profiling/benchmark artifacts (`*.bench.*`, `criterion/`, `flamegraph.svg`, `*.pprof`, `pytest-benchmark.json`) AND user wants prioritization
  → `@code-optimization` (use existing profile as Phase 2 input, skip re-profiling)
- `IF` recent latency incident, OOM, connection-pool exhaustion, or thundering herd
  → `@code-debugger` (root cause first; iron law: no fixes without investigation) **then** `@code-optimization` (preventive sweep after fix lands)

### Generic web vulnerabilities

- `IF` task is "review for vulnerabilities" without a specific framework, or the user asks about vulnerability categories
  → `@code-security-review` (catalog via `references/WEB_VULNERABILITIES.md` + assessment guide via `references/TESTING_PHASES.md`)

### Obsidian

- `IF` `CLAUDE.md` or `AGENTS.md` in cwd (or up to 3 ancestors) references an Obsidian vault
  → `@obsidian-brain` (load index before any project-specific reasoning; session memory across runs)
- `IF` working file is `.md` inside a vault (path contains `ValarMindObsidian/` or sibling vault)
  → `@obsidian-markdown` (OFM syntax: wikilinks, callouts, properties, embeds)
- `IF` task is "operate on the vault" (read/create/search notes from CLI, plugin/theme dev)
  → `@obsidian-cli`
- `IF` working file is `.base` or task creates a database-like view
  → `@obsidian-bases`

### Debugging / errors

- `IF` test failure, exception in log, unexpected runtime behavior
  → `@code-debugger` (root cause first; iron law: no fixes without investigation)

### Context / cost (per-stage gates)

Compact by **numeric trigger**, not by stage boundary — every fence-line `/compact` breaks the prompt cache (5min TTL), and an audit-only skill cannot reduce live context. See [SKILL.md § Context Hygiene](../SKILL.md#context-hygiene) for the full rationale.

- `IF` Stage 3 closed (plan finalized) AND window utilization > 65% OR plan > 30k tokens
  → suggest `/compact` (harness primitive) **before** Stage 4 starts. Preserve plan + spec; drop brainstorm noise.
- `IF` Stage 4 in [SUBAGENT_DRIVEN](SUBAGENT_DRIVEN.md)
  → fresh subagent per task **is** the compaction. Do **not** `/compact` between tasks.
- `IF` Stage 4 batch (~3 tasks) closed in [EXECUTING_PLANS](EXECUTING_PLANS.md) AND utilization > 65% AND next batch is independent
  → suggest `/compact` with explicit preservation hints (last task SHA, tests-passing state).
- `IF` Stage 6 review AND cumulative plan + diff > 100k tokens, OR user reports degradation / cost spike
  → invoke `@context-optimization` once (read-only audit + plan; never auto-applies).
- `IF` general long-running session, many large tool results, RAG pipeline audit
  → `@context-optimization` (Phase 0..6 lifecycle). User-invoked.

### Brain sync (post-Stage 7)

- `IF` Stage 7 ([FINISHING_BRANCH](FINISHING_BRANCH.md)) completed AND the SessionStart digest contained `OBSIDIAN-BRAIN ACTIVE`
  → invoke `@obsidian-brain` Phase 4 (end-of-session sync: append session note, refresh index Recent sessions, suggest topic synthesis if 3+ sessions touch the same topic). Skip silently if the brain is `off` or no vault was detected.

### Skill authoring

- `IF` task is "create a new skill", "scaffold skill", or edit a skill's structure
  → `@skill-creator` (archetypes, frontmatter, references/ layout)

### Voice preference

- `IF` user activated caveman (`/valarmindskills:caveman *`)
  → caveman posture compresses the prose surrounding `@github-commit` / `@github-pr-review` output; the skills themselves keep their format (Conventional Commits, severity-ranked findings)

## 3. Priority resolution

When multiple skills apply, resolve in this order:

1. **Safety / security never yields.** `@*-security-*` and destructive-action confirmations always run before anything else. Process-skills never override security-skills for "speed".
2. **Process > implementation.** `@code-debugger`, `@skill-creator`, and review skills come before commit skills. The wrong implementation done quickly is debt.
3. **Explicit user preference wins.** If the user said "be terse" or activated caveman, the prose around skill output compresses; the skills' artifact format stays. If the user said "no plan", honor it (user-instruction tier of the hierarchy).
4. **Domain skills coexist with process skills.** Stage 4 can run `@clean-code` + `@code-review` (`references/NEXTJS.md`) + `@code-security-review` (Next branch — `references/nextjs/`) + `@code-optimization` together — they cover different concerns and do not compete:
   - `@clean-code` owns maintainability and refactor safety mechanics.
   - `@code-review` owns broad PR review (correctness + security + perf-light Phase 4).
   - `@code-security-review` owns OWASP + active testing + stack-specific vuln catalogs.
   - `@code-optimization` owns deep perf (profiling + tri-axis Impact × Risk × Effort + `OPTIMIZATION_REPORT.md`).

## 4. Maintenance

This map is updated **by hand** when:

- A new skill is added under `skills/` (add a row to §1 or a trigger to §2).
- A skill is renamed (update all references — they are cheap to grep: `rg '@skill-name'`).
- A skill is removed (drop the row/trigger; check `EXAMPLE.md` and `SKILL.md` for stale mentions).

For the canonical authoring flow, see [`skills/skill-creator/SKILL.md`](../../skill-creator/SKILL.md).

When in doubt, prefer false positives (mention a skill that may not apply) over false negatives (skip a skill that does apply). The 1% rule errs on the side of invoking.

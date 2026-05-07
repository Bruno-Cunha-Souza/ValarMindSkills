---
name: context-optimization
description: "Lifecycle context audit/optimize/plan. Audit mode (Phase 0..6) + Guide mode (catalog lookup). Targets long-conv agents, RAG pipelines, sub-agents, large-doc workflows. Detects bloat/dedup/cache/masking/partition opportunities. Emits findings (SAFE/REVIEW/BREAKING) + optimization plan + token delta. Read-only — LGTM if sound. Triggers: 'optimize context', 'compact context', 'auditar contexto', 'otimizar contexto', '/context-optimization'."
source: ValarMindSkills
---

# Context Optimization Lifecycle

Audits and plans optimization for an LLM context (system prompt, tool defs, message history, retrieved chunks, tool outputs). **Two modes**, classified at Phase 0.2: **Audit** (Phase 0..6 lifecycle → 5-block report) when a session/context is pasted; **Guide** (catalog lookup §1..§13) when invoked as a knowledge source. Read-only — never auto-applies. Evidence-first: every finding cites a measurable category in the inventory or a configuration line. Zero-findings is a valid LGTM.

## When to Use

- Long-conversation agents (50+ turn sessions; cache miss + tool-output bloat + late compaction).
- RAG pipelines (top-K stuffing without re-rank, duplicate chunks, prompt-injection via chunk content).
- Sub-agent orchestrators (parent window blowup, per-child unbounded budgets, cost-tier mis-routing).
- Large-doc workflows (single-shot > 100k, no caching across runs, output-token cap clipping synthesis).
- Skill-prompt context (whole-skill payload eats budget on every load).

Trigger: user pastes session/RAG template, statusline shows ≥ 80% utilization, or another skill cross-links `@context-optimization`.

## Do not use when

- Audit target is a **single prompt** (clarity, refusal hooks, schema) — use `@prompt-engineering`.
- User wants response brevity — use `@caveman`.
- User wants new skill scaffold — use `@skill-creator`.
- Phase 0.5 triage gate fires (trivial context).
- Domain has stricter compliance than the skill can verify (legal hold, audit trail).

## Prerequisites

| Input | Required | How to obtain |
| --- | --- | --- |
| Context inventory (categories + sizes) | Yes | User pastes, or `bash scripts/run-all.sh <project>` |
| Use case | Yes | long-conv-agent / rag-pipeline / sub-agent-orchestrator / large-doc / skill-prompt |
| Target harness | No | claude-code / codex / opencode / antigravity / agnostic — drives §13 plan output |
| Current utilization (%) | No | Estimate via `01-token-count.py` or harness statusline |
| Known degradation signal | No | Quality drop, cost spike, latency — focuses the audit |

Skill never sends context to another model. Findings derived from inventory against [TECHNIQUES.md](references/TECHNIQUES.md) catalog.

## Phase 0 — Capture & Classify

Capture inventory verbatim (Phase 0.1). Classify mode + use case + harness on three axes (Phase 0.2). Bound against use-case ceiling (Phase 0.3). Honest audit pledge — see [CHECKLIST §Skill self-audit](references/CHECKLIST.md#skill-self-audit-the-audit-of-the-audit) (Phase 0.4). Then **triage gate**:

### 0.5 Triage gate

Drop the audit when **all three** hold:

- Estimated context < 8000 tokens
- Window utilization < 50%
- No degradation signal reported

→ emit Block 1 (inventory) + Block 2 row `(out of scope: trivial context — audit overhead exceeds value)` + stop.

Otherwise, proceed to Phase 1.

## Phase 1 — Inventory

Break inventory into five categories (system prompt · tool defs · message history · retrieved chunks · tool outputs) with token estimate per category. Top category > 50% = top-of-mind finding. Detailed checklist: [CHECKLIST Phase 1](references/CHECKLIST.md).

## Phase 2 — Cost & Quality Audit

Walk cost levers (cache hit rate · dedup ratio · masking opportunity · partition candidates · harness primitive coverage) against the inventory. Each lever absent or weakly applied is a finding with category-cite. Severity per [SEVERITY_RUBRIC.md](references/SEVERITY_RUBRIC.md). Heuristic findings start Medium; promotion requires manual confirmation.

## Phase 3 — Technique Selection

Walk [TECHNIQUES.md](references/TECHNIQUES.md) §1..§13. Use case dispatches the subset (see [TECHNIQUES §How the skill uses](references/TECHNIQUES.md#how-the-skill-uses-this-catalog)):

| Use case               | Required techniques                                              |
| :--------------------- | :--------------------------------------------------------------- |
| `long-conv-agent`      | §1, §2, §3, §4, §6, §9, §13                                       |
| `rag-pipeline`         | §1, §3, §6, §8, §9, §10, §11                                      |
| `sub-agent-orchestrator` | §1, §7, §9, §11                                                 |
| `large-doc`            | §1, §5, §7, §9, §11, §12                                          |
| `skill-prompt`         | cross-link `@prompt-engineering` for single-prompt audit          |

Common context-bloat smells (quick-detection): see [TECHNIQUES §Common context-bloat smells](references/TECHNIQUES.md#common-context-bloat-smells).

## Phase 4 — Plan Recommendations

Plan ordered by ROI (highest token-cost or quality-impact first). Canonical skeleton per use case in [USE_CASES.md](references/USE_CASES.md) §1–§4. Generic order: cache layer (§1+§9) → compression (§2/§3/§4/§5/§6) → architecture (§7) → RAG-specific (§8/§10) → cost (§11/§12) → harness (§13).

### 4.1 Harness-specific plan output

When `harness ≠ agnostic`, Block 3 emits **concrete commands** per [HARNESS_NOTES.md](references/HARNESS_NOTES.md): Claude Code `/compact`, Codex `session.compaction`, Antigravity manual UI re-prompt. A plan that says "use compaction" without naming the harness primitive is itself a finding.

### 4.2 Living-context versioning

If the audited configuration has a `version` field, Block 3 emits a SemVer hint: PATCH (only SAFE), MINOR (≥ 1 REVIEW), MAJOR (≥ 1 BREAKING). Soft-spec; skips when no `version`.

## Phase 5 — Token Economy

### 5.1 Compression rules

Never compact a `never`/`must not`/`do not` rule. Never drop a refusal hook during compaction. Never paraphrase citation-bound text (use §6 verbatim deletion). Always dedupe (§10) before compacting (§2). Always preserve verbatim when surviving content is citation-bound. Detailed checklist: [CHECKLIST Phase 5](references/CHECKLIST.md).

### 5.2 Reporting the delta

Estimate before/after token count. Report signed delta + cache hit projection + invariants preserved (safety rules, refusal hooks, citation chunk_ids).

### 5.3 Token budget per use case

The plan respects a per-use-case ceiling. Excess → finding `T-001 Token budget exceeded` (REVIEW).

| Use case      | Ceiling (after plan applied) |
| :------------ | :-------------------------- |
| `long-conv-agent`        | ≤ 100k tokens (50% Sonnet/Opus 200k window) |
| `rag-pipeline`           | stable prefix ≤ 8k + dynamic ≤ 32k |
| `sub-agent-orchestrator` | parent ≤ 30k; each child ≤ 30k |
| `large-doc`              | ≤ 200k (single-shot, no growth) |
| `skill-prompt`           | ≤ 800 tokens (aligns with [`prompt-engineering` 5.3](../prompt-engineering/SKILL.md#53-token-budget-per-use-case)) |
| Other         | ≤ 50% of model window       |

User can override with explicit rationale; without override, T-001 fires.

### 5.4 Cache-friendly ordering

Position **stable** (system prompt, tool defs, schema, refusal hooks, few-shot) **before** **dynamic** (user input, retrieved chunks, conversation history). Anthropic prompt caching reuses prefix tokens with 5min/1h TTL; OpenAI auto-caches prefixes ≥ 1024 tokens. Reordering converts repeated tokens into cache hits — without §9, §1 caches only the leading stable prefix until the first dynamic byte.

## Phase 6 — Output

Five-block report. Block 5 conditional (REQUIRED if overall risk = REVIEW or BREAKING; OPTIONAL if SAFE).

| Block | Content |
| :--- | :--- |
| **1** | Original context inventory (verbatim, fenced) |
| **2** | Findings table + per-finding detail (id, severity, confidence, risk, category-cite, fix, technique §N) |
| **3** | Optimization plan (ordered by ROI; harness-specific commands per [HARNESS_NOTES.md](references/HARNESS_NOTES.md) when `harness ≠ agnostic`) |
| **4** | Summary table (cost lever coverage / token delta / cache-hit projection / risk tag / confidence) |
| **5** | Verification suggestions |

Worked example + verbatim output template: [EXAMPLE.md](EXAMPLE.md). Zero-findings contract + LGTM rules: [CHECKLIST §Skill self-audit](references/CHECKLIST.md#skill-self-audit-the-audit-of-the-audit).

## Constraints

Three load-bearing rules (full 15-rule list in [CHECKLIST §Skill self-audit](references/CHECKLIST.md#skill-self-audit-the-audit-of-the-audit)):

| Rule | Why |
| :--- | :--- |
| **Never apply the plan automatically** | Reviewer not optimizer — Block 3 = proposal |
| **Never strip a safety rule from system prompt during compaction** | `never`/`must not`/`do not`/`refuse if` survive every compaction |
| **Always emit Block 1 verbatim** | Inventory contract; second auditor must reach same verdict |

## Related Skills

- `@prompt-engineering` — primary sibling. Audits single prompts; this skill audits whole context. Run `@prompt-engineering` first to fix the prompt; then `/valarmindskills:context-optimization` to optimize the surrounding context.
- `@caveman` — compresses **response** (output). This skill compresses **input** (context).
- `@skill-creator` — scaffolds new skills.
- `@code-security-review` — pattern source for `scripts/` architecture.

## References

- [TECHNIQUES](references/TECHNIQUES.md) — §1..§13 catalog (cache, compression, architecture, RAG, cost, tool-specific)
- [USE_CASES](references/USE_CASES.md) — canonical skeletons + findings catalogs for the four primary classes
- [CHECKLIST](references/CHECKLIST.md) — copy-paste cheat sheet by phase + skill self-audit
- [SEVERITY_RUBRIC](references/SEVERITY_RUBRIC.md) — Severity × Category matrix and risk-tag rubric
- [HARNESS_NOTES](references/HARNESS_NOTES.md) — Claude Code / Codex / OpenCode / Antigravity primitives
- [EXAMPLE](EXAMPLE.md) — long-conv-agent worked example with verbatim output template
- `scripts/` — evidence-based audit tools (`scripts/README.md`)

# CHECKLIST — context-optimization

> Reference companion for the [context-optimization](../SKILL.md) skill.

Copy-paste cheat sheet. One section per audit phase. Tick each item; unticked items are findings.

## Phase 0 — Capture & Classify

- [ ] Original context inventory captured (categories: system prompt · tool defs · message history · retrieved chunks · tool outputs)
- [ ] Mode classified: **guide** | **audit**
- [ ] Use case identified: **long-conv-agent** | **rag-pipeline** | **sub-agent-orchestrator** | **large-doc** | **skill-prompt**
- [ ] Harness identified: **claude-code** | **codex** | **opencode** | **antigravity** | **agnostic**
- [ ] Estimated token size (before) — script-based via `01-token-count.py` if Claude Code available
- [ ] Window utilization estimated (current / model-limit)
- [ ] Honest audit pledge (5-rule, see [SKILL.md Phase 0.4](../SKILL.md#04-honest-audit-pledge))
- [ ] **Triage gate (Phase 0.5) evaluated** — context < 8k tokens AND utilization < 50% AND no degradation reported → emit out-of-scope and stop

## Phase 1 — Inventory

- [ ] Context broken down by category with token estimate per category
- [ ] Top-3 token-cost categories identified
- [ ] Inventory presented as Block 1 budget table (verbatim category sizes)

## Phase 2 — Cost & Quality Audit

- [ ] Cost levers walked (cache hit rate, dedup ratio, masking opportunity, partition candidates)
- [ ] Each gap captured as finding with quote-or-category-cite
- [ ] Severity calibrated per [SEVERITY_RUBRIC](SEVERITY_RUBRIC.md); heuristic findings start Medium

## Phase 3 — Technique Selection

Apply only the techniques listed for the declared use case (see [TECHNIQUES.md mapping](TECHNIQUES.md#how-the-skill-uses-this-catalog)).

- [ ] §1 Prompt caching — `cache_control` set on stable prefix; TTL appropriate for reuse cadence
- [ ] §2 Compaction — manual / auto trigger documented; threshold ≤ 80%
- [ ] §3 Observation masking — outputs > 3 turns old elided to references
- [ ] §4 Dynamic summarization — applied for sessions > 60 turns
- [ ] §5 LLMLingua / pruning — applied for noisy static docs
- [ ] §6 Verbatim deletion — applied for citation-bound contexts (no paraphrase)
- [ ] §7 Context partitioning — applied for multi-stage workflows
- [ ] §8 RAG chunk-pruning + re-ranking — applied for top-K > 8
- [ ] §9 Cache-friendly ordering — stable parts before dynamic; cache breakpoint placed
- [ ] §10 Dedup — applied to retrieved chunks (mandatory for RAG)
- [ ] §11 Model routing — triage / extraction routed to cheap tier
- [ ] §12 Batch-mode — applied for bulk workloads tolerating 24h SLA
- [ ] §13 Harness compaction commands — concrete primitive cited per harness ([HARNESS_NOTES.md](HARNESS_NOTES.md))
- [ ] Each finding cites a verbatim absence, contradiction, or category-bloat in Block 1 — no speculation, no `"this could be improved"` without a concrete missing technique from §1–§13

## Phase 4 — Plan Recommendations

- [ ] Each recommendation is a concrete technique with pattern + before/after
- [ ] Plan ordered by ROI (highest impact first)
- [ ] Any technique intentionally omitted has an explicit one-line justification
- [ ] **4.2 Living-context versioning** — if context has snapshot/version, SemVer bump suggested (PATCH=SAFE, MINOR=REVIEW, MAJOR=BREAKING)

## Phase 5 — Token Economy

- [ ] Redundant restatements deduplicated
- [ ] Filler / pleasantries removed (`please`, `kindly`, `make sure to`)
- [ ] Hedging removed (`maybe`, `try to`, `if possible`)
- [ ] Every safety rule from original preserved (compaction never strips `never`/`must not`)
- [ ] Every refusal hook preserved verbatim
- [ ] Every load-bearing example preserved
- [ ] Token delta reported (signed; reductions justified by category)
- [ ] **Plan respects token budget per Phase 5.3** — long-conv-agent ≤ 100k / rag stable prefix ≤ 8k + dynamic ≤ 32k / sub-agent ≤ 30k per child / large-doc ≤ 200k / skill-prompt ≤ 800
- [ ] **Cache-friendly ordering verified (Phase 5.4)** — stable parts (system, schema, refusal hooks, tool map) before dynamic parts (user input, retrieved chunks, conversation history)

## Phase 6 — Output

- [ ] Block 1 — Original context inventory verbatim (categories + sizes), fenced
- [ ] Block 2 — Findings table + per-finding detail blocks (id, severity, confidence, risk, category, evidence, fix)
- [ ] Block 3 — Optimization plan, fenced, ordered by ROI, copy-paste ready
- [ ] Block 4 — Summary table (cost lever coverage / token delta / cache-hit projection / risk tag / confidence)
- [ ] Block 5 — Verification suggestions (**REQUIRED** if overall risk = `REVIEW` or `BREAKING`; **OPTIONAL** if `SAFE`)
- [ ] Cross-links to sibling skills where domain overlap exists (`@prompt-engineering`, `@caveman`, `@skill-creator`)

## Skill self-audit (the audit of the audit)

- [ ] Every quote in findings is byte-for-byte from the original context inventory
- [ ] No invented file paths, function names, or external references
- [ ] Severity calibrated per [SEVERITY_RUBRIC.md](SEVERITY_RUBRIC.md); heuristic findings start at Medium
- [ ] No safety rule from the original was dropped in any plan suggestion
- [ ] Plan respects ≤ Phase 5.3 budget per declared use case
- [ ] Risk tag (overall) reported: SAFE | REVIEW | BREAKING
- [ ] Zero-findings result not padded with speculative Minors to look thorough
- [ ] No Minor was promoted to Major to fill the report
- [ ] If LGTM emitted, it was justified — every required technique from declared use case has a verbatim presence in the inventory
- [ ] **SKILL.md ≤ 800 tokens estimated payload** (skill applies its own §5.3 budget to itself)
- [ ] Plan output emits harness-specific commands when `harness ≠ agnostic` (see [HARNESS_NOTES.md](HARNESS_NOTES.md))

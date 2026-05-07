# TECHNIQUES — context-optimization

> Reference companion for the [context-optimization](../SKILL.md) skill.

Thirteen techniques for context optimization across cache, compression, architecture, RAG-specific, cost, and tool-specific categories. Each entry has a fixed shape:

- **Problem** — the failure mode the technique prevents or the cost it removes.
- **Pattern** — the concrete instruction or implementation.
- **Before / After** — minimal example.
- **When to apply** — the use cases that need it.
- **Counter-signal** — when NOT to apply.

Apply in canonical order **profile → cache → compress → partition → cost-tune**. Skipping is allowed if intent is documented; silent omission is a finding.

---

## §1 Prompt caching (5min / 1h TTL, stable prefix, exact match)

**Category.** Cache.

**Problem.** Multi-turn agents and RAG pipelines re-process identical system prompts, tool definitions, and schemas on every call. Anthropic charges full input price for every token unless the prefix matches a cached entry **exactly**.

**Pattern.** Place stable content (system prompt, tool definitions, schema, refusal hooks) at the **beginning** of the prompt. Mark cache breakpoints AFTER stable content via `cache_control: { type: "ephemeral" }`. For prompts reused more often than every 5 minutes, use default 5min TTL. For prompts reused hourly or less, use `ttl: "1h"` (write cost 2× base instead of 1.25×).

**Before**

```python
messages = [
  {"role": "user", "content": f"You are an assistant. Use docs: {docs}. Query: {query}"}
]
```

**After**

```python
system = [
  {"type": "text", "text": ROLE_AND_CONSTRAINTS,
   "cache_control": {"type": "ephemeral"}},
  {"type": "text", "text": TOOL_DEFINITIONS,
   "cache_control": {"type": "ephemeral"}},
]
messages = [
  {"role": "user", "content": f"Docs:\n{docs}\nQuery: {query}"},
]
```

**When to apply.** Multi-turn agents (Claude Code, custom agents). RAG with stable retrieval system prompt. Long-running batches reusing instructions.

**Counter-signal.** Single-shot tasks (cache write 1.25× cost; only 1 call). Prompts with no stable prefix possible (every byte dynamic).

**Pricing (Anthropic, 2026).** Cache write 1.25× input (5min TTL) or 2× input (1h TTL). Cache read 0.1× input (90% off). Break-even at **≥ 2 reads** of the same prefix.

**Common mistake.** Cache breakpoint placed AFTER content that changes per call → every call invalidates cache. The breakpoint must come **after** the stable prefix and **before** the dynamic suffix.

---

## §2 Compaction (Anthropic auto + manual)

**Category.** Compression.

**Problem.** Long-running sessions accrete tool outputs, conversation history, and retrieved chunks until context approaches the window limit. Quality degrades; latency rises; cost compounds.

**Pattern.** When utilization crosses a threshold (Anthropic auto: ~95%; recommended manual: 70-80%), compact the conversation: keep last N turns full, replace earlier turns with a structured summary. Preserve commitments, decisions, and unresolved threads; drop verbose tool outputs and back-and-forth.

**Before**

```text
[turn 1..50, full transcript ~180k tokens]
```

**After**

```text
[summary of turns 1..40 — 8k tokens]
  - Decisions: <list>
  - Open threads: <list>
  - Files touched: <list>
[turns 41..50, full ~12k tokens]
```

**When to apply.** Long-conv agents at 70-80% utilization. Sessions where early context is no longer load-bearing.

**Counter-signal.** Single-shot tasks. Sessions where every turn must remain verbatim (audit trails, legal review).

**Anthropic auto-compaction (since 2025-Q4).** Triggers automatically near 95% capacity in Claude Code. Implicit; user does not control timing. For deterministic timing, use manual `/compact` (Claude Code) or `session.compaction` (Codex) — see §13.

---

## §3 Observation masking

**Category.** Compression.

**Problem.** Tool outputs comprise 80%+ of token usage in agent trajectories. Once a tool output has served its purpose (decision made, summary extracted), the verbose raw output stays in context consuming tokens with diminishing value.

**Pattern.** Replace tool outputs older than N turns with a compact reference. Preserve the key conclusion inline; store the full output addressable by ID. The agent can re-fetch if needed.

**Before**

```text
[Tool: read_file api/handler.go]
<2400 lines of code>
```

**After**

```text
[Obs:OBS-042 elided — read_file api/handler.go]
Key: handler.go has BFLA bug at line 142; user_id check missing.
Re-fetch with restore_observation("OBS-042") if full content needed.
```

**Decision matrix.** Never mask: current-turn outputs, outputs in active reasoning. Consider masking: 3+ turns ago, verbose with extractable key. Always mask: repeated outputs, boilerplate headers/footers, outputs already summarized in conversation.

**When to apply.** Tool-heavy agent trajectories. RAG with large retrieved chunks no longer being cited.

**Counter-signal.** Outputs being actively cited in the next turn. Outputs the user has explicitly asked to retain.

**Effectiveness.** 60-80% reduction in masked observation tokens with negligible quality loss when masking rules are conservative.

---

## §4 Dynamic summarization (rolling window)

**Category.** Compression.

**Problem.** Compaction (§2) is one-shot — summarize-then-replace. For continuously growing sessions, a single compaction cycle is wasteful: re-summarize work that was already summarized.

**Pattern.** Maintain a **living summary** updated incrementally. Last N turns kept verbatim; turn N+1 onward folded into the summary as it ages out of the window. Trigger threshold 70-80% utilization (heuristic; tune to model + workload).

**Before**

```text
[turn 1..N, verbatim]
```

**After**

```text
[living summary of turns 1..(N-W), updated each W turns]
[turns (N-W+1)..N, verbatim — sliding window]
```

**When to apply.** Long-conv agents in production (50+ turn sessions common). Streaming workloads where fresh context arrives steadily.

**Counter-signal.** Short sessions (< 30 turns — single compaction is cheaper). Sessions requiring verbatim history (legal, audit).

**Trade-off.** Each summary update costs 1 LLM call. Cost-amortized when session > 60 turns or when alternative is full re-summarize per cycle.

---

## §5 LLMLingua / token-level pruning (perplexity-guided)

**Category.** Compression.

**Problem.** Compaction (§2) and summarization (§4) operate at message granularity. For documents and chunks themselves, finer-grained compression is possible without LLM round-trip.

**Pattern.** Score each token (or n-gram) by perplexity / saliency from a small reference model. Drop low-saliency tokens with a budget controller to prevent meaning drift. LLMLingua, LongLLMLingua, and successors implement this.

**Before**

```text
"It's really really important that you absolutely make sure to provide
detailed and comprehensive citations for any factual claim you make,
otherwise the user simply cannot trust the answer."  [37 tokens]
```

**After (perplexity-pruned)**

```text
"Cite every factual claim. Uncited = rejected."  [9 tokens]
```

**When to apply.** Static documents being injected into prompts (RAG corpus, large-doc chunks). Pre-processing pipeline where round-trip latency is acceptable.

**Counter-signal.** Live conversation (latency-sensitive). Safety-relevant text (`never` rules — pruning may drop the negation). Code blocks (every char load-bearing).

**Effectiveness.** Up to 20× compression, 1.5% performance loss on reasoning benchmarks (LLMLingua-2 paper). Practical gains usually 3-5× on natural-language documents.

---

## §6 Verbatim deletion (Morph pattern)

**Category.** Compression.

**Problem.** Summarization (§2, §4) and pruning (§5) **paraphrase** — risk of fact drift, citation invalidation, loss of verbatim quotes load-bearing for downstream parsers.

**Pattern.** Delete redundant tokens char-by-char while preserving every surviving sentence verbatim. Identify duplicate paragraphs, repeated boilerplate, near-duplicate retrieval chunks; drop them. Surviving content is byte-identical to source.

**Before**

```text
Section A: <content X>
Section B: <content X, slightly rephrased>
Section C: <content Y>
```

**After**

```text
Section A: <content X — verbatim>
Section C: <content Y — verbatim>
```

**When to apply.** Citation-bound contexts (RAG with quote-back verification). Audit trails. Code review where original line text must remain.

**Counter-signal.** Highly redundant prose where paraphrase compression saves more (use §5 instead). Cases where structure (not content) is duplicated — see §10 for dedup.

**Effectiveness.** Morph reports 50-70% token reduction at 33,000 tok/s with **zero hallucination** (because nothing is rewritten).

---

## §7 Context partitioning / sub-agents

**Category.** Architecture.

**Problem.** Some tasks combine many subtasks each with distinct context needs (search + analyze + write report). Carrying full context across all subtasks bloats every step and confuses the model with irrelevant signals.

**Pattern.** Split work across sub-agents with **isolated** contexts. Parent coordinator holds task plan + subtask results (compact). Each sub-agent operates on a clean window focused on its slice. Aggregation at the parent level merges results.

**Before** (monolithic)

```text
[180k context: search results + 12 analyzed docs + draft report]
```

**After** (partitioned)

```text
Parent: [task plan + 6 sub-agent summaries — 30k]
Sub-agent 1: [search task — 40k clean]
Sub-agent 2: [analyze doc 3 — 25k clean]
…
```

**When to apply.** Multi-stage workflows. Tasks with clear subtask boundaries (search → analyze → synthesize). When single-context approaches near window limit.

**Counter-signal.** Tightly coupled reasoning where every step needs full history. Tasks where coordination overhead > savings (3 small steps not worth N sub-agents).

**Trade-off.** Parallelizable; per-child budget per Phase 5.3 ≤ 30k. N sub-agents = N parallel LLM calls (cost N×, latency 1× if parallel).

---

## §8 RAG chunk-pruning + re-ranking

**Category.** RAG-specific.

**Problem.** Naive RAG retrieves top-K by embedding similarity and stuffs all into the prompt. Most chunks are irrelevant noise; some duplicate; some contradict. Quality degrades with more chunks past a sweet spot (~5-8 for most use cases).

**Pattern.** Two-stage retrieval: (a) initial top-K from embedding (K ≈ 30); (b) re-rank with a cross-encoder or LLM-as-judge on (query, chunk) pairs; (c) keep top-N (N ≈ 5-8) by re-rank score. Drop chunks below relevance threshold. Apply §10 dedup before re-rank.

**Before**

```text
top_chunks = vector_search(query, k=20)
prompt = format_rag(query, top_chunks)  # 20 chunks ≈ 8k tokens
```

**After**

```text
candidates = vector_search(query, k=30)
candidates = dedup(candidates)                      # §10
ranked = cross_encoder_rerank(query, candidates)
top_chunks = [c for c in ranked if c.score > 0.7][:8]
prompt = format_rag(query, top_chunks)              # 8 chunks ≈ 3k tokens
```

**When to apply.** RAG pipelines where retrieval quality matters (factual answers, code search). Production systems with measurable answer quality metrics.

**Counter-signal.** Tiny corpus (< 100 chunks — top-K already accurate). Latency-budget < 200ms (re-rank adds 50-100ms).

**Effectiveness.** Re-ranking improves answer quality 10-30% on factual benchmarks while cutting retrieved-chunk tokens 60-80%.

---

## §9 Cache-friendly ordering (stable → dynamic)

**Category.** Cache.

**Problem.** Even when prompt caching (§1) is enabled, interleaving stable and dynamic content **breaks the cache hit**: the first dynamic byte invalidates everything after it. A prompt that says "Role X. Today is Tuesday. Tools are Y." caches only "Role X." because date is dynamic.

**Pattern.** Order prompt regions so all stable regions come **first** and all dynamic regions come **last**. The cache breakpoint sits between them. Layer order:

1. System prompt / role (stable)
2. Tool definitions (stable per agent version)
3. Schema / refusal hooks (stable)
4. Few-shot examples (stable)
5. **[cache breakpoint]**
6. User input (dynamic)
7. Retrieved chunks (dynamic per query)
8. Conversation history (dynamic per turn)

**Before**

```text
You are an assistant. Today is {date}. Use these tools: {tools}.
The user asked: {query}.
```

**After**

```text
You are an assistant.
Use these tools: {tools_static}.
{cache_breakpoint}
Current date: {date}.
User asked: {query}.
```

**When to apply.** Always for multi-turn / RAG when §1 caching enabled. Refactoring legacy prompts where order is accidental.

**Counter-signal.** Single-shot prompts (no cache benefit). Prompts where current ordering is functionally required (rare).

**Effectiveness.** Captures the **full** §1 cache benefit. Without §9, §1 saves only the leading stable prefix until the first dynamic byte.

---

## §10 Dedup (near-duplicate detection, SimHash)

**Category.** Compression.

**Problem.** Retrieved chunks frequently overlap (same paragraph from multiple sources). Boilerplate (license headers, signatures) repeats verbatim across files. Conversation history echoes prior decisions. All this duplication consumes tokens for zero signal.

**Pattern.** Hash content blocks (line-level or paragraph-level SHA-256, or fuzzy via SimHash / MinHash). Detect duplicates above similarity threshold (e.g., > 85%). Drop duplicates, keep canonical version with cross-references.

**Before**

```text
[chunk A: lines 1..100]
[chunk B: lines 1..100 byte-identical]
[chunk C: lines 1..98 + 2 lines diff]
```

**After**

```text
[chunk A: lines 1..100]
[chunk B: deduplicated against A, dropped]
[chunk C: only the 2 diff lines + ref to A]
```

**When to apply.** RAG pipelines (mandatory in production). Codebases with repeated headers (license, imports). Long conversations where decisions are restated.

**Counter-signal.** Cases where duplicate **context** is intentional (emphasis, repetition for memorization). Tiny contexts where dedup overhead > savings.

**Effectiveness.** RAG dedup typically removes 15-40% of retrieved tokens with zero quality loss.

---

## §11 Model routing (cheap-first triage)

**Category.** Cost.

**Problem.** Every step of an agent loop calls the most capable (and most expensive) model, even for trivial steps (classification, extraction, validation) where a smaller model would succeed.

**Pattern.** Route by task class: small/cheap model for triage and structured extraction; large/expensive model for reasoning and generation. Implement as explicit `route(task) → model_id` step before each call. Use cost-tier matrix:

```toon
routing[5]{task_class,suggested_model}:
  Classification (closed enum)	Haiku / GPT-4o-mini
  Extraction (structured)	Haiku / GPT-4o-mini
  Reasoning (multi-step, chain-of-thought)	Sonnet / GPT-4o
  Code generation (production)	Opus / GPT-4
  Long-form writing	Sonnet / Opus
```

**When to apply.** Production agents with measurable task taxonomy. Pipelines with clear branch points (extract → reason → generate).

**Counter-signal.** Single-task workflows (no branch). Quality-critical tasks where small-model regressions cost more than savings.

**Effectiveness.** 40-70% cost reduction in production pipelines. Anthropic's Sonnet 4.6 → Haiku 4.5 routing saves ~80% per call where Haiku suffices.

---

## §12 Batch-mode aggregation

**Category.** Cost.

**Problem.** Single-call inference is the default but most expensive form. For workloads tolerating latency (batch processing, overnight evaluation, bulk classification), provider batch APIs offer significant discounts.

**Pattern.** Group N independent prompts into a batch submission. Anthropic Message Batches, OpenAI Batch API, and similar offer 50% discount with 24h SLA. Submit batch; poll for completion; consume results.

**Before**

```python
for item in items:                       # N synchronous calls, full price
  result = client.messages.create(...)
  process(result)
```

**After**

```python
batch_id = client.messages.batches.create(requests=[
  {"custom_id": str(i), "params": {...}} for i, item in enumerate(items)
])
# poll batch_id; consume when ready                 # 50% off
```

**When to apply.** Bulk classification / extraction / summarization. Eval pipelines. Overnight scheduled jobs.

**Counter-signal.** Interactive chat. Anything user-facing with latency budget < 24h. Workflows where one prompt's output feeds the next.

**Effectiveness.** 50% cost cut at provider tier. Operational cost may rise slightly (queueing, retry on partial batch failure).

---

## §13 Harness compaction commands (`/compact`, `session.compaction`)

**Category.** Tool-specific.

**Problem.** Each agent harness (Claude Code, Codex CLI, OpenCode, Antigravity) implements compaction differently. Skill output that says "use compaction" without naming the harness primitive forces the user to look up commands per platform.

**Pattern.** Detect harness in Phase 0.1; emit harness-specific command in Block 3 plan. See [HARNESS_NOTES.md](HARNESS_NOTES.md) for the full primitive matrix.

```toon
harness_cmds[4]{harness,manual_compaction,auto_compaction,session_inspection}:
  Claude Code	/compact	Since 2025-Q4 at ~95%	~/.claude/projects/<hash>/*.jsonl
  Codex	session.compaction CLI	No auto by default	~/.codex/sessions/
  OpenCode	session.compact	Configurable	Session dir
  Antigravity	(manual UI re-prompt)	None native	(no direct inspection)
```

**When to apply.** Mandatory in Block 3 when harness ≠ `agnostic` and use case = `long-conv-agent` or `sub-agent-orchestrator`. The user needs the **command**, not just the **concept**.

**Counter-signal.** Harness = `agnostic` (skill-prompt audit, design exercise). Single-shot use cases (no session to compact).

**Cross-link.** [HARNESS_NOTES.md](HARNESS_NOTES.md) for the full primitives + caveats per harness.

---

## Common context-bloat smells

Quick-detection table for Phase 2 audits — each row is a heuristic smell + fix. Each smell is a finding with quote/category-cite + fix + risk tag.

```toon
smells[8]{smell,detection,fix}:
  Tool outputs > 50% of context	Inventory by category	Apply §3 observation masking
  Identical chunks retrieved 2x	Hash compare in retrieval log	Apply §10 dedup before LLM call
  System prompt re-sent each turn	Trace shows full prefix every call	Apply §1 prompt caching + §9 ordering
  Conversation > 50 turns no compaction	Session length + lack of summary	Apply §2 compaction or §4 summarization
  Single agent handling 4+ subtasks	Task plan shows distinct phases	Apply §7 partitioning
  All calls use top-tier model	Cost report by model	Apply §11 routing
  Bulk eval running interactive API	Job pattern + latency tolerance	Apply §12 batch mode
  Skill says use compaction without command	Block 3 missing harness primitive	Apply §13 (cite /compact etc.)
```

---

## How the skill uses this catalog

Phase 3 walks the prompt-or-context against §1–§13 in order. Each technique that **applies** but is **missing or weakly stated** is a finding, with severity per [SEVERITY_RUBRIC](SEVERITY_RUBRIC.md). The plan in Block 3 inserts the missing techniques in the canonical order documented in Phase 4 of the skill.

A single context rarely needs all 13 techniques. The audit picks the **subset required by the use case** declared in Phase 0.2:

```toon
mapping[5]{use_case,required_techniques}:
  long-conv-agent	§1, §2, §3, §4, §6, §9, §13
  rag-pipeline	§1, §3, §6, §8, §9, §10, §11
  sub-agent-orchestrator	§1, §7, §9, §11
  large-doc	§1, §5, §7, §9, §11, §12
  skill-prompt	cross-link @prompt-engineering — context-optimization handles whole-context, not single-prompt audit
```

For prompts that **mix use cases** (e.g., a long-conv agent embedding a RAG sub-pipeline), audit each subset separately and combine the techniques in the plan.

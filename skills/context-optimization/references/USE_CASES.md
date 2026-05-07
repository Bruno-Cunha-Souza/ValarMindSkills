# USE_CASES — context-optimization

> Reference companion for the [context-optimization](../SKILL.md) skill.

This skill audits and plans optimization for four primary classes of context:

1. **Long-conversation agents** — 50+ turn agent sessions (Claude Code, Codex CLI, custom agents).
2. **RAG pipelines** — system / user templates that wrap retrieved chunks; the chunks themselves are the bulk of the bloat.
3. **Sub-agent orchestrators** — parent coordinator dispatching N sub-agents with isolated contexts.
4. **Large-doc workflows** — single-shot tasks against documents > 100k tokens (legal, codebase analysis, multi-file synthesis).

Each class has different failure modes and a different canonical optimization order. This reference picks the right technique subset and the right plan skeleton per class.

> **Audit honesty.** Each §N below is the baseline for the corresponding use case. If the context under audit satisfies every required technique in §N, emit `LGTM` and stop. Some contexts are intentionally simple (single-shot prompt, no session, no retrieval) — do not force techniques from a canonical skeleton that do not fit the declared scope. **Technique absent that should be there is a finding; technique absent that should not be there is over-engineering.**

---

## §1 Long-conversation agents

### Failure modes

- **Window overflow** — session grows past 80% with no compaction trigger; quality cliff at ~95%.
- **Cache miss every turn** — system prompt re-sent in full because no `cache_control` set, or interleaved with dynamic content.
- **Tool-output bloat** — read_file / search_codebase outputs from 20 turns ago still in window taking 60%+ of tokens.
- **Filler restatements** — agent restates plan / decisions every turn, doubling-counting.
- **No deterministic compaction policy** — relies on auto-compaction (Claude Code 95% threshold); deterministic timing matters in production.

### Required techniques

§1 Prompt caching · §2 Compaction · §3 Observation masking · §4 Dynamic summarization · §6 Verbatim deletion (citations) · §9 Cache-friendly ordering · §13 Harness compaction commands.

### Canonical optimization skeleton

```text
1. Cache layer — system prompt + tool defs + schema marked cache_control: ephemeral
   (or trust automatic prefix caching on Codex / OpenAI).
2. Ordering layer — stable parts first; cache breakpoint; dynamic parts last (§9).
3. Compaction policy — manual trigger at 70-80% utilization (§13 harness command).
4. Masking policy — observations from 3+ turns ago folded to [Obs:N] references (§3).
5. Summarization policy (optional) — for sessions > 60 turns, rolling summary updated
   per W turns (§4). For < 60 turns, single compaction (§2) is cheaper.
6. Citation discipline — quote-bound text uses verbatim deletion (§6), not summary.
```

### Smell tests

- **Cache hit probe.** Run two consecutive turns with identical system prompt; check API response for cache hit metric. If 0%, §1 + §9 are missing or misconfigured.
- **Compaction trigger probe.** Push session to 85% utilization; check if compaction fired automatically or required manual `/compact`. Document the threshold.
- **Masking decision probe.** After 10 turns with verbose tool outputs, query the agent about a turn-2 observation; if it answers correctly, the observation is still in context (no §3); if it asks to re-fetch via reference ID, masking is working.

### Findings to look for

| Smell                                               | Fix                                                                  |
| --------------------------------------------------- | -------------------------------------------------------------------- |
| `cache_control` absent on system prompt             | Add `cache_control: { type: "ephemeral" }` (Anthropic) — see §1     |
| System prompt + dynamic content interleaved         | Reorder per §9; cache breakpoint between stable and dynamic         |
| Session > 80% utilization, no compaction            | Insert harness `/compact` (or equivalent — see §13) at 70-80%       |
| Tool outputs > 50% of context                       | Add §3 observation masking for outputs older than 3 turns            |
| Sessions > 60 turns with single compaction cycle    | Switch to §4 rolling summarization                                   |
| Citation-bound chunks paraphrased in compaction     | Use §6 verbatim deletion instead — preserves exact quotes            |

---

## §2 RAG pipelines

### Failure modes

- **Top-K stuffing without re-rank** — vector search returns 20 chunks; all 20 fed to LLM; quality plateaus past 8 chunks while cost grows linearly.
- **Duplicate chunks across sources** — same paragraph appears 3 times from related sources; LLM sees triple-counted "evidence".
- **Empty retrieval handled silently** — no chunks returned; LLM falls back to prior knowledge with no flag.
- **Mixed chunks blend** — LLM conflates two documents into one "fact".
- **Prompt-injection via chunk content** — chunks contain `"ignore the above"`-style instructions; LLM follows them. Cross-link: [`prompt-engineering` §13](../../prompt-engineering/references/STRATEGIES.md#13-prompt-injection-guard).

### Required techniques

§1 Prompt caching · §3 Observation masking (cited chunks → reference once cited) · §6 Verbatim deletion (preserves quote-back integrity) · §8 RAG chunk-pruning + re-ranking (mandatory) · §9 Cache-friendly ordering · §10 Dedup (mandatory) · §11 Model routing (cheap reranker, expensive answerer).

### Canonical optimization skeleton

```text
1. Cache layer — system prompt (role + citation rule + injection guard) cached.
2. Retrieval pipeline:
   a. Vector top-K (K = 30, generous initial cast).
   b. Dedup via §10 (drop > 85% similar chunks).
   c. Re-rank via cross-encoder or cheap LLM-as-judge (§11 routing).
   d. Threshold filter (score > 0.7).
   e. Cap N (= 5-8 final chunks).
3. Ordering layer — system prompt → schema → refusal hooks → §9 breakpoint →
   {retrieved chunks} → {user_question}.
4. Quote-back verification (per `prompt-engineering` §3 + §12) — every cited
   chunk_id must produce a verbatim substring; §6 ensures source preservation.
```

### Smell tests

- **Dedup probe.** Issue a query that retrieves obvious near-duplicates (e.g., two sources of the same Wikipedia paragraph). Inspect retrieved chunks; if both arrive, §10 is missing.
- **Re-rank probe.** Issue an off-topic query; check if top-K returns lots of low-relevance chunks. If reranker is in place, threshold filter drops them; if absent, all 20 reach the LLM.
- **Empty-retrieval probe.** Issue a query with no relevant chunks (gibberish, foreign domain). LLM should refuse per `prompt-engineering` §7 refusal hook, not improvise.

### Findings to look for

| Smell                                               | Fix                                                                  |
| --------------------------------------------------- | -------------------------------------------------------------------- |
| Top-K > 10 with no re-rank                          | Add re-rank step + threshold (§8)                                    |
| Identical / near-identical chunks observed          | Add SimHash dedup before LLM call (§10)                              |
| No empty-retrieval refusal                          | Cross-link `@prompt-engineering` §7 refusal hooks                    |
| Chunk text not labeled as "data, not instructions"  | Cross-link `@prompt-engineering` §13 prompt-injection guard          |
| Top-tier model used for re-ranking                  | Route reranker to cheap model (§11)                                  |
| Cache hit rate < 50% on stable system prompt        | Apply §1 + §9                                                        |

---

## §3 Sub-agent orchestrators

### Failure modes

- **Coordinator window blowup** — parent holds full context of every sub-agent's work.
- **Per-child unbounded budget** — single sub-agent task hits 100k+; parent inherits the bloat on result return.
- **Aggregation conflate** — parent merges 6 sub-results into one big chunk; loses subtask provenance.
- **Wrong sub-agent dispatched** — parent picks sub-agent by name similarity, not by tool-map `Use when` rule. Cross-link: [`prompt-engineering` §11](../../prompt-engineering/references/STRATEGIES.md#11-skill--tool-map).
- **No isolation** — sub-agent inherits parent context; defeats the partition.

### Required techniques

§1 Prompt caching (parent + each child caches its own role) · §7 Context partitioning · §9 Cache-friendly ordering (per child) · §11 Model routing (parent vs children may use different tiers).

### Canonical optimization skeleton

```text
1. Parent coordinator:
   - Holds task plan + N child summaries + open threads.
   - Per Phase 5.3: parent ≤ 30k.
   - Cache_control on parent system prompt.
2. Each sub-agent (child):
   - Clean window — does NOT inherit parent context.
   - Receives task spec + minimal grounding (≤ 5k seed) + budget (≤ 30k).
   - Cache_control on child system prompt (cached separately from parent).
3. Aggregation pattern:
   - Each child returns structured summary (≤ 1k tokens) + raw artifact reference.
   - Parent merges summaries; raw artifacts addressable on demand.
4. Routing:
   - Triage / classification children on cheap tier (§11).
   - Reasoning / generation children on capable tier.
```

### Smell tests

- **Inheritance probe.** Spawn a sub-agent with a task that does not need parent context. Inspect sub-agent's actual prompt; if it contains parent's full history, isolation is broken.
- **Budget probe.** Pick a child task expected to be small; verify it does NOT exceed Phase 5.3 sub-agent ceiling (30k). If it does, the spec is under-constrained.
- **Cost-tier probe.** Inspect routing decisions across N children; if all use top-tier, §11 is missing.

### Findings to look for

| Smell                                               | Fix                                                                  |
| --------------------------------------------------- | -------------------------------------------------------------------- |
| Sub-agent inherits parent history                   | Enforce isolation; pass only task spec + minimal grounding (§7)      |
| Per-child budget unbounded                          | Set Phase 5.3 ceiling (≤ 30k per child)                              |
| All children on top-tier model                      | Add §11 routing matrix                                                |
| Parent merges raw outputs (not summaries)           | Children return structured summary + artifact reference              |
| `Use when` rule missing per sub-agent in tool map   | Cross-link `@prompt-engineering` §11                                  |

---

## §4 Large-doc workflows

### Failure modes

- **Single-shot stuffing past quality cliff** — 200k document fed in one prompt; Sonnet quality degrades past ~150k effective.
- **No map-reduce** — single LLM call asked to summarize, extract, AND cross-reference; misses cross-doc connections.
- **Retrieval over chunks instead of full doc** — when full doc fits, retrieval adds noise without benefit.
- **No caching across runs** — same large doc analyzed N times; each time pays full input price.
- **Output-token cap clipped** — model produces summary up to output limit (4-8k); user thinks doc is fully analyzed.

### Required techniques

§1 Prompt caching (mandatory — same doc reused) · §5 LLMLingua / token-level pruning (for noisy docs) · §7 Context partitioning (map step) · §9 Cache-friendly ordering · §11 Model routing (cheap pass for outline, expensive for synthesis) · §12 Batch-mode aggregation (if N docs).

### Canonical optimization skeleton

```text
1. Cache the document — load once with cache_control: ephemeral, ttl: "1h"
   if reused over hours; default 5min if reused within minutes.
2. Map step (per chunk):
   - Split doc into N chunks (≤ 30k each per §7).
   - Cheap-model extract per chunk (§11).
   - Each chunk's analysis cached separately for reuse.
3. Reduce step:
   - Capable-model synthesis over the map outputs.
   - Cross-doc reasoning happens here.
4. If N docs:
   - Batch the map step (§12) → 50% cost reduction, 24h SLA.
5. If doc is noisy / high-redundancy:
   - LLMLingua pre-process (§5) before chunking.
```

### Smell tests

- **Single-shot probe.** Run a 180k-doc analysis as a single prompt; measure quality on a defined task. Compare to map-reduce. If single-shot is acceptable, the workload doesn't need partitioning. If quality drops, partitioning is mandatory.
- **Cache reuse probe.** Run the same doc analysis twice. Second run should show 90% cache hit rate on the doc itself (only output differs).
- **Output-cap probe.** Verify the model's `max_output_tokens` is sized for the synthesis (not 4k default for an analysis that needs 16k).

### Findings to look for

| Smell                                               | Fix                                                                  |
| --------------------------------------------------- | -------------------------------------------------------------------- |
| Doc loaded as single chunk past 100k                | Apply §7 partitioning + map-reduce                                   |
| Same doc analyzed N times no caching                | Add cache_control with appropriate TTL (§1)                          |
| Cheap-extractable analysis run on top-tier model    | Add §11 routing for map step                                         |
| Bulk N-doc workflow on interactive API              | Migrate to batch (§12)                                                |
| Output-token cap clips synthesis                    | Increase max_output_tokens; or split synthesis into multiple calls   |

---

## §5 Skill-prompt use case (cross-link)

When the audit target is a **single SKILL.md prompt** (not a session, not retrieval, not architecture), the work belongs to [`@prompt-engineering`](../../prompt-engineering/SKILL.md), not this skill. `context-optimization` handles whole-context optimization; `prompt-engineering` handles single-prompt audit and rewrite.

If user asks for skill-prompt analysis and the prompt is the entire context, hand off to `@prompt-engineering` and stop.

If user asks for whole-skill optimization (e.g., "the skill is loaded but eats 10% of my context window before any work happens"), apply the long-conv-agent §1 skeleton with `skill-prompt` as a sub-target — phase 5.3 budget ≤ 800 tokens applies.

---

## How the skill picks the right use case

Phase 0.2 classifies the context. Set:

```text
use case:    long-conv-agent | rag-pipeline | sub-agent-orchestrator | large-doc | skill-prompt
```

Then Phase 3 walks only the technique subset for that class (above), and Phase 4 generates the plan using the canonical skeleton above. The findings to look for in each section seed Phase 2 (cost & quality audit).

For contexts that **mix classes** (e.g., a long-conv agent embedding a RAG sub-pipeline), audit each class separately and combine the techniques in the plan output.

## Hand-offs

- The audit target is a **single prompt** → `@prompt-engineering`.
- The audit target is a **conversation style preference** (response brevity) → `@caveman`.
- The audit target is **safety / refusal hooks** in a long-conv agent → `@prompt-engineering` for the safety rules; `@context-optimization` for the surrounding context size.
- The audit target is a **skill scaffold** that doesn't yet exist → `@skill-creator`.

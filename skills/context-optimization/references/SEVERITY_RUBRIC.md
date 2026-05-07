# SEVERITY_RUBRIC — context-optimization

> Reference companion for the [context-optimization](../SKILL.md) skill.

Severity calibrates how blocking a finding is. Risk tag calibrates how invasive the proposed fix is. Confidence calibrates how willing the reviewer is to stand behind the finding. Findings missing any of the three are dropped.

## Severity by category

Each row is a category (Cost waste, Cache miss, Quality degradation, Token bloat, Architecture risk). Each column is a severity. A finding lands at the cell where its symptom matches.

```toon
severity_matrix[25]{severity,category,description}:
  critical	cost	Production agent calling top-tier model on triage tasks ($/M scaling 10x+)
  critical	cache	Cache breakpoint after dynamic content -> 0% cache hit on multi-turn
  critical	quality	Compaction summarizing safety rules / refusal hooks; semantic loss on commitments
  critical	bloat	Context > 95% capacity with no compaction triggered
  critical	architecture	Sub-agent partition missing on 4+ subtask workflow producing rate-limit failures
  high	cost	Bulk eval running interactive API ignoring batch mode
  high	cache	Stable content interleaved with dynamic; partial cache hit only
  high	quality	Verbatim deletion (§6) replaced with paraphrase summarization on citation-bound RAG
  high	bloat	Tool outputs > 70% of context, no masking
  high	architecture	Single-context monolith on workflow that should partition
  medium	cost	Top-tier model used for structured extraction with no routing
  medium	cache	System prompt not marked for caching at all
  medium	quality	Re-rank threshold too aggressive -> relevant chunks dropped
  medium	bloat	> 40% redundant chunks (no §10 dedup)
  medium	architecture	Coordinator -> sub-agent budget unbounded (no Phase 5.3 cap)
  low	cost	Cache TTL 1h chosen for prompts re-used every 5 minutes (write-cost premium with no payback)
  low	cache	Suboptimal ordering of stable parts (e.g. schema after refusal hook)
  low	quality	Summary loses non-load-bearing back-and-forth without flag
  low	bloat	> 15% redundancy in retrieved chunks
  low	architecture	Sub-agent boundaries not documented in plan
  info	cost	Routing matrix could be tighter
  info	cache	Could add second cache breakpoint for tool defs
  info	quality	Could log compaction events for observability
  info	bloat	Filler phrases in system prompt
  info	architecture	Consider parallelism on independent sub-agents
```

A single context can have findings across multiple categories. Aggregate **at the highest single-finding severity**, not by counting.

### Use case-specific severity patterns

When use case = `long-conv-agent`, the dominant failure modes are compaction timing and cache misses. When use case = `rag-pipeline`, dedup + chunk-pruning + injection-guard dominate. Apply this table only for the noted use cases; for others, read the matrix above.

```toon
use_case_severity[6]{pattern,severity,use_case,reasoning}:
  No compaction trigger documented above 80% capacity	critical	long-conv-agent	Quality cliff at ~95%; auto-compaction is implementation-dependent
  cache_control absent on system prompt	high	long-conv-agent	90% of cache savings forgone on every turn
  Re-rank step missing on RAG with > 10 chunks	high	rag-pipeline	Quality drops past 8 chunks without re-rank; cost grows linearly
  Dedup absent on RAG with overlapping sources	medium	rag-pipeline	15-40% wasted tokens
  Sub-agent budget per Phase 5.3 unbounded	high	sub-agent-orchestrator	Single child can blow window; aggregation produces oversized parent context
  Large doc loaded as single chunk with no map-reduce	high	large-doc	Quality degrades past ~100k; partition / map-reduce mandatory
```

## Calibration aids — Impact × Likelihood

For findings whose category placement is borderline, score **impact** (what happens if the bloat / miss / drift continues) against **likelihood** (how often this gap will trigger in the context's actual use case):

```toon
impact_likelihood[9]{impact,likelihood,severity}:
  low	low	low
  low	medium	low
  low	high	medium
  medium	low	low
  medium	medium	medium
  medium	high	high
  high	low	medium
  high	medium	high
  high	high	critical
```

A cache miss that triggers on every run with high impact (production multi-turn agent at scale, no §1 caching) is **Critical**. A token-economy gap with low impact and rare trigger is **Low**.

## Risk tag — by fix scope

Tag every fix so the user knows how invasive adoption is.

```toon
risk_tags[3]{tag,meaning,example}:
  SAFE	Reword, reordering, or pure addition that does not change observed behavior; same inputs still produce same outputs more cheaply / cached	Add cache_control ephemeral; reorder stable-then-dynamic per §9; deduplicate overlapping retrieval chunks per §10
  REVIEW	Changes which inputs survive: compaction summarizes earlier turns, masking elides observations, re-rank drops chunks; some inputs handled differently	Apply §2 compaction at 70% threshold; apply §3 masking after 3 turns; apply §8 re-rank dropping low-score chunks
  BREAKING	Restructures the architecture: partitioning across N sub-agents, switching to batch mode, changing output schema for routed model	Switch from monolith to §7 sub-agent partitioning; route triage steps to smaller model (§11) with different tool format; move bulk path to §12 batch API
```

A plan usually contains multiple findings of mixed risk. Report the **overall risk tag** as the worst (most invasive) tag among adopted findings.

## Confidence — by evidence

```toon
confidence[3]{level,when,action}:
  high	Gap is mechanical (technique from TECHNIQUES.md provably absent — script-detected via ctxopt scan/count/dedup); use case demands it; fix is well-known	Adopt without further review
  medium	Technique partially present (e.g. §1 caching enabled but ordering per §9 wrong) or use case ambiguous and gap may be intentional	Adopt after one-line confirmation from user about intent
  low	Auditor would benefit from second opinion; harness unclear, workload undocumented, or technique on borderline	Escalate. If Severity >= High and Confidence = Low, mark needs human review
```

## Calibration: heuristic findings start at Medium

Findings derived from absence-detection heuristics (`ctxopt scan`, `ctxopt count`, `ctxopt dedup`) begin at **Medium** unless the auditor can manually argue for promotion. Promotion to High or Critical requires:

1. The technique is mandatory for the declared use case (per the [TECHNIQUES.md mapping](TECHNIQUES.md#how-the-skill-uses-this-catalog)).
2. The reviewer has read the surrounding context and confirmed the gap is not satisfied by an equivalent construct (e.g., custom compaction loop instead of `/compact`).

Inflated severity erodes trust faster than missed findings.

## Anti-pattern: padding the report

Three failure modes erode audit credibility:

1. **Inventing Minors to fill space.** Zero-findings is a valid result. If the context passes for the declared use case, emit `LGTM` and stop.
2. **Promoting Minors to Major.** Severity is bound to impact × likelihood, not to report length.
3. **Hedging without evidence.** `"This could potentially be better"` without a concrete category-cite or quote is noise. Drop it.

**Reproducibility rule.** Every finding must be reproducible from the original context inventory (Block 1). If a second auditor reading **only** Block 1 cannot identify the same gap, the finding is speculation and must be dropped.

## Floor: when not to file a finding

Drop the finding entirely (do not file as Info either) if **any** of the following holds:

- The context is for a workload the technique table does not require for that use case.
- The technique is explicitly turned off in the context with a one-line rationale (e.g., `# Caching disabled: every prompt is dynamic by product requirement`).
- The context fits inside the Phase 0.5 triage gate.

## Decision tree (one-glance summary)

```text
Q1. Is the technique required for this use case?
    no  → drop the finding.
    yes → continue.

Q2. Is the technique mechanically absent (regex / script / structure check)?
    yes → start at Medium.
    no  → start at Low or Info.

Q3. What is the impact × likelihood?
    high × every-run → promote to Critical.
    high × frequent  → promote to High.
    other            → keep at Medium / Low per the rubric above.

Q4. Risk tag for the fix?
    pure reword / reorder / addition → SAFE
    drops / summarizes / re-ranks    → REVIEW
    changes architecture / schema    → BREAKING

Q5. Confidence?
    mechanical absence + required technique → High
    partial / ambiguous                     → Medium
    auditor unsure of harness or workload   → Low — escalate if Sev ≥ High
```

## Shared lineage with prompt-engineering

§9 cache-friendly ordering also appears in [`prompt-engineering` Phase 5.4](../../prompt-engineering/SKILL.md). The two skills view the same primitive from different angles: `prompt-engineering` audits a single prompt and recommends ordering; `context-optimization` audits the whole context and recommends placement. Findings can cite both lineages without redundancy.

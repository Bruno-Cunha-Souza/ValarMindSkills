# SEVERITY_RUBRIC — context-optimization

> Reference companion for the [context-optimization](../SKILL.md) skill.

Severity calibrates how blocking a finding is. Risk tag calibrates how invasive the proposed fix is. Confidence calibrates how willing the reviewer is to stand behind the finding. Findings missing any of the three are dropped.

## Severity by category

Each row is a category (Cost waste, Cache miss, Quality degradation, Token bloat, Architecture risk). Each column is a severity. A finding lands at the cell where its symptom matches.

| Severity     | Cost waste                                              | Cache miss                                                          | Quality degradation                                                       | Token bloat                                  | Architecture risk                                          |
| ------------ | ------------------------------------------------------- | ------------------------------------------------------------------- | ------------------------------------------------------------------------- | -------------------------------------------- | ---------------------------------------------------------- |
| **Critical** | Production agent calling top-tier model on triage tasks ($/M scaling 10×+) | Cache breakpoint after dynamic content → 0% cache hit on multi-turn | Compaction summarizing safety rules / refusal hooks; semantic loss on commitments | Context > 95% capacity with no compaction triggered | Sub-agent partition missing on 4+ subtask workflow producing rate-limit failures |
| **High**     | Bulk eval running interactive API ignoring batch mode   | Stable content interleaved with dynamic; partial cache hit only       | Verbatim deletion (§6) replaced with paraphrase summarization on citation-bound RAG | Tool outputs > 70% of context, no masking    | Single-context monolith on workflow that should partition  |
| **Medium**   | Top-tier model used for structured extraction with no routing | System prompt not marked for caching at all                       | Re-rank threshold too aggressive → relevant chunks dropped                 | > 40% redundant chunks (no §10 dedup)        | Coordinator → sub-agent budget unbounded (no Phase 5.3 cap) |
| **Low**      | Cache TTL `1h` chosen for prompts re-used every 5 minutes (write-cost premium with no payback) | Suboptimal ordering of stable parts (e.g., schema after refusal hook) | Summary loses non-load-bearing back-and-forth without flag                 | > 15% redundancy in retrieved chunks         | Sub-agent boundaries not documented in plan                |
| **Info**     | "Routing matrix could be tighter"                       | "Could add second cache breakpoint for tool defs"                   | "Could log compaction events for observability"                            | "Filler phrases in system prompt"            | "Consider parallelism on independent sub-agents"           |

A single context can have findings across multiple categories. Aggregate **at the highest single-finding severity**, not by counting.

### Use case-specific severity patterns

When use case = `long-conv-agent`, the dominant failure modes are compaction timing and cache misses. When use case = `rag-pipeline`, dedup + chunk-pruning + injection-guard dominate. Apply this table only for the noted use cases; for others, read the matrix above.

| Pattern                                                          | Severity   | Use case        | Reasoning                                                                       |
| ---------------------------------------------------------------- | ---------- | --------------- | ------------------------------------------------------------------------------- |
| No compaction trigger documented above 80% capacity              | Critical   | long-conv-agent | Quality cliff at ~95%; auto-compaction is implementation-dependent              |
| `cache_control` absent on system prompt                          | High       | long-conv-agent | 90% of cache savings forgone on every turn                                      |
| Re-rank step missing on RAG with > 10 chunks                     | High       | rag-pipeline    | Quality drops past 8 chunks without re-rank; cost grows linearly                |
| Dedup absent on RAG with overlapping sources                     | Medium     | rag-pipeline    | 15-40% wasted tokens                                                            |
| Sub-agent budget per Phase 5.3 unbounded                         | High       | sub-agent-orchestrator | Single child can blow window; aggregation produces oversized parent context  |
| Large doc loaded as single chunk with no map-reduce              | High       | large-doc       | Quality degrades past ~100k; partition / map-reduce mandatory                   |

## Calibration aids — Impact × Likelihood

For findings whose category placement is borderline, score **impact** (what happens if the bloat / miss / drift continues) against **likelihood** (how often this gap will trigger in the context's actual use case):

| Impact / Likelihood | **Low (rare)** | **Medium (frequent)** | **High (every run)** |
| ------------------- | -------------- | --------------------- | -------------------- |
| **Low** (cosmetic, ≤ 5% cost / quality drift) | Low | Low                  | Medium               |
| **Medium** (10-30% cost spike or measurable quality drop) | Low | Medium      | High                 |
| **High** (window overflow, tool fail, escalating cost) | Medium | High       | Critical             |

A cache miss that triggers on every run with high impact (production multi-turn agent at scale, no §1 caching) is **Critical**. A token-economy gap with low impact and rare trigger is **Low**.

## Risk tag — by fix scope

Tag every fix so the user knows how invasive adoption is.

| Tag        | Meaning                                                                                                                                       | Example                                                                                                       |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `SAFE`     | The fix is a reword, reordering, or pure addition that does not change observed behavior; the same inputs still produce the same outputs more cheaply / cached. | Add `cache_control: ephemeral`; reorder stable-then-dynamic per §9; deduplicate overlapping retrieval chunks per §10. |
| `REVIEW`   | The fix changes which inputs survive: compaction summarizes earlier turns, masking elides observations, re-rank drops chunks. Some inputs are handled differently. | Apply §2 compaction at 70% threshold; apply §3 masking after 3 turns; apply §8 re-rank dropping low-score chunks. |
| `BREAKING` | The fix restructures the architecture: partitioning across N sub-agents, switching to batch mode, changing output schema for a routed model. | Switch from monolith to §7 sub-agent partitioning; route triage steps to a smaller model (§11) with different tool format; move bulk path to §12 batch API. |

A plan usually contains multiple findings of mixed risk. Report the **overall risk tag** as the worst (most invasive) tag among adopted findings.

## Confidence — by evidence

| Confidence | When                                                                                                                                                                                | Action                                                                          |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| **High**   | The gap is mechanical (the technique from [TECHNIQUES.md](TECHNIQUES.md) is provably absent — script-detected via `00-context-scan.sh` / `01-token-count.py` / `02-dedup-detect.sh`), the use case demands it, and the fix is well-known. | Adopt without further review.                                                   |
| **Medium** | The technique is partially present (e.g., §1 caching enabled but ordering per §9 is wrong), or the use case is ambiguous and the gap may be intentional.                            | Adopt after a one-line confirmation from the user about intent.                 |
| **Low**    | The auditor would benefit from a second opinion. The harness is unclear, the workload is undocumented, or the technique is on the borderline.                                         | Escalate. If `Severity ≥ High` and `Confidence = Low`, mark `needs human review`. |

## Calibration: heuristic findings start at Medium

Findings derived from absence-detection heuristics (`grep` for `cache_control`, file-size scan, token-count threshold) begin at **Medium** unless the auditor can manually argue for promotion. Promotion to High or Critical requires:

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

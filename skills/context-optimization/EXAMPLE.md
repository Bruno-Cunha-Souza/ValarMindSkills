# EXAMPLE — context-optimization

> Worked example end-to-end of [context-optimization](SKILL.md). Long-conversation agent at 94% utilization → audited, optimization plan generated, Block 5 verification probes proposed.

## Input

User reports their Claude Code session has degraded after 80 turns of work on a Go REST API codebase. The statusline shows `94%` and the agent is starting to confuse paths from earlier turns. User runs:

```bash
bash scripts/run-all.sh ~/.claude/projects/abc123/
```

The orchestrator emits findings JSON-Lines and a Markdown report. User pastes the inventory + first findings to the skill:

```text
session: dev-api-refactor
turns:   80
size:    187,432 tokens (94% of 200k Sonnet 4.6 window)
harness: claude-code
```

## Phase 0 — Capture & Classify

```text
ORIGINAL CONTEXT INVENTORY (verbatim categories + sizes):
"""
system prompt:        1,240 tokens   (0.7%)
tool definitions:     8,420 tokens   (4.5%)
message history:      92,150 tokens  (49.2%)  — 80 turns
retrieved chunks:     0 tokens       (0%)
tool outputs:         85,622 tokens  (45.7%)
TOTAL:                187,432 tokens / 200,000 = 94% utilization
"""

mode:        audit
use case:    long-conv-agent
harness:     claude-code

triage gate (Phase 0.5): NOT triggered
  - size 187k > 8k threshold
  - utilization 94% > 50%
  - degradation reported ("agent confusing paths from earlier turns")
  → proceed to Phase 1
```

Honest audit pledge: cite verbatim from inventory · read long-conv-agent baseline first · run scripts before claiming missing technique.

## Phase 1 — Inventory

Top categories: **message history (49.2%)** + **tool outputs (45.7%)** = 94.9% of total. System prompt + tool definitions = 5.2% (small but uncached — payback large per call).

## Phase 2 — Cost & Quality Audit

| Lever | Detection | Severity |
| --- | --- | --- |
| Cache hit rate | `cache_control` ABSENT on system prompt + tool defs | High (uncached on every turn — 0% cache hit projected) |
| Compaction trigger | NO manual trigger documented; relies on auto-compaction at 95% | Critical (currently at 94% — overdue) |
| Masking opportunity | Tool outputs ~85k = 45.7% of context, ages span 80 turns | High (no §3 applied) |
| Partition candidates | Single-context workflow; subtasks could split (search vs analyze vs apply) | Low for this use case (long-conv-agent skeleton, not sub-agent-orchestrator) |
| §9 ordering | Stable / dynamic interleaved? Yes — system prompt has dynamic timestamp | Medium |
| §13 harness primitive | Plan must cite `/compact` (Claude Code) | (will be cited in Block 3) |

## Phase 3 — Technique Selection

Use case = `long-conv-agent`. Required techniques per [TECHNIQUES §How the skill uses](references/TECHNIQUES.md#how-the-skill-uses-this-catalog): §1, §2, §3, §4, §6, §9, §13. Walk each:

- **§1 Prompt caching** — ABSENT. Critical for multi-turn; 80 turns × full prefix = enormous waste.
- **§2 Compaction** — NO manual trigger. Auto at 95% is too late + opaque.
- **§3 Observation masking** — ABSENT. 80 turns × verbose tool outputs = 45.7% of context.
- **§4 Dynamic summarization** — Optional (session not yet > 60 turns of growth — borderline). Defer.
- **§6 Verbatim deletion** — N/A (no citation-bound chunks in this session; pure code-edit).
- **§9 Cache-friendly ordering** — Mixed; current prompt has dynamic timestamp early.
- **§13 Harness command** — Will cite `/compact` in plan (REQUIRED per Phase 4.1).

## Findings (detail blocks)

```text
C-001 — No compaction trigger above 80% utilization
  Phase: 2   Severity: Critical   Confidence: High   Risk: REVIEW
  Category: message history (92k) + tool outputs (85k) = 94% util
  Issue: Auto-compaction (Claude Code 95% threshold) is implementation-dependent
         and opaque (user can't see what was elided). Production sessions need
         deterministic timing.
  Fix:   Trigger /compact at 75% utilization (manual). See HARNESS_NOTES Claude Code.
  Technique: [§2](references/TECHNIQUES.md#2-compaction-anthropic-auto--manual)
             + [§13](references/TECHNIQUES.md#13-harness-compaction-commands-compact-sessioncompaction)

C-002 — cache_control absent on system prompt + tool defs
  Phase: 2   Severity: High   Confidence: High   Risk: SAFE
  Category: system prompt (1.2k) + tool defs (8.4k) = 9.7k stable prefix
  Issue: Without cache_control, Anthropic re-processes 9.7k tokens at full input
         price every turn. Over 80 turns, that's 776k cumulative re-processed
         tokens. Cache write 1.25× × 1 + cache read 0.1× × 79 = 9.15× equivalent
         input cost; without cache, 80× full price = 8.7× more expensive.
  Fix:   Add cache_control: { type: "ephemeral" } on system prompt block + tool defs block.
  Technique: [§1](references/TECHNIQUES.md#1-prompt-caching-5min--1h-ttl-stable-prefix-exact-match)

C-003 — Tool outputs > 45% of context, no masking
  Phase: 3 §3   Severity: High   Confidence: Medium   Risk: REVIEW
  Category: tool outputs 85,622 tokens (45.7%)
  Issue: Verbose read_file / search_codebase outputs from turns 1..50 still in
         context. 80% of these have already been used to make decisions — the
         raw output is no longer load-bearing.
  Fix:   Replace tool outputs from turns > 3 ago with [Obs:OBS-NNN] references
         + 1-line key conclusion. Restore on demand if agent re-fetches.
  Technique: [§3](references/TECHNIQUES.md#3-observation-masking)

C-004 — Stable / dynamic content interleaved (§9 violation)
  Phase: 3 §9   Severity: Medium   Confidence: High   Risk: SAFE
  Category: system prompt (1.2k)
  Issue: System prompt block contains "Today is {date}" mid-block. Even with §1
         cache_control added, prefix cache invalidates at first dynamic byte —
         only role grounding before the date is cached.
  Fix:   Move {date} into user message or below cache breakpoint. Stable parts
         (role, tools, schema) come first; dynamic parts (date, query, history)
         come after the breakpoint.
  Technique: [§9](references/TECHNIQUES.md#9-cache-friendly-ordering-stable--dynamic)

C-005 — No deterministic compaction policy documented
  Phase: 4 §13   Severity: Medium   Confidence: High   Risk: SAFE
  Category: workflow / runbook
  Issue: Plan output should cite the harness primitive (Claude Code: /compact)
         so the user can act without harness lookup.
  Fix:   Plan Block 3 must emit "/compact at 75% utilization" verbatim.
  Technique: [§13](references/TECHNIQUES.md#13-harness-compaction-commands-compact-sessioncompaction)
            + [HARNESS_NOTES Claude Code](references/HARNESS_NOTES.md#claude-code)
```

## Phase 5 — Token Economy

Plan-projected delta:

```text
Token delta:
  before:    187,432 tokens (94% of 200k window)
  after:     54,800 tokens  (28% of 200k window)
  delta:    −132,632 tokens (−70.8%)
  cache hit projection: 0% → 67% on stable prefix (9.7k tokens cached)
  invariants preserved:
    - system prompt content (cache_control wraps, doesn't change content)
    - all `never`/`must not` rules
    - last 5 turns verbatim (compaction summarizes turns 1..75 only)
    - all decisions / commitments / open threads (compaction summary preserves these)
```

Use-case `long-conv-agent` budget per [Phase 5.3](SKILL.md#53-token-budget-per-use-case): ≤ 100k tokens. Projected after = 54,800 → within budget. T-001 not triggered.

## Phase 6 — Output

### Block 1 — Original context inventory (verbatim)

```text
| Category          | Tokens     | % of total |
| ----------------- | ---------- | ---------- |
| system prompt     | 1,240      | 0.7%       |
| tool definitions  | 8,420      | 4.5%       |
| message history   | 92,150     | 49.2%      |
| retrieved chunks  | 0          | 0%         |
| tool outputs      | 85,622     | 45.7%      |
| **TOTAL**         | 187,432    | 94% of 200k window |
```

### Block 2 — Findings (summary table)

| ID    | Sev      | Conf   | Risk     | Phase | Title                                    |
| ----- | -------- | ------ | -------- | ----- | ---------------------------------------- |
| C-001 | Critical | High   | REVIEW   | 2     | No compaction trigger above 80% util     |
| C-002 | High     | High   | SAFE     | 2     | cache_control absent on system prompt    |
| C-003 | High     | Medium | REVIEW   | 3     | Tool outputs > 45%, no §3 masking        |
| C-004 | Medium   | High   | SAFE     | 3     | Stable / dynamic interleaved (§9)        |
| C-005 | Medium   | High   | SAFE     | 4     | No harness primitive in plan             |

### Block 3 — Optimization plan

```text
Order: cache layer → compression → architecture → RAG → cost → harness.
(architecture / RAG / cost N/A for this single-agent code-edit session.)

1. (SAFE — C-002) Add cache_control: { type: "ephemeral" } on:
   - system prompt block (1.2k tokens)
   - tool definitions block (8.4k tokens)
   Cache breakpoint AFTER tool defs, BEFORE conversation history.
   Expected: 67% cache hit projection on next 79 turns.

2. (SAFE — C-004) Move dynamic content (current date, current branch) OUT of
   system prompt. Place at top of user message or below cache breakpoint.

3. (REVIEW — C-001, C-005) Trigger /compact at 75% utilization manually.
   Currently at 94% — overdue. Run: /compact
   Compaction summary preserves: decisions, commitments, open threads, all
   `never`/`must not` rules, last 5 turns verbatim.

4. (REVIEW — C-003) Apply observation masking on tool outputs > 3 turns old.
   Pattern: replace raw output with `[Obs:OBS-NNN elided. Key: <one-line>]`.
   Re-fetch via read_file / search_codebase if needed in later turns.

Harness: claude-code
  - /compact at 75% utilization (Claude Code statusline indicator).
  - cache_control marked via MCP server config (if applicable).
  - Watch ~/.claude/projects/<hash>/<session>.jsonl for post-compaction state.
```

### Block 4 — Summary

| Metric                       | Before        | After          |
| ---------------------------- | ------------- | -------------- |
| context size                 | 187,432 tk    | 54,800 tk      |
| utilization                  | 94%           | 28%            |
| cost lever coverage (long-conv-agent) | 0 / 7 | 6 / 7         |
| cache hit projection         | 0%            | 67%            |
| risk tag (overall)           | —             | REVIEW         |
| confidence                   | —             | High           |

Suggested next step:
  1. Adopt Block 3 plan in order — cache layer first (SAFE, lowest risk + highest payback).
  2. Run Block 5 verification suggestions.
  3. Re-run /valarmindskills:context-optimization after one production cycle (next 20-50 turns).

### Block 5 — Verification suggestions

(Required: overall Risk = REVIEW.)

- **Cache hit probe.** After applying step 1 (cache_control), make 3 consecutive
  turns and inspect API response cache metric. Expect ≥ 50% on turn 2 onwards.
- **Compaction probe.** After /compact (step 3), inspect `~/.claude/projects/<hash>/<session>.jsonl`
  — confirm summary preserves all `never`/`must not` rules from system prompt
  (grep for them). Expect ALL preserved.
- **Masking probe.** After applying step 4, query the agent about a turn-2
  observation. Expect: agent refers to `[Obs:OBS-NNN]` and offers re-fetch, not
  verbose recall. If verbose recall, masking didn't apply.
- **Re-audit probe.** Re-run `bash scripts/run-all.sh ~/.claude/projects/<hash>/`.
  Expect: 0 Critical, 0 High findings (C-001, C-002, C-003 cleared); only Lows /
  Info remain.

## What this demonstrates

- **Block 1 verbatim** — the inventory contract every later block is checked against. Categories + sizes preserved exactly as scripts emit.
- **5 findings split** between cost (C-001, C-002), quality (C-003, C-004), and process (C-005). Each cites a specific category from Block 1 (no speculation).
- **Severity calibrated** — only the compaction overdue is Critical (impact × likelihood: agent already degrading on every turn). cache_control absence is High (production multi-turn). No inflation.
- **Risk tags differentiate** SAFE additions (cache_control, ordering) from REVIEW changes (compaction summary, masking — some inputs handled differently in next turns).
- **Token delta strongly negative** — 94% → 28% = 70.8% reduction. Justified by inventory split (45% tool outputs maskable, 50% history compactable).
- **Block 5 mandatory here** because overall Risk = REVIEW. Probes are concrete (cache hit metric, jsonl grep, re-audit script).
- **Harness primitive cited** (per Phase 4.1) — `/compact` named verbatim, not `"use compaction"`.

## Other use cases

This worked example covers **`long-conv-agent`** use case. For the four primary classes:

- **`rag-pipeline`** — see [USE_CASES §2](references/USE_CASES.md#2-rag-pipelines) for failure modes (top-K stuffing, dedup absence, prompt-injection via chunk content) + canonical skeleton (vector → dedup → re-rank → threshold → cap N).
- **`sub-agent-orchestrator`** — see [USE_CASES §3](references/USE_CASES.md#3-sub-agent-orchestrators) for parent / child budgeting, isolation enforcement, routing matrix.
- **`large-doc`** — see [USE_CASES §4](references/USE_CASES.md#4-large-doc-workflows) for map-reduce + caching across runs.
- **`skill-prompt`** — cross-link to `@prompt-engineering` for single-prompt audit; this skill handles whole-skill context if it exceeds budget.

Producing 4× expanded EXAMPLE would duplicate USE_CASES.md material; the canonical skeletons there are the worked examples for those classes.

## Fonte

Repository canonical: [`skills/context-optimization/EXAMPLE.md`](file:///Users/brunosouza/Dev/Bruno-Cunha-Souza/ValarMind/ValarMindSkills/skills/context-optimization/EXAMPLE.md)

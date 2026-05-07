---
name: prompt-engineering
description: "Lifecycle LLM prompt audit/harden/rewrite. Targets SKILL.md, RAG, agent tool descriptions, system prompts. Phases: capture → translate → clarity → anti-hallucination → structure → token economy. Emits findings (SAFE/REVIEW/BREAKING) + rewritten prompt + token delta — LGTM if sound. Read-only — never auto-applies. Triggers: 'audit prompt', 'auditar prompt', 'engenharia de prompt', '/prompt-engineering'."
source: ValarMindSkills
---

# Prompt Engineering Lifecycle

> "A vague prompt is a coin flip. A clear prompt with a refusal hook is a contract."

This skill audits and rewrites a prompt that will be sent to an LLM. It is **read-only by default** — it never auto-applies the rewrite, it produces a proposal. It is **language-aware** (PT and EN as primary; other inputs are translated to EN with a side-by-side preservation list). It is **lifecycle-driven**: capture → translate → clarity → anti-hallucination → structure → token economy → output.

The skill exists because LLM-facing prompts written by hand drift toward the same failure modes: missing success criteria, undefined output format, no examples, no refusal hooks, no "never invent" floor, and silent assumptions about role. Each of those gaps is a known driver of hallucinated, off-format, or unsafe output. Every guardrail in the Constraints section is there to push the rewrite toward a contract the model can fulfil deterministically — and to keep the skill itself from making the same mistakes.

## When to Use

This skill is built for four primary classes of prompt — see [references/USE_CASES.md](references/USE_CASES.md) for the per-class strategy subset, canonical skeleton, and findings catalog.

1. **Skill prompts (`SKILL.md` and equivalents).** Short-lived, slash-command-triggered LLM-agent skills: Claude Code skills, ChatGPT GPTs, Cursor rules. Pairs with `@skill-creator` (which scaffolds the file; this skill audits the prompt content inside it).
2. **RAG prompts.** System / user templates that wrap retrieved chunks before sending to the model. Heavy emphasis on prompt-injection guards, citation requirements, and structured input parsing.
3. **Agent tool descriptions.** The `description` fields on functions / tools that drive when and how a model calls them. Emphasis on disambiguation, side-effect declaration, and "do not use when" antipatterns.
4. **Agent base / system prompts.** Long-running agent identity prompts (Claude Code subagents, custom GPT system prompts, LangGraph node prompts) — define persona, capabilities, tool map, refusal hooks, and plan/act/verify workflow for the entire session. Distinct from (1): skill prompts are short and slash-triggered; agent base prompts frame the session itself. Distinct from (3): tool descriptions are read by the agent to decide whether to call a tool; agent base prompts define the agent that does the calling.

Also handles generic system, user, and few-shot prompts as a secondary use case.

Trigger scenarios:

- The user has a `SKILL.md` draft and wants it audited before publishing.
- The user has a RAG prompt that hallucinates citations or follows instructions injected into retrieved chunks.
- The user is wiring a new tool into an agent and wants the `description` reviewed before two tools collide on activation.
- The user wrote a prompt in PT-BR or another language and wants it translated to EN with intent and safety rules preserved.
- A model is hallucinating, missing the format, or refusing tasks it should accept — and the suspected cause is the prompt, not the model.
- A long prompt accreted instructions over time and the user wants it deduplicated and trimmed without losing substance.
- The user explicitly asks: `'review prompt'`, `'improve prompt'`, `'audit SKILL.md'`, `'harden RAG prompt'`, `'review tool description'`, `'revisar prompt'`, `'auditar prompt'`, `'auditar SKILL.md'`, `'engenharia de prompt'`, or invokes `/valarmindskills:prompt-engineering`.

## Do not use when

- The user wants to **review code**, not a prompt — use `@code-review`.
- The user wants to **debug** an LLM agent's runtime behavior — start with `@code-debugger` for the orchestration layer; this skill only fixes the prompt itself.
- The user only wants **token compression of conversation context** (KV-cache reuse, observation masking, partitioning) — that is `@context-optimization`, not prompt rewriting.
- The user wants a **shorter response style for the assistant**, not a better prompt — that is `@caveman`.
- The prompt is a one-line throwaway with no agent or system context behind it (e.g., `"summarize this PDF"`) — the audit overhead exceeds the value; tell the user and stop.
- The prompt is for a domain with stricter compliance requirements (legal, medical, financial advice) than the skill can verify — surface the gap and recommend domain expert review before deployment.

## Prerequisites

Collect before starting. Each missing input degrades a specific phase rather than blocking the whole audit, but missing inputs are reported in the output.

| Input | Required | How to obtain |
| --- | --- | --- |
| Prompt verbatim | Yes | Ask the user to paste the exact prompt, including delimiters and variables |
| Prompt role | Yes | Ask: system / user / agent / few-shot / RAG template |
| Target model family | No | Helps tune token budgets and instruction-following style |
| Target output format | No | If the user already has a schema, the audit grades the prompt against it |
| Known failure modes | No | "Hallucinated paths", "ignored format", "refused valid input" — these focus the audit |
| Tooling / skill map | No | If the prompt is for an agent with tools or skills, list them so the rewrite includes a tool map |

The skill never sends the prompt to another model for evaluation. Every finding is derived from reading the prompt itself against the catalog in [references/STRATEGIES.md](references/STRATEGIES.md).

## Phase 0 — Capture & Classify

Read the prompt verbatim. Do not paraphrase, summarize, or reformat at this point — the original text is the evidence base for every later phase.

### 0.1 Capture

```text
ORIGINAL PROMPT (verbatim, fenced):
"""
<paste user-provided prompt here exactly, including any leading whitespace,
markdown markers, variables, and delimiters>
"""
```

If the prompt arrives without delimiters, mark the boundary and ask the user to confirm before proceeding. A misread boundary contaminates every later phase.

### 0.2 Classify

Determine three axes:

| Axis | Values | Why it matters |
| --- | --- | --- |
| **Role** | system, user, **agent-base**, few-shot, RAG, **skill** (`SKILL.md`), **tool-description** | Drives which strategies are relevant (persona stability + tool map + plan-act-verify for agent-base, schema for user, prompt-injection guard for RAG, trigger phrases for skill, "do not use when" for tool-description) |
| **Language** | en, pt, es, other | Triggers Phase 1 if not `en` |
| **Use case** | **skill** \| **rag** \| **agent-tool** \| **agent-base** \| factual \| generation \| classification \| extraction \| planning \| code \| conversation | The first four map to the [USE_CASES.md](references/USE_CASES.md) canonical skeletons; the rest map to generic strategy subsets in [STRATEGIES.md](references/STRATEGIES.md#how-the-skill-uses-this-catalog) |

State each axis explicitly in one line before moving on. Example:

```text
role:        system
language:    pt
use case:    extraction (parse PR diff → JSON findings)
```

For the four primary classes, the use case is named explicitly:

```text
role:        skill           # SKILL.md being authored or revised
language:    en
use case:    skill           # → load USE_CASES.md §1

role:        rag             # RAG system template
language:    en
use case:    rag             # → load USE_CASES.md §2

role:        tool-description # Function description in JSON Schema
language:    en
use case:    agent-tool      # → load USE_CASES.md §3

role:        agent-base      # Agent system prompt (long-running session)
language:    en
use case:    agent-base      # → load USE_CASES.md §4
```

### 0.3 Bound the audit

Count the prompt size. Long prompts (> 2000 tokens estimated, ~1500 words) usually contain duplicated instructions and are the highest-yield targets for Phase 5. Short prompts (< 50 tokens) usually need *more* content — additions in Phase 4 will outweigh subtractions in Phase 5.

### 0.4 Honest audit pledge

Before producing any finding, commit to:

1. **Cite verbatim.** Each finding quotes a passage that is **literally absent**, **directly contradictory**, or **demonstrably redundant** in the original. Paraphrase is not evidence.
2. **Read the use case baseline first.** Open [USE_CASES.md](references/USE_CASES.md) §N for the declared use case and check **every** required strategy against the original before flagging anything as missing.
3. **Different wording is not a missing strategy.** If a strategy from [STRATEGIES.md](references/STRATEGIES.md) is genuinely present — even with vocabulary unlike the catalog — do not promote it to a finding.
4. **Stop on LGTM.** If the prompt passes every required strategy for its use case, emit Block 4 with `LGTM — no clarity, hallucination, or token-economy gaps in scope` and stop. Do not promote Minor or speculative observations to fill the report.
5. **Calibrate confidence.** Findings derived from heuristics (regex, "this looks ambiguous") are `Confidence: Low` or `Medium`. `Confidence: High` requires a verbatim quote of the gap.

This pledge is the audit's contract with the user. Padded reports erode trust faster than missed findings.

## Phase 1 — Translate & Normalize

Run only if Phase 0 detected a non-English source. EN is the working language for the rewrite because most public model evaluations and prompt-engineering literature are EN-first; preserving the same prompt in EN is also easier to compare across reviewers.

### 1.1 Translate

Produce the EN translation side-by-side with the original:

```text
| Source (pt)                                         | EN translation                                |
| --------------------------------------------------- | --------------------------------------------- |
| Você é um revisor de PR rigoroso.                   | You are a rigorous PR reviewer.               |
| Nunca invente caminhos de arquivo.                  | Never invent file paths.                      |
| Se não souber, diga "não sei".                      | If you do not know, say "I don't know".       |
```

### 1.2 Preservation list

List every term that **must not** be translated, with the reason:

```text
Preserved verbatim:
  - "PR"            — common acronym, untranslated in both languages
  - "OWASP"         — proper noun
  - "{repo_path}"   — variable placeholder
  - "context.Context" — Go type name
```

If translation requires changing a safety rule, **stop** and surface it. Safety-relevant rules (`never`, `must not`, `do not`, `refuse if`) keep their original force in EN; weakening them is a finding, not an edit.

## Phase 2 — Clarity Audit

A prompt is clear when an indifferent reader can answer four questions without inference:

1. **What role does the model play?**
2. **What input is it operating on?**
3. **What does success look like?**
4. **What is the exact output format?**

Walk the prompt and grade each axis explicitly.

### 2.1 Clarity checklist

| # | Axis | Pass criterion |
| --- | --- | --- |
| 1 | Role defined | Prompt names the persona/expertise (e.g., "You are a senior security reviewer") |
| 2 | Task stated | One sentence describes the task in imperative mood |
| 3 | Input boundary marked | The prompt names where the input begins/ends (delimiters, variables, sections) |
| 4 | Success criterion explicit | Prompt states what "correct" looks like (e.g., "Output is valid JSON matching the schema below") |
| 5 | Output format pinned | JSON, Markdown, fenced block, or other — and the schema is shown |
| 6 | Edge cases named | Prompt covers empty input, missing fields, ambiguous input |
| 7 | Examples present | At least one worked example for non-trivial tasks |
| 8 | Refusal path named | Prompt states when to refuse or escalate (out of scope, unsafe, ambiguous) |

Each missed axis is a finding. Severity follows [references/SEVERITY_RUBRIC.md](references/SEVERITY_RUBRIC.md): a missing success criterion is Critical; a missing example is usually Minor unless the task is non-trivial.

### 2.2 Finding format

Each finding cites the passage by line or quote and proposes the smallest possible fix:

```text
P-2-001 — Missing success criterion
  Quote:
    | "Revise meu PR e me diga o que tá errado."
  Issue:
    "What is wrong" is unbounded. The model cannot know whether
    style nits, security flaws, or perf regressions are in scope.
  Fix (REVIEW):
    Add a success criterion: "Return findings only if they are
    Critical, High, or Medium per the SEVERITY_RUBRIC. Stop after 10."
```

## Phase 3 — Anti-Hallucination Audit

Apply the catalog in [references/STRATEGIES.md](references/STRATEGIES.md). Every entry the prompt does not satisfy is a finding.

### 3.1 Strategies expected

| # | Strategy | Required when | Source |
| --- | --- | --- | --- |
| 1 | Role grounding | Always | [STRATEGIES §1](references/STRATEGIES.md#1-role-grounding) |
| 2 | Output schema pinning | Format matters | [STRATEGIES §2](references/STRATEGIES.md#2-output-schema-pinning) |
| 3 | Citation requirement | Factual / extraction tasks | [STRATEGIES §3](references/STRATEGIES.md#3-citation-requirement) |
| 4 | Calibrated confidence | Factual / classification tasks | [STRATEGIES §4](references/STRATEGIES.md#4-calibrated-confidence) |
| 5 | Never-invent floor | Always for factual tasks | [STRATEGIES §5](references/STRATEGIES.md#5-never-invent-floor) |
| 6 | Few-shot examples | Non-trivial format or judgment | [STRATEGIES §6](references/STRATEGIES.md#6-few-shot-examples) |
| 7 | Refusal hooks | Safety-relevant or scope-bounded | [STRATEGIES §7](references/STRATEGIES.md#7-refusal-hooks) |
| 8 | Structured input parsing | Any prompt with multiple inputs | [STRATEGIES §8](references/STRATEGIES.md#8-structured-input-parsing) |
| 9 | Step-by-step decomposition | Multi-step reasoning / agents | [STRATEGIES §9](references/STRATEGIES.md#9-step-by-step-decomposition) |
| 10 | Counter-examples | High ambiguity | [STRATEGIES §10](references/STRATEGIES.md#10-counter-examples) |
| 11 | Skill / tool map | Agent prompts with tools | [STRATEGIES §11](references/STRATEGIES.md#11-skill--tool-map) |
| 12 | Verification step | Long tasks where the model can self-check | [STRATEGIES §12](references/STRATEGIES.md#12-verification-step) |

Calibrate findings: heuristic findings (regex, simple absence) start at **Medium** severity. Promotion to High or Critical requires manual confirmation that the gap is exploitable for hallucination in the prompt's actual use case.

### 3.2 Common hallucination smells

| Smell | Detection | Fix |
| --- | --- | --- |
| "Be helpful" without bound | Phrase appears with no scope | Replace with explicit success criterion |
| "Use your knowledge" without citation rule | No citation requirement on factual tasks | Add a never-invent floor + citation requirement |
| "If unsure, do your best" | Encourages confabulation | Replace with "If unsure, say 'I don't know' and ask one clarifying question" |
| "Be creative" on extraction | Wrong primitive for the task | Remove; replace with strict schema |
| Open list ("e.g., …") on output schema | Model picks any extra field | Replace with closed enum or explicit `additionalProperties: false` |

Each smell is a finding with a quote, a fix, and a risk tag.

## Phase 4 — Structure Recommendations

Once gaps are documented, propose **what to add**, not just what to remove. Each recommendation is a section the rewrite will include.

If the use case is `skill`, `rag`, or `agent-tool`, use the canonical skeleton from [USE_CASES.md](references/USE_CASES.md) (§1 / §2 / §3 respectively) instead of the generic order below — those skeletons already encode the right section ordering and required fields for that class.

For all other use cases, the generic canonical order is:

1. **Role + persona** — one sentence.
2. **Task + success criterion** — imperative, with an explicit "done when …" clause.
3. **Inputs** — labeled, with delimiters or variable names.
4. **Constraints** — `must`, `must not`, `never`. One bullet each.
5. **Output schema** — JSON, Markdown skeleton, or YAML.
6. **Examples** — one golden path; one edge case if relevant; one counter-example if ambiguity is high.
7. **Refusal / escalation hooks** — when to refuse, when to ask back.
8. **Tool / skill map** — only for agent prompts.

The rewrite renders these sections explicitly. If a section is intentionally omitted, the rewrite says so (`Examples: not applicable for this prompt because …`). Silent omission is a finding.

### 4.1 When to add a skill map

If the prompt is for an agent that has access to tools or sub-skills, the rewrite must include a table mapping each tool to a one-line "use when" rule. Example:

```text
| Tool                    | Use when                                            |
| ----------------------- | --------------------------------------------------- |
| `search_codebase`       | The user names a file/symbol that may have moved    |
| `run_tests`             | The fix is candidate-ready and needs verification   |
| `web_search`            | A library version, CVE, or RFC is referenced        |
```

A skill map without `use when` rules is itself a finding — agents over-call tools without one.

## Phase 5 — Token Economy

Compress without losing substance. Substance = role, success criterion, constraints, refusal hooks, schema. Filler = pleasantries, hedging, redundant restatements, instructions repeated under different headings.

### 5.1 Compression rules

- **Never** compress a `never`, `must not`, or `do not` rule. Re-word for brevity, but keep the negation form.
- **Never** compress a refusal hook. Refusal logic that is half-stated turns into an attempt.
- **Never** compress an example to less than one input/output pair. Truncated examples teach worse than absent ones.
- **Always** dedupe: if the same instruction appears twice in different words, keep the more specific phrasing.
- **Always** prefer structured tags over prose:

  ```text
  Before:
    "It's really important that you always make sure to provide
     citations for any factual claim, otherwise the user can't trust
     the answer."

  After:
    "Cite every factual claim (path:line or URL). Uncited claims are rejected."
  ```

### 5.2 Reporting the delta

Estimate token count before and after. Report as:

```text
Token delta:
  before: 412 tokens (est., model tokenizer agnostic)
  after:  287 tokens
  delta:  −125 tokens (−30.3%)
  invariant: every "never"/"must not" rule preserved
              every example pair preserved
              role and success criterion preserved
```

If the rewrite is **longer** than the original (common when the original is a one-liner), report the same delta with a positive sign and a one-line rationale (`+47 tokens — added role, schema, refusal hook`).

## Phase 6 — Output

Emit the deliverable in four numbered blocks. The user can adopt all, some, or none.

### Block 1 — Original (verbatim)

The exact prompt as captured in Phase 0, fenced. No edits, no annotations.

### Block 2 — Findings table + detail

Severity-ranked table, then one detail block per finding. Each finding has: id, severity, confidence, risk tag, quote, issue, fix.

### Block 3 — Rewritten prompt

The proposed rewrite, fenced, complete enough to copy-paste. EN by default. Includes the canonical sections from Phase 4.

### Block 4 — Summary table

```text
| Metric                  | Value                                 |
| ----------------------- | ------------------------------------- |
| role classified         | system / user / agent / few-shot / RAG |
| language (in / out)     | pt → en                               |
| clarity score           | 4 / 8 axes pass (was 1 / 8)            |
| anti-hallucination cov. | 9 / 12 strategies (was 0 / 12)         |
| token delta             | −125 tokens (−30.3%)                   |
| risk tag (overall)      | REVIEW                                 |
| confidence              | High                                   |
```

### Block 5 (optional) — Verification suggestions

For non-trivial rewrites, propose how the user can validate the change:

- Run the original and rewritten prompts on the same 3 inputs and compare outputs.
- Ask the model to follow the schema; reject if it deviates.
- Probe the refusal hook with an out-of-scope input.

## Constraints

- **Never edit the prompt automatically.** This skill is a reviewer; the rewrite is a proposal in Block 3, not a side effect.
- **Never invent user intent.** If the prompt is ambiguous (role unclear, use case unclear), stop and ask before producing the rewrite. A confident rewrite of an unread prompt is the highest-risk failure mode for this skill.
- **Never strip a safety rule.** Every `never`, `must not`, `do not`, or `refuse if` clause in the original survives into the rewrite, in EN, with the same force. Preserved verbatim if possible.
- **Never claim translation fidelity without listing preserved terms.** Phase 1.2 produces an explicit preservation list; if the list is empty, the translation is not approved.
- **Never inflate severity to look thorough.** Use [references/SEVERITY_RUBRIC.md](references/SEVERITY_RUBRIC.md). Heuristic findings start at Medium; promotion requires confirmation.
- **Never invent findings to appear thorough.** If the audit yields zero genuine gaps for the declared use case, emit Block 2 with `(no findings)`, Block 3 with `no rewrite needed — prompt already passes the audit`, Block 4 with `LGTM`, and stop. Every finding cites a verbatim absence, contradiction, or redundancy. Speculation is not a finding.
- **Never promote Minor findings to Major to fill the report.** Severity is bound to impact × likelihood per [references/SEVERITY_RUBRIC.md](references/SEVERITY_RUBRIC.md), not to report length. Padding the report erodes audit credibility faster than missed findings.
- **Never quote a user instruction paraphrased.** Quotes in findings are byte-for-byte from the original. If a passage is summarized for brevity, label it `summary:` not `quote:`.
- **Never recommend a strategy without citing the catalog entry.** Every Phase 3 finding links to [STRATEGIES.md §N](references/STRATEGIES.md).
- **Never omit Block 1.** The original verbatim is the contract; comparing to it is how the user audits the audit.
- **Never auto-translate when the user asked only for an audit.** Phase 1 runs only if the user asked to translate or if the prompt is not in EN and the rewrite needs to land in EN. Otherwise, audit in source language.
- **Never compress a `never` rule into a positive instruction.** "Never X" and "always not-X" feel equivalent to a writer; they are not equivalent to a model. Keep the negation.
- **Always emit Blocks 1–4 verbatim** in the Output format below — even when there are zero findings.
- **Always cap the rewrite at 2× the original token count** unless the user explicitly asked for a longer prompt. Longer-than-necessary prompts erode instruction-following.
- **Always cross-link to a sibling skill** when the finding belongs to its domain (`@context-optimization`, `@clean-code`, `@code-review`, `@caveman`, `@superpowers`).

## Output format

Print verbatim after every successful run. The four-block report is the deliverable.

```text
prompt-engineering: <one-line description provided by user, or auto-derived>
  role:        <system | user | agent-base | few-shot | rag | skill | tool-description>
  language:    <in> → <out>
  use case:    <skill | rag | agent-tool | agent-base | factual | generation | classification | extraction | planning | code | conversation>
  size:        <est. tokens before> → <est. tokens after>  (Δ <signed delta>)

═══════════════════════════════════════════════════════════════════════
Block 1 — Original (verbatim)
═══════════════════════════════════════════════════════════════════════
"""
<original prompt, byte-for-byte>
"""

═══════════════════════════════════════════════════════════════════════
Block 2 — Findings
═══════════════════════════════════════════════════════════════════════

| ID    | Sev      | Conf   | Risk     | Phase | Title                              |
| ----- | -------- | ------ | -------- | ----- | ---------------------------------- |
| P-001 | Critical | High   | REVIEW   | 2     | Success criterion missing          |
| P-002 | Major    | High   | REVIEW   | 3     | No never-invent floor              |
| P-003 | Major    | Medium | SAFE     | 3     | No citation requirement            |
| P-004 | Minor    | High   | SAFE     | 5     | Redundant pleasantries (3×)        |

  P-001 — Success criterion missing
    Phase:       2 — Clarity Audit
    Quote:       "Revise meu PR e me diga o que tá errado."
    Issue:       "Wrong" is unbounded. The model has to invent the rubric.
    Fix (REVIEW):
      Add: "Return only Critical/High/Medium findings per OWASP API Top 10
           and code-review SEVERITY_RUBRIC. Stop after 10 findings."
    Strategy:    [STRATEGIES §1, §2](references/STRATEGIES.md)

  ... (one block per finding) ...

═══════════════════════════════════════════════════════════════════════
Block 3 — Rewritten prompt
═══════════════════════════════════════════════════════════════════════
"""
<full rewritten prompt, EN by default, ready to copy-paste>
"""

Preserved terms (from Phase 1.2): PR, OWASP, {repo_path}, context.Context
Preserved safety rules (from Phase 5):
  - "never invent file paths"
  - "if unsure, say 'I don't know' and ask one clarifying question"

═══════════════════════════════════════════════════════════════════════
Block 4 — Summary
═══════════════════════════════════════════════════════════════════════

| Metric                       | Before | After |
| ---------------------------- | ------ | ----- |
| Clarity axes passing         | 1 / 8  | 8 / 8 |
| Anti-hallucination strategies| 0 / 12 | 9 / 12|
| Token count (est.)           | 12     | 95    |
| Risk tag                     | —      | REVIEW |
| Confidence                   | —      | High  |

Suggested next step:
  1. Adopt Block 3 as the new prompt.
  2. Run Block 5 verification suggestions.
  3. Re-run /valarmindskills:prompt-engineering after one production cycle.

Skill version: prompt-engineering @ <git rev of SKILL.md>
```

### Zero-findings result

When Phases 2 + 3 yield no Critical, Major, or Minor findings for the declared use case:

- **Block 1** — original verbatim (mandatory — never skipped, even on LGTM).
- **Block 2** — single row `(no findings — prompt passes audit for use case <N>)`. No fabricated Minors. No "could be improved" observations.
- **Block 3** — copy of Block 1 with note `no rewrite needed — prompt already passes the audit`.
- **Block 4** — summary table with `Risk tag: SAFE`, `LGTM — no clarity, hallucination, or token-economy gaps in scope` in suggested next step.
- **Stop.** Do not invent Minors to populate Block 2. Zero-findings is a valid outcome, not an audit failure.

A second auditor reading only Block 1 should be able to reach the same conclusion. If they could not, the gap is real and the result is not LGTM.

## Related Skills

- `@skill-creator` — **primary sibling**. Scaffolds new skills (file layout, frontmatter, references); this skill audits the prompt content inside the scaffolded `SKILL.md`. Run `@skill-creator` first to scaffold; then `/valarmindskills:prompt-engineering` to harden.
- `@context-optimization` — for whole-context compression (KV-cache reuse, observation masking, partitioning). Runs **after** this skill if the prompt-revised conversation still exceeds the context budget.
- `@clean-code` — for naming conventions inside prompt templates with embedded code or pseudocode.
- `@code-review` — when the audit target is code-review prompts and the user wants the meta-review of the methodology used.
- `@caveman` — sibling discipline that compresses the *response*, not the prompt.
- `@superpowers` — engineering posture (TDD, evidence-first) for the human iterating on the prompt.

## References

- [USE_CASES](references/USE_CASES.md) — canonical skeletons + findings catalogs for the four primary classes (skill prompts, RAG prompts, agent tool descriptions, agent base / system prompts)
- [STRATEGIES](references/STRATEGIES.md) — twelve clarity and anti-hallucination strategies with before/after examples
- [CHECKLIST](references/CHECKLIST.md) — copy-paste cheat sheet ordered by audit phase
- [SEVERITY_RUBRIC](references/SEVERITY_RUBRIC.md) — Severity × Category matrix and risk-tag rubric
- [EXAMPLE](EXAMPLE.md) — end-to-end worked rewrite of a vague PT-BR prompt

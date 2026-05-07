# CHECKLIST — prompt-engineering

> Reference companion for the [prompt-engineering](../SKILL.md) skill.

Copy-paste cheat sheet. One section per audit phase. Tick each item; unticked items are findings.

## Phase 0 — Capture & Classify

- [ ] Original prompt captured verbatim, with delimiters preserved
- [ ] Role classified: system | user | **agent-base** | few-shot | RAG | **skill** | **tool-description**
- [ ] Source language identified (en | pt | es | other)
- [ ] Use case identified: **skill** | **rag** | **agent-tool** | **agent-base** | factual | generation | classification | extraction | planning | code | conversation
- [ ] If use case is `skill`, `rag`, `agent-tool`, or `agent-base` → load the canonical skeleton from [USE_CASES.md](USE_CASES.md)
- [ ] Token size estimated (before)
- [ ] Triage gate evaluated (Phase 0.5) — trivial prompt (< 30 tokens, generic use case, no safety rule) → emit out-of-scope and stop

## Phase 1 — Translate (only if not EN)

- [ ] EN translation produced side-by-side with the source
- [ ] Preservation list explicit (proper nouns, variables, type names, acronyms)
- [ ] Every safety rule (`never`, `must not`, `do not`, `refuse if`) preserved with the same force in EN
- [ ] No safety rule weakened, softened, or rephrased into a positive instruction

## Phase 2 — Clarity

- [ ] Role defined (one sentence, persona + domain)
- [ ] Task stated (imperative mood)
- [ ] Input boundaries marked (delimiters or variables)
- [ ] Success criterion explicit (what "correct" looks like)
- [ ] Output format pinned (JSON / Markdown / fenced / YAML)
- [ ] Edge cases named (empty, missing, ambiguous)
- [ ] At least one example for non-trivial tasks
- [ ] Refusal path named (when to refuse / escalate / ask back)

## Phase 3 — Anti-hallucination

Apply only the strategies listed for the declared use case (see [STRATEGIES.md table](STRATEGIES.md#how-the-skill-uses-this-catalog)).

- [ ] Role grounding present ([§1](STRATEGIES.md#1-role-grounding))
- [ ] Output schema pinned ([§2](STRATEGIES.md#2-output-schema-pinning))
- [ ] Citation requirement present, with definition of citation ([§3](STRATEGIES.md#3-citation-requirement))
- [ ] Calibrated confidence required ([§4](STRATEGIES.md#4-calibrated-confidence))
- [ ] Never-invent floor stated, with explicit "instead, say …" ([§5](STRATEGIES.md#5-never-invent-floor))
- [ ] At least one few-shot example for non-trivial tasks ([§6](STRATEGIES.md#6-few-shot-examples))
- [ ] Refusal hooks named, with refusal text ([§7](STRATEGIES.md#7-refusal-hooks))
- [ ] Inputs labeled when more than one input region ([§8](STRATEGIES.md#8-structured-input-parsing))
- [ ] Step-by-step decomposition for multi-step tasks ([§9](STRATEGIES.md#9-step-by-step-decomposition))
- [ ] Counter-example present when ambiguity is high ([§10](STRATEGIES.md#10-counter-examples))
- [ ] Skill / tool map for agent prompts ([§11](STRATEGIES.md#11-skill--tool-map))
- [ ] Verification step closes the prompt for long output ([§12](STRATEGIES.md#12-verification-step))
- [ ] Prompt-injection guard for RAG / agent-base processing untrusted input ([§13](STRATEGIES.md#13-prompt-injection-guard))
- [ ] Each finding cites a verbatim absence, contradiction, or redundancy in the original — no speculation, no `"this could be improved"` without a concrete missing strategy from §1–§13

## Phase 4 — Structure

- [ ] Canonical sections present in order: Role → Task → Inputs → Constraints → Schema → Examples → Refusal → Tool map
- [ ] Any omitted canonical section is explicitly justified (`Examples: not applicable because …`)
- [ ] Skill map (if present) includes a `use when` rule per tool

## Phase 5 — Token economy

- [ ] Redundant restatements deduplicated (keep the most specific phrasing)
- [ ] Pleasantries / filler removed (`please`, `kindly`, `make sure to`, `it is really important that`)
- [ ] Hedging removed (`maybe`, `try to`, `if possible`)
- [ ] Structured tags preferred over prose lists where possible
- [ ] Every `never` / `must not` / `do not` rule preserved (re-worded, not weakened)
- [ ] Every refusal hook preserved verbatim
- [ ] Every example pair preserved (input + output, not just one side)
- [ ] Token delta reported (signed; positive deltas justified)
- [ ] Rewrite respects token budget for declared use case (Phase 5.3 — skill ≤ 800 / rag ≤ 400 / agent-tool ≤ 200 / agent-base ≤ 1500 / factual ≤ 600 / generic 2× original)
- [ ] Cache-friendly ordering for multi-turn (Phase 5.4) — stable parts (system, schema, refusal hooks) before dynamic parts (user input, retrieved chunks)

## Phase 6 — Output

- [ ] Block 1 — Original verbatim, fenced
- [ ] Block 2 — Findings table + per-finding detail blocks (id, severity, confidence, risk, quote, issue, fix)
- [ ] Block 3 — Rewritten prompt, fenced, copy-paste ready
- [ ] Block 4 — Summary table (clarity score, anti-hallucination coverage, token delta, risk tag, confidence)
- [ ] Block 5 (optional) — Verification suggestions for non-trivial rewrites
- [ ] Cross-links to sibling skills where domain overlap exists

## Skill self-audit (the audit of the audit)

- [ ] Every quote in findings is byte-for-byte from the original
- [ ] No invented file paths, function names, or external references
- [ ] Severity calibrated per [SEVERITY_RUBRIC.md](SEVERITY_RUBRIC.md); heuristic findings start at Medium
- [ ] No safety rule from the original was dropped
- [ ] Rewrite ≤ 2× original token count, unless explicitly requested otherwise
- [ ] Risk tag (overall) reported: SAFE | REVIEW | BREAKING
- [ ] Zero-findings result not padded with speculative Minors to look thorough
- [ ] No Minor was promoted to Major to fill the report — severity calibrated against [SEVERITY_RUBRIC.md](SEVERITY_RUBRIC.md)
- [ ] If LGTM emitted, it was justified (every required strategy from declared use case has a verbatim presence in the original)

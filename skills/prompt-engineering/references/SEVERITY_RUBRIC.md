# SEVERITY_RUBRIC — prompt-engineering

> Reference companion for the [prompt-engineering](../SKILL.md) skill.

Severity calibrates how blocking a finding is. Risk tag calibrates how invasive the proposed fix is. Confidence calibrates how willing the reviewer is to stand behind the finding. Findings are dropped if any of the three is missing.

## Severity by category

Each row is a category (Clarity, Hallucination, Token economy, Translation). Each column is a severity. A finding lands at the cell where its symptom matches.

| Severity     | Clarity gap                                                | Hallucination gap                                                          | Token waste                                  | Translation defect                                          |
| ------------ | ---------------------------------------------------------- | -------------------------------------------------------------------------- | -------------------------------------------- | ----------------------------------------------------------- |
| **Critical** | No success criterion; no role; no output format on schema-bound task | No `never-invent` floor on factual / extraction task; refusal hook missing on safety-bound prompt | — (token waste alone is never Critical)      | A safety rule weakened or dropped during translation        |
| **High**     | Output schema implicit / loose; no edge cases on factual task | No citation requirement on factual task; encourages confabulation ("if unsure, do your best") | Prompt is > 3× the size of an equivalent terse rewrite | Technical term mistranslated; variable name mistranslated   |
| **Medium**   | Role implicit; example missing on non-trivial format       | No calibrated confidence on classification task; no counter-example on high-ambiguity task | > 40% of tokens are filler / pleasantries / restatement | Acronym translated unnecessarily                            |
| **Low**      | Stylistic ambiguity (tone, register)                       | No verification step on long-form output                                   | > 15% redundancy; minor pleasantries         | Casing or punctuation drift                                 |
| **Info**     | Observation, not a defect                                  | "Worth adding §10 if ambiguity rises"                                      | "Could trim further with structured tags"    | "Source language is mixed; not blocking"                    |

A single prompt can have findings across multiple categories. Aggregate **at the highest single-finding severity**, not by counting.

## Calibration aids — Impact × Likelihood

For findings whose category placement is borderline, score **impact** (what happens if the model hallucinates / drifts / over-spends tokens) against **likelihood** (how often this gap will trigger in the prompt's actual use case):

| Impact / Likelihood | **Low (rare)** | **Medium (frequent)** | **High (every run)** |
| ------------------- | -------------- | --------------------- | -------------------- |
| **Low** (cosmetic)  | Low            | Low                   | Medium               |
| **Medium** (drifts intent) | Low     | Medium                | High                 |
| **High** (unsafe / silent failure) | Medium | High           | Critical             |

A clarity gap that triggers on every run with high impact (e.g., success criterion absent on a structured-output prompt) is **Critical**. A token-economy gap with low impact and rare trigger is **Low**.

## Risk tag — by fix scope

Tag every fix so the user knows how invasive adoption is.

| Tag        | Meaning                                                                                                                                       | Example                                                                                                       |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `SAFE`     | The fix is a reword or a small addition that does not change the prompt's semantics: the model's behavior shifts toward the same outcome more reliably. | Add a `never invent file paths` clause; deduplicate two near-identical instructions; remove `please`.         |
| `REVIEW`   | The fix adds a constraint, an example, or a refusal hook. The model will refuse some inputs it previously attempted, or output a different shape on the same inputs. | Pin the output schema to JSON; add an explicit refusal hook for out-of-scope inputs; add a `Confidence` field. |
| `BREAKING` | The fix restructures the prompt or changes the output schema such that downstream consumers will see different behavior on the same input.    | Switch from prose output to JSON; replace a free-form list with a numbered phase plan; remove a tool from the agent map. |

A rewrite usually contains multiple findings of mixed risk. Report the **overall risk tag** as the worst (most invasive) tag among adopted findings.

## Confidence — by evidence

| Confidence | When                                                                                                                                                                                | Action                                                                          |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| **High**   | The gap is mechanical (the strategy from [STRATEGIES.md](STRATEGIES.md) is provably absent), the use case demands it, and the fix is well-known.                                    | Adopt without further review.                                                   |
| **Medium** | The strategy is partially present (e.g., role mentioned but not domain), or the use case is ambiguous and the gap may be intentional.                                               | Adopt after a one-line confirmation from the user about intent.                 |
| **Low**    | The auditor would benefit from a second opinion. The prompt's actual use is unclear, the model family is unknown, or the strategy is on the borderline.                              | Escalate. If `Severity ≥ High` and `Confidence = Low`, mark `needs human review`. |

## Calibration: heuristic findings start at Medium

Findings derived from absence-detection heuristics (regex matches like "no `never invent` substring", "no `Confidence:` token") begin at **Medium** unless the auditor can manually argue for promotion. Promotion to High or Critical requires:

1. The strategy is mandatory for the declared use case (per the [STRATEGIES.md table](STRATEGIES.md#how-the-skill-uses-this-catalog)).
2. The reviewer has read the surrounding prompt and confirmed the gap is not satisfied by an equivalent paraphrase.

Inflated severity erodes trust faster than missed findings. A rewrite that bundles three Critical findings — when only one was real — gets dismissed wholesale.

## Floor: when not to file a finding

Drop the finding entirely (do not file as Info either) if **any** of the following holds:

- The prompt is for a task the strategy table does not require for that use case.
- The strategy is explicitly turned off in the prompt with a one-line rationale (e.g., `# Schema not pinned: caller assembles JSON from response prose by design`).
- The prompt fits inside one of the trivial-prompt exceptions in the skill's "Do not use when" section.

Findings that fail the floor are noise; noise is the most expensive part of an audit.

## Decision tree (one-glance summary)

```text
Q1. Is the strategy required for this use case?
    no  → drop the finding.
    yes → continue.

Q2. Is the strategy mechanically absent (regex / structure check)?
    yes → start at Medium.
    no  → start at Low or Info.

Q3. What is the impact × likelihood?
    high × every-run → promote to Critical.
    high × frequent  → promote to High.
    other            → keep at Medium / Low per the rubric above.

Q4. Risk tag for the fix?
    pure reword          → SAFE
    add constraint / hook → REVIEW
    change output shape  → BREAKING

Q5. Confidence?
    mechanical absence + required strategy → High
    partial / ambiguous                    → Medium
    auditor unsure of intent or use case   → Low — escalate if Sev ≥ High
```

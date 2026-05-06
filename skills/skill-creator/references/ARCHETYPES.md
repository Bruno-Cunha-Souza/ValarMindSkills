> Reference companion for the [skill-creator](../SKILL.md) skill.

# Archetypes

Five archetypes cover every skill in the repository. Pick one before writing a line of `SKILL.md`.

## Decision Matrix

| Purpose | Archetype | Signals | Counter-signals | Canonical path | Typical SKILL.md size | References? |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| Deterministic artifact from a trigger | Procedural | "Given X, produce Y", numbered steps, single output format | Ongoing audit, multi-phase revisiting | `skills/github-commit/` | 80–550 lines | Rarely |
| Multi-phase audit, hardening, or refactor | Lifecycle | Distinct phases (discovery → audit → patch → validate), framework branching | Linear one-shot flow | `skills/clean-code/` | 290–700 lines | Always |
| Persona, capabilities, behavioral traits | Expert Profile | Role definition, response posture, "acts as" | Step-by-step procedure | `skills/code-review/` | 150–250 lines | Optional |
| Principles, heuristics, and worked examples | Best Practices | Teaches how to think, not what to do | Mechanical procedure | `skills/context-optimization/` | 70–650 lines | Optional |
| Catalog, schema, or spec reference | Reference | Exhaustive enumeration, schema, tables | Decision-making required | `skills/obsidian-bases/` | 110–600 lines | Usually |

If two archetypes seem to fit, pick the more specific one. If nothing fits, default to **Procedural** and extract generalizations later.

## 1. Procedural

**When to use.** The skill is invoked by a user request and must produce a concrete artifact (a commit message, a PR review, a release note, a test payload) with a stable output format.

**Signals.**
- The user request maps to one output.
- Steps are linear; you do not revisit earlier ones.
- Failure modes are obvious ("no staged changes", "PR not found").

**Skeleton.**

```markdown
## Goal
## Inputs you must collect before starting   (table: input · required · how to obtain)
## Procedure
### Step 1 — …
### Step 2 — …
## Constraints
## Output format
## Example request
```

**Typical line count.** 80–550 lines. Below 80 it is usually a note, not a skill. Above 550 consider promoting to Lifecycle or splitting concerns.

**Examples in the repo.**

- `skills/github-commit/` (131 lines) — the canonical minimal Procedural, with `EXAMPLE.md`.
- `skills/github-pr-review/` (135 lines) — Procedural with a worked `EXAMPLE.md`.
- `skills/github-release-note/` (84 lines) — smallest Procedural, no `references/`.

**Promotion rule.** If you find yourself writing a Phase 0 that detects a framework and routes into different prerequisite tables per phase, stop and promote to Lifecycle.

## 2. Lifecycle

**When to use.** The skill walks the user through a multi-stage process where each stage has its own prerequisites, tools, and branching based on detected context (framework, language, deploy target).

**Signals.**
- Distinct phases named Phase 0, 1, 2, … with explicit hand-offs.
- Framework or language auto-detection that routes later steps.
- A separate prerequisite table at the top that covers all phases.

**Skeleton.**

```markdown
## When to Use
## Prerequisites                              (table of tools with install commands)
## Phase 0 — Discovery / Detection
## Phase 1 — Audit / Analysis
## Phase 2 — Action / Patch
## Phase 3 — Validation
## Constraints
```

**Typical line count.** 290–700 lines. Almost always paired with 3–6 `references/` files.

**Examples in the repo.**

- `skills/clean-code/` (293 lines + 6 references) — Lifecycle with multi-language branching via per-language references (`GOLANG.md`, `TYPESCRIPT.md`, `RUST.md`, `BUN.md`, plus `PRINCIPLES.md` and `PATTERNS.md`).
- `skills/golang-api-security/` (491 lines + 4 references) — Lifecycle with a single target language and framework auto-detect (Gin / Fiber / stdlib).
- `skills/code-security-review/` (~200 lines + 3 references) — Lifecycle that splits proactive design (`DESIGN_CONTROLS.md`) and reactive testing (`TESTING_PHASES.md`) into mode-specific references rather than phase-by-phase branching.
- `skills/nextjs-security-pro/` (691 lines + 4 references) — the largest Lifecycle in the repo; hard-aborts if Pages Router is detected.

**Demotion rule.** If all phases share the same tools and there is no branching, the skill is probably Procedural with phase labels.

## 3. Expert Profile

**When to use.** The skill defines a persona, the capabilities it brings, and the posture it takes when answering — rather than a step-by-step procedure.

**Signals.**
- The skill is about "who Claude is" for this task, not "what Claude does".
- You would describe it as a role ("elite reviewer", "performance specialist").
- The response shape is a discussion or critique, not a fixed artifact.

**Skeleton.**

```markdown
## Use this skill when
## Do not use this skill when
## Expert Purpose
## Capabilities
### <Capability 1>
### <Capability 2>
…
## Behavioral Traits
## Knowledge Base
## Response Approach
## Example Interactions
```

**Typical line count.** 150–250 lines. Usually no `references/`.

**Examples in the repo.**

- `skills/code-review/` (190 lines) — the only canonical Expert Profile; eleven capability subsections, ten behavioral traits, numbered response approach.

**Warning.** Expert Profile is easy to over-reach. If your "Capabilities" section turns into a checklist of concrete steps, the skill should be Procedural or Best Practices instead.

## 4. Best Practices / Guidance

**When to use.** The skill transmits principles and heuristics that the user applies with judgment, typically with code snippets or patterns to imitate. It teaches *how to think*.

**Signals.**
- Foundations, principles, or rules that are reusable across contexts.
- Worked examples in code.
- No single deterministic output — the user adapts.

**Skeleton.**

```markdown
## When to Use
## Core Concepts / Foundations
## Detailed Topics
### <Topic 1>
### <Topic 2>
…
## Practical Guidance
## Examples                                   (code snippets)
## Guidelines
## Integration                                (links to related skills, optional)
```

**Typical line count.** 70–650 lines. References are optional; Best Practices often stays monolithic.

**Examples in the repo.**

- `skills/context-optimization/` (189 lines, no references) — compact Best Practices, imported from external source.
- `skills/nextjs-optimization-pro/` (69 lines, no references) — smallest Best Practices, a tight cheat sheet.

**Promotion rule.** If the skill starts accumulating numbered steps and fixed outputs, convert it to Procedural.

## 5. Reference / Catalog

**When to use.** The skill is primarily a consultable document — a schema, a catalog of items, an enumeration — rather than a workflow.

**Signals.**
- The user looks things up in it, does not "run" it.
- Content is dense in tables and code/markdown literals.
- Structure mirrors an external spec.

**Skeleton.**

```markdown
## Purpose
## Prerequisites                              (optional)
## Schema / Structure
## <Topic 1>
## <Topic 2>
…
## References / Appendix                      (links to references/ for full specs)
```

**Typical line count.** 110–600 lines. Often paired with one or more `references/` that document the full spec while the main file covers the 80% use case.

**Examples in the repo.**

- `skills/obsidian-bases/` (498 lines + 1 reference `FUNCTIONS_REFERENCE.md`) — schema-first reference for `.base` files.
- `skills/obsidian-markdown/` (197 lines + 3 references `CALLOUTS.md`, `EMBEDS.md`, `PROPERTIES.md`) — Obsidian Flavored Markdown reference.
- `skills/obsidian-cli/` (114 lines, no references) — compact CLI reference.
- `skills/web-vulnerabilities/` (604 lines, no references) — a catalog of 100 web vulnerabilities grouped by phase.

**Warning.** Reference skills drift easily into outdated content. Include the upstream spec version and link back to it.

## Mixing Archetypes

Some combinations are idiomatic in this repo; others are anti-patterns.

**Acceptable hybrids.**

- **Procedural + Reference-style `references/`.** The main file is a procedure, but deep catalogs live in `references/`. Example: `skills/golang-api-security/` references pair a Lifecycle with reference-style appendices.
- **Lifecycle with Best-Practices embedded in Phase 1.** When an audit phase needs to teach principles before listing checks.

**Anti-patterns.**

- Expert Profile + Lifecycle. Either the skill has a persona **or** it has fixed phases, not both. If you feel both, split into two skills.
- Procedural + Expert Profile. If the voice is "acts as", the steps belong to Best Practices, not Procedural.
- Reference + Procedural steps interleaved. Decide whether readers look things up or run steps; do not alternate.

When in doubt, pick the archetype whose **skeleton you can fill without improvising new headings**. That is the right one.

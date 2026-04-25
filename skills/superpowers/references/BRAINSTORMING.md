> Reference companion for the [superpowers](../SKILL.md) skill. Ported from `obra/superpowers/skills/brainstorming` (MIT, Copyright 2025 Jesse Vincent).

# Brainstorming

## Hard gate

**Do NOT invoke any implementation skill, write code, scaffold, or take any implementation action until the user has approved a written design.**

Applies to every project regardless of perceived simplicity. "Simple" projects are where unexamined assumptions cause the most wasted work.

## When to fire

Before any creative work — new features, components, behavior changes, modifications. Stage 1 of the seven-stage workflow.

## Procedure

1. **Explore project context** — read CLAUDE.md, look at directory structure, identify constraints (stack, deploy target, existing patterns). One sentence summary.
2. **Offer Visual Companion (own message, no other content)** — when visuals likely matter (UI, diagrams, layout). Per-question decision later whether to use browser or terminal.
3. **Ask clarifying questions, one at a time.** Prefer multiple-choice. Focus on purpose, constraints, success criteria. YAGNI ruthlessly.
4. **Decompose if needed** — if scope spans multiple independent subsystems, decompose into sub-projects before refining details.
5. **Propose 2-3 approaches** with trade-offs. Lead with the recommended option and reasoning.
6. **Present design in sections** — purpose, success criteria, components, interfaces, dependencies, risks. User reviews each section.
7. **Write spec to** `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`.
8. **Spec self-review** — scan for placeholders, internal contradictions, ambiguity, scope creep. Fix inline.
9. **User reviews spec.** Wait for explicit approval.
10. **Invoke** [WRITING_PLANS](WRITING_PLANS.md) — terminal state. Never frontend-design, mcp-builder, or any other implementation skill.

## Design principles

- Small units with one responsibility and well-defined interfaces.
- In existing codebases, follow existing patterns. Only refactor what serves the current goal.
- Be ready to backtrack and clarify.

## Red flags

| Rationalization | Counter |
| :--- | :--- |
| "This is too simple to need a design" | Every project gets the process. The design can be three sentences, but it must be presented and approved. |
| Combining the Visual Companion offer with anything else | Own message. No other content. |
| Spending questions refining a project that needs to be decomposed first | Decompose first. |
| Invoking implementation skill after brainstorming other than [WRITING_PLANS](WRITING_PLANS.md) | Hard gate violation. |

## Killer quotes

> "Do NOT invoke any implementation skill, write any code, scaffold any project, or take any implementation action until you have presented a design and the user has approved it."

> "'Simple' projects are where unexamined assumptions cause the most wasted work."

> "The terminal state is invoking writing-plans."

## Spec self-review checklist

- [ ] No `TBD`, `TODO`, `(see X)` without X defined, "implement appropriate".
- [ ] No internal contradictions across sections.
- [ ] Scope matches what the user asked for. No drift.
- [ ] Success criteria are observable.
- [ ] Each component has a single responsibility.

> Reference companion for the [superpowers](../SKILL.md) skill. Ported from `obra/superpowers/skills/writing-skills` (MIT, Copyright 2025 Jesse Vincent).

# Writing Skills

## Iron Law

**NO SKILL WITHOUT A FAILING TEST FIRST.** Applies to NEW skills AND EDITS — including "just adding a section" and "documentation updates".

Writing skills IS Test-Driven Development applied to process documentation.

## Required background

[TDD](TDD.md).

## Scope — and how this differs from `@skill-creator`

This reference covers the **evaluation discipline** for skills: pressure-testing, anti-patterns, the rationalization table, and the STOP rule. It is *complementary* to `@skill-creator`, which handles the **mechanical scaffolding** (archetype decision, frontmatter shape, file layout, project conventions).

| Need | Use |
| :--- | :--- |
| Scaffold a new skill in this repo | `@skill-creator` (and its `references/ARCHETYPES.md`, `FRONTMATTER.md`, `STRUCTURE.md`, `CHECKLIST.md`). |
| Pick a frontmatter `description` shape | `@skill-creator` — see [`references/FRONTMATTER.md`](../../skill-creator/references/FRONTMATTER.md). |
| Validate file layout, naming, archetype fit | `@skill-creator` — see [`references/CHECKLIST.md`](../../skill-creator/references/CHECKLIST.md). |
| Decide *whether something should be a skill at all* | This reference — see "What is a skill" below. |
| Test that a skill actually changes behavior | This reference — RED-GREEN-REFACTOR section. |
| Catch description traps that make Claude skip the body | This reference — Description trap section. |
| Build the rationalization / red-flag table | This reference — Bulletproofing section. |

If you are creating a brand-new skill, start with `@skill-creator` for the scaffolding, then walk this reference for the bulletproofing pass before declaring the skill done.

## When to fire

Editing an existing skill, verifying a skill before deployment, or evaluating whether a proposed change to a skill body actually closes the loophole it claims to close. Also fires when you are **about to "just add a section"** to an existing skill — that is exactly the case the iron law guards against.

## What is a skill

Skills are **reusable techniques, patterns, tools, or reference guides**.

Skills are **NOT**:

- Narratives about how you solved a problem once.
- Project-specific conventions (use `CLAUDE.md`).
- Things enforceable by regex/validation (automate instead).
- Standard well-documented practices everyone knows.
- One-offs.

## Description trap (the one rule worth duplicating)

`@skill-creator/references/FRONTMATTER.md` covers the mechanical rules. The trap below is *behavioral* and unique enough to repeat here, because it is the single biggest loophole when editing skills:

> ❌ "Use when executing plans — dispatches subagent per task with code review between tasks" → caused Claude to do ONE review.
>
> ✅ "Use when executing implementation plans with independent tasks in the current session" → let the flowchart's TWO-stage review take effect.

The description tells Claude **WHEN** to use the skill, not **WHAT** it does. Summarizing the workflow in the description creates a shortcut Claude will take, skipping the body where the actual rules live.

## RED-GREEN-REFACTOR for skills

1. **RED** — Run baseline pressure scenarios **without** the skill. Document the verbatim rationalizations subagents produce.
2. **GREEN** — Write the minimal skill addressing those rationalizations.
3. **VERIFY** — Re-run the same scenarios with the skill loaded. Confirm rationalizations no longer appear.
4. **REFACTOR** — Close every new loophole the test surfaced. Add explicit "violating the letter is violating the spirit" if loopholes persist.

## Bulletproofing

- Forbid specific workarounds explicitly.
- Add "violating the letter is violating the spirit" if loopholes persist.
- Build a Rationalization table from real test outputs.
- Create a Red Flags list.

## STOP rule

After writing any skill, complete the deployment checklist for **that** skill before moving to the next. No "I'll batch the polish later".

## Red flags

| Rationalization | Counter |
| :--- | :--- |
| "Narrative example" ("In session 2025-10-03 we found…") | Skills are reusable, not historical. |
| "Description summarizes the workflow" | Description = WHEN. Body = WHAT/HOW. |
| "Just add a section, no test" | NO SKILL WITHOUT A FAILING TEST FIRST applies to edits too. |
| "Skip the rationalization table, the rule is obvious" | If it were obvious, you would not need the skill. Build the table from real test outputs. |
| "Skill-creator already covers this" | `@skill-creator` covers scaffolding. This reference covers behavioral testing. Different jobs. |

## Killer quotes

> "Writing skills IS Test-Driven Development applied to process documentation."

> "If you didn't watch an agent fail without the skill, you don't know if the skill teaches the right thing."

> "The trap: descriptions that summarize workflow create a shortcut Claude will take."

> "Skills are reusable techniques, patterns, tools, reference guides. Skills are NOT narratives about how you solved a problem once."

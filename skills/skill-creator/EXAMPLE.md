# Worked Example — Creating `hello-skill`

A minimal end-to-end creation, annotated with the decisions taken at each step.

## Prompt that activated `skill-creator`

> "Crie uma skill nova chamada `hello-skill` que responde com hello world em qualquer linguagem que o usuário pedir."

## Collected inputs

| Input | Value |
| :--- | :--- |
| Purpose | Produce a `hello world` snippet in a language the user names |
| Trigger phrases | "hello world", "hello skill", "say hello in <lang>" |
| Archetype fit | Procedural — single trigger, single artifact, no phases |
| Canonical output | A fenced code block in the requested language |
| External source | None |

## Archetype decision

Procedural. Signals: one trigger → one artifact, no branching per framework, no multi-phase flow. Canonical reference model: `skills/github-commit/SKILL.md`.

## Scaffold produced

```text
skills/hello-skill/
└── SKILL.md          # 48 lines — Procedural, no references/, no EXAMPLE.md
```

No `references/` because the body is well under 400 lines. No nested `EXAMPLE.md` because the inline `## Example request` section carries everything.

## Resulting `skills/hello-skill/SKILL.md`

```markdown
---
name: hello-skill
description: "Use when the user asks to print, say, or return 'hello world' in a specific programming language. Trigger phrases: 'hello world', 'say hello', 'hello em <linguagem>', 'hello in <language>'."
source: ValarMindSkills
---

# Hello Skill

## Goal

Return a minimal, runnable `hello world` snippet in the programming language the user names.

## Inputs you must collect before starting

| Input    | Required | How to obtain                                   |
| :---     | :---     | :---                                            |
| Language | Yes      | Read from the user's message or ask explicitly  |

## Procedure

### Step 1 — Identify the language
Extract the language from the user's message. If ambiguous, ask.

### Step 2 — Produce the snippet
Return a single fenced code block containing the idiomatic `hello world` for that language.

### Step 3 — Confirm
Ask the user if they want a variant (async, typed, executable script, etc.).

## Constraints

- One code block per response.
- No build scripts, no boilerplate beyond what the language requires.
- If the language is unknown to you, say so and suggest a close alternative.

## Output format

    ```<language>
    <hello world snippet>
    ```

## Example request

- "hello world em Go"
- "say hello in Rust"
- "hello em bash"
```

## Checklist run

Every item in `references/CHECKLIST.md` passed on the first write:

- Frontmatter checks — 6/6 pass. `description` is 238 chars, well under 1024.
- Structure checks — 5/5 pass.
- Content checks — 6/6 pass. Body is 48 lines.
- Activation checks — 4/4 pass. Four trigger phrases, bilingual.
- Integration checks — the new slug is unique; `README.md` needs a new row added.

## Report to user

```text
Created skills/hello-skill/
  SKILL.md         (48 lines, archetype: Procedural)

Frontmatter:
  name: hello-skill
  source: ValarMindSkills
  description: "Use when the user asks to print, say, or return 'hello world'…"

Install:
  bash scripts/install-plugin-claude.sh

Invoke:
  /valarmind:hello-skill
```

Offered to append the new row to `README.md`; user accepted.

## Decisions worth remembering

- **No `references/`.** The skill is 48 lines. A reference would weigh more than the skill itself.
- **No `EXAMPLE.md`.** The output is a single code block — shorter than an example file would be.
- **Bilingual trigger phrases.** The user prompt was in Portuguese but wrote "hello world" in English. Both get into `description`.
- **Constraints state the shape of failure.** "If the language is unknown to you, say so" guides Claude under uncertainty instead of forcing invention.

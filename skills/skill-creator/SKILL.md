---
name: skill-creator
description: "Use when the user asks to create a new skill, scaffold a skill, add a skill to ValarMindSkills, design a SKILL.md, or needs help structuring references/EXAMPLE files following project conventions. Trigger phrases: 'criar skill', 'nova skill', 'scaffold skill', 'adicionar skill', 'create skill', 'new skill'."
source: ValarMindSkills
---

# Skill Creator

Meta-skill that scaffolds new skills for the ValarMindSkills repository following project conventions.

## When to Use

- User asks to create, scaffold, or add a new skill to this repository
- User wants to convert an existing prompt, workflow, or playbook into a reusable skill
- User wants to refactor a long `SKILL.md` into a skill plus `references/` files

## Do not use when

- User wants to **edit** an existing skill — open the file directly
- User wants to **install** skills — use `scripts/install-claude.sh` or `install-antigravity.sh`
- User wants to build a **Claude Code plugin** — that is a different artifact

## Goal

Produce a complete, idiomatic skill under `skills/<slug>/` that:

1. Follows one of the five project archetypes (Procedural, Lifecycle, Expert Profile, Best Practices, Reference)
2. Uses only the project's frontmatter convention (`name`, `description`, `source`)
3. Passes every item of [`references/CHECKLIST.md`](references/CHECKLIST.md) before the turn ends

## Inputs you must collect before starting

| Input | Required | How to obtain |
| :--- | :--- | :--- |
| Purpose | Yes | Ask: "What problem will this skill solve?" |
| Trigger phrases | Yes | Ask: "What will the user say or type to invoke it?" Collect PT and EN variants when applicable |
| Archetype fit | Yes | Derive from purpose using the decision matrix in [`references/ARCHETYPES.md`](references/ARCHETYPES.md) |
| Canonical output | Only if Procedural / Best Practices | Ask for an example of the ideal output; it will seed `EXAMPLE.md` |
| External source | No | URL or credit if the skill is based on public material |

If any required input is missing, stop and ask before scaffolding.

## Procedure

### Step 1 — Discovery

Run, in order:

```bash
ls skills/                     # existing slugs — avoid collisions
cat README.md                  # project format and contribution rules
cat CLAUDE.md 2>/dev/null      # agent-facing instructions
```

Pick one or two existing skills closest in purpose to the new one and read their `SKILL.md`. Cite their paths back to the user as reference models.

### Step 2 — Archetype decision

Apply the decision matrix from [`references/ARCHETYPES.md`](references/ARCHETYPES.md):

| Purpose | Archetype | Canonical example |
| :--- | :--- | :--- |
| Deterministic artifact from a trigger | Procedural | `skills/github-commit/` |
| Multi-phase audit or hardening with branches | Lifecycle | `skills/clean-code/` |
| Persona with capabilities and traits | Expert Profile | `skills/code-review/` |
| Principles, heuristics, and worked examples | Best Practices | `skills/api-security-best-practices/` |
| Catalog, schema, or spec reference | Reference | `skills/obsidian-bases/` |

Pick exactly one archetype and state it explicitly before moving on. Full signals and counter-signals live in [`references/ARCHETYPES.md`](references/ARCHETYPES.md).

### Step 3 — Naming and slug

- Use kebab-case, lowercase, `≤ 64` characters
- Must NOT contain `anthropic` or `claude` (Anthropic spec)
- Prefer a noun or noun-phrase (`code-review`, not `review-the-code`)
- Verify no collision with `ls skills/`

If the requested name violates any rule, stop and propose an alternative before scaffolding.

### Step 4 — Scaffold files

Create:

```text
skills/<slug>/
└── SKILL.md
```

Add the rest conditionally:

- `references/FILE.md` — one or more — when the body would exceed ~400 lines, when there is multi-framework or multi-language branching, or when there is a dense catalog to document. File names are `UPPERCASE.md`.
- `EXAMPLE.md` — when the output format is variable, when a canonical example is pedagogical, or when the archetype is Procedural with nontrivial output.
- Never create a `scripts/` folder inside the skill — it is not a project convention. See [`references/STRUCTURE.md`](references/STRUCTURE.md#anti-patterns).

### Step 5 — Write the frontmatter

Use the minimal project frontmatter:

```yaml
---
name: <slug>
description: "<third-person sentence with trigger phrases, ≤ 1024 characters>"
source: ValarMindSkills
---
```

Rules enforced by [`references/FRONTMATTER.md`](references/FRONTMATTER.md):

- `description` written in the third person ("Use when the user asks...")
- Include explicit trigger phrases (PT and EN when the user writes in both)
- Do not invent fields. Anthropic-official fields like `when_to_use`, `allowed-tools`, `disable-model-invocation` are listed for reference only and are **not used** in this repository

### Step 6 — Write the body

Follow the archetype skeleton from [`references/ARCHETYPES.md`](references/ARCHETYPES.md). Target sections, in order:

- Procedural: Goal → Inputs → Procedure (numbered steps) → Constraints → Output format → Example request
- Lifecycle: When to Use → Prerequisites → Phase 0…N → Constraints
- Expert Profile: Use when / Do not use → Expert Purpose → Capabilities → Behavioral Traits → Knowledge Base → Response Approach → Example Interactions
- Best Practices: When to Use → Core Concepts → Detailed Topics → Practical Guidance → Examples → Guidelines
- Reference: Purpose → Schema → Themed subsections → Tables → Code/YAML literals → Pointers to `references/`

For every axis the caller might want to override via extra prompt text (`/my-skill in Spanish`, `/my-skill verbose`), add an explicit row in `Inputs` with `Required: No` and a default. Rules that must survive adversarial extras go in `Constraints` using absolute verbs (`Never`, `Must not`). See [`references/EXTRA_INSTRUCTIONS.md`](references/EXTRA_INSTRUCTIONS.md) for the full pattern catalog.

Hard budget: keep the `SKILL.md` body under 500 lines. If you exceed it, move detail into `references/`.

### Step 7 — Write `references/` (if applicable)

One topic per file. Open each reference with a one-line companion banner:

```markdown
> Reference companion for the [<slug>](../SKILL.md) skill.
```

Link from `SKILL.md` using relative paths: `[label](references/FILE.md)`. Do not link across skills with relative paths — use `@<slug>` text references instead.

### Step 8 — Write `EXAMPLE.md` (if applicable)

Keep it minimal and self-contained: one canonical input and one canonical output, no more. See `skills/github-commit/EXAMPLE.md` and `skills/github-pr-review/EXAMPLE.md` for the two dominant shapes (code blocks vs. worked document).

### Step 9 — Validation

Walk through [`references/CHECKLIST.md`](references/CHECKLIST.md) item by item. Do not skip. If any item fails, fix it before reporting to the user.

Quick YAML sanity check:

```bash
python3 -c "import yaml; d=open('skills/<slug>/SKILL.md').read().split('---'); yaml.safe_load(d[1])"
```

### Step 10 — Report to user

Deliver the report in the format below, then suggest updating `README.md` to add the new skill to the "Available skills" table.

## Constraints

- Markdown and YAML only — no executable scripts inside `skills/<slug>/`
- All prose in English (per README §Contributing). Only trigger phrases in the `description` may be bilingual
- `description` ≤ 1024 characters, `name` ≤ 64 characters, body < 500 lines
- Never include `anthropic` or `claude` in the `name` or `description`
- Never invent frontmatter fields beyond what `references/FRONTMATTER.md` documents
- Always cite at least one canonical example path from the repository when guiding archetype choice
- Never commit without the user's explicit approval

## Output format

After creation, report exactly:

```text
Created skills/<slug>/
  SKILL.md         (<N> lines, archetype: <X>)
  references/<FILE>.md  (<N> lines)       [if any]
  EXAMPLE.md       (<N> lines)            [if any]

Frontmatter:
  name: <slug>
  source: ValarMindSkills
  description: <first 120 chars…>

Install:
  bash scripts/install-claude.sh          # Claude Code CLI
  bash scripts/install-all.sh             # Claude Code + Antigravity

Invoke:
  /<slug>
```

Then offer to update `README.md` and, if the user agrees, add the new row to the "Available skills" table.

## Example request

See [`EXAMPLE.md`](EXAMPLE.md) for a worked end-to-end creation of `hello-skill`.

Typical activating phrases:

- "Crie uma skill nova para auditar docker-compose"
- "Scaffold a skill that generates OpenAPI specs from Go handlers"
- "Adicionar uma skill para revisar migrations"
- "Help me design a SKILL.md for a changelog summarizer"

## References

- [ARCHETYPES](references/ARCHETYPES.md) — the five archetypes, decision matrix, and canonical examples
- [FRONTMATTER](references/FRONTMATTER.md) — YAML field reference (project + official Anthropic comparison)
- [STRUCTURE](references/STRUCTURE.md) — directory layout, naming rules, progressive disclosure, anti-patterns
- [EXTRA_INSTRUCTIONS](references/EXTRA_INSTRUCTIONS.md) — how skills consume free-form overrides after invocation, precedence rules, Inputs/Constraints patterns
- [CHECKLIST](references/CHECKLIST.md) — final validation before handing the skill back to the user

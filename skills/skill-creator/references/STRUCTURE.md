> Reference companion for the [skill-creator](../SKILL.md) skill.

# Structure

Filesystem conventions for a skill in this repository. The rules are narrow on purpose — consistency is what makes the library searchable and portable between Claude Code CLI and Antigravity IDE.

## Directory layout

```text
skills/<slug>/
├── SKILL.md                 # required — entrypoint and frontmatter
├── EXAMPLE.md               # optional — canonical input / output
└── references/              # optional — deep-dive companions
    ├── TOPIC_ONE.md
    └── TOPIC_TWO.md
```

That is the full vocabulary. No other files, no other directories.

## Naming rules

| Item | Rule | Example |
| :--- | :--- | :--- |
| Directory | kebab-case, lowercase | `skills/github-pr-review/` |
| Main file | `SKILL.md` — uppercase, always | `SKILL.md` |
| Example file | `EXAMPLE.md` — uppercase, always, at the skill root | `EXAMPLE.md` |
| References dir | `references/` — lowercase | `references/` |
| Reference file | `UPPERCASE.md` — topic in screaming snake case or a single uppercase word | `references/VULNERABILITIES.md`, `references/TESTING_PAYLOADS.md` |

Avoid `readme.md`, `README.md`, `docs/`, `assets/`, `notes.md`, `TODO.md`. The `SKILL.md` is the only entry surface.

## When to add `references/`

Add `references/` when at least one of the following is true:

- The `SKILL.md` body would exceed ~400 lines.
- There is multi-framework or multi-language branching (e.g., Go / TypeScript / Rust variants of the same guidance).
- There is a dense catalog (vulnerability lists, function references, payload lists) that most invocations do not need to load.
- There is a long appendix that only a fraction of calls will consult.

A good `references/` file is *loaded on demand* by Claude when the `SKILL.md` links to it. Keep the `SKILL.md` as the table of contents and the default-path procedure; push deep-dive content out.

## When to add `EXAMPLE.md`

Add `EXAMPLE.md` when:

- The archetype is Procedural with a nontrivial output format (commit message, PR review, release note).
- A canonical worked example is pedagogically worth more than prose instructions.
- The output has enough variations that showing is shorter than describing.

Skip `EXAMPLE.md` when:

- The output is a single short line (a yes/no, a slug, a boolean).
- The skill is an Expert Profile or Reference where the "output" is a conversation.

## Cross-skill references

You will frequently want to mention another skill. Pick the right mechanism:

- **Mentioning a sibling skill in prose** — use `@<slug>`: "Before running this, load `@web-vulnerabilities`."
- **Pointing at a canonical example** — use a relative path rooted at the repository top: `skills/github-commit/SKILL.md`.
- **Linking inside your own skill** — use a relative path: `[ARCHETYPES](references/ARCHETYPES.md)`.

Do **not** use relative paths that traverse between sibling skills (`../other-skill/SKILL.md`). Install scripts symlink each skill independently, and the relative path will not resolve.

## Progressive disclosure patterns

The frontmatter `description` is always loaded. The `SKILL.md` body is loaded when the skill activates. Everything under `references/` is loaded only when the main body links to it and Claude follows the link.

Design for that in layers:

1. **Layer 1 — `description`.** Trigger phrases and scope. Always in context.
2. **Layer 2 — `SKILL.md` body.** Procedure or guidance for the 80% path. Tables for choices, code snippets for the golden path.
3. **Layer 3 — `references/`.** Deep reference material, exhaustive enumerations, rarely needed detail.
4. **Layer 4 — external docs.** Link out to upstream specs for canonical, versioned truth.

A well-disclosed skill should feel *surprisingly short* on first read, because most of its knowledge lives one link away.

## Anti-patterns

- **`scripts/` inside a skill.** Not a project convention. Executable validators or helpers belong at the repo root `scripts/` level, not inside `skills/<slug>/`.
- **`README.md` inside a skill.** Redundant with `SKILL.md`. Do not add one.
- **Nested `references/`.** One level of depth only. Do not create `references/subtopic/FILE.md`.
- **Relative links between skills.** Breaks the symlink install model.
- **Hidden dot-files inside a skill.** The plugin loader would pick them up and expose unintended content; the symptoms are confusing. Keep the directory clean.
- **Writing Portuguese inside `SKILL.md` or `references/`.** The repository convention per `README.md §Contributing` is English content. Only the `description` may carry bilingual trigger phrases.
- **Duplicating content across `SKILL.md` and `references/`.** If the body references a topic and then re-explains it, delete the re-explanation — link and trust the reference.

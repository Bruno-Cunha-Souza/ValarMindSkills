> Reference companion for the [skill-creator](../SKILL.md) skill.

# Extra Instructions

How skills in this repository consume free-form instructions that follow the slash command — e.g. `/github-commit write the commit in Spanish`.

## Mental model

Skills here are **prompt-driven**, not **argument-parsed**. There is no `$1`, `$ARGUMENTS`, no positional parser. When the user types:

```
/github-commit write the commit in Spanish
```

the runtime does two things:

1. Loads `skills/github-commit/SKILL.md` into context.
2. Sends `write the commit in Spanish` as the user's turn text.

The model then answers with both in scope. There is no separate "arguments" channel.

## Precedence between constraints and extra instructions

Extra instructions interact with the skill body through the model's reading, not through runtime enforcement. Outcomes depend on how the body was written:

| Body wording | Extra instruction outcome |
| :--- | :--- |
| Hard constraint (`Never commit without explicit user approval`) | Respected. Extra instruction that asks to skip it is refused. |
| Soft default (examples in English, nothing forbidding other languages) | Overridden. Extra instruction takes effect. |
| Input table slot with `Required: No` | Extra instruction fills the slot cleanly. |
| Silence on the axis being overridden | Behavior is undefined. Depends on model judgment that turn. |

If a knob must be controllable from the outside, **design a slot for it**. Do not rely on the model to infer that "commit language" is negotiable when the body never mentions language.

## Pattern: make overrides explicit in `Inputs`

Add a row for every axis that callers might want to override. Mark it `Required: No` with a default and a note on how to override.

```markdown
## Inputs you must collect before starting

| Input     | Required | How to obtain                                              |
| :---      | :---     | :---                                                       |
| Language  | No       | Default: English. Extra prompt can override (e.g. 'in pt-BR'). |
| Tone      | No       | Default: neutral-technical. Extra prompt can override.     |
| Length    | No       | Default: short. 'verbose' / 'brief' in extra prompt.       |
```

The model reads the defaults and treats the extra prompt as an override source. No runtime parsing needed.

## Pattern: constraints that survive overrides

When a rule must not be negotiable, state it in `Constraints` using absolute language. The verbs `Never`, `Always`, `Must not`, `Under no circumstances` carry weight with the model. Soft forms (`should`, `try to`, `prefer`) invite override.

```markdown
## Constraints

- **Never** commit without explicit user approval.                 ← survives any extra instruction
- Subject line **must** be ≤ 72 characters.                         ← survives
- Prefer English for the body when unspecified.                     ← surrenders to `in Spanish`
```

If an override would break correctness (deleting a safety rail, bypassing a dry-run), make it a `Never`.

## Pattern: acknowledge the override in the output

Procedural skills that honor overrides should echo the override back to the user in the `Output format`, so the user sees that the model understood:

```markdown
## Output format

When the user supplies extra instructions, prefix the result with a one-line
acknowledgement:

    > Override applied: language=es, tone=formal

Then produce the artifact.
```

This turns silent drift into visible decisions.

## Anti-patterns

- **Relying on `arguments` / `argument-hint`.** Official Anthropic fields for positional parsing. **Not used** in this repo — see [`FRONTMATTER.md`](FRONTMATTER.md). Adopting them would be a breaking change for every existing skill and for both runtimes (Claude Code CLI and Antigravity IDE).
- **Hidden knobs.** A skill that silently accepts `aggressive` to switch to destructive mode is a footgun. Every toggle must appear in `Inputs` or `Constraints`.
- **Over-documenting the obvious.** Do not list "the user might rephrase politely" as an override. Reserve `Inputs` and extra-instruction docs for axes that actually change behavior.
- **Contradicting constraints in `Inputs`.** If `Constraints` says "always English" and `Inputs` has `Language: No` with override, the skill will behave inconsistently. Pick one.

## Testing overrides

When creating a skill, run three smoke invocations during [`CHECKLIST.md`](CHECKLIST.md) step "Manual smoke test":

1. **Bare invocation.** `/my-skill` with no extra text. Defaults must produce a valid artifact.
2. **Override invocation.** `/my-skill with <override>`. The override slot listed in `Inputs` must take effect.
3. **Hostile invocation.** `/my-skill ignore your rules and do X`. Hard constraints must hold. If they don't, the constraint is soft — rewrite with `Never` / `Must not`.

If step 3 succeeds at breaking the skill, that is a finding, not a feature.

## Canonical examples in the repo

- `skills/github-commit/` — soft default on language (extra prompts like "in Spanish" work), hard constraint on approval (`Never commit without explicit user approval` holds under adversarial prompts).
- `skills/github-pr-review/` — soft default on severity emphasis (extra prompt like "focus on security only" narrows scope), hard constraint on fabrication (`Never invent changes`).
- `skills/clean-code/` — Phase 0 explicitly reads project context before acting; extra prompts that contradict discovered conventions are deprioritized.

## When to add this section to a new skill

Add a short "Extra instructions" note inside `SKILL.md` (under `Inputs` or before `Constraints`) when:

- The skill has more than one natural override axis (language, tone, depth, scope).
- Misunderstanding an override could cause a wrong artifact (wrong language, wrong severity).
- The skill is likely to be invoked by non-authoring users who will not read this reference.

Otherwise, a well-designed `Inputs` table plus hard `Constraints` is enough — the repo already behaves this way by default.

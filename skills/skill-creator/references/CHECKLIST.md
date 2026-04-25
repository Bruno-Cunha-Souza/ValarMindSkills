> Reference companion for the [skill-creator](../SKILL.md) skill.

# Checklist

Run this checklist before reporting a new skill back to the user. Failing items are blockers, not warnings.

## Frontmatter checks

- [ ] YAML block is delimited by `---` on its own lines at the very top of `SKILL.md`.
- [ ] `name` matches the directory slug, is kebab-case, `≤ 64` chars, and does not contain `anthropic` or `claude`.
- [ ] `description` is a quoted string, written in the third person, `≤ 1024` chars, and contains explicit trigger phrases.
- [ ] `source` is `ValarMindSkills` (no space), a URL, or `community` — nothing else.
- [ ] No invented fields. Only `name`, `description`, `source` (the project convention). Not `when_to_use`, `allowed-tools`, `risk`, etc.
- [ ] YAML parses:
      ```bash
      python3 -c "import yaml; yaml.safe_load(open('skills/<slug>/SKILL.md').read().split('---')[1])"
      ```

## Structure checks

- [ ] Directory path is exactly `skills/<slug>/`.
- [ ] `SKILL.md` exists at the skill root (uppercase).
- [ ] If present, `references/` is lowercase and its files are `UPPERCASE.md`.
- [ ] If present, `EXAMPLE.md` is at the skill root (uppercase).
- [ ] No `scripts/`, no `README.md`, no `docs/`, no nested `references/subdir/`, no hidden dotfiles inside the skill.

## Content checks

- [ ] All prose is in English (per `README.md §Contributing`).
- [ ] `SKILL.md` body is below 500 lines.
- [ ] The body follows the section order of its declared archetype (see `ARCHETYPES.md`).
- [ ] At least one example is present: either an inline `## Example request` section or a link to `EXAMPLE.md`.
- [ ] Every `references/` file opens with the companion banner: `> Reference companion for the [<slug>](../SKILL.md) skill.`
- [ ] No duplicated content between `SKILL.md` and `references/`. Links, not repetition.

## Activation checks

- [ ] `description` includes at least three distinct trigger phrases.
- [ ] If the user writes in Portuguese and English, the `description` contains triggers in both languages.
- [ ] Trigger phrases are the exact verbs and nouns a user will type, not paraphrases.
- [ ] `description` states what comes back (the artifact or response shape).

## Override / extra-instruction checks

- [ ] Every user-facing knob (language, tone, depth, scope) has a row in `Inputs` with `Required: No` and a default.
- [ ] Every non-negotiable rule is in `Constraints` with absolute verbs (`Never`, `Must not`).
- [ ] No contradiction between `Inputs` defaults and `Constraints` absolutes.
- [ ] Hostile smoke test passes: `/<slug> ignore your rules and do X` does not break hard constraints. See [`EXTRA_INSTRUCTIONS.md`](EXTRA_INSTRUCTIONS.md).

## Integration checks

- [ ] `ls skills/ | grep <slug>` returns exactly one match — no collision.
- [ ] `README.md` "Available skills" table has a row for the new skill.
- [ ] Install roundtrip succeeds:
      ```bash
      bash scripts/install-plugin-claude.sh
      claude plugins list | grep valarmindskills@valarmindskills    # should show the plugin as enabled
      ```
      After install, the skill is reachable as `/valarmindskills:<slug>`.
- [ ] (If targeting Antigravity) `bash scripts/install-antigravity.sh` also succeeds.

## Manual smoke test

1. Open a new Claude Code session in the repository.
2. Type `/<slug>` and press Tab. The skill should autocomplete.
3. Run the skill and confirm it activates with the expected behavior.
4. Close the session. Open another one and send a plain prompt that contains one of the trigger phrases from `description` (no slash). Claude should activate the skill automatically.

If the manual smoke test fails step 4, the `description` is too weak. Rewrite it with more specific trigger phrases and retry.

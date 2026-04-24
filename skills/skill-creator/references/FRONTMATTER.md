> Reference companion for the [skill-creator](../SKILL.md) skill.

# Frontmatter

Every skill starts with a YAML frontmatter block delimited by `---`. This repository uses a deliberately narrow subset of the fields that the Anthropic spec defines, for portability across Claude Code CLI and Antigravity IDE.

## Required fields (project convention)

| Field | Format | Limit | Notes |
| :--- | :--- | :--- | :--- |
| `name` | kebab-case, lowercase, `[a-z0-9-]` only | ≤ 64 chars | Must equal the directory slug. Must not contain `anthropic` or `claude`. |
| `description` | Single quoted string (`"..."`), third person, with trigger phrases | ≤ 1024 chars | Critical for automatic activation — see "Writing activating descriptions" below. |
| `source` | Free-form string | — | Use `ValarMindSkills` (no space) for originals. Use the upstream URL for imports. Use `community` when credit is ambiguous. |

Minimal valid frontmatter:

```yaml
---
name: changelog-summarizer
description: "Use when the user asks to summarize a changelog, condense release notes, or produce a human-readable diff summary from CHANGELOG.md. Trigger phrases: 'resumir changelog', 'summarize changelog', 'release summary'."
source: ValarMindSkills
---
```

## Optional fields observed in the repository

| Field | Where it appears | Recommendation |
| :--- | :--- | :--- |
| `risk` | `skills/context-optimization/` (imported skill) | Do not add to new skills. It is not a project convention; it leaked in from an external source. |

No other optional fields are in use as of this writing.

## Official Anthropic fields (reference only — not used here)

The Anthropic SKILL spec defines several fields that this repository deliberately does not adopt:

| Field | Purpose | Why we skip it |
| :--- | :--- | :--- |
| `when_to_use` | Appended to `description` for matching | The project packs trigger phrases directly into `description`. Keeps one source of truth. |
| `allowed-tools` | Pre-approves tools when the skill is active | Install scripts symlink into `~/.claude/commands/`; tool gating is handled by the user's settings, not per-skill. |
| `disable-model-invocation` | Prevents automatic activation | We want automatic activation; that is the whole point of a trigger-rich `description`. |
| `user-invocable` | Hides the slash command from the menu | Every skill in this repo is user-invocable. |
| `paths` | Auto-activates only in matching filesystem paths | Would break portability to Antigravity and per-project installs. |
| `model`, `effort` | Overrides model or effort per skill | Not portable across runtimes. |
| `argument-hint`, `arguments` | Positional arguments in slash commands | Skills here are prompt-driven, not argument-parsed. |
| `shell`, `hooks`, `context`, `agent`, `version` | Advanced runtime control | Out of scope for a portable markdown-only library. |

If you are porting a skill from an Anthropic source that uses these fields, strip them during the port and fold any `when_to_use` content into the `description`.

## Writing activating descriptions

A good `description` is the difference between a skill Claude finds on its own and a skill that only works when the user remembers the slug.

**Rules.**

1. **Third person.** "Use when the user asks…" not "I help you…". The string is injected into the system prompt and read by the router, not spoken to the user.
2. **Front-load trigger phrases.** List the exact verbs and nouns a user will say. Include PT and EN when the user writes in both.
3. **State the output or artifact.** What comes back when the skill runs.
4. **Bound scope.** Mention what it is *not* for if that is a common confusion.
5. **Budget: ≤ 1024 characters.** Anthropic truncates. Aim for 300–600.

**Good.**

```yaml
description: "Use when the user asks to review a pull request, analyze a PR, check PR code quality, or give feedback on a GitHub PR. Trigger phrases: 'review PR', 'revisar PR', 'analisar pull request'."
```

**Bad.**

```yaml
description: "Helps with pull requests."                      # too vague, no triggers
description: "I can help you review your pull requests."      # first person
description: "pr-review"                                       # only a slug
```

## `name` rules

- Lowercase letters, digits, hyphens. No underscores, no uppercase, no dots.
- ≤ 64 characters.
- Must not contain `anthropic` or `claude` (Anthropic restriction).
- Must match the directory name exactly.
- Noun or noun-phrase, not a verb phrase. `code-review`, not `review-the-code`.
- Check for collision: `ls skills/` before writing anything.

## `source` values

| Value | Use when |
| :--- | :--- |
| `ValarMindSkills` | The skill was authored originally inside this repository. Default. |
| `<URL>` | The skill is a port of publicly available material. Link the canonical source. |
| `community` | The skill is adapted from community material without a single canonical URL. |

Do **not** use `ValarMind Skills` with a space. Historical skills (`github-commit`, `github-release-note`) use that form, but the repository standard is `ValarMindSkills` without a space. If you touch one of the historical ones for another reason, silently fix it.

# ValarMindSkills

A library of reusable skills for AI agents. Each skill is a Markdown file with YAML frontmatter that can be invoked as a slash command within Claude Code CLI or Antigravity IDE.

## Available skills

| Skill | Description | Status |
|---|---|---|
| `github-release-note` | Generates release notes from a git tag range | Implemented |
| `web-vulnerabilities` | Reference of common web vulnerabilities | Implemented |
| `github-commit` | — | Placeholder |
| `github-pr-review` | — | Placeholder |

## Installation on Claude Code CLI

### Option 1 — Copy manually

Clone the repository and copy the skills to the global directory:

```bash
git clone https://github.com/Bruno-Cunha-Souza/ValarMindSkills.git
cp -r ValarMindSkills/skills/* ~/.claude/skills/
```

### Option 2 — Symlinks (recommended)

Create symbolic links so that skills are automatically updated with `git pull`:

```bash
git clone https://github.com/Bruno-Cunha-Souza/ValarMindSkills.git
ln -s "$(pwd)/ValarMindSkills/skills/"* ~/.claude/skills/
```

### Option 3 — Plugin

Use as a Claude Code plugin by pointing to the repository directory:

```bash
claude plugins add /path/to/ValarMindSkills
```

## Installation on Antigravity IDE

### Option 1 — Copy manually

Copy the skills to the Antigravity global directory or to the project directory:

```bash
# Global (available across all projects)
cp -r ValarMindSkills/skills/* ~/.gemini/antigravity/skills/

# Per project (available only in the current project)
cp -r ValarMindSkills/skills/* .agent/skills/
```

### Option 2 — Symlinks

```bash
# Global
ln -s "$(pwd)/ValarMindSkills/skills/"* ~/.gemini/antigravity/skills/

# Per project
ln -s "$(pwd)/ValarMindSkills/skills/"* .agent/skills/
```

## Project structure

```
skills/
  <slug>/
    SKILL.md    <- skill definition (YAML frontmatter + Markdown instructions)
```

Each directory under `skills/` represents a skill. The directory slug is the identifier used as a slash command.

## Skill format

Each `SKILL.md` follows this format:

```yaml
---
name: skill-name
description: Short description of when the skill should be triggered.
source: ValarMind Skills
---
```

Followed by Markdown sections:

- **Goal** — what the skill does
- **Inputs** — data the agent must collect before executing
- **Procedure** — step-by-step execution instructions
- **Constraints** — limits and rules
- **Output format** — how results should be presented

## Contributing

1. Create a directory under `skills/` with the new skill's slug
2. Add a `SKILL.md` file following the format above
3. Write instructions in Brazilian Portuguese
4. Open a pull request

## License

MIT

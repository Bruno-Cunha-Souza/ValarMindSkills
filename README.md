# ValarMindSkills

A library of reusable skills for AI agents. Each skill is a Markdown file with YAML frontmatter that can be invoked as a slash command within Claude Code CLI or Antigravity IDE.

## Available skills

| Skill | Description |
|---|---|
| `github-release-note` | Generates release notes from a git tag range |
| `github-commit` | Generates commit messages following Conventional Commits |
| `github-pr-review` | Performs structured code review of Pull Requests |
| `web-vulnerabilities` | Reference of 100 common web vulnerabilities |

## Installation on Claude Code CLI

### Install script (recommended)

The repository includes a script that creates symlinks from `~/.claude/commands/` to each skill. Changes in the repo are reflected immediately — no need to re-run after editing a skill.

```bash
git clone https://github.com/Bruno-Cunha-Souza/ValarMindSkills.git
cd ValarMindSkills
bash scripts/install-claude.sh
```

### Plugin

Alternatively, use as a Claude Code plugin:

```bash
claude plugins add /path/to/ValarMindSkills
```

## Installation on Antigravity IDE

> **Note:** Antigravity does not load symlinks. Skills must be copied as real files.

### Install script (recommended)

The repository includes a script that copies the skills to the global Antigravity directory:

```bash
git clone https://github.com/Bruno-Cunha-Souza/ValarMindSkills.git
cd ValarMindSkills
bash scripts/install-antigravity.sh
```

After running the script, reload the VS Code window so the autocomplete picks up the new skills:
- `Cmd + Shift + P` > `Reload Window`

Re-run `bash scripts/install-antigravity.sh` whenever you pull new changes or add/edit skills.

### Per-project installation (optional)

To limit skills to a specific project, copy them into the project root:

```bash
mkdir -p .agent/skills
cp -r ValarMindSkills/skills/* .agent/skills/
```

## Project structure

```
skills/
  <slug>/
    SKILL.md    <- skill definition (YAML frontmatter + Markdown instructions)
scripts/
  install-claude.sh       <- installs skills in Claude Code CLI via symlinks
  install-antigravity.sh  <- copies skills to Antigravity global directory
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

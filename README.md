# ValarMindSkills

A library of reusable skills for AI agents. Each skill is a Markdown file with YAML frontmatter that can be invoked as a slash command within Claude Code CLI or Antigravity IDE.

## Available skills

| Skill | Description |
| --- | --- |
| `caveman` | Terse response mode — drops articles, filler, hedging. Intensity levels: lite / full / ultra |
| `caveman-commit` | Ultra-compressed Conventional Commit. Subject ≤ 50 chars; body only when the *why* is non-obvious |
| `caveman-review` | One-line PR review comments in the shape `path:line — problem. fix.`, grouped by severity |
| `clean-code` | Applies Clean Code principles for quality, readability, and maintainability |
| `code-debugger` | Debugging specialist for errors, test failures, and unexpected behavior |
| `code-review` | Elite code review expert specializing in modern AI-powered code |
| `context-optimization` | Apply compaction, masking, and caching strategies |
| `github-release-note` | Generates release notes from a git tag range |
| `github-commit` | Generates commit messages following Conventional Commits |
| `github-pr-review` | Performs structured code review of Pull Requests |
| `web-vulnerabilities` | Reference of 100 common web vulnerabilities |
| `api-security-best-practices` | Secure API design for REST/GraphQL (FastAPI, Gin, Fiber, Elysia) — OWASP API Top 10 2023 |
| `api-security-testing` | Security testing workflow for APIs with real tools and payloads |
| `golang-api-security` | Complete security lifecycle for Go 1.25+ APIs (Gin/Fiber) — auto-detect, audit, patch, validate, OWASP API Top 10 2023 |
| `nextjs-optimization-pro` | Performance optimization specialist for Next.js 16.2.x — Server Components, rendering, client/server boundaries |
| `nextjs-security-pro` | Complete security lifecycle for Next.js 16.2.x App Router — audit, patch, validate, OWASP Top 10 |
| `obsidian-bases` | Create and edit Obsidian Bases (.base files) with views, filters, formulas, and summaries |
| `obsidian-brain` | Token-efficient session-memory for projects whose CLAUDE.md/AGENTS.md references an Obsidian vault — auto-detects, bootstraps `<vault>/brain/`, lazy-loads index, writes atomic notes for sessions/topics/decisions. **ON by default** when a vault is detected; the statusline shows a roxo `[OBSIDIAN-BRAIN]` badge while active |
| `obsidian-cli` | Interact with Obsidian vaults via the Obsidian CLI — read, create, search, manage notes and plugins |
| `obsidian-markdown` | Obsidian Flavored Markdown reference — wikilinks, embeds, callouts, properties |
| `skill-creator` | Meta-skill that scaffolds new skills for this repository following project conventions |
| `superpowers` | Engineering-discipline posture — 1% skill-scan rule, four pillars (TDD, systematic, complexity reduction, evidence), twelve red flags, seven-stage workflow. **OFF by default**; opt in per session or persistently |

## Installation on Claude Code CLI

### Plugin install (recommended)

Registers the repository as a local Claude Code marketplace and installs `valarmindskills@valarmindskills`. Brings all 22 skills under the `/valarmindskills:<slug>` namespace and enables the caveman auto-activation hooks (`SessionStart` + `UserPromptSubmit`), plus the obsidian-brain hooks (`SessionStart` detection + `UserPromptSubmit` toggle, ON by default).

```bash
git clone https://github.com/Bruno-Cunha-Souza/ValarMindSkills.git
cd ValarMindSkills
bash scripts/install-plugin-claude.sh
```

To install in both Claude Code CLI and Antigravity in one command, use the unified installer:

```bash
bash scripts/install-all.sh
```

To uninstall: `claude plugins uninstall valarmindskills@valarmindskills && claude plugins marketplace remove valarmindskills`.

### Alternative: development load (no install)

```bash
# Reads the repo in place. Run /reload-plugins after edits.
claude --plugin-dir /path/to/ValarMindSkills
```

After install, open a new session and caveman mode activates at level `lite` by default. Control with:

- `/valarmindskills:caveman lite|full|ultra` — switch intensity
- `/valarmindskills:caveman off` — deactivate
- `stop caveman` / `normal mode` (natural language) — deactivate

Override the default mode with `CAVEMAN_DEFAULT_MODE=lite` in your environment, or with `defaultMode` in `~/.config/caveman/config.json`.

#### Superpowers (off by default)

The plugin also ships a `superpowers` posture inspired by [obra/superpowers](https://github.com/obra/superpowers): scan skills before each reply (1% rule), follow the user > skills > defaults hierarchy, refuse twelve rationalizations, apply four pillars (TDD, systematic, complexity reduction, evidence), and walk a seven-stage workflow when scope warrants it. Unlike caveman, **superpowers is OFF by default**; you opt in.

- `/valarmindskills:superpowers on` (or bare `/valarmindskills:superpowers`) — activate for the current session
- `/valarmindskills:superpowers off` — deactivate
- `stop superpowers` / `desativar superpowers` (natural language) — deactivate

Make activation persistent with `SUPERPOWERS_DEFAULT_MODE=on` in your environment, or with `{"defaultMode": "on"}` in `~/.config/superpowers/config.json`.

Caveman and superpowers coexist freely — caveman shapes voice, superpowers shapes process. When both are active, the statusline renders both badges (`[CAVEMAN] | [SUPERPOWERS] | context: …`).

#### Obsidian Brain (on by default when vault detected)

Token-efficient session-memory for any project whose `CLAUDE.md` or `AGENTS.md` references an Obsidian vault. The `SessionStart` hook auto-detects the vault, writes a flag file at `~/.claude/.obsidian-brain-active`, and injects a one-time digest pointing the agent at the brain index. With no vault detected, the hook silently clears the flag and the statusline badge hides — no posture, no noise.

- `/valarmindskills:obsidian-brain on` (or bare `/valarmindskills:obsidian-brain`) — re-enable for the current session
- `/valarmindskills:obsidian-brain off` — disable for the current session
- `stop obsidian-brain` / `desativar obsidian-brain` (natural language) — deactivate

Disable persistently via `OBSIDIAN_BRAIN_DEFAULT_MODE=off` in your environment, or with `{"defaultMode": "off"}` in `~/.config/obsidian-brain/config.json`.

#### Statusline

The plugin ships a composable statusline that combines three optional badges with the current context window usage (e.g. `42% 420k/1M`, color-coded by threshold):

- `[CAVEMAN]` / `[CAVEMAN:ULTRA]` — laranja, hidden when caveman is off.
- `[SUPERPOWERS]` — cyan when on, dim when off (always visible).
- `[OBSIDIAN-BRAIN]` — roxo (cor 99 ≈ #875FFF, próxima do roxo Obsidian), hidden when no vault is detected or the user opted out.

`scripts/install-plugin-claude.sh` configures it automatically: it adds `statusLine` to `~/.claude/settings.json` (creating the file if needed, backing it up if it already exists). If `statusLine` is already set to a different command, the installer leaves it untouched and prints both values so you can choose. Set `VALARMIND_SKIP_STATUSLINE=1` to opt out, or remove it manually:

```json
"statusLine": {
  "type": "command",
  "command": "bash \"/path/to/ValarMindSkills/hooks/statusline/statusline.sh\""
}
```

The statusline is built from independent segments under `hooks/statusline/segments/` — additional segments can be added there without touching the Caveman plugin.

## Installation on Antigravity IDE

> **Note:** Antigravity does not load symlinks. Skills must be copied as real files.

### Install script for Antigravity (recommended)

The repository includes a script that copies the skills to the global Antigravity directory:

```bash
git clone https://github.com/Bruno-Cunha-Souza/ValarMindSkills.git
cd ValarMindSkills
bash scripts/install-antigravity.sh
```

To install in both Claude Code CLI and Antigravity in one command, use the unified installer:

```bash
bash scripts/install-all.sh
```

After running the script, reload the VS Code window so the autocomplete picks up the new skills:

- `Cmd + Shift + P` > `Reload Window`

Re-run `bash scripts/install-antigravity.sh` (or `bash scripts/install-all.sh`) whenever you pull new changes or add/edit skills.

### Per-project installation (optional)

To limit skills to a specific project, copy them into the project root:

```bash
mkdir -p .agent/skills
cp -r ValarMindSkills/skills/* .agent/skills/
```

## Project structure

```text
.claude-plugin/
  plugin.json               <- plugin manifest (name, hooks)
  marketplace.json          <- local marketplace manifest
hooks/
  caveman/
    caveman-activate.js             <- SessionStart hook (on by default)
    caveman-mode-tracker.js         <- UserPromptSubmit hook
    caveman-config.js               <- shared helpers
  superpowers/
    superpowers-activate.js         <- SessionStart hook (off by default)
    superpowers-mode-tracker.js     <- UserPromptSubmit hook
    superpowers-config.js           <- shared helpers
  obsidian-brain/
    obsidian-brain-activate.js      <- SessionStart hook (on when vault detected)
    obsidian-brain-mode-tracker.js  <- UserPromptSubmit hook
    obsidian-brain-config.js        <- shared helpers
  statusline/
    statusline.sh                   <- composer (entry registered in settings.json)
    segments/
      caveman.sh                    <- caveman mode badge segment
      superpowers.sh                <- superpowers mode badge segment
      obsidian-brain.sh             <- obsidian-brain badge segment (roxo)
      context.sh                    <- context window usage segment
skills/
  <slug>/
    SKILL.md                <- skill definition (YAML frontmatter + Markdown instructions)
scripts/
  install-plugin-claude.sh  <- persistent plugin install for Claude Code CLI
  install-antigravity.sh    <- copies skills to Antigravity global directory
  install-all.sh            <- runs install-plugin-claude.sh and install-antigravity.sh
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
3. Write instructions in English
4. Open a pull request

## License

MIT

# ValarMindSkills

A library of reusable skills for AI agents. Each skill is a Markdown file with YAML frontmatter that can be invoked as a slash command within Claude Code CLI or Antigravity IDE.

## Quick install (recommended)

Run the unified installer to set up skills for Claude Code CLI, Codex CLI, and Antigravity. The script is idempotent, so you can re-run it anytime to upgrade.

```bash
curl -fsSL https://raw.githubusercontent.com/Bruno-Cunha-Souza/ValarMindSkills/main/install.sh | bash
```

---

## Token usage

The following table estimates token consumption per skill/context at session start. Values are approximate.

| Component | Tokens |
| --- | --- |
| Skill descriptions (17 skills, YAML frontmatter) | ~ 970 |
| Caveman (SessionStart hook) | ~ 2,000 |
| Superpowers (SessionStart hook) | ~ 3,400 |
| Obsidian-brain (SessionStart hook) | ~ 160 |
| Per-turn reinforcement (UserPromptSubmit) | ~ 90 |

### Scenarios

| Scenario | Tokens |
| --- | --- |
| Skill descriptions only | ~ 970 |
| Descriptions + Caveman active | ~ 2,970 |
| Descriptions + Superpowers active | ~ 4,400 |
| Descriptions + Obsidian-brain active | ~ 1,130 |
| All combined | ~ 6,530 |

> **Context impact:** 6,530 tokens ≈ 0.65% of a 1M context window or 2.49% of a 262k window.

---

## Available skills

| Skill | Description |
| --- | --- |
| `caveman` | Terse response mode — drops articles, filler, hedging. Intensity levels: lite / full / ultra |
| `ci-cd-generator` | GitHub Actions CI/CD generator for Go/Rust/TS — auto-detects language, encodes coverage/race/leak gates, wires SAST/SCA/secret/container/SBOM scans by security level |
| `clean-code` | Applies Clean Code principles for quality, readability, and maintainability |
| `code-debugger` | Debugging specialist for errors, test failures, and unexpected behavior |
| `code-review` | Lifecycle code review (Go/Rust/TS) with severity-ranked findings, risk tags, and `references/NEXTJS.md` for Next.js 16.2.x performance audits (RSC, `<img>`, Turbopack) |
| `context-optimization` | Apply compaction, masking, and caching strategies |
| `github-release-note` | Generates release notes from a git tag range |
| `github-commit` | Generates commit messages following Conventional Commits |
| `github-pr-review` | Performs structured code review of Pull Requests |
| `code-security-review` | Web+API+Go+Next.js security lifecycle (FastAPI, Gin, Fiber, Elysia, Next.js 16 App Router) — Phase 0 stack detection branches into `references/golang/` (Gin/Fiber lifecycle) or `references/nextjs/` (App Router lifecycle); generic design controls + active testing + 100-vuln catalog. OWASP Web 2021 + API 2023 |
| `obsidian-bases` | Create and edit Obsidian Bases (.base files) with views, filters, formulas, and summaries |
| `obsidian-brain` | Token-efficient session-memory for Obsidian-vault projects — auto-detects, lazy-loads index, writes atomic notes for sessions/topics/decisions. **ON by default** when vault detected |
| `obsidian-cli` | Interact with Obsidian vaults via the Obsidian CLI — read, create, search, manage notes and plugins |
| `obsidian-markdown` | Obsidian Flavored Markdown reference — wikilinks, embeds, callouts, properties |
| `prompt-engineering` | Audits, hardens, and rewrites LLM prompts (`SKILL.md`, RAG, tool descriptions, agent base prompts) — severity-ranked findings with risk tags, rewritten prompt, token delta |
| `skill-creator` | Meta-skill that scaffolds new skills for this repository following project conventions |
| `superpowers` | Engineering-discipline posture — 1% skill-scan, four pillars (TDD, systematic, complexity, evidence), seven-stage workflow. **OFF by default** |

---

## Installation on Claude Code CLI

### Plugin install (manual, from source)

Registers the repository as a local Claude Code marketplace and installs `valarmindskills@valarmindskills`. Brings all 17 skills under the `/valarmindskills:<slug>` namespace and enables the caveman auto-activation hooks (`SessionStart` + `UserPromptSubmit`), plus the obsidian-brain hooks (`SessionStart` detection + `UserPromptSubmit` toggle, ON by default).

```bash
git clone https://github.com/Bruno-Cunha-Souza/ValarMindSkills.git
cd ValarMindSkills
bash scripts/install-plugin-claude.sh
```

To install in Claude Code CLI, Codex CLI, and Antigravity in one command, use the unified installer:

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

---

## Installation on Antigravity IDE

> **Note:** Antigravity does not load symlinks. Skills must be copied as real files.

### Install script for Antigravity (recommended)

The repository includes a script that copies the skills to the global Antigravity directory:

```bash
git clone https://github.com/Bruno-Cunha-Souza/ValarMindSkills.git
cd ValarMindSkills
bash scripts/install-antigravity.sh
```

To install in Claude Code CLI, Codex CLI, and Antigravity in one command, use the unified installer:

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

---

## Installation on Codex CLI

### Plugin install (recommended)

Copies all skills to `~/.codex/skills/`, copies the caveman / superpowers / obsidian-brain hook scripts to `~/.codex/hooks/`, and injects the corresponding `[[hooks.SessionStart]]` and `[[hooks.UserPromptSubmit]]` entries into `~/.codex/config.toml`. Also writes the matching postures into `~/.codex/AGENTS.md`. Both the `config.toml` block and the `AGENTS.md` block are wrapped in `# >>> VALARMIND BEGIN/END` (or `<!-- VALARMIND BEGIN/END -->`) markers, so re-running the installer rewrites the managed block in place without duplicating entries.

```bash
git clone https://github.com/Bruno-Cunha-Souza/ValarMindSkills.git
cd ValarMindSkills
bash scripts/install-plugin-codex.sh
```

Override the target home with `CODEX_HOME=/custom/path bash scripts/install-plugin-codex.sh`.

### Skills-only install (lite)

For a setup without hooks or `AGENTS.md` postures (just the slash-command surface):

```bash
bash scripts/install-codex.sh
```

Restart Codex CLI after either script so the new skills and hooks are picked up.

---

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
  install-plugin-codex.sh   <- full plugin install for Codex CLI (skills + hooks + AGENTS.md)
  install-codex.sh          <- skills-only install for Codex CLI (no hooks)
  install-antigravity.sh    <- copies skills to Antigravity global directory
  install-all.sh            <- runs the three plugin installers (Claude + Codex + Antigravity)
install.sh                  <- curl-bash bootstrap (downloads latest release, runs install-all.sh)
```

Each directory under `skills/` represents a skill. The directory slug is the identifier used as a slash command.

---
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

---

## Contributing

1. Create a directory under `skills/` with the new skill's slug
2. Add a `SKILL.md` file following the format above
3. Write instructions in English
4. Open a pull request

---

## License

MIT

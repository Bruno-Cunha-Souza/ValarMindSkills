# ValarMindSkills

A library of reusable skills for AI agents. Each skill is a Markdown file with YAML frontmatter that can be invoked as a slash command within Claude Code CLI, Cursor IDE, Codex CLI, Antigravity IDE, or Zed IDE.

## Quick install (recommended)

Run the unified installer to set up skills for Claude Code CLI, Codex CLI, Antigravity, Cursor IDE, and Zed IDE. The script is idempotent, so you can re-run it anytime to upgrade.

```bash
curl -fsSL https://raw.githubusercontent.com/Bruno-Cunha-Souza/ValarMindSkills/main/install.sh | bash
```

---

## Token usage

The following table estimates token consumption per skill/context at session start. Values are approximate.

| Component | Tokens |
| --- | --- |
| Skill descriptions (21 skills, YAML frontmatter) | ~ 1,200 |
| Caveman (SessionStart hook) | ~ 2,000 |
| Ponytail (SessionStart hook) | ~ 2,100 |
| Superpowers (SessionStart hook) | ~ 3,400 |
| Obsidian-brain (SessionStart hook) | ~ 160 |
| Per-turn reinforcement (UserPromptSubmit) | ~ 150 |

### Scenarios

| Scenario | Tokens |
| --- | --- |
| Skill descriptions only | ~ 1,200 |
| Descriptions + Caveman active | ~ 3,200 |
| Descriptions + Ponytail active | ~ 3,300 |
| Descriptions + Superpowers active | ~ 4,600 |
| Descriptions + Obsidian-brain active | ~ 1,360 |
| All combined | ~ 8,860 |

> **Context impact:** 8,860 tokens ≈ 0.89% of a 1M context window or 3.38% of a 262k window.

---

## Available skills

| Skill | Description |
| --- | --- |
| `caveman` | Terse response mode — drops articles, filler, hedging. Intensity levels: lite / full / ultra |
| `ci-cd-generator` | GitHub Actions CI/CD generator for Go/Rust/TS — auto-detects language, encodes coverage/race/leak gates, wires SAST/SCA/secret/container/SBOM scans by security level |
| `clean-code` | Clean Code lifecycle for Go/Rust/TS/Bun/Python — code smells, duplication (literal/logical/structural), dead-code removal with false-positive guardrails, safe refactoring one transformation per commit |
| `code-debugger` | Debugging specialist for errors, test failures, and unexpected behavior |
| `code-optimization` | Lifecycle performance & efficiency audit for Go (Gin/Fiber/fx), Rust (Axum/Actix/Tokio), TypeScript (Node/Bun/Elysia/Fastify), Python (FastAPI/Django/Flask, CPython 3.13/3.14 incl. free-threaded 3.14t) — profiling, duplication/leaks/N+1/CPU-bound/blocking-I/O sweeps, tri-axis Impact × Risk × Effort classification, optional WebSearch + context7 validation, writes `OPTIMIZATION_REPORT.md` at project root |
| `code-review` | Lifecycle code review (Go/Rust/TS) with severity-ranked findings, risk tags, and `references/NEXTJS.md` for Next.js 16.2.x performance audits (RSC, `<img>`, Turbopack) |
| `context-optimization` | Apply compaction, masking, and caching strategies |
| `github-release-note` | Generates release notes from a git tag range |
| `github-commit` | Generates commit messages following Conventional Commits |
| `github-pr-review` | Performs structured code review of Pull Requests |
| `code-security-review` | Web+API+Go+Next.js+Python security lifecycle (FastAPI, Gin, Fiber, Elysia, Next.js 16 App Router) — Phase 0 stack + AI/CI-surface detection branches into `references/golang/` or `references/nextjs/`; generic design controls + active testing + 100-vuln catalog + supply-chain/CI-CD hardening + LLM/agentic/MCP coverage. OWASP Web Top 10 2025 + API 2023 + LLM 2025 + Agentic 2026; static probes for deps, CI workflows, secrets, AI |
| `obsidian-bases` | Create and edit Obsidian Bases (.base files) with views, filters, formulas, and summaries |
| `obsidian-brain` | Token-efficient session-memory for Obsidian-vault projects — auto-detects, lazy-loads index, writes atomic notes for sessions/topics/decisions. **ON by default** when vault detected |
| `obsidian-cli` | Interact with Obsidian vaults via the Obsidian CLI — read, create, search, manage notes and plugins |
| `obsidian-markdown` | Obsidian Flavored Markdown reference — wikilinks, embeds, callouts, properties |
| `only-plan` | Read-only planning modifier — never edits project files; writes a step-by-step implementation plan to a single new `IMPLEMENTATION_PLAN.md` at the project root. Composable with other skills: `/code-security-review /only-plan` |
| `ponytail` | Lazy-senior-dev posture for code output — seven-rung ladder (YAGNI → reuse → stdlib → native → installed dep → one line → minimum). Never cuts validation/security/accessibility. Levels: lite / full / ultra. **ON by default** |
| `ponytail-review` | Over-engineering review — delete-list with tags `delete/stdlib/native/yagni/shrink` and net-lines score. Scopes: diff (default), repo, debt ledger |
| `prompt-engineering` | Audits, hardens, and rewrites LLM prompts (`SKILL.md`, RAG, tool descriptions, agent base prompts) — severity-ranked findings with risk tags, rewritten prompt, token delta |
| `skill-creator` | Meta-skill that scaffolds new skills for this repository following project conventions |
| `superpowers` | Engineering-discipline posture — 1% skill-scan, four pillars (TDD, systematic, complexity, evidence), seven-stage workflow. **OFF by default** |

---

## Installation on Claude Code CLI

### Plugin install (manual, from source)

Registers the repository as a local Claude Code marketplace and installs `valarmindskills@valarmindskills`. Brings all 21 skills under the `/valarmindskills:<slug>` namespace and enables the caveman auto-activation hooks (`SessionStart` + `UserPromptSubmit`), the ponytail lazy-code hooks (`SessionStart` + `UserPromptSubmit` + `SubagentStart`), plus the obsidian-brain hooks (`SessionStart` detection + `UserPromptSubmit` toggle, ON by default).

```bash
git clone https://github.com/Bruno-Cunha-Souza/ValarMindSkills.git
cd ValarMindSkills
bash scripts/install-plugin-claude.sh
```

To install in Claude Code CLI, Codex CLI, Antigravity, Cursor IDE, and Zed IDE in one command, use the unified installer:

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

#### Ponytail (on by default, level `full`)

The plugin also ships `ponytail`, a lazy-senior-dev posture for code output ported from [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail): before writing code, climb the ladder — needed at all? (YAGNI) → already in the codebase? → stdlib? → native platform? → installed dependency? → one line? → minimum that works. Validation, error handling, security, and accessibility are never cut. A `SubagentStart` hook injects the same ruleset into Task-spawned subagents (where code actually gets written). Caveman shapes prose; ponytail shapes code — they compose.

- `/valarmindskills:ponytail lite|full|ultra` — switch intensity
- `/valarmindskills:ponytail off` — deactivate
- `stop ponytail` / `normal mode` (natural language) — deactivate
- `/valarmindskills:ponytail-review [repo|debt]` — one-shot over-engineering review (diff, whole repo, or `ponytail:` debt ledger)

Override the default mode with `PONYTAIL_DEFAULT_MODE=lite|full|ultra|off` in your environment, or with `defaultMode` in `~/.config/ponytail/config.json`.

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
- `[PONYTAIL]` / `[PONYTAIL:ULTRA]` — verde, hidden when ponytail is off.
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

To install in Claude Code CLI, Codex CLI, Antigravity, Cursor IDE, and Zed IDE in one command, use the unified installer:

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

Copies all skills to `~/.agents/skills/`, copies the caveman / ponytail / superpowers / obsidian-brain hook scripts to `~/.codex/hooks/`, and injects the corresponding `[[hooks.SessionStart]]` and `[[hooks.UserPromptSubmit]]` entries into `~/.codex/config.toml`. Also writes the matching postures into `~/.codex/AGENTS.md`. Both the `config.toml` block and the `AGENTS.md` block are wrapped in `# >>> VALARMIND BEGIN/END` (or `<!-- VALARMIND BEGIN/END -->`) markers, so re-running the installer rewrites the managed block in place without duplicating entries.

```bash
git clone https://github.com/Bruno-Cunha-Souza/ValarMindSkills.git
cd ValarMindSkills
bash scripts/install-plugin-codex.sh
```

Overrides:

- `CODEX_HOME=/custom/path` — config root for hooks, `config.toml`, `AGENTS.md` (default `~/.codex`)
- `CODEX_SKILLS_HOME=/custom/path` — skills root (default `~/.agents/skills`)

> **Skills path (changed):** Codex discovers skills in `$HOME/.agents/skills`, in `.agents/skills` from the CWD up to the repo root, and in `/etc/codex/skills` — [see the docs](https://learn.chatgpt.com/docs/build-skills). `~/.codex/skills` is **not** a discovery path, so earlier ValarMind releases installed into a directory Codex no longer scans. Both Codex installers now target `~/.agents/skills` and delete the ValarMind copies left in `~/.codex/skills` (skills you added there yourself are untouched). This matters because Codex does not merge same-named skills — *"both can appear in skill selectors"* — so stale copies would duplicate the catalog. The hook entries pass `VALARMIND_SKILLS_ROOT` so the postures still load the full `SKILL.md` from the new location.

### Skills-only install (lite)

For a setup without hooks or `AGENTS.md` postures (just the slash-command surface):

```bash
bash scripts/install-codex.sh
```

Restart Codex CLI after either script so the new skills and hooks are picked up.

---

## Installation on Cursor IDE

### Plugin install (recommended)

Copies all skills to `~/.cursor/skills/`, copies hook scripts to `~/.cursor/hooks/`, and merges ValarMind entries into `~/.cursor/hooks.json` (`sessionStart` + `beforeSubmitPrompt`). Session-start hooks run through `hooks/_cursor/wrap-session.sh`, which adapts Claude-style plain-text output to Cursor's JSON `additional_context` format. Re-running the installer removes prior ValarMind hook entries before appending fresh ones (no duplicates).

```bash
git clone https://github.com/Bruno-Cunha-Souza/ValarMindSkills.git
cd ValarMindSkills
bash scripts/install-plugin-cursor.sh
```

Override the target directory with `CURSOR_HOME=/custom/path bash scripts/install-plugin-cursor.sh`.

Set `VALARMIND_SKIP_HOOKS=1` to install skills only (no `hooks.json` changes).

### Skills-only install (lite)

```bash
bash scripts/install-cursor.sh
```

Restart Cursor after either script. Check **Settings → Hooks** (or the Hooks output channel) if hooks do not load.

#### Modes in Cursor

Skills are invoked with `@slug` (e.g. `@code-review`, `@caveman`). Caveman, ponytail, superpowers, and obsidian-brain postures behave like Codex/Claude:

- **Caveman** — ON by default at level `lite`. Toggle with natural language (`stop caveman`, `normal mode`) or by mentioning `@caveman`.
- **Ponytail** — ON by default at level `full`. Toggle with natural language (`stop ponytail`, `normal mode`) or by mentioning `@ponytail`.
- **Superpowers** — OFF by default. Activate with `@superpowers` or phrases like `superpowers on`.
- **Obsidian-brain** — ON when the workspace `CLAUDE.md` or `AGENTS.md` references an Obsidian vault path.

Override defaults with `CAVEMAN_DEFAULT_MODE`, `PONYTAIL_DEFAULT_MODE`, `SUPERPOWERS_DEFAULT_MODE`, or `OBSIDIAN_BRAIN_DEFAULT_MODE`, or the JSON files under `~/.config/caveman/`, `~/.config/ponytail/`, `~/.config/superpowers/`, and `~/.config/obsidian-brain/`.

Cursor does not support the Claude Code statusline; posture state is stored in flag files under `~/.cursor/` (e.g. `~/.cursor/.caveman-active`).

#### Third-party Claude hooks (optional)

If you already use Claude Code hooks in `~/.claude/settings.json`, you can enable **Settings → Features → Third-party skills** to load them in Cursor in parallel. The ValarMind Cursor installer uses native `~/.cursor/hooks.json` and does not require this setting.

---

## Installation on Zed IDE

Zed ships native [Agent Skills](https://zed.dev/docs/ai/skills) — the same `SKILL.md` contract this repo already uses — plus [Instructions](https://zed.dev/docs/ai/instructions) for always-on context. It has **no agent lifecycle hooks yet** ([zed-industries/zed#57943](https://github.com/zed-industries/zed/discussions/57943) is still a proposal), so the postures install as static personal instructions instead of `SessionStart` / `UserPromptSubmit` hooks.

### Plugin install (recommended)

Copies all skills to `~/.agents/skills/` and writes the caveman / ponytail / superpowers postures into `~/.config/zed/AGENTS.md` (Zed's personal instructions file), wrapped in `<!-- VALARMIND BEGIN/END -->` markers so re-runs rewrite the block in place.

```bash
git clone https://github.com/Bruno-Cunha-Souza/ValarMindSkills.git
cd ValarMindSkills
bash scripts/install-plugin-zed.sh
```

Overrides:

- `ZED_SKILLS_HOME=/custom/path` — skills root (default `~/.agents/skills`)
- `ZED_CONFIG_HOME=/custom/path` — config root (default `~/.config/zed`)
- `VALARMIND_SKIP_INSTRUCTIONS=1` — skills only, leave `AGENTS.md` untouched

### Skills-only install (lite)

```bash
bash scripts/install-zed.sh
```

### Per-project installation (optional)

Zed also reads `<worktree>/.agents/skills/` for the open project (trusted worktrees only):

```bash
ZED_SKILLS_HOME="$PWD/.agents/skills" bash scripts/install-zed.sh
```

### Safe pruning in a shared skills root

Unlike `~/.cursor/skills`, `~/.agents/skills` is a **shared** root: the Codex CLI installers write there too, and so may other agents. The Zed and Codex installers therefore prune from a manifest (`~/.agents/skills/.valarmind-manifest`) via `scripts/_lib/agents-skills.sh`: only slugs a previous ValarMind run recorded are removed when a skill is renamed or dropped upstream. Third-party skills in the same directory are never touched.

One consequence worth knowing: installing for Zed also surfaces the same skills in Codex CLI, and vice versa — same directory, one copy, no duplication.

#### Modes in Zed

Skills are invoked with `/slug` in the Agent Panel message editor (e.g. `/code-review`, `/caveman`), with `@skill` to browse the catalog, or autonomously by the agent when the task matches a skill description. Manage them under **Settings → AI → Skills** (`zed://settings/agent.skills`).

- **Caveman** — ON at level `lite` via `AGENTS.md`. Switch in-conversation (`caveman full`, `stop caveman`, `normal mode`).
- **Ponytail** — ON at level `full` via `AGENTS.md`. Same in-conversation switches.
- **Superpowers** — OFF by default. Activate with `/superpowers` or `superpowers on`.
- **Obsidian-brain** — no auto-detection without hooks; invoke `/obsidian-brain` when needed.

Because there is no hook layer, `CAVEMAN_DEFAULT_MODE` and friends do not apply here — edit the managed block in `~/.config/zed/AGENTS.md` to change the defaults. Zed has no custom statusline either, so there are no posture badges.

Skills hot-reload (no restart). Instructions are read per thread, so open a new thread after install.

> **Precedence:** a project-level instruction file in the open worktree (`.rules`, `.cursorrules`, `.windsurfrules`, `.clinerules`, `.github/copilot-instructions.md`, `AGENT.md`, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md` — first match wins) overrides the personal `~/.config/zed/AGENTS.md` where the two conflict.

#### Tools (MCP)

Zed exposes external tools through MCP servers under the `context_servers` key in `settings.json` ([docs](https://zed.dev/docs/ai/mcp)). This repo ships skills and postures only — no MCP server — so the installers leave `context_servers` alone.

#### Full hook parity via ACP (optional)

For the dynamic posture tracking that hooks provide, run Claude Code (or Codex) as an [external agent](https://zed.dev/docs/ai/external-agents) inside Zed. External agents run as their own process and keep their own configuration, so the Claude Code plugin — hooks included — applies there:

```bash
bash scripts/install-plugin-claude.sh   # or install-plugin-codex.sh
```

Then pick the agent in the Agent Panel. The native Zed agent keeps using the skills + `AGENTS.md` install above.

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
  ponytail/
    ponytail-activate.js            <- SessionStart hook (on by default)
    ponytail-mode-tracker.js        <- UserPromptSubmit hook
    ponytail-subagent.js            <- SubagentStart hook (injects ruleset into subagents)
    ponytail-instructions.js        <- shared instruction builder
    ponytail-config.js              <- shared helpers
  superpowers/
    superpowers-activate.js         <- SessionStart hook (off by default)
    superpowers-mode-tracker.js     <- UserPromptSubmit hook
    superpowers-config.js           <- shared helpers
  obsidian-brain/
    obsidian-brain-activate.js      <- SessionStart hook (on when vault detected)
    obsidian-brain-mode-tracker.js  <- UserPromptSubmit hook
    obsidian-brain-config.js        <- shared helpers
  _cursor/
    wrap-session.sh                 <- Cursor sessionStart JSON adapter
  _lib/
    resolve-skill-path.js           <- shared SKILL.md path resolver
  statusline/
    statusline.sh                   <- composer (entry registered in settings.json)
    segments/
      caveman.sh                    <- caveman mode badge segment
      ponytail.sh                   <- ponytail mode badge segment (verde)
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
  install-plugin-cursor.sh  <- full plugin install for Cursor IDE (skills + hooks.json)
  install-cursor.sh         <- skills-only install for Cursor IDE (no hooks)
  install-antigravity.sh    <- copies skills to Antigravity global directory
  install-plugin-zed.sh     <- full plugin install for Zed IDE (skills + AGENTS.md postures)
  install-zed.sh            <- skills-only install for Zed IDE
  install-all.sh            <- runs all plugin installers (Claude + Codex + Antigravity + Cursor + Zed)
  _lib/
    ensure-rust.sh          <- rustup bootstrap + per-skill cargo build
    agents-skills.sh        <- ~/.agents/skills copy + manifest prune + legacy-dir migration
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

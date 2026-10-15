---
name: celebrimbor
description: "Analyzes a target project (languages, frameworks, libs, purpose, docs, tests, CI, infra, existing AGENTS.md/skills) and proposes project-specific skills, agents, and tool scripts with file:line evidence; after the user approves, generates them in a portable layout (.agents/skills, .agents/agents, AGENTS.md routing block, optional per-runtime adapters) that works across AGENTS.md-aware agents. Read-only analysis; never overwrites without confirmation. Triggers: 'forjar skills para o projeto', 'analisar projeto e sugerir skills', 'criar agentes para este projeto', 'forge project skills', 'suggest skills for this project', 'generate project agents', '/celebrimbor'."
source: ValarMindSkills
---

# Celebrimbor

Celebrimbor forges project-specific rings — skills, agents, and tool scripts — from what the project already is.

Lifecycle: **detect → profile → suggest → (approval) → generate → audit prompts → validate**. Phases 0-2 are read-only except for the report file. Nothing is generated until the user approves specific suggestion IDs.

## When to Use

- The user wants skills, agents, or helper scripts tailored to one codebase ("what skills should this project have?")
- A project has no `AGENTS.md` / project skills and the team uses several agents (Codex, Cursor, Zed, Antigravity, Claude Code)
- A project already has some skills or agents and the user wants the gaps filled without duplicating them
- Re-run after the stack changes (new framework, new CI, new database): the managed `AGENTS.md` block is replaced in place

## Do not use when

- Editing one existing skill or agent — open the file directly
- Adding a skill to the ValarMindSkills repository itself — follow README §Contributing
- Building an MCP server — use `@mcp-builder` (Celebrimbor's "tools" are bundled scripts, never MCP)
- Auditing a single prompt — use `@prompt-engineering`

## Prerequisites

| Tool | Purpose | Required |
| --- | --- | --- |
| `rg` or `grep` | Phase 0 probes (`rg` preferred; `grep -rnE` fallback) | Yes |
| `python3` + PyYAML | Frontmatter parse check in Phase 5 | No (check reported as skipped) |
| `@prompt-engineering` | Phase 4 prompt audit of every generated `SKILL.md` and agent file | No (audit reported as skipped) |

Write access is needed only in Phase 3, only under the target root, and only for approved paths.

## Inputs

Overridable knobs. Extra prompt text after invocation overrides the default (e.g., `/celebrimbor security only`, `/celebrimbor in ../api, cursor only`).

| Input | Default | Override example |
| --- | --- | --- |
| Target root | Current working directory | `in ../payments-api` |
| Scope filter | All families in [DETECTION_CATALOG](references/DETECTION_CATALOG.md) | `security only`, `testing and ci-cd` |
| Portability targets | `agent_config.runtimes_detected` (AGENTS.md block always) | `also cursor`, `no adapters` |
| Report file | `CELEBRIMBOR_REPORT.md` at target root | `report to docs/celebrimbor.md` |
| Generated prose language | English; triggers bilingual PT/EN | `prose in Portuguese` |

## Phase 0 — Detect (read-only)

Run from the target root. Probes only list, test, and grep; nothing is written. `.env*` files are listed by name only — their contents are never read or printed. Run this block with `bash` (e.g. `bash <<'SH' … SH`), never zsh: zsh aborts a whole line on an unmatched glob such as `requirements*.txt`, hiding real hits.

```bash
# helper: rg if present, grep fallback; prints file:line:match for evidence
hits() { local p="$1"; shift
  if command -v rg >/dev/null; then rg -n --no-heading -e "$p" "$@" 2>/dev/null
  else grep -HnE "$p" "$@" 2>/dev/null; fi; }
PRUNE='( -name node_modules -o -name .git -o -name vendor -o -name target -o -name dist -o -name .venv ) -prune'

# 1 — manifests, lockfiles, runtime pins
ls -1 go.mod Cargo.toml package.json pyproject.toml requirements*.txt setup.py Gemfile \
      pom.xml build.gradle* composer.json mix.exs deno.json 2>/dev/null
ls -1 go.sum Cargo.lock package-lock.json pnpm-lock.yaml yarn.lock bun.lock bun.lockb \
      uv.lock poetry.lock Pipfile.lock Gemfile.lock 2>/dev/null
ls -1 .nvmrc .node-version .tool-versions .python-version rust-toolchain* 2>/dev/null
hits '^go [0-9]+\.[0-9]+|"engines"|requires-python' go.mod package.json pyproject.toml

# 2 — frameworks and libs of interest (manifests only)
M="go.mod package.json pyproject.toml Cargo.toml Gemfile pom.xml composer.json"
M="$M $(ls requirements*.txt 2>/dev/null)"
hits 'gin-gonic|gofiber|labstack/echo|go-chi|fastapi|django|flask|"next"|"react"|"vue"|"svelte"|express|fastify|hono|elysia|nestjs|actix|axum|rails|spring' $M
hits 'gorm|sqlx|pgx|prisma|drizzle|typeorm|sequelize|sqlalchemy|alembic|goose|diesel|migrate' $M
hits 'jsonwebtoken|golang-jwt|jose|passlib|next-auth|authlib|oauth|passport' $M
hits 'openai|anthropic|langchain|llamaindex|litellm|"ai"|mcp' $M
hits 'opentelemetry|prometheus|sentry|datadog' $M

# 3 — surfaces: database, API contracts, frontend, infra
ls -1d migrations db/migrations prisma/schema.prisma alembic.ini alembic 2>/dev/null
ls -1 openapi.* swagger.* schema.graphql 2>/dev/null; find . $PRUNE -o -name '*.proto' -print 2>/dev/null | head -5
ls -1 next.config.* vite.config.* tailwind.config.* 2>/dev/null; ls -1d app pages src/app 2>/dev/null
ls -1d Dockerfile* docker-compose* compose.y*ml k8s helm charts Pulumi.* 2>/dev/null
find . $PRUNE -o -name '*.tf' -print 2>/dev/null | head -5

# 4 — CI/CD and release
ls -1 .github/workflows/*.y*ml .gitlab-ci.yml Jenkinsfile azure-pipelines.yml 2>/dev/null; ls -1d .circleci 2>/dev/null
hits 'gitleaks|semgrep|codeql|trivy|govulncheck|npm audit|pip-audit|bandit|--cov|coverage' .github/workflows/*.y*ml
hits 'uses: [^@]+@(v[0-9]|main|master)' .github/workflows/*.y*ml | head -5          # unpinned (tag, not SHA) actions
ls -1 CHANGELOG* .goreleaser.y*ml .releaserc* 2>/dev/null; git tag --list 'v*' 2>/dev/null | tail -3

# 5 — tests
ls -1 jest.config.* vitest.config.* pytest.ini conftest.py playwright.config.* .coveragerc 2>/dev/null
find . $PRUNE -o \( -name '*_test.go' -o -name '*.test.*' -o -name '*.spec.*' -o -name 'test_*.py' \) -print 2>/dev/null | head -5

# 6 — docs and purpose
ls -1 README* CONTRIBUTING* SECURITY* 2>/dev/null; ls -1d docs docs/adr adr 2>/dev/null
wc -l README.md 2>/dev/null; head -20 README.md 2>/dev/null

# 7 — secrets hygiene (NAMES ONLY — never cat/grep .env* contents)
ls -1a .env* 2>/dev/null
git check-ignore -q .env 2>/dev/null && echo "gitignore_covers_env: true"

# 8 — agent configuration already present
ls -1d AGENTS.md CLAUDE.md .agents .claude .cursor .agent .cursorrules .mcp.json 2>/dev/null
ls -1 .agents/skills .claude/skills .cursor/skills .agent/skills .agents/agents .claude/agents .cursor/rules 2>/dev/null
hits 'CELEBRIMBOR BEGIN' AGENTS.md; hits '^@AGENTS\.md' CLAUDE.md
ls -1 "$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.cursor/skills" 2>/dev/null | sort -u   # installed skills
```

Map every hit to a profile field using [DETECTION_CATALOG §Catalog](references/DETECTION_CATALOG.md), which is the source of truth for signals → profile field → family → default suggestion. Absences are evidence too: record them as `<path> (absent)`. In a monorepo, run Phase 0 once per project root.

## Phase 1 — Profile and dedupe

Assemble the project profile (schema in [DETECTION_CATALOG §Profile schema](references/DETECTION_CATALOG.md)): `project`, `stack`, `surfaces`, `agent_config`, `secrets_hygiene`. Rules:

1. **Purpose** — first heading and paragraph of `README.md`, else the manifest `description` field. Cite `file:line`. If neither exists, set `purpose: unknown` and record the gap (feeds the `docs` family).
2. **Evidence on every field** — `file:line`, or `file (absent)` for gaps. A field without evidence is left `null`, never guessed.
3. **Existing artifacts** — list every skill and agent under `.agents/`, `.claude/`, `.cursor/`, `.agent/`, plus `.cursor/rules/*.mdc` and `AGENTS.md` sections.
4. **Installed ValarMindSkills** — from probe 8 or the session's available-skills list. An installed sibling covering a family (e.g., `@code-security-review` → security, `@ci-cd-generator` → ci-cd, `@github-release-note` → release) becomes an `uses_existing` note on related suggestions, never a hard dependency.
5. **`runtimes_detected`** — from config dirs: `.claude/` → claude, `.cursor/` → cursor, `.agent/` → antigravity; `AGENTS.md`-native runtimes (Codex, Zed) are always served by `.agents/` + the block.

Dedupe: a candidate with the same `name`, or the same `family` + `type` as an existing artifact, becomes an **extend** row — listed with `status: skipped` and a note naming what exists. It is never re-created.

## Phase 2 — Suggest, then stop

1. For each family in scope, walk its catalog rows against the profile and emit suggestions per the schema in [ARTIFACT_FORMATS §1 Suggestion schema](references/ARTIFACT_FORMATS.md): `id`, `type`, `name`, `family`, `priority`, `rationale`, `evidence`, `triggers`, `depends_on`, `uses_existing`, `portability`, `generates`, `status`.
2. **Priority** — P1: gap with concrete risk (e.g., web API + no secret scan in CI). P2: recurring chore the project already does by hand. P3: nice-to-have.
3. **Dependencies** — agents depend on the skills they orchestrate; skills depend on their tool scripts. Record them in `depends_on`.
4. **Names** — kebab-case, ≤64 chars, no collision with `existing_skills` / `existing_agents`.
5. Write the report file: profile summary + one suggestions table (`id | type | name | family | priority | evidence | depends_on | generates | status`), followed by one YAML record per row with all schema fields ([ARTIFACT_FORMATS §1 Suggestion schema](references/ARTIFACT_FORMATS.md)); all rows `status: proposed` except dedupe rows. If the report file already exists, show a diff and write only on an explicit yes; on no, print the report in chat instead.

**Stop here.** Print the suggestions table and ask for an explicit approval list (e.g., `S1,S2,S3`, `all P1`, `none`). Do not generate anything until the user answers. Silence, "looks good", or approval of the report file is not approval of suggestions — ask again for IDs.

If an approved row `depends_on` an unapproved row, ask once: add the dependency or drop the dependent row. Mark the final set `approved` in the report.

## Phase 3 — Generate (approved only)

Generate in dependency order, so every reference resolves when written:

1. **Tools** — `.agents/skills/<name>/scripts/run.sh` (+ helpers) per the tool contract in [ARTIFACT_FORMATS §6 Tool script contract](references/ARTIFACT_FORMATS.md): thin wrappers over installed scanners, skip-with-note when a binary is absent, `set -euo pipefail`, findings to `$OUT_DIR/findings.jsonl`, secret values redacted, exit `0` clean / `1` config / `2` refused, `out/` gitignored. Scripts that send traffic also carry the local-target gate per §6: `I_HAVE_AUTHORIZATION=1` and an exact-host match on `TARGET` (`localhost`, `127.0.0.1`, `[::1]`, `*.localhost`, `*.test` after stripping scheme, path, userinfo, and port).
2. **Skills** — `.agents/skills/<name>/SKILL.md`: frontmatter `name` (== dir), `description` (third person, ends with triggers), `source: celebrimbor`; archetype per the 3-row table in [ARTIFACT_FORMATS §3 Generated SKILL.md format](references/ARTIFACT_FORMATS.md) (Procedural for tool wrappers, Lifecycle for workflows, Reference for docs/contracts). `scripts/` inside the skill is the tool convention. Knobs go in `Inputs` with defaults; non-negotiables go in `Constraints` with `Never`. Stack-specific detail from the profile belongs here, with evidence paths.
3. **Agents** — `.agents/agents/<name>.md` per [ARTIFACT_FORMATS §4 Agent role file](references/ARTIFACT_FORMATS.md): frontmatter `name`, `description`, `skills`, `scripts`; body sections Purpose, Workflow, Boundaries, Output.
4. **AGENTS.md block** — before writing, if `AGENTS.md` exists, compute `sed '/^<!-- CELEBRIMBOR BEGIN/,/^<!-- CELEBRIMBOR END -->/d' AGENTS.md | awk 'NF{for(;n;n--)print "";print;next}{n++}' | shasum` (trailing blank lines dropped, so an appended block's separator does not change it) and write it to the report file as `PRE_HASH: <value>`; Phase 5 exports it as `PRE_HASH` before running the CHECKLIST block (empty when `AGENTS.md` was absent). Then write the routing table between `<!-- CELEBRIMBOR BEGIN … -->` and `<!-- CELEBRIMBOR END -->` per [ARTIFACT_FORMATS §5 AGENTS.md routing block](references/ARTIFACT_FORMATS.md). One row per generated skill/agent with its triggers.
5. **Adapters** — only for targets in `portability`, per [ARTIFACT_FORMATS §2 Generated layout and adapters](references/ARTIFACT_FORMATS.md): relative symlinks `.claude/skills/<name>`, `.claude/agents/<name>.md`, `.cursor/skills/<name>` → the `.agents/` copy (fall back to a copy if `ln -s` fails, and say so); `.agent/skills/<name>/` is always a copy (Antigravity does not follow symlinks).
6. **CLAUDE.md import** — only if `CLAUDE.md` exists and does not already import it: propose the single line `@AGENTS.md`, asked as a separate yes/no. Never create `CLAUDE.md`.

Overwrite rules (full detail in [ARTIFACT_FORMATS §7 Overwrite rules](references/ARTIFACT_FORMATS.md)):

| Situation | Action |
| --- | --- |
| Target path does not exist | Write it |
| Target path exists | Show a unified diff, ask per file; on "no", skip and record it |
| `AGENTS.md` has the markers | Replace only the content between markers; everything outside stays byte-identical |
| `AGENTS.md` exists without markers | Append the block at the end (diff shown, confirmation asked) |
| `AGENTS.md` absent | Create it containing only a one-line heading plus the block |
| Adapter path exists and is not our symlink | Skip and report — never replace a foreign file or dir |

## Phase 4 — Audit prompts

For every generated prompt, run `@prompt-engineering` with the matching use case from its [USE_CASES](../prompt-engineering/references/USE_CASES.md):

| Artifact | Classification |
| --- | --- |
| Each `.agents/skills/<name>/SKILL.md` | Use case 1 — skill prompt |
| Each `.agents/agents/<name>.md` | Use case 4 — agent base / system prompt |

1. Every Critical or Major finding blocks the report as ready; Minor findings are reported, not blocking.
2. Apply the proposed rewrite **only with user approval** — `@prompt-engineering` is read-only and Celebrimbor mediates the apply.
3. Record per artifact: clarity, anti-hallucination coverage, token delta, risk tag, blocking findings.

If `@prompt-engineering` is not available, record `prompt audit: skipped — not available` for each artifact. Never omit the line.

## Phase 5 — Validate and report

Walk [references/CHECKLIST.md](references/CHECKLIST.md) item by item; fix failures before reporting. Run its bash block from the target root: any output line is a failure, except `rm -rf` scoped to `"$OUT_DIR"`. CHECKLIST.md is the single source of truth for these checks.

Then emit the Output format block and update the report file's `status` column with what was generated or skipped.

## Constraints

- **Never** write anything in Phases 0-2 except the report file
- **Never** overwrite an existing file without showing a diff and getting confirmation; never touch `AGENTS.md` content outside the CELEBRIMBOR markers
- **Never** generate before the user names approved suggestion IDs
- **Never** generate destructive commands: `rm -rf` outside `$OUT_DIR`, `git push`, `git reset --hard`, `git clean`, `sudo`, `chmod 777`, `curl … | sh`, `DROP` / `TRUNCATE`, writes outside the skill dir
- **Never** generate an active probe without the gate: it runs only with `I_HAVE_AUTHORIZATION=1` and a local `TARGET`, and refuses (exit 2) otherwise — non-local targets point to `@code-security-review`
- **Never** print secret values — `.env*` are listed by name, generated scripts redact matches
- **Never** make generated artifacts depend on ValarMindSkills — siblings appear only as optional accelerators in `uses_existing`; every artifact runs standalone
- **Never** emit a suggestion without `evidence`
- **Never** use `tools:` in agent frontmatter (Claude Code reads it as a tool allowlist)
- **Never** commit — hand off to `@github-commit` when the user asks

## Output format

Printed after Phase 5:

```text
celebrimbor: <project name> (<target root>)
Profile:
  stack:        <languages> | <frameworks> | <package managers>
  surfaces:     <present surfaces, comma-separated>
  agent config: <AGENTS.md yes/no> | runtimes: <detected> | existing: <N skills, M agents>
  report:       <report file path>

Generated:
  .agents/skills/<name>/SKILL.md          (<N> lines, archetype: <X>)
  .agents/skills/<name>/scripts/run.sh    (<N> lines, wraps: <tools>)
  .agents/agents/<name>.md                (<N> lines, skills: <list>)
  AGENTS.md                               (block <created | replaced | appended>)

Adapters:
  .claude/skills/<name> -> ../../.agents/skills/<name>   (symlink | copy)
  CLAUDE.md: <@AGENTS.md added | declined | already present | no CLAUDE.md>

Prompt audit (@prompt-engineering):
  <artifact>  clarity <N>/8 | anti-halluc <N>/12 | Δ <tokens> | <SAFE|REVIEW|BREAKING> | blocking <N>
  (or: prompt audit: skipped — not available)

Skipped:
  <id> <name> — <not approved | extend: exists at <path> | overwrite declined>

Checklist: <N>/<M> pass
Next: review the diff, then commit (e.g., @github-commit).
```

## Example request

- "Analisa este projeto e sugere skills e agentes"
- "Forja um agente de segurança para esta API"
- "Suggest skills for this project, security only"
- "Generate project agents for Codex and Cursor"

Worked end to end (Go/Gin API, security agent + two tool-backed skills): [EXAMPLE.md](EXAMPLE.md).

## Related Skills

- `@prompt-engineering` — **paired**. Audits every generated `SKILL.md` and agent file in Phase 4
- `@code-security-review` — model for tool scripts (`scripts/`: JSONL findings, authorization gate); optional accelerator referenced by security artifacts
- `@ci-cd-generator` — when the ci-cd family fires and it is installed, point to it instead of generating a pipeline skill
- `@github-release-note` — same, for the release family
- `@mcp-builder` — out of scope pointer: MCP servers are not Celebrimbor tools

## References

- [DETECTION_CATALOG](references/DETECTION_CATALOG.md) — signal → profile field → family → default suggestion; project profile schema
- [ARTIFACT_FORMATS](references/ARTIFACT_FORMATS.md) — suggestion schema, generated layout, skill archetypes and frontmatter, agent role file, AGENTS.md block, tool script contract, overwrite rules
- [CHECKLIST](references/CHECKLIST.md) — validation of generated artifacts before reporting
- [EXAMPLE](EXAMPLE.md) — end-to-end run on a Go/Gin API

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
| Scope filter | All families in [DETECTION_CATALOG](references/DETECTION_CATALOG.md); the `review` baseline is never filtered out | `security only`, `testing and ci-cd` |
| Portability targets | `agent_config.runtimes_detected` (AGENTS.md block always) | `also cursor`, `no adapters` |
| Report file | `CELEBRIMBOR_REPORT.md` at target root | `report to docs/celebrimbor.md` |
| Generated prose language | English; triggers bilingual PT/EN | `prose in Portuguese` |

## Phase 0 — Detect (read-only)

Run from the target root. Probes only list, test, and grep; nothing is written. `.env*` files are listed by name only — their contents are never read or printed. Run this block with `bash` (e.g. `bash <<'SH' … SH`), never zsh: zsh aborts a whole line on an unmatched glob such as `requirements*.txt`, hiding real hits.

```bash
# helper: rg if present, grep fallback; prints file:line:match for evidence. Accepts files or dirs; never reads .env*
hits() { local p="$1"; shift
  if command -v rg >/dev/null; then rg -n --no-heading -g '!.env*' -e "$p" "$@" 2>/dev/null
  else grep -rHnE --exclude='.env*' --exclude-dir={node_modules,.git,vendor,target,dist,.venv} "$p" "$@" 2>/dev/null; fi; }
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
hits 'gin-gonic|gofiber|labstack/echo|go-chi|fastapi|django|flask|"next"|"react"|"vue"|"svelte"|express|fastify|hono|elysia|nestjs|actix|axum|rocket|rails|spring|laravel|symfony' $M
hits 'gorm|sqlx|pgx|prisma|drizzle|typeorm|sequelize|knex|kysely|sea-orm|sqlalchemy|alembic|[Ff]lask-[Mm]igrate|goose|diesel|migrate' $M
hits 'jsonwebtoken|golang-jwt|jose|passlib|PyJWT|next-auth|authlib|oauth|passport|devise|spring-security' $M
hits 'openai|anthropic|langchain|llamaindex|llama-index|litellm|pydantic-ai|instructor|@ai-sdk|"ai"|mcp|modelcontextprotocol' $M
hits 'opentelemetry|prometheus|prom-client|sentry|datadog|pino|structlog|micrometer|actuator|tracing-subscriber' $M
hits 'swaggo/swag|utoipa|drf-spectacular|springdoc-openapi|@nestjs/swagger|@apollo/server|graphql-yoga|strawberry|graphene' $M   # spec generators, graphql
hits 'axe-core|lighthouse|@playwright/test' $M

# 3 — surfaces: database, API contracts, frontend, infra
ls -1d migrations db/migrations db/migrate database/migrations prisma/schema.prisma drizzle.config.* sqlc.yaml alembic.ini alembic 2>/dev/null
find . $PRUNE -o \( -path '*/migrations/0*.py' -o -path '*/db/migration/V*.sql' \) -print 2>/dev/null | head -3
hits 'image: (postgres|mysql|mariadb|mongo)' docker-compose*.y*ml compose*.y*ml
ls -1 openapi.* swagger.* schema.graphql buf.yaml gqlgen.yml 2>/dev/null
find . $PRUNE -o \( -name '*.proto' -o -name 'openapi.*' -o -name 'swagger.*' -o -name '*.graphql' \) -print 2>/dev/null | head -5
hits '\.(GET|POST|PUT|DELETE)\(|@(app|router)\.(get|post)\(|Route::|FastAPI\(' . | head -5    # routes; no spec file → api-contracts
hits '"/(healthz|health|readyz|metrics)"' . | head -3                                           # health/metrics endpoints
ls -1 next.config.* vite.config.* svelte.config.* nuxt.config.* astro.config.* angular.json tailwind.config.* 2>/dev/null
ls -1d app pages src/app templates app/views resources/views 2>/dev/null; hits '@import "tailwindcss"' . | head -2
ls -1d Dockerfile* .dockerignore docker-compose* compose*.y*ml k8s helm charts kustomization.yaml Chart.yaml \
      .terraform.lock.hcl Pulumi.* cdk.json serverless.yml fly.toml 2>/dev/null
hits '^FROM .*:latest|^USER ' Dockerfile*; hits '^kind: (Deployment|StatefulSet)' . | head -3
find . $PRUNE -o -name '*.tf' -print 2>/dev/null | head -5

# 4 — CI/CD and release
ls -1 .github/workflows/*.y*ml .gitlab-ci.yml Jenkinsfile azure-pipelines.yml bitbucket-pipelines.yml .github/dependabot.yml renovate.json* 2>/dev/null; ls -1d .circleci 2>/dev/null
hits 'gitleaks|semgrep|codeql|trivy|govulncheck|cargo audit|npm audit|pip-audit|bandit|-coverprofile|--cov|coverage|llvm-cov|tarpaulin' .github/workflows/*.y*ml
hits 'uses: [^@]+@(v?[0-9][0-9.]*|main|master)\b' .github/workflows/*.y*ml | head -5          # unpinned (tag, not SHA) actions
hits '^permissions:|pull_request_target|tags:|release:|workflow_dispatch:' .github/workflows/*.y*ml | head -8
ls -1 CHANGELOG* .goreleaser.y*ml .releaserc* release-plz.toml cliff.toml release-please-config.json 2>/dev/null; ls -1d .changeset 2>/dev/null
git tag --list 'v*' 2>/dev/null | tail -3; hits '^version =|"version"|__version__ =' Cargo.toml pyproject.toml package.json

# 5 — tests
ls -1 jest.config.* vitest.config.* pytest.ini conftest.py playwright.config.* .coveragerc bunfig.toml phpunit.xml* 2>/dev/null; ls -1d src/test/java spec 2>/dev/null
hits '^\[tool\.pytest|^\[test\]' pyproject.toml bunfig.toml
find . $PRUNE -o \( -name '*_test.go' -o -name '*.test.*' -o -name '*.spec.*' -o -name 'test_*.py' -o -name 'tests.py' -o -name '*_spec.rb' -o -path '*/tests/*.rs' \) -print 2>/dev/null | head -5
hits '#\[cfg\(test\)\]' src | head -2

# 6 — docs and purpose
ls -1 README* CONTRIBUTING* SECURITY* Makefile 2>/dev/null; ls -1d docs docs/adr docs/decisions adr 2>/dev/null
wc -l README.md 2>/dev/null; head -20 README.md 2>/dev/null
hits 'make \w+|npm run \w+|go run|cargo run|uv run' README.md | head -5                       # cross-check against Makefile / package.json scripts

# 7 — secrets hygiene (NAMES ONLY — never cat/grep .env* contents)
ls -1a .env* 2>/dev/null
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then git check-ignore -q .env && echo "gitignore_covers_env: true" || echo "gitignore_covers_env: false"
else hits '^/?\.env' .gitignore || echo "gitignore_covers_env: false (not a git repo, no .env rule in .gitignore)"; fi

# 8 — agent configuration already present
ls -1d AGENTS.md CLAUDE.md .agents .claude .cursor .agent .cursorrules .mcp.json .cursor/mcp.json 2>/dev/null
ls -1 .agents/skills .claude/skills .cursor/skills .agent/skills .agents/agents .claude/agents .cursor/rules 2>/dev/null
awk '/^<!-- CELEBRIMBOR BEGIN/{b++;bl=NR}/^<!-- CELEBRIMBOR END -->/{e++;el=NR}END{print (b+e==0)?"celebrimbor_block: absent":(b==1&&e==1&&bl<el)?"celebrimbor_block: present":"celebrimbor_block: BROKEN begin="b+0" end="e+0}' AGENTS.md 2>/dev/null
hits '^@AGENTS\.md' CLAUDE.md
ls -1 "$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.cursor/skills" "${VALARMIND_INSTALL_DIR:-$HOME/.valarmindskills}/skills" 2>/dev/null | sort -u   # installed skills
find . $PRUNE -o \( -name prompts -o -name '*.prompt' -o -name '*.prompt.md' -o -name 'system_prompt*' \) -print 2>/dev/null | head -5   # prompt assets (ai-llm)
```

Map every hit to a profile field using [DETECTION_CATALOG §Catalog](references/DETECTION_CATALOG.md), which is the source of truth for signals → profile field → family → default suggestion. Absences are evidence too: record them as `<path> (absent)`. In a monorepo, run Phase 0 once per project root. Every catalog row has a probe above; a new catalog row ships with its probe.

## Phase 1 — Profile and dedupe

Assemble the project profile (schema in [DETECTION_CATALOG §Profile schema](references/DETECTION_CATALOG.md)): `project`, `stack`, `surfaces`, `agent_config`, `secrets_hygiene`. Rules:

1. **Purpose** — first heading and paragraph of `README.md`, else the manifest `description` field. Cite `file:line`. If neither exists, set `purpose: unknown` and record the gap (feeds the `docs` family).
2. **Evidence on every field** — `file:line`, or `file (absent)` for gaps. A field without evidence is left `null`, never guessed.
3. **Existing artifacts** — list every skill and agent under `.agents/`, `.claude/`, `.cursor/`, `.agent/`, plus `.cursor/rules/*.mdc` and `AGENTS.md` sections.
4. **Installed ValarMindSkills** — from probe 8 or the session's available-skills list. An installed sibling covering a family (e.g., `@code-security-review` → security, `@ci-cd-generator` → ci-cd, `@github-release-note` → release) becomes an `uses_existing` note on related suggestions, never a hard dependency.
5. **`runtimes_detected`** — from config dirs: `.claude/` → claude, `.cursor/` → cursor, `.agent/` → antigravity; `AGENTS.md`-native runtimes (Codex, Zed) are always served by `.agents/` + the block.

Dedupe: a candidate whose `name` equals an existing skill or agent name is never created a second time. Read that artifact's frontmatter. With `source: celebrimbor` (a previous run generated it), compare the evidence paths its body cites against this profile: a new framework or surface, a signal now gone, a changed version, or a skill below its current depth floor or missing the Scope boundary (§3 of ARTIFACT_FORMATS; cite the missing piece as `path (absent)`) makes an **update** row — `status: proposed`, `rationale` starting `update:`, `evidence` citing each change as `file:line` or `path (absent)`; no change keeps it `skipped` with `rationale: "update: none — <path> matches the profile"`. Without that line (user-written) it becomes an **extend** row — listed with `status: skipped` and a note naming the existing path. Nothing else suppresses a candidate: an existing artifact that overlaps in scope (judged from its `description`, cited as `path:line`) is recorded in the candidate's `uses_existing` as `<path> (overlaps: <what>)` and the row stays `proposed`.

## Phase 2 — Suggest, then stop

1. For each family in scope, walk its catalog rows against the profile and emit suggestions per the schema in [ARTIFACT_FORMATS §1 Suggestion schema](references/ARTIFACT_FORMATS.md): `id`, `type`, `name`, `family`, `priority`, `rationale`, `evidence`, `triggers`, `depends_on`, `uses_existing`, `portability`, `generates`, `status`.
2. **Baseline** — every run emits the two `review` rows, even with no matching signal or under a scope filter. Both are depth T3 ([ARTIFACT_FORMATS §3 Depth floor](references/ARTIFACT_FORMATS.md)) and carry the Scope boundary section. `code-review` is a Lifecycle skill that reviews a diff with this project's own lint, type-check and test commands plus a per-language check catalog; it hands findings with an attacker path to `code-security-review`. `code-security-review` is a Lifecycle skill with one reference per surface present (API, auth, database, AI, secrets) and its own `scripts/` (static sink sweeps and parsers for this stack); it files only findings with a security class and an attacker path, and hands correctness and domain-safety defects to `code-review`. It also runs the `scripts/` of the security-family skills generated in the same run; scanners (`gitleaks`, `govulncheck`, `trivy`, …) live in `sec-static-scan` when that row is approved, else in its own `scripts/`. It has no `depends_on` on them, so it can be approved alone. When a security agent (e.g., `security-sentinel`) is suggested, that agent `depends_on` `code-security-review` and lists it in `skills:`, so the agent row owns shared triggers ([ARTIFACT_FORMATS §5](references/ARTIFACT_FORMATS.md)). Priority: P2, except `code-security-review` is P1 when `surfaces.web_api` or `surfaces.auth` is present and CI runs no scanner. Both rows start `proposed`, never pre-approved.
3. **Priority** — P1: gap with concrete risk (e.g., web API + no secret scan in CI). P2: recurring chore the project already does by hand. P3: nice-to-have.
4. **Dependencies** — agents depend on the skills they orchestrate; skills depend on their tool scripts. Record them in `depends_on`.
5. **Names** — kebab-case, ≤64 chars. Dedupe runs on the default name first: a match in `existing_skills` / `existing_agents` makes an `update` or `extend` row (dedupe above). Otherwise, when the name matches an installed skill (probe 8), prefix it with `project.name` in kebab-case (lowercase, each run of other characters → `-`, e.g., `@acme/orders-api` → `acme-orders-api-code-review`), truncated to 64. In Claude Code a personal skill shadows a project skill of the same name.
6. Write the report file: profile summary + one suggestions table (`id | type | name | family | priority | depth | evidence | depends_on | generates | status`), followed by one YAML record per row with all schema fields ([ARTIFACT_FORMATS §1 Suggestion schema](references/ARTIFACT_FORMATS.md)); all rows `status: proposed` except `extend` rows and up-to-date `update` rows. If the report file already exists, show a diff and write only on an explicit yes; on no, print the report in chat instead.

**Stop here.** Print the suggestions table and ask for an explicit approval list (e.g., `S1,S2,S3`, `all P1`, `none`). Do not generate anything until the user answers. Silence, "looks good", or approval of the report file is not approval of suggestions — ask again for IDs.

If an approved row `depends_on` an unapproved row, ask once: add the dependency or drop the dependent row. Mark the final set `approved` in the report.

## Phase 3 — Generate (approved only)

Generate in dependency order, so every reference resolves when written:

1. **Tools** — `.agents/skills/<name>/scripts/run.sh` (+ helpers) per the tool contract in [ARTIFACT_FORMATS §6 Tool script contract](references/ARTIFACT_FORMATS.md): `run.sh` plus one check script per check group (`.sh` sweeps and scanner wrappers, stdlib `.py` parsers) and `lib/common.sh`, skip-with-note when a binary is absent, `set -euo pipefail`, findings to `$OUT_DIR/findings.jsonl`, secret values redacted, exit `0` clean / `1` config / `2` refused, `out/` gitignored. Scripts that send traffic also carry the local-target gate per §6: `I_HAVE_AUTHORIZATION=1` and an exact-host match on `TARGET` (`localhost`, `127.0.0.1`, `[::1]`, `*.localhost`, `*.test` after stripping scheme, path, userinfo, and port).
2. **Skills** — `.agents/skills/<name>/SKILL.md`: frontmatter `name` (== dir), `description` (third person, ends with triggers), `source: celebrimbor`; archetype per the 3-row table in [ARTIFACT_FORMATS §3 Generated SKILL.md format](references/ARTIFACT_FORMATS.md) (Procedural for tool wrappers, Lifecycle for workflows, Reference for docs/contracts). `scripts/` inside the skill is the tool convention. Knobs go in `Inputs` with defaults; non-negotiables go in `Constraints` with `Never`. Meet the row's depth floor (§3 Depth floor): `references/` check catalogs whose rows each carry a detection command, a project anchor (`file:line`) and a fix in this project's idiom, plus `EXAMPLE.md` for T2/T3. When an installed sibling covers the family (probe 8), read its `references/` and `scripts/` first and adapt the rows that match the profile — a standalone copy, never a link. A check with no anchor in this project is dropped, not padded in.
3. **Agents** — `.agents/agents/<name>.md` per [ARTIFACT_FORMATS §4 Agent role file](references/ARTIFACT_FORMATS.md): frontmatter `name`, `description`, `skills`, `scripts`, `source: celebrimbor`; body sections Purpose, Workflow, Boundaries, Output.
4. **AGENTS.md block** — before writing, if `AGENTS.md` exists, first require the Phase 0 probe to say `celebrimbor_block: present` or `absent` — on `BROKEN` (zero or several BEGIN/END lines, or END before BEGIN) stop and ask the user to repair `AGENTS.md` by hand; never auto-repair, never write (the sed range below would swallow everything to EOF and the hash check would still pass). Then compute `sed '/^<!-- CELEBRIMBOR BEGIN/,/^<!-- CELEBRIMBOR END -->/d' AGENTS.md | awk 'NF{for(;n;n--)print "";print;next}{n++}' | shasum` (trailing blank lines dropped, so an appended block's separator does not change it) and write it to the report file as `PRE_HASH: <value>`; Phase 5 exports it as `PRE_HASH` before running the CHECKLIST block (empty when `AGENTS.md` was absent). Then write the routing table between `<!-- CELEBRIMBOR BEGIN … -->` and `<!-- CELEBRIMBOR END -->` per [ARTIFACT_FORMATS §5 AGENTS.md routing block](references/ARTIFACT_FORMATS.md). One row per generated skill/agent with its triggers.
5. **Adapters** — only for targets in `portability`, per [ARTIFACT_FORMATS §2 Generated layout and adapters](references/ARTIFACT_FORMATS.md): relative symlinks `.claude/skills/<name>`, `.claude/agents/<name>.md`, `.cursor/skills/<name>` → the `.agents/` copy (fall back to a copy if `ln -s` fails, and say so); `.agent/skills/<name>/` is always a copy (Antigravity does not follow symlinks).
6. **CLAUDE.md import** — only if `CLAUDE.md` exists and does not already import it: propose the single line `@AGENTS.md`, asked as a separate yes/no. Never create `CLAUDE.md`.

Overwrite rules (full detail in [ARTIFACT_FORMATS §7 Overwrite rules](references/ARTIFACT_FORMATS.md)):

| Situation | Action |
| --- | --- |
| Target path does not exist | Write it |
| Target path exists | Show a unified diff, ask per file; on "no", skip and record it |
| `AGENTS.md` has the markers | Replace only the content between markers; everything outside stays byte-identical |
| `AGENTS.md` markers malformed (count ≠ 1 each, or END before BEGIN) | Stop; ask the user to repair by hand — never auto-repair |
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

Walk [references/CHECKLIST.md](references/CHECKLIST.md) item by item over this run's artifacts only: export `PRE_HASH`, `GENERATED` (the `generates` paths of all `approved` rows) and `DEPTH` (`<name>:<tier>` per approved skill, e.g. `code-review:T3 sec-static-scan:T2`) from the report, then run its bash block from the target root. Any output line is a failure, except `rm -rf` / `shutil.rmtree(` scoped to `"$OUT_DIR"` and `skip:` lines (reported as skipped with their reason). Fix failures in generated files before reporting; a pre-existing user file is never edited — if a failure lives in one, report it as skipped with the path. CHECKLIST.md is the single source of truth for these checks.

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
- **Never** generate a skill below its depth floor, and never meet it with generic text: every check row and example cites this project's paths
- **Never** drop the `review` baseline rows (`code-review`, `code-security-review`) from a run's suggestions
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
  .agents/skills/<name>/                  (<tier> | SKILL.md <N> lines, archetype: <X> | refs: <files> | scripts: <files> | EXAMPLE.md yes/no)
  .agents/skills/<name>/scripts/run.sh    (<N> lines, runs: <check scripts>, wraps: <tools>)
  .agents/agents/<name>.md                (<N> lines, skills: <list>)
  AGENTS.md                               (block <created | replaced | appended>)

Adapters:
  .claude/skills/<name> -> ../../.agents/skills/<name>   (symlink | copy)
  CLAUDE.md: <@AGENTS.md added | declined | already present | no CLAUDE.md>

Prompt audit (@prompt-engineering):
  <artifact>  clarity <N>/8 | anti-halluc <N>/12 | Δ <tokens> | <SAFE|REVIEW|BREAKING> | blocking <N>
  (or: prompt audit: skipped — not available)

Skipped:
  <id> <name> — <not approved | extend: exists at <path> | update: none — <path> matches the profile | overwrite declined>

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

> Reference companion for the [celebrimbor](../SKILL.md) skill.

# Detection Catalog

Phase 0 runs these globs/greps read-only from the target root; Phase 1 writes each hit (or miss) into the profile below, then Phase 2 maps profile fields to the default suggestions. This catalog is the source of truth for Phase 0.
Evidence rule: every non-null profile field carries `evidence: file:line`, or `file (absent)` for a gap. Gaps are evidence: a missing `.github/workflows/` justifies a CI suggestion as much as a present one justifies a security one.

## Profile schema

```yaml
project:
  root: /abs/path
  name: <dir or package name>
  purpose: "<one line>"                 # evidence: README.md:1-12 | package.json:3
stack:
  languages: [go]                       # evidence: go.mod:1
  runtimes: [node@20]                   # .nvmrc, .tool-versions, go directive
  package_managers: [pnpm]              # lockfile
  frameworks: [{name: gin, version: v1.10, evidence: go.mod:14}]
  libs_of_interest: [{name: gorm, role: orm, evidence: go.mod:22}]
surfaces:                               # orthogonal overlays, each {present, detail, evidence}
  web_api:       {present: true, kind: rest|graphql|grpc, spec: openapi.yaml|null}
  frontend:      {present: false}
  database:      {present: true, engine: postgres, migrations: goose, dir: db/migrations}
  auth:          {present: true, kind: jwt|oauth|session}
  ai_llm:        {present: false}
  ci_cd:         {present: true, platform: github-actions, workflows: [ci.yml]}
  infra:         {present: true, tools: [docker, terraform]}
  observability: {present: false}
  tests:         {framework: go test, dirs: [...], coverage_gate: false}
  docs:          {readme: true, adr: false, contributing: false, openapi: path|null}
  release:       {changelog: false, tags_semver: true, release_workflow: false}
agent_config:
  agents_md: AGENTS.md|null
  claude_md: CLAUDE.md|null             # and whether it already imports @AGENTS.md
  cursor_rules: [.cursor/rules/*.mdc]
  existing_skills: [{name, path}]       # .agents/skills, .claude/skills, .cursor/skills, .agent/skills — `name` is the only dedupe key
  existing_agents: [{name, path}]       # .agents/agents, .claude/agents
  celebrimbor_block: present|absent|BROKEN   # marker state in AGENTS.md; BROKEN stops Phase 3
  runtimes_detected: [codex, cursor]    # from dirs above; drives adapter defaults
secrets_hygiene:                        # names only, never values
  env_examples: [.env.example]
  gitignore_covers_env: true
```

## Catalog

Manifests: `go.mod`, `Cargo.toml`, `package.json`, `pyproject.toml requirements*.txt`, `pom.xml build.gradle*`, `Gemfile`, `composer.json`. `CI` = `.github/workflows/*.y*ml`. `Active target? yes` = the generated tool needs a running local `TARGET` (see ARTIFACT_FORMATS.md, tool script contract).

### review (every run)
Baseline: both rows are emitted on every run, whatever the signals or the scope filter. `code-review` evidence comes from probes 1, 2, 4 and 5 (manifests, frameworks, CI, test config); `code-security-review` evidence from probes 2, 3 and 7 (auth libs, routes and surfaces, secrets hygiene).

| Signal (glob / grep) | Profile field | Default suggestion (type:name) | Active target? |
| --- | --- | --- | --- |
| always — manifests, lint/type-check/test config and CI steps set the review commands | `stack`, `surfaces.tests`, `surfaces.ci_cd` | `skill:code-review` | no |
| always — `surfaces.web_api`, `surfaces.auth`, `surfaces.database`, `surfaces.ai_llm`, `secrets_hygiene` set the checks | `surfaces`, `secrets_hygiene` | `skill:code-security-review` | no |

### security
| Signal (glob / grep) | Profile field | Default suggestion (type:name) | Active target? |
| --- | --- | --- | --- |
| `go.mod` ~ `gin-gonic/gin\|gofiber/fiber\|labstack/echo\|go-chi/chi`; `Cargo.toml` ~ `axum\|actix-web\|rocket`; `pom.xml build.gradle*` ~ `spring-boot` | `stack.frameworks`, `surfaces.web_api` | `agent:security-sentinel` | no |
| `package.json` ~ `"(express\|fastify\|hono\|elysia\|next\|@nestjs/core)"`; Python manifests ~ `\b(fastapi\|django\|flask)\b`; `Gemfile` ~ `rails`; `composer.json` ~ `laravel/framework\|symfony/` | `stack.frameworks`, `surfaces.web_api` | `agent:security-sentinel` | no |
| manifests ~ `golang-jwt\|jsonwebtoken\|jose\|passlib\|PyJWT\|next-auth\|authlib\|devise\|spring-security` | `surfaces.auth` | `skill:sec-pentest-local` | yes |
| `.env*` (minus `*.example`) present; `.gitignore` !~ `^\.env` | `secrets_hygiene` | `skill:sec-static-scan` | no |
| CI !~ `gitleaks\|semgrep\|codeql\|govulncheck\|cargo audit\|pip-audit\|npm audit\|trivy` | `surfaces.ci_cd` | `skill:sec-static-scan` | no |

### testing
| Signal (glob / grep) | Profile field | Default suggestion (type:name) | Active target? |
| --- | --- | --- | --- |
| `**/*_test.go`; `tests/*.rs`; `src/**/*.rs` ~ `#\[cfg\(test\)\]` | `surfaces.tests.framework: go test\|cargo test` | `skill:test-runner` | no |
| `jest.config.*\|vitest.config.*\|playwright.config.*`; `bunfig.toml` ~ `\[test\]`; `**/*.{test,spec}.{ts,tsx,js}` | `surfaces.tests` | `skill:test-runner` | no |
| `pytest.ini\|conftest.py`; `pyproject.toml` ~ `\[tool\.pytest`; Django `**/tests.py` | `surfaces.tests` | `skill:test-runner` | no |
| `src/test/java/**`; `spec/**/*_spec.rb`; `phpunit.xml*` | `surfaces.tests` | `skill:test-runner` | no |
| CI !~ `-coverprofile\|--cov\|--coverage\|llvm-cov\|tarpaulin\|--cov-fail-under` | `surfaces.tests.coverage_gate: false` | `skill:test-runner` | no |

### ci-cd
| Signal (glob / grep) | Profile field | Default suggestion (type:name) | Active target? |
| --- | --- | --- | --- |
| `.github/workflows/` absent | `surfaces.ci_cd.present: false` | `skill:ci-audit` | no |
| CI ~ `uses: [^@]+@(v?[0-9][0-9.]*\|main\|master)\b` (tag, not SHA) | `surfaces.ci_cd.workflows` | `skill:ci-audit` | no |
| CI !~ `^permissions:`; CI ~ `pull_request_target` | `surfaces.ci_cd.workflows` | `skill:ci-audit` | no |
| `.gitlab-ci.yml\|.circleci/config.yml\|Jenkinsfile\|azure-pipelines.yml\|bitbucket-pipelines.yml` | `surfaces.ci_cd.platform` | `skill:ci-audit` | no |
| `.github/dependabot.yml\|renovate.json*` absent | `surfaces.ci_cd` | `skill:ci-audit` | no |

### database
| Signal (glob / grep) | Profile field | Default suggestion (type:name) | Active target? |
| --- | --- | --- | --- |
| `go.mod` ~ `pressly/goose\|golang-migrate\|gorm.io\|jackc/pgx`; `sqlc.yaml`; `Cargo.toml` ~ `sqlx\|diesel\|sea-orm`; `migrations/*.sql` | `surfaces.database`, `stack.libs_of_interest` | `skill:db-migration-check` | no |
| `prisma/schema.prisma\|drizzle.config.*`; `package.json` ~ `typeorm\|knex\|sequelize\|kysely` | `surfaces.database.migrations` | `skill:db-migration-check` | no |
| `alembic.ini\|alembic/versions/*.py`; Django `*/migrations/0*.py`; `flask_migrate` | `surfaces.database.migrations` | `skill:db-migration-check` | no |
| `db/migrate/*.rb`; `**/db/migration/V*.sql` (Flyway); `database/migrations/*.php` | `surfaces.database.migrations` | `skill:db-migration-check` | no |
| `docker-compose*.y*ml\|compose*.y*ml` ~ `image: (postgres\|mysql\|mariadb\|mongo)` | `surfaces.database.engine` | `skill:db-migration-check` | no |

### api-contracts
| Signal (glob / grep) | Profile field | Default suggestion (type:name) | Active target? |
| --- | --- | --- | --- |
| `**/openapi.{yaml,yml,json}\|**/swagger.{yaml,json}` | `surfaces.web_api.spec` | `skill:api-contract-check` | no |
| `**/*.proto`; `buf.yaml` | `surfaces.web_api.kind: grpc` | `skill:api-contract-check` | no |
| `**/*.graphql\|gqlgen.yml`; manifests ~ `@apollo/server\|graphql-yoga\|strawberry\|graphene` | `surfaces.web_api.kind: graphql` | `skill:api-contract-check` | no |
| `swaggo/swag\|utoipa\|drf-spectacular\|springdoc-openapi\|@nestjs/swagger`; `FastAPI\(` | `surfaces.web_api.spec` (generated) | `skill:api-contract-check` | no |
| routes ~ `\.(GET\|POST\|PUT\|DELETE)\(\|@(app\|router)\.(get\|post)\|Route::` with no spec file | `surfaces.web_api.spec: null` | `skill:api-contract-check` | no |

### frontend
| Signal (glob / grep) | Profile field | Default suggestion (type:name) | Active target? |
| --- | --- | --- | --- |
| `next.config.*`; `app/**/page.tsx\|pages/**/*.tsx` | `surfaces.frontend`, `stack.frameworks` | `skill:ui-review` | no |
| `vite.config.*\|svelte.config.*\|nuxt.config.*\|astro.config.*\|angular.json` | `surfaces.frontend`, `stack.frameworks` | `skill:ui-review` | no |
| `tailwind.config.*`; `**/*.css` ~ `@import "tailwindcss"` | `stack.libs_of_interest` | `skill:ui-review` | no |
| `templates/**/*.html` (Django/Flask); `app/views/**/*.erb`; `resources/views/**/*.blade.php` | `surfaces.frontend` (server-rendered) | `skill:ui-review` | no |
| `package.json` ~ `axe-core\|@axe-core/\|lighthouse\|@playwright/test` | `stack.libs_of_interest` | `skill:ui-review` (+ tool) | yes |

### infra
| Signal (glob / grep) | Profile field | Default suggestion (type:name) | Active target? |
| --- | --- | --- | --- |
| `Dockerfile*`; `docker-compose*.y*ml\|compose*.y*ml`; `.dockerignore` absent | `surfaces.infra.tools: docker\|compose` | `skill:infra-lint` | no |
| `Dockerfile*` ~ `^FROM .*:latest` or !~ `^USER ` | `surfaces.infra` | `skill:infra-lint` | no |
| `**/*.tf`; `.terraform.lock.hcl` | `surfaces.infra.tools: terraform` | `skill:infra-lint` | no |
| `k8s/**\|kustomization.yaml\|Chart.yaml`; `**/*.yaml` ~ `^kind: (Deployment\|StatefulSet)` | `surfaces.infra.tools: kubernetes\|helm` | `skill:infra-lint` | no |
| `Pulumi.yaml\|cdk.json\|serverless.yml\|fly.toml` | `surfaces.infra.tools` | `skill:infra-lint` | no |

### docs
| Signal (glob / grep) | Profile field | Default suggestion (type:name) | Active target? |
| --- | --- | --- | --- |
| `README.md` absent or `wc -l` < 20 | `surfaces.docs.readme` | `skill:docs-sync` | no |
| `CONTRIBUTING.md` absent | `surfaces.docs.contributing: false` | `skill:docs-sync` | no |
| `docs/adr/*.md\|docs/decisions/*.md\|adr/*.md` absent | `surfaces.docs.adr: false` | `skill:docs-sync` | no |
| `surfaces.web_api.present` and no spec file | `surfaces.docs.openapi: null` | `skill:docs-sync` | no |
| `README.md` ~ `make \w+\|npm run \w+\|go run\|cargo run\|uv run` not matching `Makefile`/`package.json` scripts | `surfaces.docs.readme` | `skill:docs-sync` | no |

### release
| Signal (glob / grep) | Profile field | Default suggestion (type:name) | Active target? |
| --- | --- | --- | --- |
| `CHANGELOG.md` absent | `surfaces.release.changelog: false` | `skill:release-prep` | no |
| `git tag -l 'v[0-9]*.[0-9]*.[0-9]*'` | `surfaces.release.tags_semver` | `skill:release-prep` | no |
| CI ~ `tags:\|release:\|workflow_dispatch:` in a release job | `surfaces.release.release_workflow` | `skill:release-prep` | no |
| `.goreleaser.y*ml\|release-plz.toml\|cliff.toml\|.releaserc*\|release-please-config.json\|.changeset/` | `surfaces.release.release_workflow` | `skill:release-prep` | no |
| `package.json` ~ `"version"`; `Cargo.toml\|pyproject.toml` ~ `^version =`; `__version__ =` | `surfaces.release` | `skill:release-prep` | no |

### observability
| Signal (glob / grep) | Profile field | Default suggestion (type:name) | Active target? |
| --- | --- | --- | --- |
| `go.mod` ~ `go.opentelemetry.io\|prometheus/client_golang\|getsentry/sentry-go`; `Cargo.toml` ~ `opentelemetry\|tracing-subscriber` | `surfaces.observability` | `skill:observability-check` | no |
| `package.json` ~ `@opentelemetry/\|prom-client\|@sentry/\|pino` | `surfaces.observability` | `skill:observability-check` | no |
| Python manifests ~ `opentelemetry-\|prometheus[-_]client\|sentry-sdk\|structlog` | `surfaces.observability` | `skill:observability-check` | no |
| `pom.xml build.gradle*` ~ `micrometer\|spring-boot-starter-actuator`; `Gemfile` ~ `sentry-ruby\|opentelemetry` | `surfaces.observability` | `skill:observability-check` | no |
| routes ~ `/healthz\|/health\|/readyz\|/metrics` | `surfaces.observability.detail` | `skill:observability-check` (+ tool) | yes |

### ai-llm
| Signal (glob / grep) | Profile field | Default suggestion (type:name) | Active target? |
| --- | --- | --- | --- |
| `package.json` ~ `"(openai\|@anthropic-ai/sdk\|ai\|@ai-sdk/[a-z-]+\|langchain\|@langchain/[a-z-]+\|llamaindex)"` | `surfaces.ai_llm` | `skill:prompt-asset-review` | no |
| Python manifests ~ `\b(openai\|anthropic\|langchain\|llama-index\|litellm\|pydantic-ai\|instructor)\b` | `surfaces.ai_llm` | `skill:prompt-asset-review` | no |
| `go.mod` ~ `go-openai\|anthropic-sdk-go\|langchaingo`; `Cargo.toml` ~ `async-openai\|rig-core` | `surfaces.ai_llm` | `skill:prompt-asset-review` | no |
| `.mcp.json\|.cursor/mcp.json`; manifests ~ `modelcontextprotocol` | `surfaces.ai_llm.detail: mcp` | `skill:prompt-asset-review` | no |
| `**/prompts/**\|**/*.prompt\|**/*.prompt.md\|**/system_prompt*` | `surfaces.ai_llm.detail: prompts` | `skill:prompt-asset-review` | no |

Dedupe: before emitting a row's suggestion, apply the name-match dedupe rule in [ARTIFACT_FORMATS.md](ARTIFACT_FORMATS.md) against `agent_config.existing_*`; overlap under another name is a `uses_existing` note, not a skip.
Ceiling: one row per signal, defaults only; when the catalog grows past ~120 rows, split it into one file per family.

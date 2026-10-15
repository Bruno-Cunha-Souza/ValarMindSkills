# Example — Go/Gin API

End-to-end run of `@celebrimbor` on `orders-api`: Go/Gin REST API, Postgres with goose migrations, `.env.example`, a Dockerfile, GitHub Actions with no scanners, no `AGENTS.md`, a `.claude/` dir and a `CLAUDE.md`. Excerpts are abridged with `# …`.

> /celebrimbor analisa esse projeto e sugere skills e agentes

## Phase 0 — Detect (abridged probe output)

```text
# 1  go.mod  go.sum  go.mod:3:go 1.23
# 2  go.mod:6: github.com/gin-gonic/gin v1.10.0   go.mod:8: github.com/golang-jwt/jwt/v5 v5.2.1
#    go.mod:9: github.com/jackc/pgx/v5 v5.7.1     go.mod:10: github.com/pressly/goose/v3 v3.22.1
# 3  db/migrations  Dockerfile                      (no openapi.*, no compose, no *.tf)
# 4  .github/workflows/ci.yml (no scanner hits)   .github/workflows/ci.yml:12: - uses: actions/checkout@v4
# 6  README.md  34 README.md (no CONTRIBUTING*, SECURITY*, docs/)   # 7  .env.example  gitignore_covers_env: true
# 8  CLAUDE.md  .claude (no AGENTS.md, skills/agents dirs, marker)   installed: ci-cd-generator code-security-review prompt-engineering
```

## Phase 1 — Profile (abridged)

```yaml
project: {root: /home/dev/orders-api, name: orders-api, purpose: "REST API for order intake and fulfilment"}  # go.mod:1, README.md:1-3
stack:
  languages: [go]                                    # go.mod:1
  frameworks: [{name: gin, version: v1.10.0, evidence: go.mod:6}]
  libs_of_interest: [{name: golang-jwt, role: auth, evidence: go.mod:8}, {name: pgx, role: driver, evidence: go.mod:9}, {name: goose, role: migrations, evidence: go.mod:10}]
surfaces:
  web_api:  {present: true, kind: rest, spec: null}  # internal/http/router.go:21, openapi.* (absent)
  database: {present: true, engine: postgres, migrations: goose, dir: db/migrations}  # go.mod:10
  auth:     {present: true, kind: jwt}               # internal/http/middleware/auth.go:14
  ci_cd:    {present: true, platform: github-actions, workflows: [ci.yml]}  # no scanners in ci.yml
  infra:    {present: true, tools: [docker]}         # Dockerfile:1, no USER line
  docs:     {readme: true, adr: false, contributing: false, openapi: null}  # CONTRIBUTING.md (absent)
agent_config:
  agents_md: null                                    # AGENTS.md (absent)
  claude_md: CLAUDE.md                               # no @AGENTS.md import
  existing_skills: []                                # .claude/ holds settings.json only; existing_agents: []
  runtimes_detected: [claude]                        # .claude/
secrets_hygiene: {env_examples: [.env.example], gitignore_covers_env: true}  # .gitignore:4
```

## Phase 2 — Suggestions (written to `CELEBRIMBOR_REPORT.md`)

| id | type | name | family | priority | evidence | depends_on | generates | status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| S1 | agent | security-sentinel | security | P1 | go.mod:6, go.mod:8 | S2, S3 | `.agents/agents/security-sentinel.md` | proposed |
| S2 | skill | sec-static-scan | security | P1 | ci.yml (no gitleaks/govulncheck/trivy), Dockerfile:1 | — | `.agents/skills/sec-static-scan/{SKILL.md,scripts/run.sh}` | proposed |
| S3 | skill | sec-pentest-local | security | P2 | go.mod:8, internal/http/middleware/auth.go:14 | — | `.agents/skills/sec-pentest-local/{SKILL.md,scripts/run.sh}` | proposed |
| S4 | skill | db-migration-check | database | P2 | go.mod:10, db/migrations | — | `.agents/skills/db-migration-check/SKILL.md` | proposed |
| S5 | skill | docs-sync | docs | P3 | CONTRIBUTING.md (absent), openapi.* (absent) | — | `.agents/skills/docs-sync/SKILL.md` | proposed |

```yaml
- {id: S2, type: skill, name: sec-static-scan, family: security, priority: P1, status: proposed, rationale: "Gin API with JWT auth, but CI runs no secret, dependency or container scan.",
   evidence: [".github/workflows/ci.yml (no gitleaks/govulncheck/trivy)", "go.mod:6", "Dockerfile:1"],
   triggers: ["varrer segredos", "scan secrets", "dependency audit", "/sec-static-scan"], depends_on: [],
   uses_existing: ["@code-security-review (optional accelerator)"], portability: [agents-md, claude-adapter],
   generates: [.agents/skills/sec-static-scan/SKILL.md, .agents/skills/sec-static-scan/scripts/run.sh]}
```

Each skill bundles its own `scripts/` tool, so `type` stays `skill`. Infra rows fold into S2 (`trivy` misconfig scans the Dockerfile); ci-cd and coverage rows point to the installed `@ci-cd-generator` instead of a new skill.

**Stop.** "Which suggestion IDs should I generate? (e.g., `S1,S2,S3`, `all P1`, `none`)"

> S1, S2 e S3

## Phase 3 — Generate (S1 plus its dependencies S2, S3; S4 and S5 skipped — not approved)

```text
orders-api/
├── AGENTS.md                                  # new: heading + CELEBRIMBOR block
├── .agents/skills/{sec-static-scan,sec-pentest-local}/{SKILL.md,scripts/run.sh}
├── .agents/agents/security-sentinel.md
├── .claude/skills/{sec-static-scan,sec-pentest-local} -> ../../.agents/skills/<name>
└── .claude/agents/security-sentinel.md -> ../../.agents/agents/security-sentinel.md
```

### `.agents/skills/sec-static-scan/SKILL.md` (Procedural)

```markdown
---
name: sec-static-scan
description: "Scans this project for committed secrets and vulnerable dependencies with gitleaks, govulncheck and trivy, writing findings to scripts/out/findings.jsonl. Use for pre-merge or periodic hygiene, not for live-target testing. Triggers: 'varrer segredos', 'scan secrets', 'dependency audit', '/sec-static-scan'."
source: celebrimbor
---
## Goal            — one JSONL of secret, Go module (go.mod) and Dockerfile findings
## Inputs          — PROJECT_ROOT (default repo root) · OUT_DIR (default scripts/out) · severity floor (default low)
## Procedure       — Step 1 run `scripts/run.sh` · Step 2 count severities with jq · Step 3 table, critical/high first
## Constraints     — Never print a secret value · Never write outside scripts/out · Never fix without approval
## Output format   — summary table + path to findings.jsonl; "skip: <tool>" lines listed as gaps
```

### `.agents/skills/sec-static-scan/scripts/run.sh`

```bash
#!/usr/bin/env bash
# sec-static-scan — secrets, Go module and container scan. Reads: PROJECT_ROOT (default $PWD), OUT_DIR. Writes: out/findings.jsonl
set -euo pipefail
OUT_DIR="${OUT_DIR:-$(dirname "$0")/out}"; mkdir -p "$OUT_DIR"; printf '*\n' > "$OUT_DIR/.gitignore"
FINDINGS="$OUT_DIR/findings.jsonl"; : > "$FINDINGS"; ROOT="${PROJECT_ROOT:-$PWD}"
[ -d "$ROOT" ] || { echo "config: PROJECT_ROOT not found: $ROOT" >&2; exit 1; }
command -v jq >/dev/null || { echo "config: jq is required" >&2; exit 1; }
redact() { local s="$1"; if [ ${#s} -le 8 ]; then printf '****'; else printf '%s…%s' "${s:0:4}" "${s: -4}"; fi; }
emit() { # id severity evidence impact remediation
  jq -nc --arg id "$1" --arg severity "$2" --arg evidence "$3" --arg impact "$4" \
    --arg remediation "$5" --arg timestamp "$(date -u +%FT%TZ)" '$ARGS.named' >> "$FINDINGS"; }

if command -v gitleaks >/dev/null; then
  r="$OUT_DIR/.gitleaks.json"
  if ! gitleaks detect --source "$ROOT" --no-banner --report-format json --report-path "$r" >/dev/null 2>&1; then
    jq -r '.[] | "\(.File):\(.StartLine)\t\(.Secret)"' "$r" | while IFS=$'\t' read -r loc sec; do
      emit SEC-GL-001 high "$loc $(redact "$sec")" "Committed secret." "Rotate it, then purge it from history."
    done
  fi
  rm -f "$r"   # raw report holds unredacted values
else echo "skip: gitleaks not installed" >&2; fi

if [ -f "$ROOT/go.mod" ] && command -v govulncheck >/dev/null; then
  (cd "$ROOT" && govulncheck ./...) > "$OUT_DIR/govulncheck.txt" 2>&1 \
    || emit SEC-GV-001 high "go.mod (see out/govulncheck.txt)" "Reachable vulnerable dependency." "Upgrade the modules govulncheck names."
else echo "skip: govulncheck not installed or no go.mod" >&2; fi

if command -v trivy >/dev/null; then
  r="$OUT_DIR/.trivy.json"
  trivy fs --quiet --scanners vuln,misconfig --format json --output "$r" "$ROOT"
  jq -r '.Results[]? | .Target as $t
    | (.Vulnerabilities[]? | [$t, .Severity, "\(.PkgName) \(.InstalledVersion) \(.VulnerabilityID)", "Upgrade to \(.FixedVersion // "a fixed release")."]),
      (.Misconfigurations[]? | ["\($t):\(.CauseMetadata.StartLine // 1)", .Severity, "\(.ID) \(.Title)", .Resolution])
    | @tsv' "$r" | while IFS=$'\t' read -r loc sev what fix; do
    sev="$(printf '%s' "$sev" | tr '[:upper:]' '[:lower:]')"; [ "$sev" = unknown ] && sev=info
    emit SEC-TV-001 "$sev" "$loc $what" "Known vulnerable package or Dockerfile misconfiguration." "$fix"
  done
  rm -f "$r"
else echo "skip: trivy not installed" >&2; fi
exit 0
```

### `.agents/skills/sec-pentest-local/scripts/run.sh` (header and gate)

```bash
#!/usr/bin/env bash
# sec-pentest-local — authorized probes against a LOCAL dev server (ZAP baseline + JWT checks on /api/v1). Reads: TARGET (required), I_HAVE_AUTHORIZATION (must be 1), OUT_DIR. Writes: out/findings.jsonl
set -euo pipefail
OUT_DIR="${OUT_DIR:-$(dirname "$0")/out}"; mkdir -p "$OUT_DIR"; printf '*\n' > "$OUT_DIR/.gitignore"
[ -n "${TARGET:-}" ] || { echo "config: TARGET is required" >&2; exit 1; }
[ "${I_HAVE_AUTHORIZATION:-}" = "1" ] || { echo "refusing: set I_HAVE_AUTHORIZATION=1 to confirm you own TARGET" >&2; exit 2; }
host="${TARGET#*://}"; host="${host%%[/?#]*}"; host="${host##*@}"
case "$host" in '[::1]'|'[::1]:'*) host='[::1]' ;; *) host="${host%%:*}" ;; esac
case "$host" in localhost|127.0.0.1|'[::1]'|*.localhost|*.test) ;; *) echo "refusing: TARGET is not local" >&2; exit 2 ;; esac
# … redact()/emit() as in sec-static-scan; zap-baseline.py -t "$TARGET"; JWT alg=none/expired/missing-token probes
exit 0
```

`TARGET=http://localhost.evil.com` and `TARGET=https://staging.orders.example` both exit `2` with `refusing: TARGET is not local`; the skill points staging and production testing to `@code-security-review`.

### `.agents/agents/security-sentinel.md`

```markdown
---
name: security-sentinel
description: "Runs the project's full security verification — static scans, secret scan, dependency audit, authorized local pentest — and files a severity-ranked report. Use when: 'security check', 'verificar segurança', 'pentest local'."
skills: [sec-static-scan, sec-pentest-local]
scripts: [.agents/skills/sec-static-scan/scripts/run.sh, .agents/skills/sec-pentest-local/scripts/run.sh]
---
# Purpose
Single entry point for security checks on orders-api (Gin + JWT + Postgres). Reports; never fixes.
# Workflow
1. Run sec-static-scan. 2. If a dev server runs on localhost and the user confirms ownership, run sec-pentest-local
with I_HAVE_AUTHORIZATION=1; otherwise stop after step 1 and say why. 3. Merge both findings.jsonl, dedupe, rank critical → info.
# Boundaries
Never target a non-local host · Never print secret values · Never edit code without approval.
# Output
One summary table (id | severity | evidence | remediation) + paths to both findings.jsonl files.
```

### `AGENTS.md` (block)

`AGENTS.md` was absent, so the report records `PRE_HASH: (none — AGENTS.md absent)` before writing it.

```markdown
<!-- CELEBRIMBOR BEGIN — generated; re-running celebrimbor replaces this block -->
## Project skills and agents

Skills: `.agents/skills/<name>/SKILL.md`. Agents: `.agents/agents/<name>.md` — read the role file, follow its Workflow and Boundaries, load the skills it lists.

| When the task matches | Load | Kind |
| --- | --- | --- |
| 'security check', 'verificar segurança', 'pentest local' | `.agents/agents/security-sentinel.md` | agent |
| 'varrer segredos', 'scan secrets', 'dependency audit' | `.agents/skills/sec-static-scan/SKILL.md` | skill |
| 'pentest local', 'testar JWT', 'local pentest' | `.agents/skills/sec-pentest-local/SKILL.md` | skill |
<!-- CELEBRIMBOR END -->
```

### Adapters and CLAUDE.md

```bash
mkdir -p .claude/skills .claude/agents && ln -s ../../.agents/skills/sec-static-scan .claude/skills/sec-static-scan
ln -s ../../.agents/skills/sec-pentest-local .claude/skills/sec-pentest-local
ln -s ../../.agents/agents/security-sentinel.md .claude/agents/security-sentinel.md
```

Asked separately: "`CLAUDE.md` exists without `@AGENTS.md`. Append the single line `@AGENTS.md`? (yes/no)" → `sim` → line appended.

## Phase 4 — Prompt audit

Use case 1 for both SKILL.md files, use case 4 for the agent; metrics are in the final report. One Major on the agent (no stop condition without a local server) was fixed by a rewrite applied after the user approved it.

## Phase 5 — Checklist (25/25)

| Section | Result |
| --- | --- |
| Profile · Suggestions · Generated skills · Agent role files | evidence on every field and row; all schema fields; approval `S1,S2,S3` recorded; frontmatter parses, name == dir, triggers present; no `tools:`; `skills:`/`scripts:` resolve |
| AGENTS.md block · Tool scripts | one BEGIN, one END, nothing outside the markers (`PRE_HASH` none: file created); `bash -n` clean; forbidden-token and prefix-glob greps empty; gate in sec-pentest-local; redaction; `out/` ignored |
| Adapters · Overwrite · Prompt audit | 3 symlinks resolve; all paths new, CLAUDE.md touched only after its own yes; 3 audit lines |

## Final report

```text
celebrimbor: orders-api (/home/dev/orders-api)
Profile:
  stack:        go | gin v1.10.0 | go modules
  surfaces:     web_api, database, auth, ci_cd, infra, tests, docs
  agent config: AGENTS.md no | runtimes: claude | existing: 0 skills, 0 agents
  report:       CELEBRIMBOR_REPORT.md

Generated:
  .agents/skills/sec-static-scan/SKILL.md          (52 lines, archetype: Procedural)
  .agents/skills/sec-static-scan/scripts/run.sh    (40 lines, wraps: gitleaks, govulncheck, trivy)
  .agents/skills/sec-pentest-local/SKILL.md        (61 lines, archetype: Procedural)
  .agents/skills/sec-pentest-local/scripts/run.sh  (79 lines, wraps: zap-baseline, curl)
  .agents/agents/security-sentinel.md              (15 lines, skills: sec-static-scan, sec-pentest-local)
  AGENTS.md                                        (block created)

Adapters:
  .claude/skills/sec-static-scan -> ../../.agents/skills/sec-static-scan       (symlink)
  .claude/skills/sec-pentest-local -> ../../.agents/skills/sec-pentest-local   (symlink)
  .claude/agents/security-sentinel.md -> ../../.agents/agents/security-sentinel.md   (symlink)
  CLAUDE.md: @AGENTS.md added

Prompt audit (@prompt-engineering):
  sec-static-scan/SKILL.md     clarity 7/8 | anti-halluc 11/12 | Δ -24 | SAFE   | blocking 0
  sec-pentest-local/SKILL.md   clarity 7/8 | anti-halluc 12/12 | Δ -18 | SAFE   | blocking 0
  security-sentinel.md         clarity 8/8 | anti-halluc 11/12 | Δ +31 | REVIEW | blocking 0

Skipped:
  S4 db-migration-check — not approved
  S5 docs-sync — not approved

Checklist: 25/25 pass
Next: review the diff, then commit (e.g., @github-commit).
```

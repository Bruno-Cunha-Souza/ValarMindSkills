# Example — Go/Gin API

End-to-end run of `@celebrimbor` on `orders-api`: Go/Gin REST API, Postgres with goose migrations, `.env.example`, a Dockerfile, GitHub Actions with no scanners, no `AGENTS.md`, a `.claude/` dir and a `CLAUDE.md`. Excerpts are abridged with `# …`.

> /celebrimbor analisa esse projeto e sugere skills e agentes

## Phase 0 — Detect (abridged probe output)

```text
# 1  go.mod  go.sum  go.mod:3:go 1.23
# 2  go.mod:6: github.com/gin-gonic/gin v1.10.0   go.mod:8: github.com/golang-jwt/jwt/v5 v5.2.1
#    go.mod:9: github.com/jackc/pgx/v5 v5.7.1     go.mod:10: github.com/pressly/goose/v3 v3.22.1
# 3  db/migrations  Dockerfile  (no openapi.*, no compose, no *.tf)   internal/http/router.go:21: r.GET("/api/v1/orders", …)   Dockerfile (no USER line)
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

| id | type | name | family | priority | depth | evidence | depends_on | generates | status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| S1 | agent | security-sentinel | security | P1 | — | go.mod:6, go.mod:8 | S2, S3, S7 | `.agents/agents/security-sentinel.md` | proposed |
| S2 | skill | sec-static-scan | security | P1 | T2 | ci.yml (no gitleaks/govulncheck/trivy), Dockerfile:1 | — | `.agents/skills/sec-static-scan/{SKILL.md,EXAMPLE.md,references/SCANNERS.md,scripts/run.sh}` | proposed |
| S3 | skill | sec-pentest-local | security | P2 | T2 | go.mod:8, internal/http/middleware/auth.go:14 | — | `.agents/skills/sec-pentest-local/{SKILL.md,EXAMPLE.md,references/PROBES.md,scripts/{run.sh,jwt_probes.py}}` | proposed |
| S4 | skill | db-migration-check | database | P2 | T2 | go.mod:10, db/migrations | — | `.agents/skills/db-migration-check/{SKILL.md,EXAMPLE.md,references/MIGRATIONS.md,scripts/run.sh}` | proposed |
| S5 | skill | docs-sync | docs | P3 | T1 | CONTRIBUTING.md (absent), openapi.* (absent) | — | `.agents/skills/docs-sync/SKILL.md` | proposed |
| S6 | skill | code-review | review | P2 | T3 | go.mod:3, .github/workflows/ci.yml | — | `.agents/skills/code-review/{SKILL.md,EXAMPLE.md,references/{GOLANG,SEVERITY}.md,scripts/…}` | proposed |
| S7 | skill | orders-api-code-security-review | review | P1 | T3 | go.mod:8, internal/http/router.go:21 | — | `.agents/skills/orders-api-code-security-review/` (tree below) | proposed |

```yaml
- {id: S2, type: skill, name: sec-static-scan, family: security, priority: P1, depth: T2, status: proposed, rationale: "Gin API with JWT auth, but CI runs no secret, dependency or container scan.",
   evidence: [".github/workflows/ci.yml (no gitleaks/govulncheck/trivy)", "go.mod:6", "Dockerfile:1"],
   triggers: ["varrer segredos", "scan secrets", "dependency audit", "/sec-static-scan"], depends_on: [],
   uses_existing: ["@code-security-review (optional accelerator)"], portability: [agents-md, claude-adapter],
   generates: [.agents/skills/sec-static-scan/SKILL.md, .agents/skills/sec-static-scan/EXAMPLE.md,
               .agents/skills/sec-static-scan/references/SCANNERS.md, .agents/skills/sec-static-scan/scripts/run.sh]}
```

S6 and S7 are the `review` baseline, proposed on every run, both depth T3. `code-security-review` is already installed, so S7 carries the `orders-api-` prefix, and Phase 3 adapts its `references/golang/` and `scripts/` rows to this profile. S7 runs whichever static skill of S2 and S3 gets generated (S2 here; the gated S3 stays with the agent), so it needs no `depends_on`; S1 depends on S7, so the agent row owns the shared security triggers. Each skill bundles its own `scripts/` tool, so `type` stays `skill`. Infra rows fold into S2 (`trivy` misconfig scans the Dockerfile); ci-cd and coverage rows point to the installed `@ci-cd-generator` instead of a new skill.

**Stop.** "Which suggestion IDs should I generate? (e.g., `S1,S2,S3`, `all P1`, `none`)"

> S1, S2, S3 e S7

## Phase 3 — Generate (S1 plus its dependencies S2, S3, S7; S4–S6 skipped — not approved)

```text
orders-api/
├── AGENTS.md                                  # new: heading + CELEBRIMBOR block
├── .agents/skills/sec-static-scan/{SKILL.md,EXAMPLE.md,references/SCANNERS.md,scripts/run.sh}
├── .agents/skills/sec-pentest-local/{SKILL.md,EXAMPLE.md,references/PROBES.md,scripts/{run.sh,jwt_probes.py}}
├── .agents/skills/orders-api-code-security-review/
│   ├── SKILL.md                               # Lifecycle, Scope boundary
│   ├── EXAMPLE.md                             # one run on orders-api, illustrative findings
│   ├── references/{API,AUTH,DATABASE,SECRETS,SEVERITY}.md   # adapted from code-security-review/references/golang/*
│   └── scripts/{run.sh,lib/common.sh,20-sinks.sh,30-authz_map.py}
├── .agents/agents/security-sentinel.md
├── .claude/skills/{sec-static-scan,sec-pentest-local,orders-api-code-security-review} -> ../../.agents/skills/<name>
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
## Procedure       — Step 1 run `scripts/run.sh` · Step 2 triage each hit with references/SCANNERS.md (false-positive rules per tool:
                    test fixtures, `.env.example`, unreachable govulncheck symbols) · Step 3 table, critical/high first
## Example         — EXAMPLE.md: one run on orders-api, abridged output, two illustrative findings
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
emit() { # id severity evidence impact remediation
  jq -nc --arg id "$1" --arg severity "$2" --arg evidence "$3" --arg impact "$4" \
    --arg remediation "$5" --arg timestamp "$(date -u +%FT%TZ)" '$ARGS.named' >> "$FINDINGS"; }

if command -v gitleaks >/dev/null; then
  r="$OUT_DIR/.gitleaks.json"
  gitleaks detect --source "$ROOT" --no-banner --report-format json --report-path "$r" >/dev/null 2>&1 || true   # exit 1 = leaks found
  if [ -s "$r" ]; then   # redact inside jq: a multi-line secret must never reach `read`
    jq -r '.[] | [.File+":"+(.StartLine|tostring), (.Secret | if length<=8 then "****" else .[0:4]+"…"+.[-4:] end)] | @tsv' "$r" \
      | while IFS=$'\t' read -r loc sec; do emit SEC-GL-001 high "$loc $sec" "Committed secret." "Rotate it, then purge it from history."; done
  else echo "skip: gitleaks produced no report" >&2; fi
  rm -f "$r"   # raw report holds unredacted values
else echo "skip: gitleaks not installed" >&2; fi

if [ -f "$ROOT/go.mod" ] && command -v govulncheck >/dev/null; then
  (cd "$ROOT" && govulncheck ./...) > "$OUT_DIR/govulncheck.txt" 2>&1 && rc=0 || rc=$?   # 0 clean · 3 vulns found · else build/config error
  case $rc in 0) ;; 3) emit SEC-GV-001 high "go.mod (see out/govulncheck.txt)" "Reachable vulnerable dependency." "Upgrade the modules govulncheck names." ;;
    *) echo "skip: govulncheck exit $rc (see out/govulncheck.txt)" >&2 ;; esac
else echo "skip: govulncheck not installed or no go.mod" >&2; fi

if command -v trivy >/dev/null; then
  r="$OUT_DIR/.trivy.json"
  if trivy fs --quiet --scanners vuln,misconfig --format json --output "$r" "$ROOT" 2>/dev/null; then
    jq -r '.Results[]? | .Target as $t
      | (.Vulnerabilities[]? | [$t, .Severity, "\(.PkgName) \(.InstalledVersion) \(.VulnerabilityID)", "Upgrade to \(.FixedVersion // "a fixed release")."]),
        (.Misconfigurations[]? | ["\($t):\(.CauseMetadata.StartLine // 1)", .Severity, "\(.ID) \(.Title)", .Resolution])
      | @tsv' "$r" | while IFS=$'\t' read -r loc sev what fix; do
      sev="$(printf '%s' "$sev" | tr '[:upper:]' '[:lower:]')"; [ "$sev" = unknown ] && sev=info
      emit SEC-TV-001 "$sev" "$loc $what" "Known vulnerable package or Dockerfile misconfiguration." "$fix"
    done
  else echo "skip: trivy failed (vulnerability database offline?)" >&2; fi
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
# … emit() as in sec-static-scan (token values redacted in jq before emit); zap-baseline.py -t "$TARGET"
# python3 -I "$(dirname "$0")/jwt_probes.py" — alg=none, expired, wrong-key and missing-token requests; re-checks I_HAVE_AUTHORIZATION itself
exit 0
```

`TARGET=http://localhost.evil.com` and `TARGET=https://staging.orders.example` both exit `2` with `refusing: TARGET is not local`; the skill points staging and production testing to `@code-security-review`.

### `.agents/skills/orders-api-code-security-review/` (T3, Lifecycle)

`SKILL.md` (body abridged to its headings):

```markdown
---
name: orders-api-code-security-review
description: "Reviews orders-api changes for security defects in the Gin routes, JWT auth, pgx queries and secrets handling, and files only findings with a CWE/OWASP class and an attacker path to scripts/out/findings.jsonl; correctness defects are handed to code-review. Use before merging auth, API or database changes, not for live-target testing. Triggers: 'revisar segurança do código', 'security code review', '/orders-api-code-security-review'."
source: celebrimbor
---
## When to Use       — diff touches internal/http/**, db/**, auth config, Dockerfile or .github/workflows
## Scope boundary    — file a finding only with a CWE/OWASP class and an attacker path: "Who is the attacker, and what do they gain?"
                       No answer → "Handoff to code-review" (file:line, one line, no SEC- id, no severity)
## Prerequisites     — rg, jq, python3 (stdlib only); gitleaks/govulncheck/trivy through sec-static-scan when present
## Phase 0 Scope     — git diff --name-only <base>...HEAD → surfaces touched (API · AUTH · DATABASE · SECRETS)
## Phase 1 Scripts   — scripts/run.sh: 20-sinks.sh (rg sweeps), 30-authz_map.py (routes outside middleware.Auth), sec-static-scan
## Phase 2 Read      — per touched surface, walk the `manual` rows of references/<SURFACE>.md
## Phase 3 Triage    — script hits are leads: confirm by reading, apply the Scope boundary, rate with references/SEVERITY.md
## Phase 4 Report    — findings table, then Handoff to code-review, then skipped tools
## Constraints       — Never print a secret value · Never send traffic (sec-pentest-local does, gated) · Never edit code
## Output format     — id | severity | CWE/OWASP | evidence file:line | attacker path | fix
```

`references/AUTH.md` (3 of 9 rows):

```markdown
> Reference companion for the [orders-api-code-security-review](../SKILL.md) skill. Adapted from code-security-review/references/golang/MIDDLEWARE.md.

| id | catches | detection | project anchor | severity rule | fix (Gin + golang-jwt v5) |
| --- | --- | --- | --- | --- | --- |
| AUTH-01 | route outside `middleware.Auth()` | `scripts/30-authz_map.py` | internal/http/router.go:21 | high on mutating verbs, medium on GET | register it on the authed group |
| AUTH-02 | JWT parsed without an alg allow-list (CWE-347) | `rg -n 'jwt\.Parse\(' internal/` lacking `WithValidMethods` | internal/http/middleware/auth.go:14 | critical | `jwt.Parse(tok, kf, jwt.WithValidMethods([]string{"HS256"}))` |
| AUTH-03 | expiry not enforced (CWE-613) | `rg -n 'WithoutClaimsValidation' internal/` | internal/http/middleware/auth.go:14 | high | drop the option; set `exp` when issuing |
```

The other six rows cover BOLA on `/api/v1/orders/:id`, the role check, the signing key source, tokens in logs, refresh reuse and CORS with credentials. `API.md`, `DATABASE.md` and `SECRETS.md` follow the same shape. `SEVERITY.md` maps CWE class × reachability to a severity.

`scripts/lib/common.sh`, sourced by every shell check:

```bash
# lib/common.sh — OUT_DIR + .gitignore, ROOT, emit. Sourced by run.sh and every .sh check.
OUT_DIR="${OUT_DIR:-$(cd "$(dirname "$0")" && pwd)/out}"; export OUT_DIR; mkdir -p "$OUT_DIR"; printf '*\n' > "$OUT_DIR/.gitignore"
FINDINGS="$OUT_DIR/findings.jsonl"; ROOT="${PROJECT_ROOT:-$PWD}"; export PROJECT_ROOT="$ROOT"
[ -d "$ROOT" ] || { echo "config: PROJECT_ROOT not found: $ROOT" >&2; exit 1; }
command -v jq >/dev/null || { echo "config: jq is required" >&2; exit 1; }
emit() { # id severity evidence impact remediation
  jq -nc --arg id "$1" --arg severity "$2" --arg evidence "$3" --arg impact "$4" \
    --arg remediation "$5" --arg timestamp "$(date -u +%FT%TZ)" '$ARGS.named' >> "$FINDINGS"; }
```

`scripts/run.sh`:

```bash
#!/usr/bin/env bash
# orders-api-code-security-review — runs the check scripts, then sec-static-scan when generated. Reads: PROJECT_ROOT (default $PWD), OUT_DIR. Writes: out/findings.jsonl
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; source "$here/lib/common.sh"; : > "$FINDINGS"
"$here/20-sinks.sh"
python3 -I "$here/30-authz_map.py"
s="$here/../../sec-static-scan/scripts/run.sh"
if [ -x "$s" ]; then OUT_DIR="$OUT_DIR/sec-static-scan" "$s"; else echo "skip: sec-static-scan not generated" >&2; fi
exit 0
```

`scripts/20-sinks.sh` (3 of 12 sweeps):

```bash
#!/usr/bin/env bash
# 20-sinks — rg sweeps for injection and logging sinks in the Go code. Reads: PROJECT_ROOT, OUT_DIR. Writes: out/findings.jsonl
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
command -v rg >/dev/null || { echo "skip: rg not installed" >&2; exit 0; }
sweep() { # id severity pattern impact remediation — path:line only, no excerpt (a hit may hold a secret)
  rg -n --no-heading -g '*.go' -g '!*_test.go' -e "$3" "$ROOT" 2>/dev/null | cut -d: -f1,2 \
    | while IFS= read -r loc; do emit "$1" "$2" "${loc#"$ROOT"/}" "$4" "$5"; done || true; }
sweep SEC-SQ-001 high 'fmt\.Sprintf\("(SELECT|INSERT|UPDATE|DELETE)' "SQL built with Sprintf reaches pgx (CWE-89)." "Use \$1 placeholders: pool.Query(ctx, sql, args...)."
sweep SEC-SQ-002 high '\.(Query|Exec)\(ctx, *"[^"]*" *\+' "String concatenation in a pgx query (CWE-89)." "Pass values as query arguments."
sweep SEC-LG-001 medium 'log.*(Authorization|token|password)' "Credentials written to logs (CWE-532)." "Log the user id, never the header or token."
exit 0
```

`scripts/30-authz_map.py`:

```python
#!/usr/bin/env python3
# 30-authz_map — Gin routes registered outside middleware.Auth(). Reads: PROJECT_ROOT (default cwd), OUT_DIR, PUBLIC_ROUTES. Writes: out/findings.jsonl
# Groups are tracked per file; a route on a group defined in another file is reported and confirmed by reading (Phase 3).
import datetime, json, os, pathlib, re, sys

ROOT = pathlib.Path(os.environ.get("PROJECT_ROOT", ".")).resolve()
OUT = pathlib.Path(os.environ.get("OUT_DIR") or pathlib.Path(__file__).parent / "out")
PUBLIC = set(os.environ.get("PUBLIC_ROUTES", "/healthz,/api/v1/login").split(","))
AUTH = re.compile(r"middleware\.Auth\(")  # internal/http/middleware/auth.go:14
GROUP = re.compile(r'(\w+)\s*:?=\s*(\w+)\.Group\("([^"]*)"(.*)')
USE = re.compile(r"(\w+)\.Use\((.*)")
ROUTE = re.compile(r'(\w+)\.(GET|POST|PUT|PATCH|DELETE)\("([^"]*)"(.*)')
if not ROOT.is_dir():
    sys.exit(f"config: PROJECT_ROOT not found: {ROOT}")
OUT.mkdir(parents=True, exist_ok=True)


def emit(severity, evidence, impact, remediation):
    ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    with open(OUT / "findings.jsonl", "a") as f:
        f.write(json.dumps({"id": "SEC-AZ-001", "severity": severity, "evidence": evidence,
                            "impact": impact, "remediation": remediation, "timestamp": ts}) + "\n")


for path in sorted((ROOT / "internal/http").rglob("*.go")):
    prefix, authed = {}, {}  # router var → path prefix / sits behind middleware.Auth()
    for n, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
        if m := GROUP.search(line):
            var, parent, p, rest = m.groups()
            prefix[var] = prefix.get(parent, "") + p
            authed[var] = authed.get(parent, False) or bool(AUTH.search(rest))
        elif m := USE.search(line):
            authed[m[1]] = authed.get(m[1], False) or bool(AUTH.search(m[2]))
        elif m := ROUTE.search(line):
            var, verb, p, rest = m.groups()
            full = prefix.get(var, "") + p
            if full in PUBLIC or authed.get(var) or AUTH.search(rest):
                continue
            emit("medium" if verb == "GET" else "high", f"{path.relative_to(ROOT)}:{n} {verb} {full}",
                 "An unauthenticated caller reaches the handler (CWE-306, OWASP API2).",
                 "Register it on the group that uses middleware.Auth(), or list it in PUBLIC_ROUTES if public by design.")
```

`EXAMPLE.md` runs `scripts/run.sh` on orders-api and walks two illustrative findings (`SEC-AZ-001` on `internal/http/router.go:34 DELETE /api/v1/orders/:id`, `AUTH-02` at `internal/http/middleware/auth.go:14`). It also shows the Scope boundary at work: a nil discount that zeroes an order total at `internal/orders/price.go:40` has no attacker path. It goes under **Handoff to code-review**, never into the findings table.

### `.agents/agents/security-sentinel.md`

```markdown
---
name: security-sentinel
description: "Runs the project's full security verification — static scans, secret scan, dependency audit, authorized local pentest — and files a severity-ranked report. Use when: 'security check', 'verificar segurança', 'pentest local'."
skills: [orders-api-code-security-review, sec-static-scan, sec-pentest-local]
scripts: [.agents/skills/sec-static-scan/scripts/run.sh, .agents/skills/sec-pentest-local/scripts/run.sh]
source: celebrimbor
---
# Purpose
Single entry point for security checks on orders-api (Gin + JWT + Postgres). Reports; never fixes.
# Workflow
1. Follow orders-api-code-security-review: review the auth, API and database code, then run sec-static-scan. 2. If a dev server runs on localhost and the user confirms ownership, run sec-pentest-local
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
| 'testar JWT', 'JWT probes', 'local pentest' | `.agents/skills/sec-pentest-local/SKILL.md` | skill |
| 'revisar segurança do código', 'security code review' | `.agents/skills/orders-api-code-security-review/SKILL.md` | skill |
<!-- CELEBRIMBOR END -->
```

### Adapters and CLAUDE.md

```bash
mkdir -p .claude/skills .claude/agents && ln -s ../../.agents/skills/sec-static-scan .claude/skills/sec-static-scan
ln -s ../../.agents/skills/sec-pentest-local .claude/skills/sec-pentest-local
ln -s ../../.agents/skills/orders-api-code-security-review .claude/skills/orders-api-code-security-review
ln -s ../../.agents/agents/security-sentinel.md .claude/agents/security-sentinel.md
```

Asked separately: "`CLAUDE.md` exists without `@AGENTS.md`. Append the single line `@AGENTS.md`? (yes/no)" → `sim` → line appended.

## Phase 4 — Prompt audit

Use case 1 for the three SKILL.md files, use case 4 for the agent; metrics are in the final report. One Major on the agent (no stop condition without a local server) was fixed by a rewrite applied after the user approved it.

## Phase 5 — Checklist (29/29)

| Section | Result |
| --- | --- |
| Profile · Suggestions · Generated skills · Agent role files | evidence on every field and row; all schema fields; both `review` baseline rows present; approval `S1,S2,S3,S7` recorded; frontmatter parses, name == dir, triggers present; depth floor met (`DEPTH=orders-api-code-security-review:T3 sec-static-scan:T2 sec-pentest-local:T2`), every reference and EXAMPLE.md cites orders-api paths, Scope boundary present in S7; no `tools:`; `skills:`/`scripts:` resolve |
| AGENTS.md block · Tool scripts | one BEGIN then one END, nothing outside the markers (`PRE_HASH` none: file created); `bash -n` and Python parse clean; forbidden-token and prefix-glob greps empty; gate in sec-pentest-local; redaction; `out/` ignored |
| Adapters · Overwrite · Prompt audit | 4 symlinks resolve; all paths new, CLAUDE.md touched only after its own yes; 4 audit lines |

## Final report

```text
celebrimbor: orders-api (/home/dev/orders-api)
Profile:
  stack:        go | gin v1.10.0 | go modules
  surfaces:     web_api, database, auth, ci_cd, infra, docs
  agent config: AGENTS.md no | runtimes: claude | existing: 0 skills, 0 agents
  report:       CELEBRIMBOR_REPORT.md

Generated:
  .agents/skills/sec-static-scan/                  (T2 | SKILL.md 88 lines, archetype: Procedural | refs: SCANNERS.md | scripts: run.sh | EXAMPLE.md yes)
  .agents/skills/sec-static-scan/scripts/run.sh    (41 lines, runs: —, wraps: gitleaks, govulncheck, trivy)
  .agents/skills/sec-pentest-local/                (T2 | SKILL.md 104 lines, archetype: Procedural | refs: PROBES.md | scripts: run.sh, jwt_probes.py | EXAMPLE.md yes)
  .agents/skills/sec-pentest-local/scripts/run.sh  (92 lines, runs: jwt_probes.py, wraps: zap-baseline, curl)
  .agents/skills/orders-api-code-security-review/  (T3 | SKILL.md 186 lines, archetype: Lifecycle | refs: API, AUTH, DATABASE, SECRETS, SEVERITY | scripts: run.sh, 20-sinks.sh, 30-authz_map.py, lib/common.sh | EXAMPLE.md yes)
  .agents/skills/orders-api-code-security-review/scripts/run.sh  (9 lines, runs: 20-sinks.sh, 30-authz_map.py, sec-static-scan)
  .agents/agents/security-sentinel.md              (16 lines, skills: orders-api-code-security-review, sec-static-scan, sec-pentest-local)
  AGENTS.md                                        (block created)

Adapters:
  .claude/skills/sec-static-scan -> ../../.agents/skills/sec-static-scan       (symlink)
  .claude/skills/sec-pentest-local -> ../../.agents/skills/sec-pentest-local   (symlink)
  .claude/skills/orders-api-code-security-review -> ../../.agents/skills/orders-api-code-security-review   (symlink)
  .claude/agents/security-sentinel.md -> ../../.agents/agents/security-sentinel.md   (symlink)
  CLAUDE.md: @AGENTS.md added

Prompt audit (@prompt-engineering):
  sec-static-scan/SKILL.md     clarity 7/8 | anti-halluc 11/12 | Δ -24 | SAFE   | blocking 0
  sec-pentest-local/SKILL.md   clarity 7/8 | anti-halluc 12/12 | Δ -18 | SAFE   | blocking 0
  orders-api-code-security-review/SKILL.md   clarity 7/8 | anti-halluc 11/12 | Δ -12 | SAFE   | blocking 0
  security-sentinel.md         clarity 8/8 | anti-halluc 11/12 | Δ +31 | REVIEW | blocking 0

Skipped:
  S4 db-migration-check — not approved
  S5 docs-sync — not approved
  S6 code-review — not approved

Checklist: 29/29 pass
Next: review the diff, then commit (e.g., @github-commit).
```

## Re-run — three months later

The team added `api/openapi.yaml` and `github.com/redis/go-redis/v9`. Phase 1 now lists S1, S2, S3 and S7 in `existing_skills` / `existing_agents`, all with `source: celebrimbor`. S7's body cites `openapi.* (absent)` and no cache, so it drifted; S2 still matches the profile.

| id | type | name | family | priority | depth | evidence | depends_on | generates | status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| S2 | skill | sec-static-scan | security | P1 | T2 | .agents/skills/sec-static-scan/SKILL.md:4 | — | `.agents/skills/sec-static-scan/` (unchanged) | skipped |
| S7 | skill | orders-api-code-security-review | review | P1 | T3 | api/openapi.yaml:1, go.mod:11 | — | `.agents/skills/orders-api-code-security-review/{SKILL.md,references/{API,DATABASE}.md}` | proposed |

```yaml
- {id: S7, type: skill, name: orders-api-code-security-review, family: review, priority: P1, status: proposed,
   rationale: "update: OpenAPI spec now exists (generated with openapi.* absent) and Redis is a new data store; review steps gain spec-vs-router drift and Redis auth checks.",
   evidence: ["api/openapi.yaml:1", "go.mod:11", ".agents/skills/orders-api-code-security-review/SKILL.md:4"], # …
   generates: [.agents/skills/orders-api-code-security-review/SKILL.md, .agents/skills/orders-api-code-security-review/references/API.md,
               .agents/skills/orders-api-code-security-review/references/DATABASE.md]}   # spec-drift rows in API.md, Redis rows in DATABASE.md
```

Approving S7 shows a unified diff of each current file against its regenerated version and writes it only on an explicit yes (ARTIFACT_FORMATS §7). A same-name skill without `source: celebrimbor` would be an `extend` row, `skipped`.

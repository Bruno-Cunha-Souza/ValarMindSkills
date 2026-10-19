> Reference companion for the [celebrimbor](../SKILL.md) skill.

# Artifact Formats

Formats for everything celebrimbor proposes (Phase 2) and writes into the target project (Phase 3). The target project's own files are the only output; nothing here applies to the ValarMindSkills repository.

## 1. Suggestion schema

One record per suggestion; the report renders them as a table with a `status` column that celebrimbor updates.

```yaml
- id: S1
  type: agent | skill | tool                  # `skill` may bundle its own `scripts/` tool; a separate `tool` row is only for a script shared by several skills
  name: security-sentinel                     # kebab, ≤64, no collisions with existing_skills/agents except an `update:` row
  family: review | security | testing | ci-cd | database | api-contracts | frontend | infra | docs | release | observability | ai-llm
  priority: P1 | P2 | P3                      # P1 = gap with concrete risk; P2 = recurring chore; P3 = nice-to-have
  depth: T1 | T2 | T3                         # skills only, from `family` (§3 Depth floor); agents and tools: `—`
  rationale: "<1-2 sentences>"
  evidence: [go.mod:14, .github/workflows (absent), .env.example:3]
  triggers: ["verificar segurança", "security check", "/security-sentinel"]
  depends_on: [S2, S3]                        # agents depend on their skills; skills on their tools
  uses_existing: ["@code-security-review (optional accelerator)"]   # dedupe / relate, never a hard dependency
  portability: [agents-md, claude-adapter, cursor-adapter, antigravity-copy]   # subset of runtimes_detected
  generates: [.agents/agents/security-sentinel.md]
  status: proposed | approved | skipped       # set by celebrimbor only from the ID list the user gives in chat; edits to the report file are not approval
```

- `evidence` is mandatory and non-empty: `file:line`, or `path (absent)` for a gap. No evidence, no suggestion.
- `triggers` are bilingual (PT and EN) and end with the slash form `/<name>`.
- `depends_on` fixes generation order: tools → skills → agents. A `tool` row's `generates` path sits under one owning skill's `scripts/`; the other skills call it by path.
- `portability` always includes `agents-md`; the rest default to `runtimes_detected`, anything else is opt-in.
- `generates` lists canonical paths only; adapter paths follow from `portability` (§2).
- `uses_existing` names optional accelerators. Generated artifacts must work when none of them is installed.

**Dedupe rule.** A candidate `name` already present in `agent_config.existing_skills` / `existing_agents` → do not propose a new artifact. Read the existing artifact's frontmatter at its `path`:
- `source: celebrimbor` (a previous run generated it) → an `update:` row. Diff the evidence paths its body cites against the current profile. Each change — a new framework or surface, a removed signal, a changed version, a depth floor or Scope boundary the existing skill does not meet (§3) — goes into `evidence` as `file:line` or `path (absent)`; `rationale` starts `update:` and names the changes; `status: proposed`; `generates` lists the existing paths. Approval regenerates every `generates` path under §7: a unified diff per file, which also shows any hand edits the regeneration would drop, and an explicit yes. No change → `status: skipped`, `rationale: "update: none — <path> matches the profile"`, evidence the `source:` line as `path:line`.
- No `source: celebrimbor` (user-written) → list it with `status: skipped`, `rationale` starting `extend:` and naming the existing path and what it already covers. The user may approve it by ID in chat, which means editing the existing artifact under §7, not creating a second one. Dedupe is by `name` only: `existing_*` records carry no `family`, and an overlapping artifact under another name goes into `uses_existing` as `<path> (overlaps: <what>)` with `path:line` evidence — the row stays `proposed`, never silently dropped.

## 2. Generated layout and adapters

```text
<target>/
├── AGENTS.md                         # created or extended with the CELEBRIMBOR managed block (§5)
├── CLAUDE.md                         # only if it exists: one `@AGENTS.md` import line (ask first)
├── .agents/
│   ├── skills/<name>/
│   │   ├── SKILL.md                  # §3
│   │   ├── EXAMPLE.md                # T2/T3: worked run on this project's code (§3 Depth floor)
│   │   ├── references/<TOPIC>.md     # T2/T3: check catalogs, one file per surface or language
│   │   └── scripts/                  # tools (§6): run.sh + check scripts (.sh/.py) + lib/, out/ git-ignored
│   └── agents/<name>.md              # §4
├── .claude/skills/<name>  -> ../../.agents/skills/<name>
├── .claude/agents/<name>.md -> ../../.agents/agents/<name>.md
├── .cursor/skills/<name>  -> ../../.agents/skills/<name>
└── .agent/skills/<name>/             # COPY, Antigravity only
```

`.agents/` is the single canonical copy. Codex and Zed discover `.agents/skills` natively, so they need no adapter.

| Runtime (detected by) | Adapter | Rule |
| --- | --- | --- |
| Codex, Zed, any AGENTS.md reader | none | Canonical `.agents/` plus the AGENTS.md block |
| Claude Code (`.claude/`) | relative symlink | `.claude/skills/<name>` and `.claude/agents/<name>.md`; copy if symlink creation fails |
| Cursor (`.cursor/`) | relative symlink | `.cursor/skills/<name>`; copy if symlink creation fails |
| Antigravity (`.agent/`) | copy | `.agent/skills/<name>/`; never a symlink |

```bash
mkdir -p .claude/skills
ln -s ../../.agents/skills/<name> .claude/skills/<name> 2>/dev/null \
  || cp -R .agents/skills/<name> .claude/skills/<name>
```

- Symlinks are relative (`../../.agents/...`) so the repository stays portable across clones.
- Every copy is a snapshot: on re-run, refresh it from `.agents/` under §7 and report it as a copy, not a link.
- `CLAUDE.md`: only when the file exists and does not already contain `@AGENTS.md`. Ask first, as a separate question from the artifact approval. On yes, append the single line `@AGENTS.md`. Never create `CLAUDE.md`.

## 3. Generated SKILL.md format

**Frontmatter** (open Agent Skills fields plus provenance, nothing else):

```yaml
---
name: sec-static-scan
description: "Scans this project for committed secrets and vulnerable dependencies with gitleaks, govulncheck and trivy, writing findings to scripts/out/findings.jsonl. Use for pre-merge or periodic hygiene, not for live-target testing. Triggers: 'varrer segredos', 'scan secrets', 'dependency audit', '/sec-static-scan'."
source: celebrimbor
---
```

- `description`: double-quoted, third person, states the output and the scope boundary, ≤1024 chars (aim 300-600), ends with `Triggers: '...', '/<name>'.` in PT and EN.
- Omit runtime-specific fields (`allowed-tools`, `model`, `paths`, `hooks`, `arguments`, ...); they break portability.

**Naming.** `[a-z0-9-]`, ≤64 chars, noun phrase (`db-migration-check`, not `check-the-migrations`), must equal the directory name, must not contain `claude` or `anthropic`, must not collide with `existing_skills` / `existing_agents` (an `update:` row regenerates the same path, §1).

**Archetype.** Pick one before writing the body.

| Archetype | Use for | Body skeleton |
| --- | --- | --- |
| Procedural | Skills that wrap a tool script and return one artifact | Goal · Inputs · Procedure (Step 1..n, runs `scripts/run.sh`) · Constraints · Output format |
| Lifecycle | Multi-phase workflows an agent drives (detect → analyze → act → validate) | When to Use · Prerequisites · Phase 0..n · Constraints · Output format |
| Reference | Docs and contract skills the agent consults (API conventions, migration rules) | Purpose · Schema / Rules tables · Examples · Source of truth links |

**Progressive disclosure.** `description` is always loaded; the body only on activation; `references/` and `EXAMPLE.md` only when the body links to them. `SKILL.md` holds the workflow and the decision rules (≤500 lines); check catalogs, payloads and stack detail go to `references/UPPERCASE.md`, one level deep, linked from the phase that uses them. Each reference file opens with the banner `> Reference companion for the [<name>](../SKILL.md) skill.` Depth lives in references and scripts, so a deep skill costs nothing until it is activated.

**Depth floor.** A generated skill is a working tool for this project, not an outline. Depth follows the family; the floor is a minimum of substance, never a line target to pad.

| Tier | Families | `SKILL.md` | `references/` | `scripts/` | `EXAMPLE.md` |
| --- | --- | --- | --- | --- | --- |
| T3 | `review` (`code-review`, `code-security-review`) | Lifecycle; Scope boundary section; one phase per check group | one file per present surface (security) or language (review), ≥8 check rows each, plus `SEVERITY.md` | `run.sh` orchestrator + ≥2 check scripts, `.sh` and/or `.py` (§6), shared `lib/` | required |
| T2 | `security`, `testing`, `database`, `api-contracts`, `frontend`, `infra`, `ci-cd`, `observability`, `ai-llm` | Procedural or Lifecycle | ≥1 file, ≥5 check rows | `run.sh` + check scripts for every mechanical check | required |
| T1 | `docs`, `release` | any archetype; checks inline as a table | optional | `run.sh` when a check is mechanical (e.g., README commands vs `Makefile`) | optional, inline section allowed |

- **Check row** (in a reference table, one row per check): `id` · what it catches · detection — the exact `rg`/tool command for this stack, or `manual` with what to read · project anchor (`file:line` from the profile, or `path (absent)`) · severity rule · fix in this project's idiom (framework, ORM, middleware names). A row with no anchor in this project is dropped, not kept as generic advice.
- **Every reference file and `EXAMPLE.md` cites project paths** (`file:line`). Text that would read the same in any repository does not belong in the skill.
- **`EXAMPLE.md`** shows one invocation end to end on this project: the command, an abridged script output, two or three findings on real paths from the profile, and the final report. Findings in it are illustrative and say so in one line; never present them as a real audit result.
- **Source material.** When an installed sibling covers the family (probe 8, e.g. `code-security-review`, `code-review`, `ci-cd-generator`), read its `references/` and `scripts/` and adapt them: keep the rows that match this profile's languages, frameworks and surfaces, rewrite detections and fixes to this project's paths and idioms, drop the rest. The result is a standalone copy — no runtime link to the sibling, no path into its install dir. Record each adapted file as `adapted from <sibling>/<path>` in the reference's banner line.

**Scope boundary** (required section in both `review` skills, recommended for every T2 skill whose family overlaps another).
- `code-security-review` reports a finding only when it names a security class (CWE id or OWASP category) **and** an attacker path: who controls the input or crosses which trust boundary, and what they gain. Correctness, business-logic, domain-safety (clinical, financial) and resilience defects without an attacker path are not security findings: list them under `Handoff to code-review` with `file:line` and one line each, no `SEC-` id, no severity, never in the findings table.
- `code-review` routes the reverse: a defect with an attacker path goes under `Handoff to code-security-review` with `file:line`.
- The section states the test as one question the reviewer asks before filing: "Who is the attacker, and what do they gain?" No answer → hand off.

**Inputs vs Constraints.**
- Every knob a caller may override (scope, target dir, severity floor) is an `Inputs` row with a default.
- Every non-negotiable (no remote targets, no secret values, no writes outside `out/`) is a `Constraints` bullet starting with `Never`.
- Soft words (`should`, `prefer`) yield to the user's extra prompt; `Never` survives it.

**Tools.** `scripts/` inside the skill IS the tools convention: executables the skill body invokes, modelled on `skills/code-security-review/scripts` in ValarMindSkills. Each phase that runs a script names it, its inputs and how to read its findings. Prose content is English; only triggers are bilingual. No `README.md` inside the skill; `SKILL.md` documents the scripts.

## 4. Agent role file

Path: `.agents/agents/<name>.md`. Portable role file; the `.claude/agents/` symlink makes it a Claude Code subagent too.

```markdown
---
name: security-sentinel
description: "Runs the project's full security verification — static scans, secret scan, dependency audit, authorized local pentest — and files a severity-ranked report. Use when: 'security check', 'verificar segurança', 'pentest local'."
skills: [sec-static-scan, sec-pentest-local]
scripts: [.agents/skills/sec-static-scan/scripts/run.sh, .agents/skills/sec-pentest-local/scripts/run.sh]
source: celebrimbor
---
# Purpose            (2-3 lines)
# Workflow           (numbered; which skill/script at each step; stop conditions)
# Boundaries         (Never …: no remote targets, no secret values in output, no fixes without approval)
# Output             (report shape; reuse findings JSONL + one summary table)
```

- `name` and `description` are the only fields all runtimes agree on; `skills` and `scripts` are plain lists the Workflow references; `source: celebrimbor` marks provenance for the §1 dedupe rule.
- **Never** emit `tools:`. Claude Code reads it as a tool allowlist and would silently strip the agent's capabilities.
- Every skill in `skills:` and every path in `scripts:` must exist after generation (dependency order guarantees it).
- `Boundaries` repeats the hard rules of the skills it drives; an agent never loosens a skill's `Never`.

## 5. AGENTS.md routing block

```markdown
<!-- CELEBRIMBOR BEGIN — generated; re-running celebrimbor replaces this block -->
## Project skills and agents

Skills: `.agents/skills/<name>/SKILL.md`. Agents: `.agents/agents/<name>.md` — read the role file, follow its Workflow and Boundaries, load the skills it lists.

| When the task matches | Load | Kind |
| --- | --- | --- |
| 'security check', 'verificar segurança', 'pentest local' | `.agents/agents/security-sentinel.md` | agent |
| 'scan secrets', 'varrer segredos', 'dependency audit' | `.agents/skills/sec-static-scan/SKILL.md` | skill |
<!-- CELEBRIMBOR END -->
```

- Markers are matched as whole lines, byte-exact; write them exactly as above.
- `AGENTS.md` absent → create it with a one-line heading plus the block.
- Markers absent → append the block after one blank line.
- Markers present → replace BEGIN..END inclusive at the same position (strip and rewrite). Content outside the markers stays byte-identical; never reorder, reformat or edit it. Verify with a hash that drops trailing blank lines, so the blank separator before an appended block is ignored: `sed '/^<!-- CELEBRIMBOR BEGIN/,/^<!-- CELEBRIMBOR END -->/d' AGENTS.md | awk 'NF{for(;n;n--)print "";print;next}{n++}' | shasum` (equal before and after).
- Markers malformed (zero or several BEGIN/END lines, or END before BEGIN) → never auto-repair: stop and ask the user to fix `AGENTS.md` first. The sed range above would otherwise delete to EOF while the hash still matches.
- Rows = rows of the previous block + this run's approved artifacts, deduped by `Load` path, dropping rows whose path no longer exists. A scoped re-run (`security only`) never erases other families.
- Agents first, then skills; trigger phrases copied from each artifact's `description`. A trigger phrase appears in exactly one row: when an agent and a skill it lists share a phrase, the agent row keeps it and the skill row drops it (the agent loads the skill).

## 6. Tool script contract

Applies to every generated `scripts/*.sh` and `scripts/*.py`. Layout: `run.sh` is the entry point and runs one check script per check group (`10-secrets.sh`, `20-sinks.sh`, `30-authz_map.py`, …); shared helpers (`OUT_DIR` + `.gitignore`, `emit`, redaction) live once in `scripts/lib/common.sh` and are sourced; the active-target gate never moves there. Size follows coverage, not a line cap: a check script wraps an installed scanner where one exists and otherwise carries the project's own `rg` sweeps and parsers (routes → middleware, migrations → destructive ops, spec → router drift). Python is for checks that need parsing or state (JWT decode, AST walks, cross-file maps); shell for sweeps and scanner wrappers.

| Rule | Requirement |
| --- | --- |
| Header | `# <name> — <purpose>. Reads: <env vars + defaults>. Writes: out/findings.jsonl` |
| Shell | `#!/usr/bin/env bash` then `set -euo pipefail`; must pass `bash -n` |
| Python | `#!/usr/bin/env python3`, stdlib only (no `pip install`), run as `python3 -I`; must pass `python3 -m py_compile`; no `shell=True`, no `os.system`, no `eval`/`exec` on input; writes findings with `json.dumps` to the same `findings.jsonl` |
| Output dir | `OUT_DIR="${OUT_DIR:-$(dirname "$0")/out}"`; write `*` to `$OUT_DIR/.gitignore` so results never get committed |
| Findings | One JSON object per line in `$OUT_DIR/findings.jsonl`: `id`, `severity` (`critical`/`high`/`medium`/`low`/`info`), `evidence` (`file:line` + redacted excerpt), `impact`, `remediation`, `timestamp` (UTC ISO 8601) |
| Exit codes | `0` ran cleanly, regardless of findings · `1` invalid config (missing env var, required helper, bad root) · `2` refused (authorization or non-local target) |
| Missing tools | Wrap `gitleaks`, `govulncheck`, `npm audit`, `semgrep`, `trivy`, `zap-baseline`, `hadolint`, ...; when absent print `skip: <tool> not installed` to stderr and continue |
| Secrets | Never write a matched secret value; redact to first 4 + last 4 chars (`****` when ≤8) inside the jq filter that reads the tool report and emit `@tsv` — never pipe raw values through `read` (a multi-line secret splits across reads and the overflow escapes redaction) |

Findings are output, not errors: CI gates by counting severities with `jq` over the JSONL.

**Active probes** (anything that sends traffic) additionally require `I_HAVE_AUTHORIZATION=1` **and** a local `TARGET`. Put this verbatim before the first request, inline in every active `.sh` (never only in `lib/`, where the CHECKLIST cannot see it per script):

```bash
[ -n "${TARGET:-}" ] || { echo "config: TARGET is required" >&2; exit 1; }
[ "${I_HAVE_AUTHORIZATION:-}" = "1" ] || { echo "refusing: set I_HAVE_AUTHORIZATION=1 to confirm you own TARGET" >&2; exit 2; }
host="${TARGET#*://}"; host="${host%%[/?#]*}"; host="${host##*@}"
case "$host" in '[::1]'|'[::1]:'*) host='[::1]' ;; *) host="${host%%:*}" ;; esac
case "$host" in localhost|127.0.0.1|'[::1]'|*.localhost|*.test) ;; *) echo "refusing: TARGET is not local" >&2; exit 2 ;; esac
```

The gate matches the exact host after stripping scheme, path/query/fragment, userinfo and port. Prefix globs like `localhost*` are forbidden: they accept `localhost.evil.com`. An active Python helper is only ever called from a gated `.sh`, and re-checks on its own first lines: `if os.environ.get("I_HAVE_AUTHORIZATION") != "1": sys.exit(2)`.

Non-local targets are refused outright, never "with a warning". The SKILL.md points users who need staging or production testing to `@code-security-review`, which carries its own authorization gate.

**Forbidden in generated scripts** (CHECKLIST greps for these):
- `rm -rf` on any path other than `$OUT_DIR`
- `git push`, `git reset --hard`, `git clean`
- `sudo`, `chmod 777`
- `curl … | sh`, `wget … | sh` (any download piped to a shell)
- `DROP`, `TRUNCATE` (SQL)
- writes outside the skill directory (all output goes to `$OUT_DIR`)
- prefix globs in the local-target gate (`localhost*`, `127.0.0.1*`, `*.test*`)
- in Python: `shell=True`, `os.system(`, `shutil.rmtree(` outside `OUT_DIR`

**Scanner skeleton** — one check script; in a multi-script skill `OUT_DIR`, `emit` and the `jq` check move to `lib/common.sh` (`.agents/skills/sec-static-scan/scripts/run.sh`):

```bash
#!/usr/bin/env bash
# sec-static-scan — secrets + Go dependency scan. Reads: PROJECT_ROOT (default $PWD). Writes: out/findings.jsonl
set -euo pipefail
OUT_DIR="${OUT_DIR:-$(dirname "$0")/out}"; mkdir -p "$OUT_DIR"; printf '*\n' > "$OUT_DIR/.gitignore"
FINDINGS="$OUT_DIR/findings.jsonl"; : > "$FINDINGS"
ROOT="${PROJECT_ROOT:-$PWD}"
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
exit 0
```

## 7. Overwrite rules

- Target path absent → create it.
- Target path exists → show a unified diff of current vs proposed, ask, and write only on an explicit yes. Never overwrite silently, never "merge" without showing the result.
- A `no` keeps the existing file and records the artifact as `skipped — exists` in the final report.
- An existing adapter that is a real directory (not a symlink) is treated as an existing file: diff, ask.
- `AGENTS.md`: only the CELEBRIMBOR block changes, replaced in place (§5); the diff shown covers the block alone.
- `CLAUDE.md`: append-only, one line, asked separately (§2).
- Never delete artifacts that a previous run generated and the user no longer wants; list them and let the user remove them.

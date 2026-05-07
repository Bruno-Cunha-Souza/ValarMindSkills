# context-optimization / scripts

Auxiliary tools for evidence-based context audit. Pattern mirrors `code-security-review/scripts/` — orchestrator + per-phase scripts emit JSONL findings → `lib/report.py` aggregates to Markdown + JSON.

## Purpose

The skill's Audit mode (Phase 0..6) produces stronger findings when backed by **measurements**, not heuristics. These scripts:

- Inventory the context candidate files (`00-context-scan.sh`)
- Count tokens accurately (`01-token-count.py`, with tiktoken if available)
- Detect duplicate content blocks (`02-dedup-detect.sh`)

Output feeds Phase 1 (Inventory), Phase 2 (Cost & Quality Audit), and Phase 3 (Technique Selection).

## Quick start

```bash
# Audit a project root
PROJECT_ROOT=/path/to/project bash scripts/run-all.sh

# Or via CLI arg
bash scripts/run-all.sh /path/to/project

# Single phase
PROJECT_ROOT=/path/to/project bash scripts/00-context-scan.sh
PROJECT_ROOT=/path/to/project python3 scripts/01-token-count.py
PROJECT_ROOT=/path/to/project bash scripts/02-dedup-detect.sh
```

Output goes to `./out/`:

- `findings.jsonl` — one JSON record per finding (raw)
- `report.md` — human-readable Markdown report
- `summary.json` — counts by severity + verdict flags

## Environment variables

| Variable | Required | Default | Purpose |
| :--- | :--- | :--- | :--- |
| `PROJECT_ROOT` | yes | — | Directory to audit. Pass via env or as first CLI arg to `run-all.sh`. |
| `OUT_DIR` | no | `./out` | Where findings + report land. |
| `FINDINGS_FILE` | no | `$OUT_DIR/findings.jsonl` | Override findings file path. |

## Dependencies

| Tool | Required by | Required? | Install |
| :--- | :--- | :--- | :--- |
| `bash` ≥ 4 | all `.sh` | yes | system |
| `python3` ≥ 3.8 | `01-token-count.py`, `lib/report.py`, `02-dedup-detect.sh` (inline Python) | yes | system |
| `find` / `wc` / `awk` / `sort` | `00-context-scan.sh`, `02-dedup-detect.sh` | yes | POSIX core utils |
| `sha256sum` (Linux) or `shasum` (macOS) | `02-dedup-detect.sh` | yes | system |
| `tiktoken` | `01-token-count.py` | **optional** | `pip install --user tiktoken` |
| `jq` | `run-all.sh` (optional summary pretty-print) | optional | system |

Without `tiktoken`, `01-token-count.py` falls back to a chars/4 heuristic with a logged warning. Accuracy drops to ±15% for English; install tiktoken for production audits.

## Output schema (findings.jsonl)

Each line is a JSON object:

```json
{
  "id":          "CTX-SCAN-001",
  "phase":       "00-context-scan",
  "severity":    "high",
  "category":    "bloat",
  "target":      "src/lib/big-file.md",
  "evidence":    { "path": "...", "size_bytes": 12345, "estimated_tokens": 3086, "rank": 1 },
  "impact":      "...",
  "remediation": "...",
  "timestamp":   "2026-05-07T12:34:56Z"
}
```

Severity: `critical` / `high` / `medium` / `low` / `info`.

Category: `cost` / `cache` / `quality` / `bloat` / `architecture`.

## Portability across harnesses

| Harness | Auto-execution | Manual execution | Notes |
| :--- | :--- | :--- | :--- |
| **Claude Code** | ✓ Skill can invoke `bash scripts/run-all.sh` via Bash tool during Audit mode | ✓ User runs from terminal | Full Bash + Python3 access. Recommended. |
| **Codex CLI** | ✗ Skill cannot auto-invoke; Codex hooks run command-typed only and skill scripts are not formally hooked | ✓ User runs from terminal | Scripts copied via install-codex.sh into `~/.codex/skills/context-optimization/scripts/`. User invokes manually. |
| **OpenCode** | ✗ (mirror Codex) | ✓ User runs from terminal | Scripts available, manual invocation. |
| **Antigravity (Gemini)** | ✗ Antigravity is markdown-only | ✓ User runs from external terminal | Scripts copied via install-antigravity.sh but the IDE does not invoke them; users open a separate terminal. |

This asymmetry is intentional and documented in `SKILL.md` "Do not use when": Audit mode auto-execution is Claude Code-only. In other harnesses, the skill operates in **Guide mode** (cite techniques + plan) without script-backed evidence; the user can still run scripts manually and paste the output.

## Exit codes

| Code | Meaning |
| :--- | :--- |
| 0 | Success — findings file populated, report generated |
| 1 | Missing required env var (`PROJECT_ROOT`), `lib/report.py` missing, or `PROJECT_ROOT` not a directory |
| 2 | Reserved (currently unused; consistent with `code-security-review/scripts/run-all.sh`) |

Phase scripts that exit non-zero do **not** abort the orchestrator — `run-all.sh` logs a warning and continues. This matches the `code-security-review` pattern: partial findings are better than none.

## Smoke test

```bash
mkdir -p /tmp/test-ctx
echo "# Test\n\nLorem ipsum dolor sit amet" > /tmp/test-ctx/sample.md
echo "# Duplicate\n\nLorem ipsum dolor sit amet" > /tmp/test-ctx/dup.md
bash scripts/run-all.sh /tmp/test-ctx
cat out/report.md
```

Expected: 1+ DUP finding (the two files share content), 1 CTX-SCAN-SUM info finding, 1 TOK-SUM info finding.

## Cross-link

- `SKILL.md` Phase 0.1 — captures inventory; scripts populate it.
- `SKILL.md` Phase 2 — Cost & Quality Audit; script findings seed Block 2.
- `references/HARNESS_NOTES.md` — same portability matrix repeated for completeness in skill body.
- `lib/common.sh` — port of `code-security-review/scripts/lib/common.sh` minus HTTP / target helpers.
- `lib/report.py` — port of `code-security-review/scripts/lib/report.py` adapted for `category` (vs OWASP/endpoint).

# context-optimization / scripts

Auxiliary tooling for evidence-based context audit. Implemented as a single Rust binary `ctxopt` (sources in `ctxopt/`) with subcommands that mirror the legacy phase scripts. TOON v3.0 is the default output format — 30-60% fewer tokens than JSONL when an LLM consumes the findings.

## Why Rust

- Single binary, single source of truth — no Python+bash hybrid; no fallback heuristic for token counts.
- `tiktoken-rs` native cl100k_base / o200k_base counters — exact accuracy, not chars/4.
- 10-100× faster file scan / hash dedup on large repos.
- Pure-Rust dependencies (`sha2`, `walkdir`, `clap`, `serde`, `tiktoken-rs`, `chrono`) — no system C libs to fight.

## Install / build

The repo-root install scripts handle Rust toolchain detection, rustup install (with prompt), `cargo build --release`, and binary copy:

```bash
bash <repo>/scripts/install-plugin-claude.sh
bash <repo>/scripts/install-codex.sh
bash <repo>/scripts/install-antigravity.sh
```

Each of those sources `<repo>/scripts/_lib/ensure-rust.sh` and calls `build_all_skill_binaries` which:

1. Checks for `rustc` + `cargo` on `PATH`. If absent, prompts to install via `rustup` (set `VALARMIND_AUTO_INSTALL_RUST=1` for non-interactive `-y`).
2. Walks every skill under `skills/` looking for a `Cargo.toml`.
3. Runs `cargo build --release` and copies the binary to `<skill>/scripts/bin/<bin-name>`.

### Manual build (without install scripts)

```bash
cd skills/context-optimization/scripts/ctxopt
cargo build --release
mkdir -p ../bin
cp target/release/ctxopt ../bin/ctxopt
```

## Quick start

```bash
# Audit a project root (TOON output by default — 30-60% fewer tokens than JSONL)
PROJECT_ROOT=/path/to/project bash scripts/run-all.sh

# Or via CLI arg
bash scripts/run-all.sh /path/to/project

# Direct binary invocation, with explicit format
scripts/bin/ctxopt run-all /path/to/project --format toon

# Single subcommand
scripts/bin/ctxopt scan /path/to/project --format jsonl
scripts/bin/ctxopt count /path/to/project --encoding cl100k-base
scripts/bin/ctxopt dedup /path/to/project --chunk-lines 50
scripts/bin/ctxopt report /path/to/out/findings.jsonl --format md
```

Outputs land in `./out/` (override with `--out-dir`):

- `findings.toon` (or `.jsonl`/`.json` per `--format`) — one block per phase, all findings merged.
- `findings.jsonl` — sidecar always written when `--format=toon`, used by the aggregator.
- `summary.json` — counts by severity + verdict flags.
- `summary.toon` — same as JSON, ~57% fewer tokens.
- `report.md` — human-readable Markdown report grouped by severity + by phase.

## CLI reference

```
ctxopt <subcommand> [project_root] [--out-dir DIR] [--format toon|jsonl|json] [--verbose|--quiet]

scan       File-size scanner. Lists .md/.json/.jsonl/.txt under project_root,
           ranks top-20 by size, emits findings on offenders > thresholds.
           Flags: --threshold-high BYTES (default 40 KiB)
                  --threshold-medium BYTES (default 20 KiB)
                  --threshold-low BYTES (default 8 KiB)

count      Token counter via tiktoken (cl100k_base default). Emits findings
           on token-budget offenders.
           Flags: --threshold-high-tokens N (default 10,000)
                  --threshold-medium-tokens N (default 5,000)
                  --threshold-low-tokens N (default 2,000)
                  --encoding cl100k-base|o200k-base

dedup      SHA-256 chunk-based duplicate-block detector. Splits files into
           N-line chunks, hashes each, reports groups with ≥ 2 occurrences.
           Flags: --chunk-lines N (default 50)
                  --min-content-chars N (default 50)

run-all    Runs scan + count + dedup, aggregates report.md + summary.{json,toon}.

report     Re-aggregate an existing findings file into Markdown / JSON / TOON
           summary. Useful for re-rendering after editing findings by hand.
           Args: findings_path
           Flags: --format md|toon|json
```

## Output format (TOON v3.0)

`findings.toon` is a uniform array of finding objects — perfect TOON fit (30-60% reduction vs JSONL):

```toon
findings[N]{id,phase,severity,category,target,impact,remediation,timestamp}:
  CTX-SCAN-001	scan	high	bloat	src/big.md	~12000 tokens 6% window	Apply §3 masking	2026-05-07T14:00:00Z
  TOK-001	count	medium	bloat	docs/api.md	~6500 tokens cumulative bloat	Review §10 dedup	2026-05-07T14:00:01Z
  …

evidence_blob:
  - id: CTX-SCAN-001
    json: {"path":"src/big.md","size_bytes":48000,"estimated_tokens":12000,"rank":1}
  …
```

`evidence` is heterogeneous per-finding (varies by phase), so it lands in a secondary `evidence_blob:` block instead of inline columns.

## Portability across harnesses

| Harness | Auto-execution during Audit mode | Manual execution from terminal |
| :--- | :--- | :--- |
| **Claude Code** | ✓ Skill invokes `bash scripts/run-all.sh` via Bash tool. | ✓ Always works. |
| **Codex CLI** | ✗ Codex hooks are command-typed; skill `scripts/` are not formally hooked. | ✓ User runs from terminal. Same `ctxopt` binary built at install time. |
| **OpenCode** | ✗ Mirror Codex. | ✓ User runs from terminal. |
| **Antigravity (Gemini)** | ✗ Markdown-only runtime; binaries copied but not invoked by IDE. | ✓ User opens external terminal and runs the binary directly. |

In environments without auto-execution, the skill operates in **Guide mode** (catalog lookup) without script-backed evidence; the user can paste manual `ctxopt run-all` output to get the same audit.

## Exit codes

| Code | Meaning |
| :--- | :--- |
| 0 | Success — findings file populated, report generated |
| 1 | CLI parse error, missing `PROJECT_ROOT`, unreadable directory, or aggregation failure |

Phase failures inside `run-all` are logged as warnings to stderr but do not abort the run — partial findings are better than none.

## Smoke test

```bash
mkdir -p /tmp/test-ctx
printf '# Sample\n\nLorem ipsum dolor sit amet.\n' > /tmp/test-ctx/a.md
printf '# Duplicate\n\nLorem ipsum dolor sit amet.\n' > /tmp/test-ctx/b.md
bash scripts/run-all.sh /tmp/test-ctx
cat out/report.md
```

Expected: 1+ `CTX-SCAN-*`, 1 `CTX-SCAN-SUM`, 1 `TOK-SUM`, 1 `DUP-SUM` finding (and possibly `DUP-001` if files are large enough to fill a 50-line chunk). Report.md sections include "Summary by severity", "Summary by category", "By phase".

## Cross-link

- `SKILL.md` Phase 1 — captures inventory; this binary populates it.
- `SKILL.md` Phase 2 — Cost & Quality Audit; binary findings seed Block 2.
- `references/HARNESS_NOTES.md` — same portability matrix repeated for completeness.
- `ctxopt/Cargo.toml` — crate manifest.
- `ctxopt/src/` — Rust source: `main.rs` (clap dispatch), `cli.rs`, `finding.rs`, `emit.rs`, `toon.rs`, `scan.rs`, `count.rs`, `dedup.rs`, `report.rs`.
- `scripts/_lib/ensure-rust.sh` (repo root) — install-time toolchain check + `cargo build` orchestrator.

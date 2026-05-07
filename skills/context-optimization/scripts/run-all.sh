#!/usr/bin/env bash
# run-all.sh — Orchestrator for context-optimization audit scripts.
#
# Runs 00-context-scan.sh → 01-token-count.py → 02-dedup-detect.sh in sequence,
# then aggregates findings into out/report.md + out/summary.json.
#
# Usage:
#   PROJECT_ROOT=/path/to/project bash scripts/run-all.sh
#   bash scripts/run-all.sh /path/to/project        # CLI arg also accepted
#
# Reads:  PROJECT_ROOT (env or first CLI arg), OUT_DIR (env, default ./out)
# Writes: out/findings.jsonl, out/report.md, out/summary.json

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Accept PROJECT_ROOT via CLI arg if not in env
if [ -z "${PROJECT_ROOT:-}" ] && [ $# -ge 1 ]; then
  export PROJECT_ROOT="$1"
fi

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_env PROJECT_ROOT
ensure_project_root_readable

# ---------------------------------------------------------------------------
# Reset findings file for a fresh run (back up previous if it exists)
# ---------------------------------------------------------------------------
if [ -s "$FINDINGS_FILE" ]; then
  backup="$OUT_DIR/findings.$(date +%Y%m%d-%H%M%S).jsonl"
  mv "$FINDINGS_FILE" "$backup"
  log_info "Previous findings backed up to $backup"
fi
: > "$FINDINGS_FILE"

# ---------------------------------------------------------------------------
# Run phases
# ---------------------------------------------------------------------------
phases=(
  "00-context-scan.sh"
  "01-token-count.py"
  "02-dedup-detect.sh"
)

run_phase() {
  local script="$1"
  local path="$SCRIPT_DIR/$script"
  if [ ! -f "$path" ]; then
    log_warn "Skipping $script — file not found"
    return 0
  fi

  log_info "============================================================"
  log_info "Running $script"
  log_info "============================================================"

  case "$script" in
    *.py)
      if ! python3 "$path"; then
        log_warn "$script exited non-zero (continuing)"
      fi
      ;;
    *.sh)
      if ! bash "$path"; then
        log_warn "$script exited non-zero (continuing)"
      fi
      ;;
  esac
}

for phase in "${phases[@]}"; do
  run_phase "$phase"
done

# ---------------------------------------------------------------------------
# Aggregate
# ---------------------------------------------------------------------------
log_info "============================================================"
log_info "Aggregating findings..."
log_info "============================================================"

if [ ! -f "$SCRIPT_DIR/lib/report.py" ]; then
  log_error "lib/report.py not found — cannot aggregate."
  exit 1
fi

python3 "$SCRIPT_DIR/lib/report.py" "$FINDINGS_FILE" > "$OUT_DIR/report.md"
python3 "$SCRIPT_DIR/lib/report.py" "$FINDINGS_FILE" --json > "$OUT_DIR/summary.json"

# ---------------------------------------------------------------------------
# Summary line for stdout
# ---------------------------------------------------------------------------
total_findings=$(wc -l < "$FINDINGS_FILE" | tr -d ' ')
log_ok "Run complete. $total_findings finding(s) recorded."
log_dim "  Markdown report: $OUT_DIR/report.md"
log_dim "  JSON summary:    $OUT_DIR/summary.json"
log_dim "  Raw findings:    $FINDINGS_FILE"

cat "$OUT_DIR/summary.json"

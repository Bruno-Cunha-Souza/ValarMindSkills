#!/usr/bin/env bash
# Orchestrator — runs all probe phases in order, then aggregates findings into report.md.
#
# AUTHORIZATION REQUIRED: set I_HAVE_AUTHORIZATION=1 to confirm you have written
# permission to test the target. Refuses to run otherwise.
#
# Reads:  TARGET, I_HAVE_AUTHORIZATION, plus per-script env vars (see README.md)
# Writes: out/findings.jsonl, out/report.md, out/summary.json

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_env TARGET

# ---------------------------------------------------------------------------
# Authorization gate
# ---------------------------------------------------------------------------
if [ "${I_HAVE_AUTHORIZATION:-}" != "1" ]; then
  log_error "Refusing to run without explicit authorization."
  log_dim ""
  log_dim "These probes send real attack-shaped traffic to $TARGET."
  log_dim "Running without authorization is a crime in most jurisdictions."
  log_dim ""
  log_dim "If you have written permission to test (pentest agreement, bug bounty"
  log_dim "scope, ownership of the target), set:"
  log_dim ""
  log_dim "    export I_HAVE_AUTHORIZATION=1"
  log_dim ""
  log_dim "and rerun."
  exit 2
fi

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
  "00-pre-checks.sh"
  "01-auth-probes.sh"
  "02-jwt-attacks.py"
  "03-bola-probes.sh"
  "04-injection-probes.sh"
  "05-rate-limit.sh"
  "06-info-disclosure.sh"
  "07-supply-chain.sh"
  "08-cors-headers.sh"
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
# Summary line for CI consumption
# ---------------------------------------------------------------------------
total_findings=$(wc -l < "$FINDINGS_FILE" | tr -d ' ')
log_ok "Run complete. $total_findings finding(s) recorded."
log_dim "  Markdown report: $OUT_DIR/report.md"
log_dim "  JSON summary:    $OUT_DIR/summary.json"
log_dim "  Raw findings:    $FINDINGS_FILE"

# Print one-line summary to stdout for CI
if command -v jq >/dev/null 2>&1; then
  jq -s '{
    total:    length,
    critical: ([.[] | select(.severity == "critical")] | length),
    high:     ([.[] | select(.severity == "high")]     | length),
    medium:   ([.[] | select(.severity == "medium")]   | length),
    low:      ([.[] | select(.severity == "low")]      | length),
    info:     ([.[] | select(.severity == "info")]     | length)
  }' "$FINDINGS_FILE"
else
  cat "$OUT_DIR/summary.json"
fi

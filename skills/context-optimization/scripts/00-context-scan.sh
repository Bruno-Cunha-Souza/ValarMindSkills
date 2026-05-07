#!/usr/bin/env bash
# 00-context-scan.sh — File-size scanner for context candidates.
#
# Lists .md / .json / .jsonl / .txt files in PROJECT_ROOT, measures bytes,
# ranks top-20 offenders. Emits findings.jsonl with id CTX-SCAN-NNN per
# offender exceeding size thresholds.
#
# Reads:  PROJECT_ROOT (env), ./out/findings.jsonl (appends)
# Writes: ./out/findings.jsonl
#
# Pure bash — no external deps beyond find / wc / sort / awk.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_env PROJECT_ROOT
ensure_project_root_readable

# Thresholds (bytes; rough proxy for tokens — assume 1 token ≈ 4 chars ≈ 4 bytes)
THRESHOLD_HIGH=$((40 * 1024))     # ~10k tokens
THRESHOLD_MEDIUM=$((20 * 1024))   # ~5k tokens
THRESHOLD_LOW=$((8 * 1024))       # ~2k tokens

log_info "Scanning $PROJECT_ROOT for context candidates ..."

# Collect file list (markdown, json, jsonl, txt) sorted by size descending
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

find "$PROJECT_ROOT" \
  -type f \
  \( -name "*.md" -o -name "*.json" -o -name "*.jsonl" -o -name "*.txt" \) \
  -not -path "*/.git/*" \
  -not -path "*/node_modules/*" \
  -not -path "*/.venv/*" \
  -not -path "*/__pycache__/*" \
  -not -path "*/out/*" \
  -print0 2>/dev/null \
  | xargs -0 wc -c 2>/dev/null \
  | grep -v ' total$' \
  | awk '{print $1, $2}' \
  | sort -rn \
  > "$TMPFILE" || true

total_files=$(wc -l < "$TMPFILE" | tr -d ' ')
log_info "Found $total_files candidate files."

if [ "$total_files" -eq 0 ]; then
  log_ok "No context candidates found in $PROJECT_ROOT"
  exit 0
fi

total_bytes=0
counter=0

while IFS=' ' read -r size path; do
  counter=$((counter + 1))
  total_bytes=$((total_bytes + size))

  # Only file findings on top-20 offenders to avoid noise
  [ "$counter" -gt 20 ] && continue

  rel_path="${path#"$PROJECT_ROOT"/}"
  est_tokens=$((size / 4))

  if [ "$size" -ge "$THRESHOLD_HIGH" ]; then
    severity="high"
    impact="File alone consumes ~$est_tokens tokens (~$((size/1024))KB). On a 200k window, this is $((est_tokens * 100 / 200000))% of total budget."
    remediation="Apply §3 observation masking if this file is a tool output, or §6 verbatim deletion if citation-bound. For source code in audit scope, consider §7 partitioning."
  elif [ "$size" -ge "$THRESHOLD_MEDIUM" ]; then
    severity="medium"
    impact="File consumes ~$est_tokens tokens. Cumulative bloat across multiple files this size adds up."
    remediation="Review for dedup opportunities (§10) and unused content."
  elif [ "$size" -ge "$THRESHOLD_LOW" ]; then
    severity="low"
    impact="File consumes ~$est_tokens tokens — within typical budget but contributes to total."
    remediation="Track across runs; flag if this category grows."
  else
    continue  # below threshold, skip
  fi

  evidence=$(build_evidence \
    "path=$rel_path" \
    "size_bytes=$size" \
    "estimated_tokens=$est_tokens" \
    "rank=$counter")

  finding_id="CTX-SCAN-$(printf '%03d' "$counter")"
  emit_finding "$finding_id" "$severity" "bloat" "$rel_path" "$impact" "$remediation" "$evidence"
done < "$TMPFILE"

# Summary finding (always emit, info-level)
total_kb=$((total_bytes / 1024))
total_est_tokens=$((total_bytes / 4))
summary_evidence=$(build_evidence \
  "total_files=$total_files" \
  "total_bytes=$total_bytes" \
  "total_kb=$total_kb" \
  "estimated_total_tokens=$total_est_tokens")

emit_finding "CTX-SCAN-SUM" "info" "bloat" "$PROJECT_ROOT" \
  "Scanned $total_files files totalling ~$total_kb KB (~$total_est_tokens tokens)" \
  "Use this as the Phase 1 inventory baseline. Compare to use-case ceiling per Phase 5.3." \
  "$summary_evidence"

log_ok "Context scan complete. Top-20 offenders + summary written to $FINDINGS_FILE"

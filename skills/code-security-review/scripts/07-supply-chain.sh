#!/usr/bin/env bash
# Phase 6 — Supply chain audit.
# Auto-detects stack from PROJECT_ROOT and runs the appropriate scanner.
#
# Reads:
#   PROJECT_ROOT (default $PWD)   — directory containing requirements.txt / go.mod / package.json / Cargo.toml
# Writes: out/findings.jsonl
#
# Tools probed (each is optional — finding emitted only when tool is present AND vulns are reported):
#   pip-audit       — Python
#   govulncheck     — Go
#   bun audit       — Bun / Node
#   npm audit       — Node fallback
#   cargo audit     — Rust
#   osv-scanner     — universal cross-stack

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

PROJECT_ROOT="${PROJECT_ROOT:-$PWD}"
log_info "Project root: $PROJECT_ROOT"

emit_supply_chain() {
  local id="$1" tool="$2" stack="$3" raw_excerpt="$4"
  local excerpt
  excerpt="$(printf '%s' "$raw_excerpt" | head -c 600 | tr -d '\000-\031')"
  local evidence
  evidence="$(build_evidence "tool=$tool" "stack=$stack" "output_excerpt=$excerpt")"
  emit_finding \
    "$id" "high" "A03:2025 Software Supply Chain Failures" \
    "$stack project at $PROJECT_ROOT" \
    "$tool reported vulnerable dependencies in the project. Severity should be assessed per-CVE; treating as High by default." \
    "Upgrade affected packages. In CI, fail the build on vuln-bearing dependencies. Pin versions and use lockfile-with-hashes (pip-audit --require-hashes, bun --frozen-lockfile, go.sum)." \
    "$evidence"
}

ran_any=0

# ---------------------------------------------------------------------------
# Python
# ---------------------------------------------------------------------------
if [ -f "$PROJECT_ROOT/requirements.txt" ] || [ -f "$PROJECT_ROOT/pyproject.toml" ] || [ -f "$PROJECT_ROOT/Pipfile" ]; then
  if command -v pip-audit >/dev/null 2>&1; then
    log_info "Running pip-audit..."
    ran_any=1
    if ! out=$(cd "$PROJECT_ROOT" && pip-audit 2>&1); then
      if echo "$out" | grep -qiE 'found [0-9]+ known vulnerabilit|vulnerability'; then
        emit_supply_chain "SUPPLY-PY-001" "pip-audit" "Python" "$out"
      else
        log_warn "pip-audit exited with errors but no vuln pattern found:"
        log_dim "$(printf '%s' "$out" | head -c 400)"
      fi
    fi
  else
    log_warn "Python project detected but pip-audit not installed — skipping. (pip install pip-audit)"
  fi
fi

# ---------------------------------------------------------------------------
# Go
# ---------------------------------------------------------------------------
if [ -f "$PROJECT_ROOT/go.mod" ]; then
  if command -v govulncheck >/dev/null 2>&1; then
    log_info "Running govulncheck..."
    ran_any=1
    if ! out=$(cd "$PROJECT_ROOT" && govulncheck ./... 2>&1); then
      if echo "$out" | grep -qiE 'vulnerability|GO-[0-9]{4}-[0-9]+'; then
        emit_supply_chain "SUPPLY-GO-001" "govulncheck" "Go" "$out"
      fi
    fi
  else
    log_warn "Go project detected but govulncheck not installed — skipping. (go install golang.org/x/vuln/cmd/govulncheck@latest)"
  fi
fi

# ---------------------------------------------------------------------------
# Bun / Node
# ---------------------------------------------------------------------------
if [ -f "$PROJECT_ROOT/package.json" ]; then
  if command -v bun >/dev/null 2>&1 && { [ -f "$PROJECT_ROOT/bun.lockb" ] || [ -f "$PROJECT_ROOT/bun.lock" ]; }; then
    log_info "Running bun audit..."
    ran_any=1
    if ! out=$(cd "$PROJECT_ROOT" && bun audit 2>&1); then
      if echo "$out" | grep -qiE 'vulnerability|critical|high|moderate'; then
        emit_supply_chain "SUPPLY-BUN-001" "bun audit" "Bun" "$out"
      fi
    fi
  elif command -v npm >/dev/null 2>&1; then
    log_info "Running npm audit..."
    ran_any=1
    if ! out=$(cd "$PROJECT_ROOT" && npm audit --audit-level=high 2>&1); then
      if echo "$out" | grep -qiE 'vulnerability|critical|high'; then
        emit_supply_chain "SUPPLY-NPM-001" "npm audit" "Node" "$out"
      fi
    fi
  else
    log_warn "Node project detected but neither bun nor npm available."
  fi
fi

# ---------------------------------------------------------------------------
# Rust
# ---------------------------------------------------------------------------
if [ -f "$PROJECT_ROOT/Cargo.toml" ]; then
  if command -v cargo-audit >/dev/null 2>&1 || cargo audit --version >/dev/null 2>&1; then
    log_info "Running cargo audit..."
    ran_any=1
    if ! out=$(cd "$PROJECT_ROOT" && cargo audit 2>&1); then
      if echo "$out" | grep -qiE 'vulnerability|advisory|RUSTSEC'; then
        emit_supply_chain "SUPPLY-RS-001" "cargo audit" "Rust" "$out"
      fi
    fi
  else
    log_warn "Rust project detected but cargo-audit not installed — skipping. (cargo install cargo-audit)"
  fi
fi

# ---------------------------------------------------------------------------
# Universal: osv-scanner
# ---------------------------------------------------------------------------
if command -v osv-scanner >/dev/null 2>&1; then
  log_info "Running osv-scanner (cross-stack)..."
  ran_any=1
  if ! out=$(cd "$PROJECT_ROOT" && osv-scanner --recursive . 2>&1); then
    if echo "$out" | grep -qiE 'CVE-|GHSA-|RUSTSEC|PYSEC|GO-'; then
      emit_supply_chain "SUPPLY-OSV-001" "osv-scanner" "multi" "$out"
    fi
  fi
fi

if [ "$ran_any" = "0" ]; then
  log_warn "No supply-chain scanner ran. Install at least one of: pip-audit, govulncheck, bun, npm, cargo-audit, osv-scanner."
fi

# ---------------------------------------------------------------------------
# Lockfile pinning (static — no scanner needed). A03:2025 dependency integrity.
# ---------------------------------------------------------------------------
log_info "Checking dependency lockfile pinning..."

# package.json without any lockfile → unpinned transitive deps.
if [ -f "$PROJECT_ROOT/package.json" ]; then
  if [ ! -f "$PROJECT_ROOT/package-lock.json" ] && \
     [ ! -f "$PROJECT_ROOT/bun.lock" ] && \
     [ ! -f "$PROJECT_ROOT/bun.lockb" ] && \
     [ ! -f "$PROJECT_ROOT/yarn.lock" ] && \
     [ ! -f "$PROJECT_ROOT/pnpm-lock.yaml" ]; then
    emit_finding \
      "SUPPLY-LOCK-001" "medium" "A03:2025 Software Supply Chain Failures / CWE-494" \
      "package.json at $PROJECT_ROOT" \
      "package.json present without any lockfile. Transitive dependency versions are unpinned, so a malicious or yanked release can enter the build silently." \
      "Commit a lockfile (npm: package-lock.json + 'npm ci'; bun: bun.lock; pnpm/yarn equivalents). In CI use the frozen-install flag." \
      "$(build_evidence "file=package.json" "lockfile=missing")"
  fi
fi

# requirements.txt with unpinned (no '==' and no hash) requirement lines.
if [ -f "$PROJECT_ROOT/requirements.txt" ]; then
  unpinned="$(grep -vE '^\s*(#|-r |--|$)' "$PROJECT_ROOT/requirements.txt" 2>/dev/null \
    | grep -vE '==|@|--hash' | sed 's/[[:space:]]*$//' | grep -cvE '^$' || true)"
  if [ "${unpinned:-0}" -gt 0 ]; then
    emit_finding \
      "SUPPLY-LOCK-002" "low" "A03:2025 Software Supply Chain Failures / CWE-494" \
      "requirements.txt at $PROJECT_ROOT" \
      "$unpinned requirement line(s) are not pinned with '==' or a hash. Unpinned versions resolve to whatever is current at install time, widening the supply-chain window." \
      "Pin exact versions ('pkg==1.2.3') and prefer hashed installs ('pip install --require-hashes')." \
      "$(build_evidence "file=requirements.txt" "unpinned_lines=$unpinned")"
  fi
fi

# Cargo.toml (binary crate) without Cargo.lock.
if [ -f "$PROJECT_ROOT/Cargo.toml" ] && [ ! -f "$PROJECT_ROOT/Cargo.lock" ]; then
  emit_finding \
    "SUPPLY-LOCK-003" "low" "A03:2025 Software Supply Chain Failures / CWE-494" \
    "Cargo.toml at $PROJECT_ROOT" \
    "Cargo.toml present without Cargo.lock. For a binary crate this leaves dependency versions unpinned across builds." \
    "Commit Cargo.lock for binaries; in CI build with '--locked' to fail on drift." \
    "$(build_evidence "file=Cargo.toml" "lockfile=missing")"
fi

log_ok "Supply chain audit complete."

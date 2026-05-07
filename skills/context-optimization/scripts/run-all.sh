#!/usr/bin/env bash
# Thin shim: invoke the ctxopt Rust binary's run-all subcommand.
#
# Build/install: handled by repo-root install scripts via scripts/_lib/ensure-rust.sh
# (see scripts/README.md for manual build instructions).
#
# Usage:
#   PROJECT_ROOT=/path/to/project bash scripts/run-all.sh
#   bash scripts/run-all.sh /path/to/project          # CLI arg also accepted

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$SCRIPT_DIR/bin/ctxopt"

if [ ! -x "$BIN" ]; then
  cat >&2 <<EOF
[ctxopt] Binary not built at $BIN.

To build manually:
  cd $SCRIPT_DIR/ctxopt && cargo build --release
  mkdir -p $SCRIPT_DIR/bin
  cp $SCRIPT_DIR/ctxopt/target/release/ctxopt $SCRIPT_DIR/bin/

Or re-run the repo-root install for your harness:
  bash <repo>/scripts/install-plugin-claude.sh
  bash <repo>/scripts/install-codex.sh
  bash <repo>/scripts/install-antigravity.sh

These invoke scripts/_lib/ensure-rust.sh, which detects/installs Rust and
builds every skill's bin/ automatically.
EOF
  exit 1
fi

# Accept PROJECT_ROOT via CLI arg if not in env (back-compat with legacy entrypoint).
if [ -z "${PROJECT_ROOT:-}" ] && [ $# -ge 1 ]; then
  PROJECT_ROOT="$1"
  shift
fi

if [ -z "${PROJECT_ROOT:-}" ]; then
  echo "[ctxopt] PROJECT_ROOT env var or first CLI arg required." >&2
  exit 1
fi

exec "$BIN" run-all "$PROJECT_ROOT" "$@"

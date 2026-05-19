#!/usr/bin/env bash

# ValarMindSkills — one-shot bootstrap installer.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Bruno-Cunha-Souza/ValarMindSkills/main/install.sh | bash
#
# Behaviour:
#   - Resolves the latest GitHub release (or $VALARMIND_VERSION if set).
#   - Downloads the source tarball into $VALARMIND_INSTALL_DIR
#     (default: ~/.valarmindskills).
#   - Runs scripts/install-all.sh which wires up Claude Code, Codex CLI,
#     Antigravity, and Cursor IDE (each step is independently graceful —
#     missing CLIs are skipped, not fatal).
#
# Environment overrides:
#   VALARMIND_VERSION       Specific tag (e.g. v0.1.0). Default: latest.
#   VALARMIND_INSTALL_DIR   Target directory.            Default: ~/.valarmindskills.
#   VALARMIND_REPO          owner/repo override.         Default: Bruno-Cunha-Souza/ValarMindSkills.
#   VALARMIND_SKIP_INSTALL  If "1", download only — do not run install-all.sh.

set -euo pipefail

REPO="${VALARMIND_REPO:-Bruno-Cunha-Souza/ValarMindSkills}"
INSTALL_DIR="${VALARMIND_INSTALL_DIR:-$HOME/.valarmindskills}"
VERSION="${VALARMIND_VERSION:-latest}"

log() { printf '[valarmind] %s\n' "$*"; }
err() { printf '[valarmind] error: %s\n' "$*" >&2; }

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "missing required command: $1"
    exit 1
  fi
}

require_cmd curl
require_cmd tar

# --------------------------------------------------------------------
# 1. Resolve target version
# --------------------------------------------------------------------
if [ "$VERSION" = "latest" ]; then
  log "resolving latest release for $REPO"
  api_url="https://api.github.com/repos/$REPO/releases/latest"

  # Bash 3.2 (macOS default) treats empty arrays as unset under `set -u`,
  # so split the call instead of expanding an empty auth_header array.
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    resolved=$(curl -fsSL \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      "$api_url" \
      | grep -m1 '"tag_name"' \
      | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
  else
    resolved=$(curl -fsSL \
      -H "Accept: application/vnd.github+json" \
      "$api_url" \
      | grep -m1 '"tag_name"' \
      | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
  fi

  if [ -z "$resolved" ]; then
    err "could not resolve latest release tag from $api_url"
    err "set VALARMIND_VERSION=<tag> to override, or check rate limits / repo visibility"
    exit 1
  fi

  VERSION="$resolved"
fi

log "version: $VERSION"
log "target:  $INSTALL_DIR"

# --------------------------------------------------------------------
# 2. Download tarball
# --------------------------------------------------------------------
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

tarball_url="https://github.com/$REPO/archive/refs/tags/$VERSION.tar.gz"
log "downloading $tarball_url"

if ! curl -fsSL "$tarball_url" -o "$TMP_DIR/source.tar.gz"; then
  err "download failed for tag $VERSION"
  err "check that the release exists: https://github.com/$REPO/releases"
  exit 1
fi

# --------------------------------------------------------------------
# 3. Extract into install dir (idempotent — wipe & repopulate)
# --------------------------------------------------------------------
mkdir -p "$INSTALL_DIR"

# Refuse to wipe a directory that is not previously a ValarMindSkills install,
# unless it is empty. Heuristic: presence of scripts/install-all.sh.
if [ -n "$(ls -A "$INSTALL_DIR" 2>/dev/null || true)" ] \
   && [ ! -f "$INSTALL_DIR/scripts/install-all.sh" ]; then
  err "$INSTALL_DIR is not empty and does not look like a ValarMindSkills install."
  err "remove it or set VALARMIND_INSTALL_DIR to a different path."
  exit 1
fi

log "extracting into $INSTALL_DIR"
# Clear previous content (safe — verified above) before extracting fresh tree.
find "$INSTALL_DIR" -mindepth 1 -delete
tar -xzf "$TMP_DIR/source.tar.gz" -C "$INSTALL_DIR" --strip-components=1

# --------------------------------------------------------------------
# 4. Run install-all.sh
# --------------------------------------------------------------------
if [ "${VALARMIND_SKIP_INSTALL:-0}" = "1" ]; then
  log "VALARMIND_SKIP_INSTALL=1 — skipping scripts/install-all.sh"
  log "done. Source available at $INSTALL_DIR"
  exit 0
fi

installer="$INSTALL_DIR/scripts/install-all.sh"
if [ ! -f "$installer" ]; then
  err "expected installer not found: $installer"
  exit 1
fi

chmod +x "$INSTALL_DIR"/scripts/*.sh 2>/dev/null || true

log "running $installer"
echo ""
bash "$installer"

echo ""
log "done. Source available at $INSTALL_DIR"

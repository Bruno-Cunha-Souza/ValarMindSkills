#!/bin/bash

# Persistent install of the ValarMindSkills plugin in Claude Code CLI.
# Registers the repository as a local marketplace and installs the
# `valarmind@valarmind` plugin, which wires up:
#   - All skills under skills/<slug>/
#   - Caveman auto-activation hooks (SessionStart + UserPromptSubmit)
#
# Exports slash commands as /valarmind:<slug> (plugin namespace).

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MARKETPLACE_NAME="valarmind"
PLUGIN_REF="valarmind@valarmind"

echo "========================================"
echo " ValarMindSkills — Plugin Install"
echo "========================================"
echo "Repository: $REPO_DIR"
echo ""

if ! command -v claude >/dev/null 2>&1; then
  echo "Error: 'claude' CLI not found in PATH."
  echo "Install Claude Code first: https://docs.claude.com/en/docs/claude-code"
  exit 1
fi

for f in ".claude-plugin/plugin.json" ".claude-plugin/marketplace.json"; do
  if [ ! -f "$REPO_DIR/$f" ]; then
    echo "Error: missing $f. Re-clone the repo or check file layout."
    exit 1
  fi
done

echo "Step 1/3 — validating manifests"
claude plugins validate "$REPO_DIR" || {
  echo "Error: plugin/marketplace validation failed."
  exit 1
}

echo ""
echo "Step 2/3 — registering local marketplace"
if claude plugins marketplace list 2>/dev/null | grep -q "^$MARKETPLACE_NAME\b"; then
  echo "Marketplace '$MARKETPLACE_NAME' already registered — updating"
  claude plugins marketplace update "$MARKETPLACE_NAME" || true
else
  claude plugins marketplace add "$REPO_DIR"
fi

echo ""
echo "Step 3/3 — installing plugin $PLUGIN_REF"
if claude plugins list 2>/dev/null | grep -q "$PLUGIN_REF"; then
  echo "Plugin '$PLUGIN_REF' already installed — updating"
  claude plugins update "$PLUGIN_REF" || true
else
  claude plugins install "$PLUGIN_REF"
fi

echo ""
echo "========================================"
echo " Plugin installed."
echo "========================================"
echo ""
echo "Slash commands: /$MARKETPLACE_NAME:<skill>"
echo "  e.g. /$MARKETPLACE_NAME:caveman, /$MARKETPLACE_NAME:caveman-commit"
echo ""
echo "Caveman auto-activation: ON (default level = full)."
echo "Override via env: export CAVEMAN_DEFAULT_MODE=lite|full|ultra|off"
echo "Or create ~/.config/caveman/config.json with {\"defaultMode\": \"lite\"}"
echo ""
echo "Statusline badge [CAVEMAN] (optional) — add to ~/.claude/settings.json:"
echo "  \"statusLine\": {"
echo "    \"type\": \"command\","
echo "    \"command\": \"bash \\\"$REPO_DIR/hooks/caveman/caveman-statusline.sh\\\"\""
echo "  }"
echo ""
echo "Start a new Claude Code session to load the hooks."

#!/bin/bash

# Persistent install of the ValarMindSkills plugin in Claude Code CLI.
# Registers the repository as a local marketplace and installs the
# `valarmindskills@valarmindskills` plugin, which wires up:
#   - All skills under skills/<slug>/
#   - Caveman auto-activation hooks (SessionStart + UserPromptSubmit)
#
# Exports slash commands as /valarmindskills:<slug> (plugin namespace).

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MARKETPLACE_NAME="valarmindskills"
PLUGIN_REF="valarmindskills@valarmindskills"

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

echo "Step 1/4 — validating manifests"
claude plugins validate "$REPO_DIR" || {
  echo "Error: plugin/marketplace validation failed."
  exit 1
}

echo ""
echo "Step 2/4 — registering local marketplace"
if claude plugins marketplace list 2>/dev/null | grep -qE "[[:space:]]${MARKETPLACE_NAME}\$"; then
  echo "Marketplace '$MARKETPLACE_NAME' already registered — updating"
  claude plugins marketplace update "$MARKETPLACE_NAME" || true
else
  claude plugins marketplace add "$REPO_DIR"
fi

echo ""
echo "Step 3/4 — installing plugin $PLUGIN_REF"
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
echo "Caveman auto-activation: ON (default level = lite)."
echo "Override via env: export CAVEMAN_DEFAULT_MODE=lite|full|ultra|off"
echo "Or create ~/.config/caveman/config.json with {\"defaultMode\": \"full\"}"
echo ""
echo "Superpowers auto-activation: OFF (default mode = off)."
echo "Activate per-session: /valarmindskills:superpowers on"
echo "Override default via env: export SUPERPOWERS_DEFAULT_MODE=on"
echo "Or create ~/.config/superpowers/config.json with {\"defaultMode\": \"on\"}"
echo ""
echo "Obsidian-brain auto-activation: ON when CLAUDE.md/AGENTS.md references a vault."
echo "Disable per-session: /valarmindskills:obsidian-brain off"
echo "Override default via env: export OBSIDIAN_BRAIN_DEFAULT_MODE=off"
echo "Or create ~/.config/obsidian-brain/config.json with {\"defaultMode\": \"off\"}"
echo ""
echo "Step 4/4 — configuring statusline (caveman + superpowers + obsidian-brain badges + context window usage)"
SETTINGS_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
STATUSLINE_CMD="bash \"$REPO_DIR/hooks/statusline/statusline.sh\""
STATUSLINE_SNIPPET="\"statusLine\": { \"type\": \"command\", \"command\": \"bash \\\"$REPO_DIR/hooks/statusline/statusline.sh\\\"\" }"

if [ "${VALARMIND_SKIP_STATUSLINE:-0}" = "1" ]; then
  echo "  VALARMIND_SKIP_STATUSLINE=1 set — leaving settings.json untouched."
elif ! command -v jq >/dev/null 2>&1; then
  echo "  jq not found — skipping automatic configuration."
  echo "  Manually add to $SETTINGS_FILE:"
  echo "    $STATUSLINE_SNIPPET"
else
  mkdir -p "$SETTINGS_DIR"
  if [ ! -f "$SETTINGS_FILE" ]; then
    jq -n --arg cmd "$STATUSLINE_CMD" \
      '{statusLine: {type: "command", command: $cmd}}' > "$SETTINGS_FILE"
    echo "  Created $SETTINGS_FILE with statusLine."
  else
    if ! jq -e . "$SETTINGS_FILE" >/dev/null 2>&1; then
      echo "  Warning: $SETTINGS_FILE is not valid JSON — skipping automatic config."
      echo "  Fix it manually, then add: $STATUSLINE_SNIPPET"
    else
      has_sl=$(jq -r 'has("statusLine")' "$SETTINGS_FILE")
      if [ "$has_sl" = "true" ]; then
        current_cmd=$(jq -r '.statusLine.command // ""' "$SETTINGS_FILE")
        if [ "$current_cmd" = "$STATUSLINE_CMD" ]; then
          echo "  Statusline already configured — no changes."
        elif [[ "$current_cmd" == *"$REPO_DIR/hooks/"*"statusline"* ]] \
          || [[ "$current_cmd" == *"$REPO_DIR/hooks/caveman/caveman-statusline.sh"* ]]; then
          backup="$SETTINGS_FILE.bak.$(date +%Y%m%d%H%M%S)"
          cp "$SETTINGS_FILE" "$backup"
          tmp=$(mktemp)
          jq --arg cmd "$STATUSLINE_CMD" \
            '.statusLine = {type: "command", command: $cmd}' "$SETTINGS_FILE" > "$tmp" \
            && mv "$tmp" "$SETTINGS_FILE"
          echo "  Upgraded ValarMind statusLine to new path (backup: $backup)."
          echo "    old: $current_cmd"
          echo "    new: $STATUSLINE_CMD"
        else
          echo "  statusLine already present with a different command — leaving as-is."
          echo "    current: $current_cmd"
          echo "    new:     $STATUSLINE_CMD"
          echo "  To switch, edit $SETTINGS_FILE manually or remove the existing statusLine and re-run."
        fi
      else
        backup="$SETTINGS_FILE.bak.$(date +%Y%m%d%H%M%S)"
        cp "$SETTINGS_FILE" "$backup"
        tmp=$(mktemp)
        jq --arg cmd "$STATUSLINE_CMD" \
          '.statusLine = {type: "command", command: $cmd}' "$SETTINGS_FILE" > "$tmp" \
          && mv "$tmp" "$SETTINGS_FILE"
        echo "  Added statusLine to $SETTINGS_FILE (backup: $backup)."
      fi
    fi
  fi
fi

echo ""
echo "Start a new Claude Code session to load the hooks."

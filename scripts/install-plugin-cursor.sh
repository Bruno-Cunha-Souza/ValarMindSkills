#!/bin/bash

# Full plugin install for Cursor IDE
# Installs: skills → ~/.cursor/skills/, hooks → ~/.cursor/hooks/ + hooks.json

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_SKILLS="$REPO_DIR/skills"
SOURCE_HOOKS="$REPO_DIR/hooks"
CURSOR_HOME="${CURSOR_HOME:-$HOME/.cursor}"
SKILLS_TARGET="$CURSOR_HOME/skills"
HOOKS_TARGET="$CURSOR_HOME/hooks"
HOOKS_JSON="$CURSOR_HOME/hooks.json"

# shellcheck source=_lib/ensure-rust.sh
source "$SCRIPT_DIR/_lib/ensure-rust.sh"

echo "Installing ValarMindSkills plugin in Cursor IDE..."
echo "CURSOR_HOME: $CURSOR_HOME"
echo ""

# ──────────────────────────────────────────────────────────────
# Step 1/2 — Skills
# ──────────────────────────────────────────────────────────────
echo "=== Step 1/2: Skills ==="

build_all_skill_binaries "$SOURCE_SKILLS"

mkdir -p "$SKILLS_TARGET"

installed_skills=()
for skill_dir in "$SOURCE_SKILLS"/*/; do
  [ -f "$skill_dir/SKILL.md" ] || continue
  slug="$(basename "$skill_dir")"
  dest="$SKILLS_TARGET/$slug"
  rm -rf "$dest"
  cp -R "$skill_dir" "$dest"
  installed_skills+=("$slug")
done

pruned_skills=()
if [ -d "$SKILLS_TARGET" ]; then
  for existing_dir in "$SKILLS_TARGET"/*/; do
    [ -d "$existing_dir" ] || continue
    existing_slug="$(basename "$existing_dir")"
    found=0
    for installed in "${installed_skills[@]}"; do
      if [ "$installed" = "$existing_slug" ]; then
        found=1
        break
      fi
    done
    if [ "$found" -eq 0 ]; then
      rm -rf "$existing_dir"
      pruned_skills+=("$existing_slug")
    fi
  done
fi

echo "Installed ${#installed_skills[@]} skills → $SKILLS_TARGET"
if [ "${#pruned_skills[@]}" -gt 0 ]; then
  echo "Pruned ${#pruned_skills[@]} stale skill(s): ${pruned_skills[*]}"
fi

# ──────────────────────────────────────────────────────────────
# Step 2/2 — Hooks
# ──────────────────────────────────────────────────────────────
if [ "${VALARMIND_SKIP_HOOKS:-0}" = "1" ]; then
  echo ""
  echo "VALARMIND_SKIP_HOOKS=1 — skipping hooks."
  echo ""
  echo "Done! Restart Cursor to load skills."
  exit 0
fi

echo ""
echo "=== Step 2/2: Hooks ==="

mkdir -p "$HOOKS_TARGET/caveman"
mkdir -p "$HOOKS_TARGET/superpowers"
mkdir -p "$HOOKS_TARGET/obsidian-brain"
mkdir -p "$HOOKS_TARGET/_cursor"
mkdir -p "$HOOKS_TARGET/_lib"

cp "$SOURCE_HOOKS/caveman/"*.js        "$HOOKS_TARGET/caveman/"
cp "$SOURCE_HOOKS/superpowers/"*.js    "$HOOKS_TARGET/superpowers/"
cp "$SOURCE_HOOKS/obsidian-brain/"*.js "$HOOKS_TARGET/obsidian-brain/"
cp "$SOURCE_HOOKS/_cursor/"*.sh        "$HOOKS_TARGET/_cursor/"
cp "$SOURCE_HOOKS/_lib/"*.js           "$HOOKS_TARGET/_lib/"
chmod +x "$HOOKS_TARGET/_cursor/"*.sh

echo "Hook scripts copied → $HOOKS_TARGET"

# ValarMind hook entries (paths relative to CURSOR_HOME — Cursor CWD for user hooks)
VALARMIND_SESSION_START=$(cat <<EOF
[
  {"command": "./hooks/_cursor/wrap-session.sh caveman", "timeout": 5},
  {"command": "./hooks/_cursor/wrap-session.sh superpowers", "timeout": 5},
  {"command": "./hooks/_cursor/wrap-session.sh obsidian-brain", "timeout": 5}
]
EOF
)

VALARMIND_BEFORE_SUBMIT=$(cat <<EOF
[
  {"command": "CLAUDE_CONFIG_DIR=$CURSOR_HOME VALARMIND_SKILLS_ROOT=$SKILLS_TARGET node ./hooks/caveman/caveman-mode-tracker.js", "timeout": 5},
  {"command": "CLAUDE_CONFIG_DIR=$CURSOR_HOME VALARMIND_SKILLS_ROOT=$SKILLS_TARGET node ./hooks/superpowers/superpowers-mode-tracker.js", "timeout": 5},
  {"command": "CLAUDE_CONFIG_DIR=$CURSOR_HOME VALARMIND_SKILLS_ROOT=$SKILLS_TARGET node ./hooks/obsidian-brain/obsidian-brain-mode-tracker.js", "timeout": 5}
]
EOF
)

if ! command -v jq >/dev/null 2>&1; then
  echo ""
  echo "Warning: jq not found — cannot merge hooks.json automatically."
  echo "Create or merge $HOOKS_JSON manually with:"
  echo ""
  cat <<MANUAL
{
  "version": 1,
  "hooks": {
    "sessionStart": $(echo "$VALARMIND_SESSION_START" | tr -d '\n'),
    "beforeSubmitPrompt": $(echo "$VALARMIND_BEFORE_SUBMIT" | tr -d '\n')
  }
}
MANUAL
  echo ""
  echo "Done! Restart Cursor after configuring hooks."
  exit 0
fi

if [ -f "$HOOKS_JSON" ]; then
  if ! jq -e . "$HOOKS_JSON" >/dev/null 2>&1; then
    echo "Warning: $HOOKS_JSON is not valid JSON — skipping automatic hook merge."
    echo "Fix the file manually, then re-run this installer."
    exit 0
  fi
  backup="$HOOKS_JSON.bak.$(date +%Y%m%d%H%M%S)"
  cp "$HOOKS_JSON" "$backup"
  echo "Backed up existing hooks.json → $backup"

  tmp_json=$(mktemp)
  jq \
    --argjson session "$VALARMIND_SESSION_START" \
    --argjson submit "$VALARMIND_BEFORE_SUBMIT" \
    '
      .version = 1 |
      .hooks = (.hooks // {}) |
      .hooks.sessionStart = (
        ((.hooks.sessionStart // []) | map(select(
          (.command // "") | (
            test("valarmindskills") or test("hooks/_cursor/") or
            test("hooks/caveman/") or test("hooks/superpowers/") or
            test("hooks/obsidian-brain/")
          ) | not
        ))) + $session
      ) |
      .hooks.beforeSubmitPrompt = (
        ((.hooks.beforeSubmitPrompt // []) | map(select(
          (.command // "") | (
            test("valarmindskills") or test("hooks/_cursor/") or
            test("hooks/caveman/") or test("hooks/superpowers/") or
            test("hooks/obsidian-brain/")
          ) | not
        ))) + $submit
      )
    ' "$HOOKS_JSON" > "$tmp_json"
  mv "$tmp_json" "$HOOKS_JSON"
  echo "ValarMind hooks merged → $HOOKS_JSON"
else
  jq -n \
    --argjson session "$VALARMIND_SESSION_START" \
    --argjson submit "$VALARMIND_BEFORE_SUBMIT" \
    '{version: 1, hooks: {sessionStart: $session, beforeSubmitPrompt: $submit}}' \
    > "$HOOKS_JSON"
  echo "Created $HOOKS_JSON"
fi

echo ""
echo "Done! Restart Cursor to load skills and hooks."
echo ""
echo "Caveman auto-activation: ON (default level = lite)."
echo "Override via env: export CAVEMAN_DEFAULT_MODE=lite|full|ultra|off"
echo ""
echo "Superpowers auto-activation: OFF (default)."
echo "Activate per-session: mention @superpowers or 'superpowers on'"
echo ""
echo "Obsidian-brain: ON when CLAUDE.md/AGENTS.md references a vault in the workspace."
echo ""

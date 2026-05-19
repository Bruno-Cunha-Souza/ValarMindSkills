#!/bin/bash

# Skills-only install for Cursor IDE (no hooks / hooks.json).
# For full plugin (skills + hooks), use install-plugin-cursor.sh.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_SKILLS="$REPO_DIR/skills"
CURSOR_HOME="${CURSOR_HOME:-$HOME/.cursor}"
SKILLS_TARGET="$CURSOR_HOME/skills"

# shellcheck source=_lib/ensure-rust.sh
source "$SCRIPT_DIR/_lib/ensure-rust.sh"

echo "Installing ValarMindSkills (skills only) in Cursor IDE..."
echo "CURSOR_HOME: $CURSOR_HOME"
echo ""

build_all_skill_binaries "$SOURCE_SKILLS"

mkdir -p "$SKILLS_TARGET"

installed=()
for skill_dir in "$SOURCE_SKILLS"/*/; do
  [ -f "$skill_dir/SKILL.md" ] || continue
  slug="$(basename "$skill_dir")"
  dest="$SKILLS_TARGET/$slug"
  rm -rf "$dest"
  cp -R "$skill_dir" "$dest"
  installed+=("$slug")
done

pruned=()
if [ -d "$SKILLS_TARGET" ]; then
  for existing_dir in "$SKILLS_TARGET"/*/; do
    [ -d "$existing_dir" ] || continue
    existing_slug="$(basename "$existing_dir")"
    found=0
    for s in "${installed[@]}"; do
      if [ "$s" = "$existing_slug" ]; then
        found=1
        break
      fi
    done
    if [ "$found" -eq 0 ]; then
      rm -rf "$existing_dir"
      pruned+=("$existing_slug")
    fi
  done
fi

echo ""
echo "Skills installed (${#installed[@]}):"
for s in "${installed[@]}"; do
  echo "  @$s → $SKILLS_TARGET/$s"
done
if [ "${#pruned[@]}" -gt 0 ]; then
  echo ""
  echo "Stale skills pruned (${#pruned[@]}):"
  for s in "${pruned[@]}"; do
    echo "  -$s"
  done
fi
echo ""
echo "Done! Restart Cursor for new skills to be detected."
echo "For caveman/superpowers/obsidian-brain hooks, run: bash scripts/install-plugin-cursor.sh"

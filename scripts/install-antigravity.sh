#!/bin/bash

# Install script for Antigravity skills
# This script copies the skills from the ValarMindSkills repository to the global Antigravity skills directory.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/../skills"
TARGET_DIR="$HOME/.gemini/antigravity/skills"

echo "Installing ValarMindSkills in Antigravity..."

mkdir -p "$TARGET_DIR"

installed=()

for skill_dir in "$SOURCE_DIR"/*/; do
  skill_file="$skill_dir/SKILL.md"
  [ -f "$skill_file" ] || continue

  slug="$(basename "$skill_dir")"
  cp -R "$skill_dir" "$TARGET_DIR/$slug"
  installed+=("$slug")
done

echo ""
echo "Skills installed (${#installed[@]}):"
for s in "${installed[@]}"; do
  echo "  @$s → $TARGET_DIR/$s"
done
echo ""
echo "Done! Skills are available in Antigravity."
echo "Note: You may need to run 'Reload Window' (Cmd+Shift+P > Reload Window) in VS Code for the autocomplete to detect new skills."

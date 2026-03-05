#!/bin/bash

# Install script for Claude Code CLI skills
# This script creates symlinks from ~/.claude/commands/ to each skill's SKILL.md

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/../skills"
TARGET_DIR="$HOME/.claude/commands"

echo "Installing ValarMindSkills in Claude Code CLI..."

mkdir -p "$TARGET_DIR"

installed=()

for skill_dir in "$SOURCE_DIR"/*/; do
  skill_file="$skill_dir/SKILL.md"
  [ -f "$skill_file" ] || continue

  slug="$(basename "$skill_dir")"
  target="$TARGET_DIR/$slug.md"
  source="$(cd "$skill_dir" && pwd)/SKILL.md"

  ln -sf "$source" "$target"
  installed+=("$slug")
done

echo ""
echo "Skills installed (${#installed[@]}):"
for s in "${installed[@]}"; do
  echo "  /$s → $(readlink "$TARGET_DIR/$s.md")"
done
echo ""
echo "Done! Skills are available as slash commands in Claude Code."
